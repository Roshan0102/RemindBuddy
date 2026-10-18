"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseUserResumeCallable = void 0;
exports.extractTextFromDocx = extractTextFromDocx;
exports.detectResumeMimeType = detectResumeMimeType;
exports.parseResumeGroundTruth = parseResumeGroundTruth;
exports.ensureUserResumeParsed = ensureUserResumeParsed;
const functions = require("firebase-functions");
const crypto = require("crypto");
const zlib = require("zlib");
const firebase_1 = require("../config/firebase");
const geminiHelper_1 = require("./geminiHelper");
const groqHelper_1 = require("./groqHelper");
/**
 * Extracts pure text from a .docx document buffer by unzipping word/document.xml
 * without requiring any heavy native or third-party dependencies.
 */
function extractTextFromDocx(buffer) {
    try {
        let offset = 0;
        while (offset < buffer.length - 4) {
            // Check for Local File Header signature 0x04034b50 ("PK\x03\x04")
            if (buffer.readUInt32LE(offset) === 0x04034b50) {
                const compressionMethod = buffer.readUInt16LE(offset + 8);
                const compressedSize = buffer.readUInt32LE(offset + 18);
                const fileNameLen = buffer.readUInt16LE(offset + 26);
                const extraFieldLen = buffer.readUInt16LE(offset + 28);
                const fileName = buffer.toString("utf8", offset + 30, offset + 30 + fileNameLen);
                const dataStart = offset + 30 + fileNameLen + extraFieldLen;
                if (fileName === "word/document.xml") {
                    const dataSlice = buffer.slice(dataStart, dataStart + compressedSize);
                    let xml = "";
                    if (compressionMethod === 8) {
                        xml = zlib.inflateRawSync(dataSlice).toString("utf8");
                    }
                    else if (compressionMethod === 0) {
                        xml = dataSlice.toString("utf8");
                    }
                    if (xml) {
                        // Replace paragraph breaks
                        let text = xml.replace(/<\/w:p>/g, "\n");
                        // Extract text nodes
                        text = text.replace(/<w:t[^>]*>(.*?)<\/w:t>/g, "$1");
                        // Strip remaining XML tags
                        text = text.replace(/<[^>]+>/g, "");
                        return text.replace(/\n\s*\n+/g, "\n\n").trim();
                    }
                }
                offset = dataStart + compressedSize;
            }
            else {
                offset++;
            }
        }
    }
    catch (e) {
        console.warn(`[ResumeParser] Docx text extraction warning: ${e.message}`);
    }
    return "";
}
/**
 * Detects the document MIME type from base64 header or binary magic bytes.
 */
function detectResumeMimeType(base64Data, fileName) {
    const ext = (fileName || "").toLowerCase().split(".").pop();
    if (ext === "docx")
        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    if (ext === "doc")
        return "application/msword";
    if (ext === "txt")
        return "text/plain";
    if (base64Data.startsWith("JVBERi0"))
        return "application/pdf";
    if (base64Data.startsWith("UEsDB")) {
        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    }
    return "application/pdf";
}
/**
 * Parses full, untruncated structured data from a candidate's resume (PDF, Word, or Text).
 * Strictly preserves EVERY bullet point, link, and authentic skill.
 */
async function parseResumeGroundTruth(cleanResumeB64, apiKey, groqApiKey, fileName) {
    var _a, _b, _c;
    const resumeHash = crypto.createHash("md5").update(cleanResumeB64).digest("hex");
    const mimeType = detectResumeMimeType(cleanResumeB64, fileName);
    let docxText = "";
    if (mimeType.includes("wordprocessingml") || (fileName && fileName.endsWith(".docx"))) {
        try {
            const buf = Buffer.from(cleanResumeB64, "base64");
            docxText = extractTextFromDocx(buf);
            if (docxText) {
                console.log(`[ResumeParser] Successfully extracted ${docxText.length} chars of raw text from docx.`);
            }
        }
        catch (err) {
            console.warn(`[ResumeParser] Could not extract raw docx text: ${err.message}`);
        }
    }
    const prompt = `You are a World-Class ATS Resume Parsing Expert.
Extract the COMPLETE, UNTRUNCATED structured ground-truth data from the candidate's attached resume document.

CRITICAL EXTRACTION RULES:
1. FULL NAME & CONTACT:
   - Extract candidate's full name into "fullName".
   - Extract contact details into "contactLine" (Format: "City, Country | Phone | Email | LinkedIn URL | GitHub URL | Portfolio URL").
   - In "links", extract verified full URLs for "linkedin", "github", and "portfolio" (if present in the resume).

2. PROFESSIONAL SUMMARY:
   - Extract candidate's summary/objective if present. If not present, craft a 2-3 sentence factual summary based strictly on their real roles and technologies.

3. SKILLS CATEGORIZATION:
   - Group all candidate technical and professional skills into clean categories (e.g. "Languages & Frameworks", "Cloud & Infrastructure", "Databases & Storage", "Tools & Methodologies", etc.).
   - DO NOT omit any skills the candidate listed in their resume.

4. WORK EXPERIENCE (ABSOLUTE FIDELITY - DO NOT TRUNCATE OR SUMMARIZE):
   - For EACH position:
     * "company": Company name
     * "role": Exact job title
     * "period": Dates (e.g. "Jan 2022 - Present")
     * "location": Location or Remote
     * "bulletPoints": EXTRACT EVERY SINGLE BULLET POINT OR ACCOMPLISHMENT THE CANDIDATE HAS LISTED.
       If the candidate has 4, 5, or 6 bullet points, YOU MUST OUTPUT ALL 4, 5, OR 6 BULLET POINTS!
       DO NOT summarize them into 2 lines. Preserve all technical details, metrics, architectures, tools, and impacts.

5. PROJECTS (FIDELITY PRESERVATION):
   - For EACH project:
     * "title": Project title
     * "techStack": Technologies used
     * "bulletPoints": ALL bullet points and descriptions for that project.

6. EDUCATION & CERTIFICATIONS:
   - Extract all degrees, institutions, periods, and locations.
   - Extract all certifications verbatim.

OUTPUT STRICT JSON FORMAT ONLY:
{
  "fullName": "Candidate Name",
  "contactLine": "City, Country | +91 ... | candidate@email.com | linkedin.com/in/... | github.com/...",
  "links": {
    "linkedin": "https://linkedin.com/in/...",
    "github": "https://github.com/...",
    "portfolio": "https://..."
  },
  "professionalSummary": "Results-driven Engineer with...",
  "skills": [
    { "category": "Languages & Frameworks", "items": "Dart, Flutter, TypeScript, React" },
    { "category": "Databases & Cloud", "items": "Firestore, PostgreSQL, GCP, Firebase" }
  ],
  "experience": [
    {
      "company": "Company Name",
      "role": "Job Title",
      "period": "2023 - Present",
      "location": "City, Country",
      "bulletPoints": [
        "First complete bullet point with metrics and tools...",
        "Second complete bullet point with architecture and impact...",
        "Third complete bullet point...",
        "Fourth complete bullet point..."
      ]
    }
  ],
  "projects": [
    {
      "title": "Project Name",
      "techStack": "Flutter, Node.js, Firebase",
      "bulletPoints": [
        "Project description point 1...",
        "Project description point 2..."
      ]
    }
  ],
  "education": [
    {
      "degree": "Bachelor of Technology in Computer Science",
      "institution": "University / Institute Name",
      "period": "2019 - 2023",
      "location": "India"
    }
  ],
  "certifications": [
    "AWS Certified Solutions Architect"
  ]
}`;
    let parsedResult = null;
    // Strategy A: If docx text was extracted, we can execute via pure text
    if (docxText && docxText.length > 50) {
        try {
            const textPrompt = `${prompt}\n\n--- CANDIDATE RESUME DOCUMENT TEXT ---\n${docxText.slice(0, 15000)}`;
            const resp = await (0, geminiHelper_1.callGeminiAPI)({
                contents: [{ role: "user", parts: [{ text: textPrompt }] }],
                generationConfig: { temperature: 0.1, responseMimeType: "application/json" }
            }, { apiKey, groqApiKey, timeout: 60000 });
            const match = resp.text.match(/\{[\s\S]*\}/);
            if (match)
                parsedResult = JSON.parse(match[0]);
        }
        catch (e) {
            console.warn(`[ResumeParser] Docx text prompt failed: ${e.message}. Trying binary fallback.`);
        }
    }
    // Strategy B: Inline document payload for PDF / docx binary
    if (!parsedResult) {
        try {
            const resp = await (0, geminiHelper_1.callGeminiAPI)({
                contents: [
                    {
                        role: "user",
                        parts: [
                            { text: prompt },
                            {
                                inlineData: {
                                    mimeType: mimeType,
                                    data: cleanResumeB64
                                }
                            }
                        ]
                    }
                ],
                generationConfig: {
                    temperature: 0.1,
                    responseMimeType: "application/json"
                }
            }, { apiKey, groqApiKey, timeout: 90000 });
            const match = resp.text.match(/\{[\s\S]*\}/);
            if (match)
                parsedResult = JSON.parse(match[0]);
        }
        catch (geminiErr) {
            console.error(`[ResumeParser] Gemini binary extraction failed: ${geminiErr.message}`);
            // Fallback to Groq if groqApiKey is provided and docxText is available
            if (groqApiKey && docxText) {
                try {
                    const groqResp = await (0, groqHelper_1.callGroqAPI)({
                        apiKey: groqApiKey,
                        messages: [
                            { role: "system", content: "You are an ATS Resume Parser. Output JSON only." },
                            { role: "user", content: `${prompt}\n\nRESUME TEXT:\n${docxText}` }
                        ],
                        responseFormat: "json_object"
                    });
                    const match = groqResp.text.match(/\{[\s\S]*\}/);
                    if (match)
                        parsedResult = JSON.parse(match[0]);
                }
                catch (groqErr) {
                    console.error(`[ResumeParser] Groq extraction fallback failed: ${groqErr.message}`);
                }
            }
        }
    }
    if (!parsedResult) {
        throw new Error("Could not extract structured data from resume document.");
    }
    const groundTruth = {
        resumeHash,
        extractedAt: new Date().toISOString(),
        fullName: (parsedResult.fullName || "Candidate").trim(),
        contactLine: (parsedResult.contactLine || "").trim(),
        links: {
            linkedin: ((_a = parsedResult.links) === null || _a === void 0 ? void 0 : _a.linkedin) || undefined,
            github: ((_b = parsedResult.links) === null || _b === void 0 ? void 0 : _b.github) || undefined,
            portfolio: ((_c = parsedResult.links) === null || _c === void 0 ? void 0 : _c.portfolio) || undefined
        },
        professionalSummary: (parsedResult.professionalSummary || "").trim(),
        skills: Array.isArray(parsedResult.skills) ? parsedResult.skills : [],
        experience: Array.isArray(parsedResult.experience)
            ? parsedResult.experience.map((e) => ({
                company: (e.company || "").trim(),
                role: (e.role || "").trim(),
                period: (e.period || "").trim(),
                location: e.location ? e.location.trim() : undefined,
                bulletPoints: Array.isArray(e.bulletPoints) ? e.bulletPoints.map((b) => String(b).trim()).filter(Boolean) : []
            }))
            : [],
        projects: Array.isArray(parsedResult.projects)
            ? parsedResult.projects.map((p) => ({
                title: (p.title || "").trim(),
                techStack: p.techStack ? p.techStack.trim() : undefined,
                link: p.link ? p.link.trim() : undefined,
                bulletPoints: Array.isArray(p.bulletPoints) ? p.bulletPoints.map((b) => String(b).trim()).filter(Boolean) : []
            }))
            : [],
        education: Array.isArray(parsedResult.education) ? parsedResult.education : [],
        certifications: Array.isArray(parsedResult.certifications) ? parsedResult.certifications : []
    };
    console.log(`[ResumeParser] Successfully parsed ground truth: ${groundTruth.fullName}, ${groundTruth.experience.length} roles, ${groundTruth.skills.length} skill categories.`);
    return groundTruth;
}
/**
 * Resolves and caches candidate resume ground truth in Firestore.
 * If hash matches existing cached data, returns instantly in 0ms without re-analyzing!
 */
async function ensureUserResumeParsed(uid, userData, resumeBase64, apiKey, groqApiKey, fileName) {
    var _a;
    if (!resumeBase64 || !resumeBase64.trim())
        return null;
    const cleanB64 = resumeBase64.replace(/^data:application\/[a-zA-Z0-9.\-_]+;base64,/, "").trim();
    if (!cleanB64)
        return null;
    const resumeHash = crypto.createHash("md5").update(cleanB64).digest("hex");
    // 1. Check in-memory / user document cache
    const existing = userData.masterResumeData || ((_a = userData.masterResume) === null || _a === void 0 ? void 0 : _a.parsedData);
    if (existing &&
        existing.resumeHash === resumeHash &&
        Array.isArray(existing.experience) &&
        existing.experience.length > 0) {
        console.log(`[ResumeParser] Using cached masterResumeData for ${uid} (hash: ${resumeHash.slice(0, 8)}, ${existing.experience.length} roles). Instant cache hit!`);
        return existing;
    }
    // 2. Parse fresh ground truth from document
    console.log(`[ResumeParser] Parsing fresh ground truth for user ${uid} (hash: ${resumeHash.slice(0, 8)})...`);
    try {
        const groundTruth = await parseResumeGroundTruth(cleanB64, apiKey, groqApiKey, fileName);
        // 3. Cache to Firestore user doc
        await firebase_1.db.collection("users").doc(uid).set({
            masterResumeData: groundTruth,
            masterResume: {
                parsedData: groundTruth,
                updatedAt: firebase_1.admin.firestore.FieldValue.serverTimestamp()
            }
        }, { merge: true });
        // Update in-memory reference
        userData.masterResumeData = groundTruth;
        if (userData.masterResume) {
            userData.masterResume.parsedData = groundTruth;
        }
        return groundTruth;
    }
    catch (err) {
        console.error(`[ResumeParser] Error parsing ground truth for user ${uid}: ${err.message}`);
        // Fallback to existing if available
        if (existing)
            return existing;
        return null;
    }
}
/**
 * Callable Cloud Function: Allows frontend to trigger ground truth indexing immediately
 * when a user uploads or updates their resume in Job Assistant settings.
 */
exports.parseUserResumeCallable = functions.runWith({ timeoutSeconds: 180, memory: "512MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
    }
    const uid = context.auth.uid;
    const resumeBase64 = (data.resumeBase64 || "").toString().trim();
    const fileName = (data.fileName || "Resume.pdf").toString().trim();
    if (!resumeBase64) {
        throw new functions.https.HttpsError("invalid-argument", "resumeBase64 is required.");
    }
    const userDoc = await firebase_1.db.collection("users").doc(uid).get();
    const userData = userDoc.data() || {};
    const userApiKeys = userData.userApiKeys || {};
    const apiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();
    const groqApiKey = (userApiKeys.groqApiKey || userData.groqApiKey || "").trim();
    const groundTruth = await ensureUserResumeParsed(uid, userData, resumeBase64, apiKey, groqApiKey, fileName);
    if (!groundTruth) {
        throw new functions.https.HttpsError("internal", "Failed to parse resume ground truth.");
    }
    return {
        success: true,
        groundTruth
    };
});
//# sourceMappingURL=resumeParser.js.map