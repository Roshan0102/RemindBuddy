import * as functions from "firebase-functions";
import { db } from "../../config/firebase";
import { callGeminiAPI } from "../../utils/geminiHelper";

export const parseJobPostersWithAI = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }

    try {
        const uid = context.auth.uid;
        let userGeminiKey = "";
        try {
            const userDoc = await db.collection("users").doc(uid).get();
            if (userDoc.exists) {
                const uData = userDoc.data() || {};
                userGeminiKey = (uData.userApiKeys?.geminiApiKey || uData.geminiApiKey || "").trim();
            }
        } catch (e: any) {
            console.warn("[JobPosterAI] Could not fetch userGeminiKey:", e.message);
        }
        const { imagesBase64, mode, resumeBase64, applicantName, customPrompt } = data;
        if (!imagesBase64 || !Array.isArray(imagesBase64) || imagesBase64.length === 0) {
            throw new functions.https.HttpsError('invalid-argument', 'No image data provided.');
        }

        const isSingleJob = (mode === 'single_job');
        const promptName = applicantName || "Roshan J";
        const userDirective = customPrompt ? `\nUSER SPECIFIC DIRECTIVE / INSTRUCTION: "${customPrompt}"\nEnsure you strictly follow this user directive when selecting and analyzing job roles from the screenshots.\n` : "";

        const prompt = isSingleJob
            ? `Analyze the provided screenshot(s) and candidate Resume (PDF). These screenshot(s) belong to the SAME SINGLE job posting.
Stitch the text and context together. Extract structured job details.
${userDirective}
CRITICAL INSTRUCTIONS FOR COVER LETTER & SUBJECT:
1. Candidate's Full Name is: "${promptName}".
2. Read the candidate's actual Resume (PDF) attached to analyze candidate's specific technical skills, certifications (e.g. AWS certifications, DevOps platform operations, Kubernetes, etc.), work history, and key projects.
3. Compare candidate's actual resume experience against the job poster requirements. Write a highly personalized, compelling, professional cover letter that directly maps candidate's specific accomplishments, certifications, and skills from their resume to the exact requirements of the job posting.
4. The cover letter MUST sound authentically human-written (not robotic, generic, or boilerplate AI output).
5. Format the generated subject as: "${promptName} - [Job Title]" or "[Job Title] - ${promptName}".
6. Sign off the cover letter with:
"Sincerely,
${promptName}"
NEVER leave generic placeholders like "[Your Name]", "[Applicant Name]", or "[Name]".

Respond ONLY with a JSON object matching this schema:
{
  "jobs": [
    {
      "jobTitle": "string",
      "companyName": "string",
      "recipientEmail": "string",
      "extractedSkills": ["string"],
      "generatedSubject": "string",
      "generatedCoverLetter": "string"
    }
  ]
}`
            : `Analyze the provided screenshots and candidate Resume (PDF). Each screenshot represents a SEPARATE, DIFFERENT job posting.
Extract structured job details for EACH job posting separately.
${userDirective}
CRITICAL INSTRUCTIONS FOR COVER LETTER & SUBJECT:
1. Candidate's Full Name is: "${promptName}".
2. Read the candidate's actual Resume (PDF) attached to analyze candidate's specific technical skills, certifications, work history, and key projects.
3. Compare candidate's actual resume experience against each job poster's requirements. Write a highly personalized, compelling, professional cover letter for EACH job posting that directly maps candidate's specific accomplishments from their resume to that job.
4. The cover letter MUST sound authentically human-written (not robotic, generic, or boilerplate AI output).
5. Format the generated subject as: "${promptName} - [Job Title]" or "[Job Title] - ${promptName}".
6. Sign off the cover letter with:
"Sincerely,
${promptName}"
NEVER leave generic placeholders like "[Your Name]", "[Applicant Name]", or "[Name]".

Respond ONLY with a JSON object matching this schema:
{
  "jobs": [
    {
      "jobTitle": "string",
      "companyName": "string",
      "recipientEmail": "string",
      "extractedSkills": ["string"],
      "generatedSubject": "string",
      "generatedCoverLetter": "string"
    }
  ]
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

        // Attach Image Screenshots
        imagesBase64.forEach((b64: string) => {
            const cleanB64 = b64.replace(/^data:image\/\w+;base64,/, '');
            inlineParts.push({
                inlineData: {
                    mimeType: "image/jpeg",
                    data: cleanB64
                }
            });
        });

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

        const geminiResult = await callGeminiAPI(payload, { apiKey: userGeminiKey, timeout: 90000 });
        const textResponse = geminiResult.text;
        if (!textResponse) {
            throw new Error('Empty response from Gemini API.');
        }

        const parsed = JSON.parse(textResponse);
        const rawJobs = parsed.jobs || [];

        // Clean any residual placeholders in subject & cover letter
        const cleanedJobs = rawJobs.map((j: any) => {
            let subj = (j.generatedSubject || '').replace(/\[Your Name\]/gi, promptName).replace(/\[Applicant Name\]/gi, promptName).replace(/\[Name\]/gi, promptName);
            let body = (j.generatedCoverLetter || '').replace(/\[Your Name\]/gi, promptName).replace(/\[Applicant Name\]/gi, promptName).replace(/\[Name\]/gi, promptName);
            return {
                ...j,
                generatedSubject: subj,
                generatedCoverLetter: body
            };
        });

        return {
            success: true,
            jobs: cleanedJobs
        };
    } catch (error: any) {
        console.error("Error in parseJobPostersWithAI:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to analyze job poster image(s).');
    }
});
