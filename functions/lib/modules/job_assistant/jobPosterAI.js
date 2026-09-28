"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseJobPostersWithAI = void 0;
const functions = require("firebase-functions");
const firebase_1 = require("../../config/firebase");
const geminiHelper_1 = require("../../utils/geminiHelper");
exports.parseJobPostersWithAI = functions.runWith({ timeoutSeconds: 540, memory: "1GB" }).https.onCall(async (data, context) => {
    var _a, _b;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    try {
        const uid = context.auth.uid;
        const userDoc = await firebase_1.db.collection("users").doc(uid).get();
        const uData = userDoc.exists ? (userDoc.data() || {}) : {};
        const enabledModules = uData.enabledModules || [];
        const jobSubPerms = uData.jobAssistantSubPermissions || {};
        const isManualApplyEnabled = (enabledModules.includes("job_assistant") || enabledModules.includes("manual_apply"))
            && jobSubPerms.manual_apply !== false;
        if (!isManualApplyEnabled) {
            throw new functions.https.HttpsError('permission-denied', 'Manual Scan & Apply module is disabled for your account.');
        }
        let userGeminiKey = (((_a = uData.userApiKeys) === null || _a === void 0 ? void 0 : _a.geminiApiKey) || uData.geminiApiKey || "").trim();
        const { applicantName } = data;
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
                console.warn("[JobPosterAI] User profile lookup:", e.message);
            }
        }
        if (!promptName)
            promptName = "Candidate";
        const { imagesBase64, jobText, mode, resumeBase64, customPrompt } = data;
        const hasImages = Array.isArray(imagesBase64) && imagesBase64.length > 0;
        const hasText = typeof jobText === "string" && jobText.trim().length > 0;
        if (!hasImages && !hasText) {
            throw new functions.https.HttpsError('invalid-argument', 'Please provide either job poster screenshot(s) or job posting text.');
        }
        const isSingleJob = (mode === 'single_job');
        const userDirective = customPrompt ? `\nUSER SPECIFIC DIRECTIVE / INSTRUCTION: "${customPrompt}"\nEnsure you strictly follow this user directive when selecting and analyzing job roles.\n` : "";
        let prompt = "";
        if (hasText && !hasImages) {
            prompt = `Analyze the provided job description / recruiter hiring post text and candidate Resume (PDF).
Extract structured job details and write an authentic, high-converting application email.
${userDirective}

Hiring Post / Job Description Content:
"""
${jobText.trim()}
"""

CRITICAL INSTRUCTIONS FOR COVER LETTER & SUBJECT:
1. Candidate's Full Name is: "${promptName}".
2. Read the candidate's actual Resume (PDF) attached to analyze candidate's specific technical skills, framework proficiencies, work history, and key projects.
3. Compare candidate's actual resume experience against the job post requirements. Write a highly personalized, compelling, professional application email that directly maps candidate's specific accomplishments, certifications, and skills from their resume to the exact requirements of the job.
4. COVER LETTER STRUCTURE & KEY CONTRIBUTIONS:
   a) Engaging Opening: Express keen, enthusiastic interest in the specific [Job Title] role at [Company], referencing details or team focus from the post.
   b) Value Proposition: Clearly explain what direct value and technical alignment the candidate brings based on real resume highlights.
   c) KEY CONTRIBUTIONS PREPARED TO DELIVER (MANDATORY):
      A dedicated bulleted section:
      "Key contributions I am prepared to deliver include:"
      Provide 3-4 concrete, impactful bullet points (using "•") directly derived from the candidate's attached resume PDF (quantified project deliverables, architectures built, optimizations achieved, and verified technical proficiencies).
   d) Strategic Alignment & Experience Gap Bridging:
      If the job seeks more experience than the candidate has, proactively and confidently bridge the gap by emphasizing deep hands-on project mastery and immediate readiness to deliver value from Day 1.
   e) Professional Call to Action & Resume Reference: Propose a brief 10-15 minute discussion and mention the attached resume.
   f) Sign-off:
"Sincerely,
${promptName}"
5. STRICT RESUME GROUNDING & NO HALLUCINATION:
   - Ground all technical skills, frameworks, and past achievements SOLELY on the candidate's attached resume PDF.
   - NEVER invent or assume skills not present on the resume.
6. The cover letter MUST sound authentically human-written (not robotic, generic, or repetitive boilerplate).
7. Format the generated subject as: "Application for [Job Title] - ${promptName}".

Respond ONLY with a JSON object matching this schema:
{
  "jobs": [
    {
      "jobTitle": "string",
      "companyName": "string",
      "recipientEmail": "string (extract recipient or recruiter email if mentioned in post, else empty string)",
      "extractedSkills": ["string"],
      "generatedSubject": "string",
      "generatedCoverLetter": "string"
    }
  ]
}`;
        }
        else if (isSingleJob) {
            prompt = `Analyze the provided screenshot(s) and candidate Resume (PDF). These screenshot(s) belong to the SAME SINGLE job posting.
Stitch the text and context together. Extract structured job details.
${userDirective}
CRITICAL INSTRUCTIONS FOR COVER LETTER & SUBJECT:
1. Candidate's Full Name is: "${promptName}".
2. Read the candidate's actual Resume (PDF) attached to analyze candidate's specific technical skills, framework proficiencies, work history, and key projects.
3. Compare candidate's actual resume experience against the job poster requirements. Write a highly personalized, compelling, professional application email that directly maps candidate's specific accomplishments, certifications, and skills from their resume to the exact requirements of the job posting.
4. COVER LETTER STRUCTURE & KEY CONTRIBUTIONS:
   a) Engaging Opening: Express keen, enthusiastic interest in the specific [Job Title] role at [Company], referencing details from the poster.
   b) Value Proposition: Clearly explain what direct value and technical alignment the candidate brings based on real resume highlights.
   c) KEY CONTRIBUTIONS PREPARED TO DELIVER (MANDATORY):
      A dedicated bulleted section:
      "Key contributions I am prepared to deliver include:"
      Provide 3-4 concrete, impactful bullet points (using "•") directly derived from the candidate's attached resume PDF (quantified project deliverables, architectures built, optimizations achieved, and verified technical proficiencies).
   d) Strategic Alignment & Experience Gap Bridging:
      If the job poster seeks more experience than the candidate currently has on their resume (e.g. posting asks for 2+ or 3+ years, but resume shows 1-2 years), proactively, diplomatically, and creatively bridge this gap. Confidently acknowledge the expectation while decisively pivoting to the candidate's deep, hands-on mastery of the exact required tools, frameworks, and architectures, demonstrating immediate readiness from Day 1.
   e) Professional Call to Action & Resume Reference: Propose a brief 10-15 minute discussion and mention the attached resume.
   f) Sign-off:
"Sincerely,
${promptName}"
5. STRICT RESUME GROUNDING: Ground all skills SOLELY on the attached resume. NEVER hallucinate skills or use generic boilerplate.
6. Format the generated subject as: "Application for [Job Title] - ${promptName}".

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
        }
        else {
            prompt = `Analyze the provided screenshots and candidate Resume (PDF). Each screenshot represents a SEPARATE, DIFFERENT job posting.
Extract structured job details for EACH job posting separately.
${userDirective}
CRITICAL INSTRUCTIONS FOR COVER LETTER & SUBJECT:
1. Candidate's Full Name is: "${promptName}".
2. Read the candidate's actual Resume (PDF) attached to analyze candidate's specific technical skills, certifications, work history, and key projects.
3. Compare candidate's actual resume experience against each job poster's requirements. Write a highly personalized, compelling, professional cover letter for EACH job posting that directly maps candidate's specific accomplishments from their resume to that job.
4. COVER LETTER STRUCTURE & KEY CONTRIBUTIONS:
   a) Engaging Opening: Express keen, enthusiastic interest in the specific role at the company.
   b) Value Proposition: Clearly explain direct technical alignment.
   c) KEY CONTRIBUTIONS PREPARED TO DELIVER (MANDATORY):
      A dedicated bulleted section:
      "Key contributions I am prepared to deliver include:"
      Provide 3-4 concrete, impactful bullet points (using "•") directly derived from the candidate's attached resume PDF.
   d) Experience Gap Bridging: Bridge any experience gap with hands-on project mastery and immediate readiness.
   e) Professional Call to Action & Resume Reference: Propose a brief discussion and mention attached resume.
   f) Sign-off:
"Sincerely,
${promptName}"
5. STRICT RESUME GROUNDING: Ground all skills SOLELY on the attached resume. NEVER hallucinate skills or use generic boilerplate.
6. Format the generated subject as: "Application for [Job Title] - ${promptName}".

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
        }
        const inlineParts = [];
        // Attach Resume PDF if present (from data or user profile)
        const effectiveResumeB64 = (resumeBase64 || ((_b = uData.masterResume) === null || _b === void 0 ? void 0 : _b.base64) || "").toString().trim();
        if (effectiveResumeB64) {
            const cleanResumeB64 = effectiveResumeB64.replace(/^data:application\/pdf;base64,/, '');
            inlineParts.push({
                inlineData: {
                    mimeType: "application/pdf",
                    data: cleanResumeB64
                }
            });
        }
        // Attach Image Screenshots if provided
        if (hasImages) {
            imagesBase64.forEach((b64) => {
                const cleanB64 = b64.replace(/^data:image\/\w+;base64,/, '');
                inlineParts.push({
                    inlineData: {
                        mimeType: "image/jpeg",
                        data: cleanB64
                    }
                });
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
        console.log(`[JobPosterAI] Calling Gemini (${payload.contents[0].parts.length - 1} attachments, mode: ${mode}) with 45s per-model cascade...`);
        const geminiResult = await (0, geminiHelper_1.callGeminiAPI)(payload, { apiKey: userGeminiKey, timeout: 45000 });
        console.log(`[JobPosterAI] Successfully analyzed job posters using ${geminiResult.modelUsed}`);
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