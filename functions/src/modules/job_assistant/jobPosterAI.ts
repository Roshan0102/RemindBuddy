import * as functions from "firebase-functions";
import { admin, db } from "../../config/firebase";
import { callGeminiAPI } from "../../utils/geminiHelper";
import { generateAtsResumePdf, TailoredResumeData } from "../../utils/pdfResumeGenerator";
import { ensureUserResumeParsed } from "../../utils/resumeParser";

export const parseJobPostersWithAI = functions.runWith({ timeoutSeconds: 540, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }

    try {
        const uid = context.auth.uid;
        const userDoc = await db.collection("users").doc(uid).get();
        const uData = userDoc.exists ? (userDoc.data() || {}) : {};
        const enabledModules = uData.enabledModules || [];
        const jobSubPerms = uData.jobAssistantSubPermissions || {};

        const isManualApplyEnabled = (enabledModules.includes("job_assistant") || enabledModules.includes("manual_apply"))
            && jobSubPerms.manual_apply !== false;

        if (!isManualApplyEnabled) {
            throw new functions.https.HttpsError('permission-denied', 'Manual Scan & Apply module is disabled for your account.');
        }

        let userGeminiKey = (uData.userApiKeys?.geminiApiKey || uData.geminiApiKey || "").trim();
        let userGroqKey = (uData.userApiKeys?.groqApiKey || uData.groqApiKey || "").trim();
        const { applicantName } = data;
        let promptName = (applicantName || uData.applicantName || uData.displayName || "").trim();
        if (!promptName) {
            try {
                const authUser = await admin.auth().getUser(uid);
                promptName = (authUser.displayName || "").trim();
                if (!promptName && authUser.email) {
                    promptName = authUser.email.split("@")[0];
                }
            } catch (e: any) {
                console.warn("[JobPosterAI] User profile lookup:", e.message);
            }
        }
        if (!promptName) promptName = "Candidate";

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
3. Compare candidate's actual resume experience against the job post requirements.
4. HUMAN-WRITTEN, HIGH-CONVERSION, MOBILE-OPTIMIZED FORMAT:
   Recruiters read emails on mobile and will NOT read long essays or bulleted lists.
   The cover letter MUST be concise, punchy, authentic, and strictly 4–5 sentences total, formatted into exactly TWO short paragraphs with a blank line between them.
   ABSOLUTELY NO BULLET POINTS ("•", "-", "*") OR LENGTHY LISTS.
5. TWO-PARAGRAPH FORMAT (4–5 LINES TOTAL):
   - Professional Greeting: "Dear [Hiring Manager / Recruiter Name if known, else 'Hiring Team'],"
   - Paragraph 1 (approx. 2 sentences):
     Direct, engaging opening expressing enthusiastic interest in the specific [Job Title] role at [Company]. Highlight candidate's core domain and top 2–3 strengths/technologies verified from their attached resume that directly match the post.
   - Paragraph 2 (approx. 2–3 sentences):
     Highlight proven hands-on project delivery and problem-solving impact from their resume. Mention that their resume is attached for complete review, and invite them for a brief 10–15 minute call to discuss how they can contribute (always use "call" or "discussion", never "chat").
   - Sign-off:
"Sincerely,
${promptName}"
6. STRICT RESUME GROUNDING & NO HALLUCINATION:
   - Ground all technical skills, frameworks, and past achievements SOLELY on the candidate's attached resume PDF.
   - NEVER invent or assume skills not present on the resume.
   - Must sound genuinely human, natural, conversational yet sharp and professional—NOT robotic or like generic AI boilerplate. Avoid clichés like "I am writing to express my strong interest...", "With extensive hands-on experience...", or "Key contributions include:".
   - Universal Generalization: Must work seamlessly for ANY user, ANY profession, and ANY experience tier.
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
        } else if (isSingleJob) {
            prompt = `Analyze the provided screenshot(s), accompanying post text (if any), and candidate Resume (PDF). These screenshot(s) belong to the SAME SINGLE job posting.
Stitch the image flyer graphic, post text, and context together. Extract structured job details and recruiter email.
${hasText ? `\nAccompanying Post Text / Link Context:\n"""\n${jobText.trim()}\n"""\n` : ''}
${userDirective}
CRITICAL INSTRUCTIONS FOR COVER LETTER & SUBJECT:
1. Candidate's Full Name is: "${promptName}".
2. Read the candidate's actual Resume (PDF) attached to analyze candidate's specific technical skills, framework proficiencies, work history, and key projects.
3. Compare candidate's actual resume experience against the job poster requirements.
4. HUMAN-WRITTEN, HIGH-CONVERSION, MOBILE-OPTIMIZED FORMAT:
   Recruiters read emails on mobile and will NOT read long essays or bulleted lists.
   The cover letter MUST be concise, punchy, authentic, and strictly 4–5 sentences total, formatted into exactly TWO short paragraphs with a blank line between them.
   ABSOLUTELY NO BULLET POINTS ("•", "-", "*") OR LENGTHY LISTS.
5. TWO-PARAGRAPH FORMAT (4–5 LINES TOTAL):
   - Professional Greeting: "Dear [Hiring Manager / Recruiter Name if known, else 'Hiring Team'],"
   - Paragraph 1 (approx. 2 sentences):
     Direct, engaging opening expressing enthusiastic interest in the specific [Job Title] role at [Company]. Highlight candidate's core domain and top 2–3 strengths/technologies verified from their attached resume that directly match the poster.
   - Paragraph 2 (approx. 2–3 sentences):
     Highlight proven hands-on project delivery and problem-solving impact from their resume. Mention that their resume is attached for complete review, and invite them for a brief 10–15 minute call to discuss how they can contribute (always use "call" or "discussion", never "chat").
   - Sign-off:
"Sincerely,
${promptName}"
6. STRICT RESUME GROUNDING & NO HALLUCINATION:
   - Ground all skills SOLELY on the attached resume. NEVER hallucinate skills or use generic boilerplate.
   - Must sound genuinely human, natural, conversational yet sharp and professional—NOT robotic or like generic AI boilerplate. Avoid clichés like "I am writing to express my strong interest...", "With extensive hands-on experience...", or "Key contributions include:".
   - Universal Generalization: Must work seamlessly for ANY user, ANY profession, and ANY experience tier.
7. Format the generated subject as: "Application for [Job Title] - ${promptName}".

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
        } else {
            prompt = `Analyze the provided screenshots and candidate Resume (PDF). Each screenshot represents a SEPARATE, DIFFERENT job posting.
Extract structured job details for EACH job posting separately.
${userDirective}
CRITICAL INSTRUCTIONS FOR COVER LETTER & SUBJECT:
1. Candidate's Full Name is: "${promptName}".
2. Read the candidate's actual Resume (PDF) attached to analyze candidate's specific technical skills, certifications, work history, and key projects.
3. Compare candidate's actual resume experience against each job poster's requirements.
4. HUMAN-WRITTEN, HIGH-CONVERSION, MOBILE-OPTIMIZED FORMAT:
   Recruiters read emails on mobile and will NOT read long essays or bulleted lists.
   The cover letter MUST be concise, punchy, authentic, and strictly 4–5 sentences total, formatted into exactly TWO short paragraphs with a blank line between them.
   ABSOLUTELY NO BULLET POINTS ("•", "-", "*") OR LENGTHY LISTS.
5. TWO-PARAGRAPH FORMAT (4–5 LINES TOTAL):
   - Professional Greeting: "Dear [Hiring Manager / Recruiter Name if known, else 'Hiring Team'],"
   - Paragraph 1 (approx. 2 sentences):
     Direct, engaging opening expressing enthusiastic interest in the specific role at the company. Highlight candidate's core domain and top 2–3 strengths/technologies verified from their attached resume that directly match the post.
   - Paragraph 2 (approx. 2–3 sentences):
     Highlight proven hands-on project delivery and problem-solving impact from their resume. Mention that their resume is attached for complete review, and invite them for a brief 10–15 minute call to discuss how they can contribute (always use "call" or "discussion", never "chat").
   - Sign-off:
"Sincerely,
${promptName}"
6. STRICT RESUME GROUNDING: Ground all skills SOLELY on the attached resume. NEVER hallucinate skills or use generic boilerplate.
   - Must sound genuinely human, natural, conversational yet sharp and professional—NOT robotic or like generic AI boilerplate. Avoid clichés like "I am writing to express my strong interest...", "With extensive hands-on experience...", or "Key contributions include:".
   - Universal Generalization: Must work seamlessly for ANY user, ANY profession, and ANY experience tier.
7. Format the generated subject as: "Application for [Job Title] - ${promptName}".

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

        const inlineParts: any[] = [];

        // Attach Resume PDF if present (from data or user profile)
        const effectiveResumeB64 = (resumeBase64 || uData.masterResume?.base64 || "").toString().trim();
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
            imagesBase64.forEach((b64: string) => {
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

        console.log(`[JobPosterAI] Calling Gemini/Groq (${payload.contents[0].parts.length - 1} attachments, mode: ${mode}) with fallback cascade...`);
        const geminiResult = await callGeminiAPI(payload, { 
            apiKey: userGeminiKey, 
            groqApiKey: userGroqKey, 
            timeout: 35000 
        });
        console.log(`[JobPosterAI] Successfully analyzed job posters using ${geminiResult.modelUsed}`);
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

        // Generate tailored ATS Resume PDFs using BYOK Gemini output if present
        for (const j of cleanedJobs) {
            if (j.tailoredResume) {
                try {
                    const tailoredResumeData: TailoredResumeData = j.tailoredResume;
                    if (tailoredResumeData.contactLine) {
                        const segs = tailoredResumeData.contactLine.split(/[|•]/).map((s: string) => s.trim()).filter(Boolean);
                        const userLinks = uData.profileLinks || uData.links || {};
                        const cleanedSegs = segs.map((seg: string) => {
                            const isBare = /^(portfolio|website|personal website)$/i.test(seg);
                            if (isBare) return userLinks.portfolio || userLinks.github || "";
                            return seg;
                        }).filter(Boolean);
                        tailoredResumeData.contactLine = cleanedSegs.join(" | ");
                    }
                    const pdfBuf = await generateAtsResumePdf(tailoredResumeData);
                    j.tailoredResumePdfBase64 = pdfBuf.toString("base64");
                    try {
                        const bucket = admin.storage().bucket();
                        const file = bucket.file(`users/${uid}/tailored_resumes/post_${Date.now()}_${Math.random().toString(36).slice(2, 6)}.pdf`);
                        await file.save(pdfBuf, { metadata: { contentType: "application/pdf" } });
                        const [signedUrl] = await file.getSignedUrl({
                            action: "read",
                            expires: Date.now() + (365 * 24 * 60 * 60 * 1000)
                        });
                        j.tailoredResumePdfUrl = signedUrl;
                    } catch (stErr: any) {
                        console.log(`[JobPosterAI] Storage upload note: ${stErr.message}`);
                    }
                } catch (pdfErr: any) {
                    console.warn(`[JobPosterAI] Failed to generate ATS PDF for ${j.jobTitle}: ${pdfErr.message}`);
                }
            }
        }

        return {
            success: true,
            jobs: cleanedJobs
        };
    } catch (error: any) {
        console.error("Error in parseJobPostersWithAI:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to analyze job poster image(s).');
    }
});

export const tailorResumeForJob = functions.runWith({ timeoutSeconds: 300, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const uid = context.auth.uid;
    const { jobTitle, companyName, jobDescription, jobId } = data;

    if (!jobTitle || !companyName) {
        throw new functions.https.HttpsError('invalid-argument', 'Job title and company name are required.');
    }

    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'User profile not found.');
    }
    const userData = userDoc.data() || {};
    const userApiKeys = userData.userApiKeys || {};
    const geminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();
    const groqKey = (userApiKeys.groqApiKey || userData.groqApiKey || "").trim();

    let resumePdfBase64 = (userData.masterResume?.base64 || userData.masterResume?.base64Data || "").toString().trim();
    if (!resumePdfBase64) {
        const pSnap = await db.collection("users").doc(uid).collection("resume_profiles").limit(1).get();
        if (!pSnap.empty) {
            resumePdfBase64 = (pSnap.docs[0].data().base64 || "").toString().trim();
        }
    }
    const cleanResumeB64 = resumePdfBase64.replace(/^data:application\/pdf;base64,/, "");
    if (!cleanResumeB64) {
        throw new functions.https.HttpsError('failed-precondition', 'Please upload your base resume PDF in Job Assistant settings before generating a tailored resume.');
    }

    const groundTruth = await ensureUserResumeParsed(uid, userData, cleanResumeB64, geminiKey, groqKey, userData.masterResume?.fileName);
    const candidateName = (userData.applicantName || userData.displayName || userData.fullName || "Candidate").trim();

    const prompt = `You are an elite Executive ATS Resume Specialist.
Tailor the candidate's verified resume specifically for the following job opportunity:
COMPANY: "${companyName}"
JOB TITLE: "${jobTitle}"
${jobDescription ? `JOB DESCRIPTION / CONTEXT:\n"""\n${jobDescription.slice(0, 4000)}\n"""` : ''}

CANDIDATE BASE RESUME GROUND TRUTH:
${groundTruth ? JSON.stringify(groundTruth, null, 2) : "Use candidate experience from PDF"}

TASK:
1. Align candidate's real accomplishments and technical skills to match the role requirements.
2. Produce a polished, ATS-optimized resume structure matching this schema:
{
  "tailoredResume": {
    "fullName": "${candidateName}",
    "contactLine": "City, Country | Phone | Email | LinkedIn | GitHub / Portfolio",
    "professionalSummary": "Results-driven...",
    "skills": [
      { "category": "Technical Skills", "items": "..." }
    ],
    "experience": [
      {
        "company": "...",
        "role": "...",
        "period": "...",
        "location": "...",
        "bulletPoints": ["..."]
      }
    ],
    "projects": [
      {
        "title": "...",
        "techStack": "...",
        "bulletPoints": ["..."]
      }
    ],
    "education": [
      {
        "degree": "...",
        "institution": "...",
        "period": "...",
        "location": "..."
      }
    ],
    "certifications": ["..."]
  }
}
STRICT RULE: Ground all skills SOLELY on candidate's verified background. NEVER hallucinate experience.`;

    const inlineParts: any[] = [];
    if (cleanResumeB64) {
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
            temperature: 0.2,
            responseMimeType: "application/json"
        }
    };

    const res = await callGeminiAPI(payload, { apiKey: geminiKey, groqApiKey: groqKey, timeout: 35000 });
    const raw = res.text || "{}";
    const parsed = JSON.parse(raw.replace(/```json/g, "").replace(/```/g, "").trim());
    const tailoredResumeData: TailoredResumeData = parsed.tailoredResume || {
        fullName: candidateName,
        contactLine: "Email | Phone"
    };

    if (tailoredResumeData.contactLine) {
        const segs = tailoredResumeData.contactLine.split(/[|•]/).map((s: string) => s.trim()).filter(Boolean);
        const userLinks = userData.profileLinks || userData.links || {};
        const cleanedSegs = segs.map((seg: string) => {
            const isBare = /^(portfolio|website|personal website)$/i.test(seg);
            if (isBare) return userLinks.portfolio || userLinks.github || "";
            return seg;
        }).filter(Boolean);
        tailoredResumeData.contactLine = cleanedSegs.join(" | ");
    }

    const pdfBuf = await generateAtsResumePdf(tailoredResumeData);
    const tailoredResumePdfBase64 = pdfBuf.toString("base64");
    let tailoredResumePdfUrl = "";

    try {
        const bucket = admin.storage().bucket();
        const fileId = jobId ? Buffer.from(jobId).toString("base64url").slice(0, 32) : Date.now().toString();
        const file = bucket.file(`users/${uid}/tailored_resumes/${fileId}.pdf`);
        await file.save(pdfBuf, { metadata: { contentType: "application/pdf" } });
        const [signedUrl] = await file.getSignedUrl({
            action: "read",
            expires: Date.now() + (365 * 24 * 60 * 60 * 1000)
        });
        tailoredResumePdfUrl = signedUrl;
    } catch (stErr: any) {
        console.log(`[JobPosterAI] Storage upload note: ${stErr.message}`);
    }

    if (jobId) {
        try {
            await db.collection("users").doc(uid).collection("job_applications").doc(jobId).set({
                tailoredResumePdfBase64,
                tailoredResumePdfUrl: tailoredResumePdfUrl || null,
                tailoredResumeData
            }, { merge: true });
        } catch (dbErr: any) {
            console.warn(`[JobPosterAI] Firestore update note: ${dbErr.message}`);
        }
    }

    return {
        success: true,
        tailoredResumePdfBase64,
        tailoredResumePdfUrl: tailoredResumePdfUrl || null,
        tailoredResumeData
    };
});
