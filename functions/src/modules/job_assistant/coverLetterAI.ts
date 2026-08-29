import * as functions from "firebase-functions";
import axios from "axios";
import { db } from "../../config/firebase";

export const generateManualJobApplicationWithAI = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }

    try {
        const { companyName, jobTitle, companyUrl, recipientEmails, companyNotes, customPrompt, resumeBase64, applicantName } = data;
        if (!companyName || !jobTitle) {
            throw new functions.https.HttpsError('invalid-argument', 'Company name and Job title are required.');
        }

        const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
        let apiKey = "";
        if (configDoc.exists) {
            apiKey = configDoc.data()?.apiKey || "";
        }
        if (!apiKey) {
            throw new functions.https.HttpsError('internal', 'Gemini API key is not configured.');
        }

        const promptName = applicantName || "Roshan J";

        const prompt = `Generate a highly personalized, human-sounding job application cover letter and email subject for the following opportunity:
Target Company Name: "${companyName}"
Job Role / Title: "${jobTitle}"
Company Website / URL: "${companyUrl || 'N/A'}"
Recipient HR Email(s): "${recipientEmails || 'N/A'}"
Company Context & Notes: "${companyNotes || 'N/A'}"
User Specific Guidance / Instructions: "${customPrompt || 'N/A'}"

CRITICAL INSTRUCTIONS FOR COVER LETTER & SUBJECT:
1. Candidate's Full Name is: "${promptName}".
2. Read the candidate's actual Resume (PDF) attached to analyze candidate's specific technical skills, certifications (e.g. AWS certifications, DevOps platform operations, Kubernetes, etc.), work history, and key projects.
3. Align candidate's actual experience from their resume with the target company (${companyName}), its domain/services, and the ${jobTitle} position.
4. The cover letter MUST sound authentically human-written (not robotic, generic, or boilerplate AI output). Address key candidate strengths and enthusiasm for joining ${companyName}.
5. Format the generated subject as: "${promptName} - ${jobTitle}".
6. Sign off the cover letter with:
"Sincerely,
${promptName}"
NEVER leave generic placeholders like "[Your Name]", "[Applicant Name]", or "[Name]".

Respond ONLY with a JSON object matching this schema:
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

        const inlineParts: any[] = [];

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

        const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
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

        const response = await axios.post(url, payload, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 90000
        });

        const candidates = response.data?.candidates;
        if (!candidates || candidates.length === 0) {
            throw new Error('No candidates returned from Gemini API.');
        }

        const textResponse = candidates[0].content?.parts[0]?.text;
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
            generatedCoverLetter: body
        };

        return {
            success: true,
            job: cleanedJob
        };
    } catch (error: any) {
        console.error("Error in generateManualJobApplicationWithAI:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to generate manual job application.');
    }
});

export const refineCoverLetterWithAI = functions.runWith({ timeoutSeconds: 60, memory: "512MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const { currentSubject, currentCoverLetter, userPrompt, jobTitle, companyName, resumeBase64, applicantName } = data;
    if (!currentCoverLetter || !userPrompt) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing cover letter or user prompt.');
    }

    try {
        const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
        let apiKey = "";
        if (configDoc.exists) {
            apiKey = configDoc.data()?.apiKey || "";
        }
        if (!apiKey) {
            throw new functions.https.HttpsError('internal', 'Gemini API key is not configured.');
        }

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

        const inlineParts: any[] = [{ text: prompt }];
        if (resumeBase64) {
            const cleanResumeB64 = resumeBase64.replace(/^data:application\/pdf;base64,/, '');
            inlineParts.push({
                inlineData: {
                    mimeType: "application/pdf",
                    data: cleanResumeB64
                }
            });
        }

        const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
        const payload = {
            contents: [{ parts: inlineParts }],
            generationConfig: { responseMimeType: "application/json" }
        };

        const response = await axios.post(url, payload, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 60000
        });

        const candidates = response.data?.candidates;
        if (!candidates || candidates.length === 0) {
            throw new Error('No response from Gemini API.');
        }

        const textResponse = candidates[0].content?.parts[0]?.text;
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
            generatedCoverLetter: genBody
        };
    } catch (error: any) {
        console.error("Error in refineCoverLetterWithAI:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to refine cover letter with AI.');
    }
});
