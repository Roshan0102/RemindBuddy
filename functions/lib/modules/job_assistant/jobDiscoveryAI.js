"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.triggerAutoJobDiscoveryAndApply = void 0;
exports.discoverAndApplyForUser = discoverAndApplyForUser;
exports.internalAutoJobDiscoveryAndApply = internalAutoJobDiscoveryAndApply;
const functions = require("firebase-functions");
const axios_1 = require("axios");
const nodemailer = require("nodemailer");
const moment = require("moment-timezone");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
/**
 * Helper to validate email strings
 */
function isValidEmail(email) {
    if (!email || typeof email !== 'string')
        return false;
    const clean = email.trim();
    const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
    // Filter out common dummy or invalid placeholder emails
    if (clean.includes('example.com') || clean.includes('yourcompany.com') || clean.includes('test.com') || clean.includes('dummy')) {
        return false;
    }
    return emailRegex.test(clean);
}
/**
 * Searches and automatically applies to matching jobs for a specific user
 */
async function discoverAndApplyForUser(uid, options) {
    var _a, _b, _c, _d, _e, _f;
    const userDoc = await firebase_1.db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
        return { success: false, appliedCount: 0, jobs: [], message: "User not found" };
    }
    const userData = userDoc.data() || {};
    const emailConfig = userData.emailConfig || {};
    const userEmail = emailConfig.email;
    const appPassword = emailConfig.appPassword;
    const masterResume = userData.masterResume || {};
    const resumeBase64 = masterResume.base64;
    const resumeFileName = masterResume.fileName || "Resume.pdf";
    const applicantName = userData.displayName || "Roshan J";
    if (!userEmail || !appPassword) {
        console.log(`[JobDiscovery] User ${uid} has not configured Gmail/App Password. Skipping.`);
        return { success: false, appliedCount: 0, jobs: [], message: "Gmail & App Password not configured." };
    }
    if (!resumeBase64) {
        console.log(`[JobDiscovery] User ${uid} has not uploaded a Master Resume. Skipping.`);
        return { success: false, appliedCount: 0, jobs: [], message: "Master Resume PDF not uploaded." };
    }
    // Resolve roles & locations from options or user profile
    const autoApplySettings = userData.autoApplySettings || {};
    let targetRoles = (options === null || options === void 0 ? void 0 : options.targetRoles) || autoApplySettings.targetRoles || [
        "Flutter Developer",
        "Mobile Application Developer",
        "DevOps Engineer",
        "Cloud Engineer",
        "Site Reliability Engineer"
    ];
    if (typeof targetRoles === 'string') {
        targetRoles = targetRoles.split(',').map((s) => s.trim()).filter((s) => s.length > 0);
    }
    if (targetRoles.length === 0) {
        targetRoles = ["Flutter Developer", "DevOps Engineer", "Cloud Engineer"];
    }
    let targetLocations = (options === null || options === void 0 ? void 0 : options.locations) || autoApplySettings.locations || [
        "Bengaluru",
        "India",
        "Remote"
    ];
    if (typeof targetLocations === 'string') {
        targetLocations = targetLocations.split(',').map((s) => s.trim()).filter((s) => s.length > 0);
    }
    if (targetLocations.length === 0) {
        targetLocations = ["Bengaluru", "India", "Remote"];
    }
    const maxApplyLimit = (options === null || options === void 0 ? void 0 : options.maxApplications) || autoApplySettings.maxPerRun || 4;
    // Fetch previously applied emails/companies to avoid duplicate applications
    const existingAppsSnap = await firebase_1.db.collection("users").doc(uid).collection("job_applications").get();
    const appliedEmails = new Set();
    const appliedCompanyRoles = new Set();
    existingAppsSnap.forEach((doc) => {
        const d = doc.data();
        if (d.recipientEmail) {
            appliedEmails.add(d.recipientEmail.toLowerCase().trim());
        }
        if (d.companyName && d.jobTitle) {
            appliedCompanyRoles.add(`${d.companyName.toLowerCase().trim()}|${d.jobTitle.toLowerCase().trim()}`);
        }
    });
    // Fetch Gemini API Key
    const configDoc = await firebase_1.db.collection("admin_creds").doc("gemini_config").get();
    let apiKey = "";
    if (configDoc.exists) {
        apiKey = ((_a = configDoc.data()) === null || _a === void 0 ? void 0 : _a.apiKey) || "";
    }
    if (!apiKey) {
        throw new Error("Gemini API key is not configured in admin_creds.");
    }
    const rolesQuery = targetRoles.join(" OR ");
    const locQuery = targetLocations.join(" OR ");
    const todayStr = moment().tz("Asia/Kolkata").format("YYYY-MM-DD");
    const prompt = `You are an elite automated job discovery and recruiter outreach AI agent.
Target Roles: ${rolesQuery}
Locations: ${locQuery}
Candidate Name: "${applicantName}"
Candidate Experience Level: ~1.5 Years Experience (Seeking 0 to 3 Years Experience / Junior / Associate / Mid-level roles).

CRITICAL SEARCH & EXTRACTION MANDATES:
1. Use Google Search grounding to discover active, recent (past 24-72 hours) job openings, recruiter hiring updates, and posts from LinkedIn public posts, Wellfound/AngelList, Cutshort, Y Combinator, and tech company career pages.
2. RECRUITER EMAIL IS MANDATORY: Every single job item MUST contain a verified recruiter / HR / hiring contact email address (e.g. hr@company.com, careers@company.com, hiring@company.com, jobs@company.com, talent@company.com, or specific recruiter email). If NO valid email address is mentioned in the job posting/snippet, DO NOT INCLUDE THAT JOB.
3. EXPERIENCE REQUIREMENT (0 TO 3 YEARS ONLY): The candidate has ~1.5 years experience. ONLY include roles requiring 0 to 3 years experience (Freshers, Junior, Associate, 1-2 years, 1-3 years). EXCLUDE any roles requiring > 3 years experience (Senior, Lead, Staff, Principal, 5+ years).
4. HUMAN-WRITTEN, HIGH-CONVERTING APPLICATION EMAIL:
   - For each matching job, write a highly authentic, natural, and engaging cover letter.
   - Read the candidate's attached Resume PDF to extract concrete accomplishments, technical skills (e.g., Flutter, Dart, State Management, REST APIs, Firebase, Cloud/DevOps, Docker, CI/CD), and align them specifically with the company's domain and job requirements.
   - Structure:
     a) Enthusiastic opening identifying the specific role and company.
     b) Value Proposition: Clear explanation of what direct value and expertise the candidate brings based on real resume highlights.
     c) Key Relevant Skills: 3-4 bullet points matching the exact requirements of the job.
     d) Professional closing & Call to Action proposing a brief discussion, mentioning the attached resume.
     e) Sign-off: "Sincerely,\\n${applicantName}" (Never use placeholders like [Your Name]).
   - Subject line format: "Application for [Job Title] - ${applicantName} (1.5 Yrs Exp)"

Respond ONLY with a JSON array matching this schema:
[
  {
    "jobTitle": "string",
    "companyName": "string",
    "recipientEmail": "string (MUST be a valid email address)",
    "location": "string",
    "experienceRequired": "string (e.g. 0-2 years, 1-3 years)",
    "sourcePlatform": "string (e.g. LinkedIn, Wellfound, Google Jobs, Company Careers)",
    "sourceUrl": "string",
    "keySkills": ["string"],
    "generatedSubject": "string",
    "generatedCoverLetter": "string"
  }
]
If no matching jobs with verified emails and 0-3 years experience are found, respond with an empty JSON array: [].`;
    const inlineParts = [];
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
        tools: [
            {
                google_search: {}
            }
        ]
    };
    console.log(`[JobDiscovery] Running Gemini Search Grounding for user ${uid} (Roles: ${targetRoles.join(', ')})...`);
    const response = await axios_1.default.post(url, payload, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 240000
    });
    const candidates = (_b = response.data) === null || _b === void 0 ? void 0 : _b.candidates;
    if (!candidates || candidates.length === 0) {
        return { success: true, appliedCount: 0, jobs: [], message: "No search candidates returned." };
    }
    const rawText = ((_e = (_d = (_c = candidates[0].content) === null || _c === void 0 ? void 0 : _c.parts) === null || _d === void 0 ? void 0 : _d[0]) === null || _e === void 0 ? void 0 : _e.text) || "";
    if (!rawText) {
        return { success: true, appliedCount: 0, jobs: [], message: "Empty response from search agent." };
    }
    // Extract JSON from response
    let discoveredJobs = [];
    try {
        const jsonMatch = rawText.match(/\[[\s\S]*\]/);
        if (jsonMatch) {
            discoveredJobs = JSON.parse(jsonMatch[0]);
        }
        else {
            discoveredJobs = JSON.parse(rawText);
        }
    }
    catch (parseErr) {
        console.error("[JobDiscovery] Failed to parse JSON from search result:", parseErr, rawText);
        return { success: false, appliedCount: 0, jobs: [], message: "Failed to parse AI job discoveries." };
    }
    if (!Array.isArray(discoveredJobs) || discoveredJobs.length === 0) {
        console.log(`[JobDiscovery] 0 matching jobs found with recruiter emails for user ${uid}.`);
        return { success: true, appliedCount: 0, jobs: [], message: "No fresh matching openings with recruiter emails found today." };
    }
    // Filter valid jobs
    const validFilteredJobs = [];
    for (const job of discoveredJobs) {
        const email = (job.recipientEmail || '').trim();
        if (!isValidEmail(email)) {
            console.log(`[JobDiscovery] Skipping job at '${job.companyName}' due to invalid/missing email: '${email}'`);
            continue;
        }
        const emailLower = email.toLowerCase();
        const compRoleKey = `${(job.companyName || '').toLowerCase().trim()}|${(job.jobTitle || '').toLowerCase().trim()}`;
        if (appliedEmails.has(emailLower) || appliedCompanyRoles.has(compRoleKey)) {
            console.log(`[JobDiscovery] Skipping duplicate application to ${emailLower} (${job.companyName})`);
            continue;
        }
        validFilteredJobs.push(job);
        if (validFilteredJobs.length >= maxApplyLimit) {
            break;
        }
    }
    if (validFilteredJobs.length === 0) {
        console.log(`[JobDiscovery] All discovered jobs were either duplicates or lacked valid emails.`);
        return { success: true, appliedCount: 0, jobs: [], message: "Discovered openings were already applied to previously." };
    }
    // Initialize Nodemailer transporter with user's Gmail App Password
    const cleanPassword = appPassword.replace(/\s+/g, '');
    const transporter = nodemailer.createTransport({
        service: 'gmail',
        auth: {
            user: userEmail,
            pass: cleanPassword
        }
    });
    const cleanPdfB64 = resumeBase64.replace(/^data:application\/pdf;base64,/, '');
    const attachments = [
        {
            filename: resumeFileName,
            content: Buffer.from(cleanPdfB64, 'base64'),
            contentType: 'application/pdf'
        }
    ];
    const successfullyAppliedJobs = [];
    for (const job of validFilteredJobs) {
        try {
            const mailOptions = {
                from: `"${applicantName}" <${userEmail}>`,
                to: job.recipientEmail.trim(),
                subject: job.generatedSubject || `Application for ${job.jobTitle} - ${applicantName}`,
                text: job.generatedCoverLetter,
                attachments: attachments
            };
            const info = await transporter.sendMail(mailOptions);
            console.log(`[JobDiscovery] Emailed application for '${job.jobTitle}' at '${job.companyName}' (${job.recipientEmail}): ${info.messageId}`);
            const applicationRecord = {
                jobTitle: job.jobTitle,
                companyName: job.companyName,
                recipientEmail: job.recipientEmail.trim(),
                location: job.location || "India",
                experienceRequired: job.experienceRequired || "0-3 Years",
                sourcePlatform: job.sourcePlatform || "LinkedIn / Search",
                sourceUrl: job.sourceUrl || "",
                subject: job.generatedSubject,
                coverLetter: job.generatedCoverLetter,
                appliedAt: firebase_1.admin.firestore.FieldValue.serverTimestamp(),
                status: "sent",
                messageId: info.messageId || "",
                isAutoApplied: true,
                appliedDateStr: todayStr
            };
            const appDocRef = await firebase_1.db.collection("users").doc(uid).collection("job_applications").add(applicationRecord);
            appliedEmails.add(job.recipientEmail.toLowerCase().trim());
            successfullyAppliedJobs.push(Object.assign({ id: appDocRef.id }, applicationRecord));
        }
        catch (mailErr) {
            console.error(`[JobDiscovery] Failed sending email to ${job.recipientEmail}:`, mailErr);
        }
    }
    // Send push notification if applications were sent
    if (successfullyAppliedJobs.length > 0) {
        try {
            const userTokenDoc = await firebase_1.db.collection("usernames").where("uid", "==", uid).limit(1).get();
            if (!userTokenDoc.empty) {
                const fcmToken = (_f = userTokenDoc.docs[0].data()) === null || _f === void 0 ? void 0 : _f.fcmToken;
                if (fcmToken) {
                    const compNames = successfullyAppliedJobs.map(j => j.companyName).filter(Boolean).slice(0, 3).join(', ');
                    const notifTitle = `🚀 Auto-Applied to ${successfullyAppliedJobs.length} New Job${successfullyAppliedJobs.length > 1 ? 's' : ''}!`;
                    const notifBody = `Sent tailored resumes & cover letters to: ${compNames}. Tap to view sent applications.`;
                    await firebase_1.admin.messaging().send({
                        token: fcmToken,
                        notification: {
                            title: notifTitle,
                            body: notifBody
                        },
                        android: {
                            notification: {
                                channelId: "job_assistant_channel",
                                tag: `job_assistant_${Date.now()}`
                            }
                        },
                        data: {
                            type: "JOB_ASSISTANT",
                            appliedCount: String(successfullyAppliedJobs.length)
                        }
                    });
                    await (0, logger_1.logNotification)(uid, notifTitle, notifBody, "JOB_ASSISTANT");
                }
            }
        }
        catch (notifErr) {
            console.error("[JobDiscovery] Failed to dispatch push notification:", notifErr);
        }
    }
    return {
        success: true,
        appliedCount: successfullyAppliedJobs.length,
        jobs: successfullyAppliedJobs,
        message: `Successfully auto-applied to ${successfullyAppliedJobs.length} matching job(s).`
    };
}
/**
 * Scheduled Master Runner: Runs twice daily at 10:00 AM & 10:00 PM IST
 */
async function internalAutoJobDiscoveryAndApply() {
    var _a, _b;
    console.log("[internalAutoJobDiscoveryAndApply] Starting twice-daily automated job discovery & apply cycle...");
    try {
        const usersSnap = await firebase_1.db.collection("users").get();
        for (const doc of usersSnap.docs) {
            const uid = doc.id;
            const data = doc.data() || {};
            const enabledModules = data.enabledModules || [];
            // Check if job_assistant is enabled for this user and autoApply is not explicitly disabled
            if (enabledModules.includes("job_assistant") || ((_a = data.autoApplySettings) === null || _a === void 0 ? void 0 : _a.enabled) === true) {
                if (((_b = data.autoApplySettings) === null || _b === void 0 ? void 0 : _b.enabled) === false) {
                    console.log(`[internalAutoJobDiscoveryAndApply] User ${uid} disabled autoApply. Skipping.`);
                    continue;
                }
                try {
                    await discoverAndApplyForUser(uid, { isManualTrigger: false });
                }
                catch (userErr) {
                    console.error(`[internalAutoJobDiscoveryAndApply] Error processing user ${uid}:`, userErr);
                }
            }
        }
        console.log("[internalAutoJobDiscoveryAndApply] Completed automated job discovery & apply cycle.");
    }
    catch (err) {
        console.error("[internalAutoJobDiscoveryAndApply] Error in scheduled job runner:", err);
    }
}
/**
 * On-Demand HTTPS Callable Function triggered from Flutter App
 */
exports.triggerAutoJobDiscoveryAndApply = functions.runWith({ timeoutSeconds: 300, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    const uid = context.auth.uid;
    try {
        const result = await discoverAndApplyForUser(uid, {
            targetRoles: data.targetRoles,
            locations: data.locations,
            maxApplications: data.maxApplications || 4,
            isManualTrigger: true
        });
        return result;
    }
    catch (error) {
        console.error(`triggerAutoJobDiscoveryAndApply failed for ${uid}:`, error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to discover and apply to jobs.');
    }
});
//# sourceMappingURL=jobDiscoveryAI.js.map