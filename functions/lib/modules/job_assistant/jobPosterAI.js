"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseJobPostersWithAI = void 0;
const functions = require("firebase-functions");
const geminiHelper_1 = require("../../utils/geminiHelper");
exports.parseJobPostersWithAI = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    try {
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
        // Attach Image Screenshots
        imagesBase64.forEach((b64) => {
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
        const geminiResult = await (0, geminiHelper_1.callGeminiAPI)(payload, { timeout: 90000 });
        const textResponse = geminiResult.text;
        if (!textResponse) {
            throw new Error('Empty response from Gemini API.');
        }
        const parsed = JSON.parse(textResponse);
        const rawJobs = parsed.jobs || [];
        // Clean any residual placeholders in subject & cover letter
        const cleanedJobs = rawJobs.map((j) => {
            let subj = (j.generatedSubject || '').replace(/\[Your Name\]/gi, promptName).replace(/\[Applicant Name\]/gi, promptName).replace(/\[Name\]/gi, promptName);
            let body = (j.generatedCoverLetter || '').replace(/\[Your Name\]/gi, promptName).replace(/\[Applicant Name\]/gi, promptName).replace(/\[Name\]/gi, promptName);
            return Object.assign(Object.assign({}, j), { generatedSubject: subj, generatedCoverLetter: body });
        });
        return {
            success: true,
            jobs: cleanedJobs
        };
    }
    catch (error) {
        console.error("Error in parseJobPostersWithAI:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to analyze job poster image(s).');
    }
});
//# sourceMappingURL=jobPosterAI.js.map