"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.refineCoverLetterWithAI = exports.generateManualJobApplicationWithAI = void 0;
const functions = require("firebase-functions");
const firebase_1 = require("../../config/firebase");
const geminiHelper_1 = require("../../utils/geminiHelper");
exports.generateManualJobApplicationWithAI = functions.runWith({ timeoutSeconds: 300, memory: "1GB" }).https.onCall(async (data, context) => {
    var _a;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    try {
        const uid = context.auth.uid;
        const userDoc = await firebase_1.db.collection("users").doc(uid).get();
        const uData = userDoc.exists ? (userDoc.data() || {}) : {};
        const enabledModules = uData.enabledModules || [];
        if (!enabledModules.includes("job_assistant")) {
            throw new functions.https.HttpsError('permission-denied', 'The AI Job Assistant module is disabled for your account.');
        }
        const { companyName, jobTitle, companyUrl, recipientEmails, companyNotes, customPrompt, resumeBase64, applicantName } = data;
        let userGeminiKey = (((_a = uData.userApiKeys) === null || _a === void 0 ? void 0 : _a.geminiApiKey) || uData.geminiApiKey || "").trim();
        let promptName = (applicantName || uData.applicantName || uData.displayName || "").trim();
        if (!promptName) {
            try {
                const authUser = await firebase_1.admin.auth().getUser(uid);
                promptName = (authUser.displayName || "").trim();
                if (!promptName && authUser.email) {
                    promptName = authUser.email.split("@")[0];
                }
            }
            catch (e) {
                console.warn("[CoverLetterAI] User profile lookup:", e.message);
            }
        }
        if (!promptName)
            promptName = "Candidate";
        if (!companyName || !jobTitle) {
            throw new functions.https.HttpsError('invalid-argument', 'Company name and Job title are required.');
        }
        const prompt = `You are an elite, top-tier executive career coach and professional copywriter.
Write an exceptionally well-crafted, natural, and compelling job application cover letter email for the candidate "${promptName}" applying for the role of "${jobTitle}" at "${companyName}".
${companyUrl ? `Company URL: ${companyUrl}` : ''}
${recipientEmails ? `Recipient(s): ${recipientEmails}` : ''}
${companyNotes ? `Job Details / Company Context: "${companyNotes}"` : ''}
${customPrompt ? `Candidate's Custom Directive / Specific Request: "${customPrompt}"` : ''}

CRITICAL INSTRUCTIONS:
1. Examine the candidate's attached Resume PDF thoroughly. Extract concrete accomplishments, technical skills, and domain expertise directly from the resume, relating them directly to the target role.
2. HUMAN-WRITTEN, HIGH-CONVERSION, MOBILE-OPTIMIZED FORMAT:
   Recruiters and hiring managers read applications on their phones and will NOT read long essays or bulleted lists.
   The email MUST be concise, punchy, authentic, and strictly 4–5 sentences total, formatted into exactly TWO short paragraphs with a blank line between them.
   ABSOLUTELY NO BULLET POINTS ("•", "-", "*") OR LENGTHY LISTS.
3. TWO-PARAGRAPH FORMAT (4–5 LINES TOTAL):
   - Professional Greeting: "Dear [Hiring Manager / Recruiter Name if known, else 'Hiring Team'],"
   - Paragraph 1 (approx. 2 sentences):
     Direct, engaging opening expressing enthusiastic interest in the "${jobTitle}" role at "${companyName}". Highlight the candidate's core domain and top 2–3 strengths/technologies verified from their attached resume that directly align with the position.
   - Paragraph 2 (approx. 2–3 sentences):
     Highlight proven hands-on project delivery and problem-solving impact from their resume. Mention that their attached resume contains full details on their background and accomplishments, and invite them for a brief 10–15 minute call to discuss how they can contribute (always use "call" or "discussion", never "chat").
   - Sign-off:
"Sincerely,
${promptName}"
     (Never use generic placeholders like "[Your Name]").
4. TONE & ANTI-AI/ANTI-BOILERPLATE MANDATES:
   - Must sound genuinely human, natural, conversational yet sharp and professional—NOT robotic, formalistic, or like generic ChatGPT/AI boilerplate.
   - Avoid tired clichés like "I am writing to express my strong interest...", "I am eager to contribute...", "With extensive hands-on experience...", or "Key contributions include:".
   - Ground all skills, tools, and background SOLELY on the candidate's attached resume. NEVER hallucinate or assume skills not on the resume.
   - Universal Generalization: Must work seamlessly for ANY user, ANY profession, and ANY experience tier.

Respond ONLY with a JSON object in this format:
{
  "job": {
    "jobTitle": "${jobTitle}",
    "companyName": "${companyName}",
    "recipientEmail": "${recipientEmails || ''}",
    "extractedSkills": ["string"],
    "generatedSubject": "Application for ${jobTitle} - ${promptName}",
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
        const geminiResult = await (0, geminiHelper_1.callGeminiAPI)(payload, { apiKey: userGeminiKey, timeout: 45000 });
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
            modelUsed: geminiResult.modelUsed || "gemini-3.8-flash"
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
exports.refineCoverLetterWithAI = functions.runWith({ timeoutSeconds: 180, memory: "512MB" }).https.onCall(async (data, context) => {
    var _a;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    const { currentSubject, currentCoverLetter, userPrompt, jobTitle, companyName, resumeBase64, applicantName } = data;
    if (!currentCoverLetter || !userPrompt) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing cover letter or user prompt.');
    }
    try {
        const uid = context.auth.uid;
        const userDoc = await firebase_1.db.collection("users").doc(uid).get();
        const uData = userDoc.exists ? (userDoc.data() || {}) : {};
        const enabledModules = uData.enabledModules || [];
        if (!enabledModules.includes("job_assistant")) {
            throw new functions.https.HttpsError('permission-denied', 'The AI Job Assistant module is disabled for your account.');
        }
        let userGeminiKey = (((_a = uData.userApiKeys) === null || _a === void 0 ? void 0 : _a.geminiApiKey) || uData.geminiApiKey || "").trim();
        let promptName = (applicantName || uData.applicantName || uData.displayName || "").trim();
        if (!promptName) {
            try {
                const authUser = await firebase_1.admin.auth().getUser(uid);
                promptName = (authUser.displayName || "").trim();
                if (!promptName && authUser.email) {
                    promptName = authUser.email.split("@")[0];
                }
            }
            catch (e) {
                console.warn("[CoverLetterAI] User profile lookup:", e.message);
            }
        }
        if (!promptName)
            promptName = "Candidate";
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
2. STRICT MOBILE FORMAT (4–5 LINES TOTAL): Keep the revised email concise, punchy, and strictly 4–5 sentences across exactly TWO short paragraphs with a single blank line between them.
3. ABSOLUTELY NO BULLET POINTS ("•", "-", "*") OR LISTS. Detailed metrics belong exclusively in the attached resume.
4. Avoid robotic AI clichés ("I am writing to express my strong interest...", "With extensive hands-on experience...", "Key contributions include:").
5. Ground all skills/experience mentioned solidly in the candidate's actual background/resume.
6. Subject line format: "Application for [Job Title] - ${promptName}".
7. Sign off MUST be:
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
        const geminiResult = await (0, geminiHelper_1.callGeminiAPI)(payload, { apiKey: userGeminiKey, timeout: 40000 });
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
            modelUsed: geminiResult.modelUsed || "gemini-3.8-flash"
        };
    }
    catch (error) {
        console.error("Error in refineCoverLetterWithAI:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to refine cover letter with AI.');
    }
});
//# sourceMappingURL=coverLetterAI.js.map