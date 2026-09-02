"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.refineCoverLetterWithAI = exports.generateManualJobApplicationWithAI = void 0;
const functions = require("firebase-functions");
const geminiHelper_1 = require("../../utils/geminiHelper");
exports.generateManualJobApplicationWithAI = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    try {
        const { companyName, jobTitle, companyUrl, recipientEmails, companyNotes, customPrompt, resumeBase64, applicantName } = data;
        if (!companyName || !jobTitle) {
            throw new functions.https.HttpsError('invalid-argument', 'Company name and Job title are required.');
        }
        const promptName = applicantName || "Roshan J";
        const prompt = `You are an elite, top-tier executive career coach and professional copywriter.
Write an exceptionally well-crafted, natural, and compelling job application cover letter email for the candidate "${promptName}" applying for the role of "${jobTitle}" at "${companyName}".
${companyUrl ? `Company URL: ${companyUrl}` : ''}
${recipientEmails ? `Recipient(s): ${recipientEmails}` : ''}
${companyNotes ? `Job Details / Company Context: "${companyNotes}"` : ''}
${customPrompt ? `Candidate's Custom Directive / Specific Request: "${customPrompt}"` : ''}

CRITICAL INSTRUCTIONS:
1. Examine the candidate's attached Resume PDF thoroughly. Extract concrete accomplishments, technical skills (e.g. Flutter, Dart, Android/iOS, State Management, Cloud, REST APIs, CI/CD, Git, DevOps), and relate them directly to the target role.
2. Structure:
   a) Engaging Opening: Express enthusiasm for "${jobTitle}" at "${companyName}".
   b) Concrete Value: Highlighting 2-3 specific achievements or competencies from the candidate's resume that make them an outstanding fit.
   c) Strategic Alignment: How the candidate can solve challenges or create value for ${companyName}.
   d) Clear, professional closing and Call to Action proposing a brief discussion.
3. Sign-off MUST be:
"Sincerely,
${promptName}"
Never use generic placeholders like "[Your Name]".
4. Tone: Confident, professional, clear, and authentic. No generic template-style cliches.

Respond ONLY with a JSON object in this format:
{
  "job": {
    "jobTitle": "${jobTitle}",
    "companyName": "${companyName}",
    "recipientEmail": "${recipientEmails || ''}",
    "extractedSkills": ["string"],
    "generatedSubject": "${promptName} - ${jobTitle}",
    "generatedCoverLetter": "string"
  }
}`;
        const inlineParts = [];
        // Attach Resume PDF if present
        if (resumeBase64) {
            const cleanResumeB64 = resumeBase64.replace(/^data:application\/pdf;base64,/, '');
            inlineParts.push({
                inlineData: {
                    mimeType: "application/pdf",
                    data: cleanResumeB64
                }
            });
        }
        const payload = {
            contents: [
                {
                    parts: [
                        { text: prompt },
                        ...inlineParts
                    ]
                }
            ],
            generationConfig: {
                responseMimeType: "application/json"
            }
        };
        const geminiResult = await (0, geminiHelper_1.callGeminiAPI)(payload, { timeout: 90000 });
        const textResponse = geminiResult.text;
        if (!textResponse) {
            throw new Error('Empty response from Gemini API.');
        }
        const parsed = JSON.parse(textResponse);
        const rawJob = parsed.job || (parsed.jobs && parsed.jobs[0]) || {
            jobTitle: jobTitle,
            companyName: companyName,
            recipientEmail: recipientEmails || '',
            extractedSkills: [],
            generatedSubject: `${promptName} - ${jobTitle}`,
            generatedCoverLetter: ''
        };
        let subj = (rawJob.generatedSubject || `${promptName} - ${jobTitle}`).replace(/\[Your Name\]/gi, promptName).replace(/\[Applicant Name\]/gi, promptName).replace(/\[Name\]/gi, promptName);
        let body = (rawJob.generatedCoverLetter || '').replace(/\[Your Name\]/gi, promptName).replace(/\[Applicant Name\]/gi, promptName).replace(/\[Name\]/gi, promptName);
        const cleanedJob = {
            jobTitle: rawJob.jobTitle || jobTitle,
            companyName: rawJob.companyName || companyName,
            recipientEmail: recipientEmails || rawJob.recipientEmail || '',
            extractedSkills: rawJob.extractedSkills || [],
            generatedSubject: subj,
            generatedCoverLetter: body,
            modelUsed: geminiResult.modelUsed || "gemini-3.7-flash"
        };
        return {
            success: true,
            job: cleanedJob
        };
    }
    catch (error) {
        console.error("Error in generateManualJobApplicationWithAI:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to generate manual job application.');
    }
});
exports.refineCoverLetterWithAI = functions.runWith({ timeoutSeconds: 60, memory: "512MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    const { currentSubject, currentCoverLetter, userPrompt, jobTitle, companyName, resumeBase64, applicantName } = data;
    if (!currentCoverLetter || !userPrompt) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing cover letter or user prompt.');
    }
    try {
        const promptName = applicantName || "Roshan J";
        const prompt = `You are an expert executive career advisor and professional writer.
Candidate's Full Name: "${promptName}".
Target Position: ${jobTitle || 'Position'}
Company Name: ${companyName || 'Company'}

Current Subject Line: ${currentSubject || ''}
Current Cover Letter:
${currentCoverLetter}

USER'S REFINEMENT / MODIFICATION INSTRUCTION:
"${userPrompt}"

CRITICAL REFINEMENT INSTRUCTIONS:
1. Revise and rewrite the cover letter and subject line adhering strictly to the user's refinement instruction.
2. If candidate resume is attached, ensure skills/experience mentioned stay grounded in candidate's background.
3. Ensure the cover letter reads like an authentic, highly convincing human-written email (not robotic AI text).
4. Subject line MUST include candidate name: e.g. "${promptName} - [Job Title]".
5. Sign off MUST be:
"Sincerely,
${promptName}"
Never use generic placeholders like "[Your Name]".

Respond ONLY with a JSON object in this format:
{
  "generatedSubject": "string",
  "generatedCoverLetter": "string"
}`;
        const inlineParts = [{ text: prompt }];
        if (resumeBase64) {
            const cleanResumeB64 = resumeBase64.replace(/^data:application\/pdf;base64,/, '');
            inlineParts.push({
                inlineData: {
                    mimeType: "application/pdf",
                    data: cleanResumeB64
                }
            });
        }
        const payload = {
            contents: [{ parts: inlineParts }],
            generationConfig: { responseMimeType: "application/json" }
        };
        const geminiResult = await (0, geminiHelper_1.callGeminiAPI)(payload, { timeout: 60000 });
        const textResponse = geminiResult.text;
        if (!textResponse) {
            throw new Error('Empty response from Gemini API.');
        }
        const parsed = JSON.parse(textResponse);
        let genSubject = parsed.generatedSubject || currentSubject;
        let genBody = parsed.generatedCoverLetter || currentCoverLetter;
        genSubject = genSubject.replace(/\[Your Name\]/gi, promptName).replace(/\[Applicant Name\]/gi, promptName);
        genBody = genBody.replace(/\[Your Name\]/gi, promptName).replace(/\[Applicant Name\]/gi, promptName);
        return {
            success: true,
            generatedSubject: genSubject,
            generatedCoverLetter: genBody,
            modelUsed: geminiResult.modelUsed || "gemini-3.7-flash"
        };
    }
    catch (error) {
        console.error("Error in refineCoverLetterWithAI:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to refine cover letter with AI.');
    }
});
//# sourceMappingURL=coverLetterAI.js.map