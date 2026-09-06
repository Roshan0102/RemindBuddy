"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.triggerAutoJobDiscoveryAndApply = exports.processAutoApplyUserTask = void 0;
exports.getBestMatchingResumeProfile = getBestMatchingResumeProfile;
exports.discoverAndApplyForUser = discoverAndApplyForUser;
exports.internalAutoJobDiscoveryAndApply = internalAutoJobDiscoveryAndApply;
const functions = require("firebase-functions");
const nodemailer = require("nodemailer");
const moment = require("moment-timezone");
const dns = require("dns");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
const geminiHelper_1 = require("../../utils/geminiHelper");
const tavilyHelper_1 = require("../../utils/tavilyHelper");
const cloudTasksHelper_1 = require("../../utils/cloudTasksHelper");
/**
 * Helper to validate email strings
 */
function isValidEmail(email) {
    if (!email || typeof email !== 'string')
        return false;
    const clean = email.trim();
    const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
    // Filter out common dummy or invalid placeholder emails
    if (clean.includes('example.com') || clean.includes('yourcompany.com') || clean.includes('test.com') || clean.includes('dummy') || clean.includes('sample.com')) {
        return false;
    }
    return emailRegex.test(clean);
}
/**
 * Verifies that the recipient email's domain has valid MX (Mail Exchange) DNS records
 * to prevent bounced/undeliverable emails ("address not found").
 */
async function verifyEmailDomainMx(email) {
    var _a;
    try {
        const domain = (_a = email.split('@')[1]) === null || _a === void 0 ? void 0 : _a.trim();
        if (!domain)
            return false;
        const records = await dns.promises.resolveMx(domain);
        return records && records.length > 0;
    }
    catch (e) {
        console.warn(`[JobDiscovery] MX DNS validation failed for domain in '${email}':`, e);
        return false;
    }
}
/**
 * Intelligently matches a discovered job role & skills to the best candidate resume profile.
 * Defaults to isDefault profile if no specific match is found.
 */
function getBestMatchingResumeProfile(jobTitle, keySkills, profiles) {
    if (!profiles || profiles.length === 0) {
        return {
            id: "master_resume",
            title: "Master Resume",
            targetRoles: [],
            fileName: "Resume.pdf",
            base64: "",
            isDefault: true
        };
    }
    if (profiles.length === 1) {
        return profiles[0];
    }
    const defaultProfile = profiles.find(p => p.isDefault) || profiles[0];
    const cleanJobTitle = (jobTitle || "").toLowerCase();
    const skillsList = (keySkills || []).map(s => s.toLowerCase());
    let bestScore = -1;
    let bestProfile = defaultProfile;
    for (const profile of profiles) {
        let score = 0;
        const profileTitle = profile.title.toLowerCase();
        // Exact / substring title match
        if (cleanJobTitle.includes(profileTitle) || profileTitle.includes(cleanJobTitle)) {
            score += 5;
        }
        // Check target roles configured on this profile
        for (const role of profile.targetRoles) {
            const rLower = role.toLowerCase().trim();
            if (!rLower)
                continue;
            if (cleanJobTitle.includes(rLower) || rLower.includes(cleanJobTitle)) {
                score += 6;
            }
            else {
                // Word level overlap
                const roleWords = rLower.split(/\s+/).filter(w => w.length > 2);
                for (const w of roleWords) {
                    if (cleanJobTitle.includes(w)) {
                        score += 2;
                    }
                }
            }
        }
        // Check key skills overlap
        for (const skill of skillsList) {
            if (!skill)
                continue;
            if (profile.targetRoles.some(r => r.toLowerCase().includes(skill))) {
                score += 2;
            }
            if (profileTitle.includes(skill)) {
                score += 2;
            }
        }
        // Give a slight tie-breaker bump to default profile
        if (profile.isDefault) {
            score += 0.5;
        }
        if (score > bestScore) {
            bestScore = score;
            bestProfile = profile;
        }
    }
    return bestProfile;
}
async function discoverAndApplyForUser(uid, options) {
    var _a, _b, _c, _d;
    const userDoc = await firebase_1.db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
        return { success: false, appliedCount: 0, jobs: [], message: "User not found" };
    }
    const userData = userDoc.data() || {};
    const emailConfig = userData.emailConfig || {};
    const userEmail = emailConfig.email;
    const appPassword = emailConfig.appPassword;
    const applicantName = userData.displayName || "Roshan J";
    if (!userEmail || !appPassword) {
        console.log(`[JobDiscovery] User ${uid} has not configured Gmail/App Password. Skipping.`);
        return { success: false, appliedCount: 0, jobs: [], message: "Gmail & App Password not configured in Job Assistant Settings." };
    }
    // Load Multi-Resume Profiles (with fallback to masterResume)
    const resumeProfiles = [];
    try {
        const profilesSnap = await firebase_1.db.collection("users").doc(uid).collection("resume_profiles").get();
        profilesSnap.forEach((doc) => {
            const p = doc.data() || {};
            if (p.base64) {
                resumeProfiles.push({
                    id: doc.id,
                    title: (p.title || p.name || "Targeted Resume").toString(),
                    targetRoles: Array.isArray(p.targetRoles)
                        ? p.targetRoles.map((s) => s.toString().trim()).filter(Boolean)
                        : (typeof p.targetRoles === 'string' ? p.targetRoles.split(',').map((s) => s.trim()).filter(Boolean) : []),
                    fileName: (p.fileName || "Resume.pdf").toString(),
                    base64: p.base64.toString(),
                    isDefault: p.isDefault === true
                });
            }
        });
    }
    catch (profErr) {
        console.warn(`[JobDiscovery] Could not load resume_profiles for ${uid}:`, profErr.message);
    }
    const masterResume = userData.masterResume || {};
    const resumeBase64 = masterResume.base64;
    const resumeFileName = masterResume.fileName || "Resume.pdf";
    if (resumeProfiles.length === 0 && resumeBase64) {
        resumeProfiles.push({
            id: "master_resume",
            title: "Master Resume",
            targetRoles: ["Flutter Developer", "DevOps Engineer", "Cloud Engineer"],
            fileName: resumeFileName,
            base64: resumeBase64,
            isDefault: true
        });
    }
    if (resumeProfiles.length === 0) {
        console.log(`[JobDiscovery] User ${uid} has not uploaded any resumes. Skipping.`);
        return { success: false, appliedCount: 0, jobs: [], message: "Please upload your resume PDF in Job Assistant Settings." };
    }
    // Record jobsLastRan timestamp immediately
    await firebase_1.db.collection("users").doc(uid).set({
        jobsLastRan: firebase_1.admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
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
    // Resolve excluded companies / agencies (Blacklist)
    let excludedCompanies = (options === null || options === void 0 ? void 0 : options.excludedCompanies) || autoApplySettings.excludedCompanies || [];
    if (typeof excludedCompanies === 'string') {
        excludedCompanies = excludedCompanies.split(',').map((s) => s.trim()).filter((s) => s.length > 0);
    }
    const minExp = (options === null || options === void 0 ? void 0 : options.minExpYears) !== undefined ? Number(options.minExpYears) : Number((_a = autoApplySettings.minExpYears) !== null && _a !== void 0 ? _a : 0);
    const maxExp = (options === null || options === void 0 ? void 0 : options.maxExpYears) !== undefined ? Number(options.maxExpYears) : Number((_b = autoApplySettings.maxExpYears) !== null && _b !== void 0 ? _b : 3);
    const maxApplyLimit = (options === null || options === void 0 ? void 0 : options.maxApplications) || autoApplySettings.maxPerRun || 6;
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
    // Fetch User BYOK API Keys from user document
    const userApiKeys = userData.userApiKeys || {};
    const userTavilyKey = (userApiKeys.tavilyApiKey || userData.tavilyApiKey || "").trim();
    const userGeminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();
    if (!userTavilyKey || !userGeminiKey) {
        console.log(`[JobDiscovery] User ${uid} has not configured their personal Tavily and Gemini API keys in Settings. Skipping.`);
        return {
            success: false,
            appliedCount: 0,
            jobs: [],
            message: "Please configure your free Tavily & Gemini API keys in Settings -> AI & Search Keys."
        };
    }
    const formattedRolesList = targetRoles.map((role, idx) => `   ${idx + 1}. "${role}"`).join("\n");
    const locQuery = targetLocations.map(l => `"${l}"`).join(" OR ");
    const todayStr = moment().tz("Asia/Kolkata").format("YYYY-MM-DD");
    const currentYear = moment().tz("Asia/Kolkata").format("YYYY");
    const isFresherCandidate = (minExp === 0 && maxExp === 0);
    const expTargetStr = isFresherCandidate
        ? "Seeking FRESHER / ENTRY-LEVEL / 0 YEARS EXPERIENCE roles ONLY."
        : `Seeking ${minExp} to ${maxExp} Years Experience / Junior / Associate / Mid-level roles.`;
    const expMandateStr = isFresherCandidate
        ? "3. EXPERIENCE REQUIREMENT (FRESHERS / 0 YEARS ONLY): ONLY include openings explicitly accepting Freshers, Entry-Level candidates, Trainees, or 0 Years Experience. STRICTLY EXCLUDE any roles requiring > 0 years prior work experience."
        : `3. EXPERIENCE REQUIREMENT (${minExp} TO ${maxExp} YEARS ONLY): ONLY include roles requiring between ${minExp} and ${maxExp} years experience (or Freshers/Entry-level if min is 0). EXCLUDE any roles requiring > ${maxExp} years experience (e.g. Senior, Lead, Staff, Principal).`;
    // 1. Perform intelligent multi-query web search via Tavily for each target role
    const allTavilyResults = [];
    const seenUrls = new Set();
    for (const role of targetRoles.slice(0, 4)) {
        try {
            const expQuery = isFresherCandidate
                ? '("fresher" OR "entry level" OR "trainee" OR "0 years")'
                : (minExp === 0
                    ? `("0-${maxExp} years" OR "fresher" OR "junior")`
                    : `("${minExp}-${maxExp} years")`);
            const query = `"${role}" ${expQuery} ("send resume to" OR "share your resume at" OR "email CV to" OR "send CV to" OR "mail your resume") "@" (${locQuery}) ${currentYear}`;
            console.log(`[JobDiscovery] Querying Tavily for user ${uid} (Role: "${role}")...`);
            const tavilyResp = await (0, tavilyHelper_1.searchTavily)({
                apiKey: userTavilyKey,
                query,
                searchDepth: "advanced",
                maxResults: 5
            });
            for (const item of tavilyResp.results) {
                if (item.url && !seenUrls.has(item.url)) {
                    seenUrls.add(item.url);
                    allTavilyResults.push(item);
                }
            }
        }
        catch (tavilyErr) {
            console.warn(`[JobDiscovery] Tavily search error for role "${role}":`, tavilyErr.message);
        }
    }
    if (allTavilyResults.length === 0) {
        console.log(`[JobDiscovery] No search results returned from Tavily for user ${uid}.`);
        return { success: true, appliedCount: 0, jobs: [], message: "No fresh matching job postings with recruiter emails found." };
    }
    const searchResultsSummary = allTavilyResults.map((r, i) => `[Live Job Post ${i + 1}]\nTitle: ${r.title}\nSource: ${r.url}\nPost Details: ${r.content}`).join("\n\n");
    const prompt = `You are an elite automated job discovery and recruiter outreach AI agent.
Below are real-time, live web search results for open job postings and recruiter hiring calls:

${searchResultsSummary}

Target Roles to Search:
${formattedRolesList}

Target Locations: ${targetLocations.join(', ')}
Candidate Name: "${applicantName}"
Candidate Experience Target: ${expTargetStr}

CRITICAL VERIFICATION & EXTRACTION MANDATES:
1. RECRUITER EMAIL IS MANDATORY: Every single job item MUST contain a verified recruiter / HR / hiring contact email address (e.g. hr@company.com, careers@company.com, hiring@company.com, jobs@company.com, talent@company.com, or specific recruiter email) found in the post snippet or source. If NO valid email address is present in the post details, DO NOT INCLUDE THAT JOB.

2. ${expMandateStr}

3. HUMAN-WRITTEN, HIGH-CONVERTING APPLICATION EMAIL:
   - For each matching job, write a highly authentic, natural, and engaging cover letter tailored specifically to that job title and company.
   - Read the candidate's attached Resume PDF to extract concrete accomplishments, technical skills (e.g., Flutter, Dart, State Management, REST APIs, Firebase, Cloud/DevOps, Docker, CI/CD), and align them specifically with the company's domain and job requirements.
   - Structure:
     a) Enthusiastic opening identifying the specific role and company.
     b) Value Proposition: Clear explanation of what direct value and expertise the candidate brings based on real resume highlights.
     c) Key Relevant Skills: 3-4 bullet points matching the exact requirements of the job.
     d) Professional closing & Call to Action proposing a brief discussion, mentioning the attached resume.
     e) Sign-off: "Sincerely,\\n${applicantName}" (Never use placeholders like [Your Name]).
   - Subject line format: "Application for [Job Title] - ${applicantName}"

4. LOCATION & WORK MODE MATCHING:
   - Match On-Site/Hybrid roles in target Indian cities/India AND Remote/WFH openings when specified.

${excludedCompanies.length > 0 ? `5. EXCLUDED COMPANIES & AGENCIES BLACKLIST:
   - STRICTLY DO NOT return any openings from these excluded companies, consultancies, or agencies: ${excludedCompanies.map(c => `"${c}"`).join(", ")}. If an opening is with any of these employers/agencies, SKIP IT COMPLETELY.\n` : ""}
Respond ONLY with a JSON array matching this schema:
[
  {
    "jobTitle": "string",
    "companyName": "string",
    "recipientEmail": "string (MUST be a valid email address)",
    "location": "string",
    "experienceRequired": "string (e.g. ${minExp}-${maxExp} years)",
    "sourcePlatform": "string (e.g. LinkedIn, Company Careers, Indeed, Glassdoor)",
    "sourceUrl": "string",
    "keySkills": ["string"],
    "generatedSubject": "string",
    "generatedCoverLetter": "string"
  }
]
If no matching jobs with verified emails and ${minExp}-${maxExp} years experience are found, respond with an empty JSON array: [].`;
    const inlineParts = [];
    const promptResumeB64 = ((_c = (resumeProfiles.find(p => p.isDefault) || resumeProfiles[0])) === null || _c === void 0 ? void 0 : _c.base64) || resumeBase64;
    if (promptResumeB64) {
        const cleanResumeB64 = promptResumeB64.replace(/^data:application\/pdf;base64,/, '');
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
        ]
    };
    console.log(`[JobDiscovery] Analyzing Tavily search results with Gemini 3.7 Flash for user ${uid} (Roles: ${targetRoles.join(', ')})...`);
    let rawText = "";
    let modelUsed = "";
    try {
        const geminiResult = await (0, geminiHelper_1.callGeminiAPI)(payload, { apiKey: userGeminiKey, timeout: 120000 });
        rawText = geminiResult.text || "";
        modelUsed = geminiResult.modelUsed || "";
    }
    catch (apiErr) {
        console.error("[JobDiscovery] Gemini analysis failed:", apiErr.message);
        return { success: false, appliedCount: 0, jobs: [], message: `Job Search AI temporarily busy: ${apiErr.message}` };
    }
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
    // Filter valid jobs with active MX record validation
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
        // Check configurable excluded companies / recruitment consultancies blacklist
        if (excludedCompanies.length > 0) {
            const compLower = (job.companyName || '').toLowerCase().trim();
            const emailDomainLower = (emailLower.split('@')[1] || '').trim();
            const isExcluded = excludedCompanies.some(ex => {
                const exLower = ex.toLowerCase().trim();
                if (!exLower)
                    return false;
                return compLower.includes(exLower) || emailDomainLower.includes(exLower);
            });
            if (isExcluded) {
                console.log(`[JobDiscovery] Skipping job at '${job.companyName}' (${email}) matching excluded companies blacklist.`);
                continue;
            }
        }
        // Verify that the email domain actually has live MX mail exchange servers
        const hasValidMx = await verifyEmailDomainMx(email);
        if (!hasValidMx) {
            console.log(`[JobDiscovery] Skipping job at '${job.companyName}' because domain '${email}' has no valid MX records (dead/unreachable email domain).`);
            continue;
        }
        validFilteredJobs.push(job);
        if (validFilteredJobs.length >= maxApplyLimit) {
            break;
        }
    }
    if (validFilteredJobs.length === 0) {
        console.log(`[JobDiscovery] All discovered jobs were either duplicates, lacked valid emails, matched excluded blacklist, or had unreachable domains.`);
        return { success: true, appliedCount: 0, jobs: [], message: "Discovered openings were excluded, already applied to, or had unreachable domains." };
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
    const successfullyAppliedJobs = [];
    for (const job of validFilteredJobs) {
        try {
            // Determine best matching resume profile for this specific job role & skills
            const matchedProfile = getBestMatchingResumeProfile(job.jobTitle, job.keySkills, resumeProfiles);
            console.log(`[JobDiscovery] Matched resume profile '${matchedProfile.title}' for role '${job.jobTitle}' at '${job.companyName}'`);
            const cleanPdfB64 = (matchedProfile.base64 || resumeBase64 || "").replace(/^data:application\/pdf;base64,/, '');
            const jobAttachments = cleanPdfB64 ? [
                {
                    filename: matchedProfile.fileName || resumeFileName || "Resume.pdf",
                    content: Buffer.from(cleanPdfB64, 'base64'),
                    contentType: 'application/pdf'
                }
            ] : [];
            const mailOptions = {
                from: `"${applicantName}" <${userEmail}>`,
                to: job.recipientEmail.trim(),
                subject: job.generatedSubject || `Application for ${job.jobTitle} - ${applicantName}`,
                text: job.generatedCoverLetter,
                attachments: jobAttachments
            };
            const info = await transporter.sendMail(mailOptions);
            console.log(`[JobDiscovery] Emailed application for '${job.jobTitle}' at '${job.companyName}' (${job.recipientEmail}) with profile '${matchedProfile.title}': ${info.messageId}`);
            const applicationRecord = {
                jobTitle: job.jobTitle,
                companyName: job.companyName,
                recipientEmail: job.recipientEmail.trim(),
                location: job.location || "India",
                experienceRequired: job.experienceRequired || "0-3 Years",
                sourcePlatform: job.sourcePlatform || "LinkedIn / Search",
                sourceUrl: job.sourceUrl || "",
                subject: job.generatedSubject,
                generatedSubject: job.generatedSubject,
                coverLetter: job.generatedCoverLetter,
                generatedCoverLetter: job.generatedCoverLetter,
                appliedAt: firebase_1.admin.firestore.FieldValue.serverTimestamp(),
                status: "sent",
                messageId: info.messageId || "",
                isAutoApplied: true,
                appliedDateStr: todayStr,
                modelUsed: modelUsed || "gemini-3.7-flash",
                resumeProfileName: matchedProfile.title
            };
            const appDocRef = await firebase_1.db.collection("users").doc(uid).collection("job_applications").add(applicationRecord);
            appliedEmails.add(job.recipientEmail.toLowerCase().trim());
            successfullyAppliedJobs.push(Object.assign({ id: appDocRef.id }, applicationRecord));
        }
        catch (mailErr) {
            console.error(`[JobDiscovery] Failed sending email to ${job.recipientEmail}:`, mailErr);
        }
    }
    // Record jobsLastRan and jobsLastApplied on user document
    const userDocUpdate = {
        jobsLastRan: firebase_1.admin.firestore.FieldValue.serverTimestamp()
    };
    if (successfullyAppliedJobs.length > 0) {
        userDocUpdate.jobsLastApplied = firebase_1.admin.firestore.FieldValue.serverTimestamp();
    }
    await firebase_1.db.collection("users").doc(uid).set(userDocUpdate, { merge: true });
    // Send push notification if applications were sent
    if (successfullyAppliedJobs.length > 0) {
        try {
            const userTokenDoc = await firebase_1.db.collection("usernames").where("uid", "==", uid).limit(1).get();
            if (!userTokenDoc.empty) {
                const fcmToken = (_d = userTokenDoc.docs[0].data()) === null || _d === void 0 ? void 0 : _d.fcmToken;
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
        // Send confirmation summary email to the user's Gmail if enabled
        const notifPrefs = userData.notificationPreferences || {};
        const isEmailEnabled = notifPrefs.job_assistant_email !== false;
        if (isEmailEnabled) {
            try {
                const mailSummaryList = successfullyAppliedJobs.map(j => `<li style="margin-bottom: 10px;"><strong>${j.jobTitle}</strong> at <strong>${j.companyName}</strong> (${j.recipientEmail})<br><span style="color: #4F46E5; font-size: 12px; font-weight: bold;">📄 Attached Resume: ${j.resumeProfileName || 'Master Resume'}</span><br><span style="color: #6B7280; font-size: 12px;">Subject: ${j.generatedSubject || j.subject}</span></li>`).join('');
                await transporter.sendMail({
                    from: `"RemindBuddy Auto Apply" <${userEmail}>`,
                    to: userEmail,
                    subject: `🚀 [RemindBuddy] Auto-Applied to ${successfullyAppliedJobs.length} Job(s) (${moment().tz('Asia/Kolkata').format('hh:mm A, DD MMM')})`,
                    html: `
                        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px;">
                            <h2 style="color: #4F46E5; margin-top: 0;">Automated Job Application Summary</h2>
                            <p>Hello <strong>${applicantName}</strong>,</p>
                            <p>RemindBuddy AI Auto-Apply Agent has applied to <strong>${successfullyAppliedJobs.length}</strong> new job opening(s) with your tailored resume and cover letter:</p>
                            <ul style="padding-left: 20px;">${mailSummaryList}</ul>
                            <p style="color: #6B7280; font-size: 13px; margin-top: 24px; border-top: 1px solid #eee; padding-top: 12px;">Executed automatically via RemindBuddy scheduled Job Agent.</p>
                        </div>
                    `
                });
                console.log(`[JobDiscovery] Sent email application report to: ${userEmail}`);
            }
            catch (sumMailErr) {
                console.warn("[JobDiscovery] Could not send confirmation email to applicant:", sumMailErr.message);
            }
        }
        else {
            console.log(`[JobDiscovery] Skipping summary email to ${userEmail}: job_assistant_email is disabled in preferences.`);
        }
    }
    // Automatically check inbox for new recruiter/founder replies after finishing application task
    try {
        const { checkUserJobReplies } = await Promise.resolve().then(() => require("./replyTracker"));
        console.log(`[JobDiscovery] Automatically scanning inbox for recruiter/founder replies for user ${uid}...`);
        await checkUserJobReplies(uid);
    }
    catch (inboxErr) {
        console.warn(`[JobDiscovery] Post-task inbox check error for user ${uid}:`, inboxErr.message || inboxErr);
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
/**
 * Cloud Tasks queue handler for isolated sequential Auto-Apply processing per user.
 * maxConcurrentDispatches: 1 guarantees strictly 1 user at a time.
 */
exports.processAutoApplyUserTask = functions.runWith({ timeoutSeconds: 300, memory: "1GB" }).tasks
    .taskQueue({
    retryConfig: { maxAttempts: 2 },
    rateLimits: { maxConcurrentDispatches: 1 },
})
    .onDispatch(async (rawPayload, context) => {
    const payload = (rawPayload && typeof rawPayload === 'object' && rawPayload.data) ? rawPayload.data : rawPayload;
    const uid = payload === null || payload === void 0 ? void 0 : payload.uid;
    if (!uid) {
        console.error("[processAutoApplyUserTask] Missing uid in payload:", rawPayload);
        return;
    }
    console.log(`[processAutoApplyUserTask] Processing automated job discovery & apply for user ${uid}`);
    try {
        const result = await discoverAndApplyForUser(uid, { isManualTrigger: false });
        console.log(`[processAutoApplyUserTask] Successfully finished auto-apply for user ${uid}:`, result);
    }
    catch (err) {
        console.error(`[processAutoApplyUserTask] Error in auto-apply for user ${uid}:`, err.message || err);
        throw err;
    }
});
/**
 * Twice-Daily Automated Job Discovery & Auto-Apply Dispatcher (10 AM & 10 PM IST)
 */
async function internalAutoJobDiscoveryAndApply() {
    var _a, _b, _c, _d, _e, _f;
    console.log("[internalAutoJobDiscoveryAndApply] Starting twice-daily automated job discovery & apply dispatcher (10 AM & 10 PM IST)...");
    try {
        const usersSnap = await firebase_1.db.collection("users").get();
        const eligibleUids = [];
        for (const doc of usersSnap.docs) {
            const uid = doc.id;
            const data = doc.data() || {};
            const enabledModules = data.enabledModules || [];
            // 1. Must have job_assistant enabled and autoApply not disabled
            const isModuleEnabled = enabledModules.includes("job_assistant") || ((_a = data.autoApplySettings) === null || _a === void 0 ? void 0 : _a.enabled) === true;
            if (!isModuleEnabled || ((_b = data.autoApplySettings) === null || _b === void 0 ? void 0 : _b.enabled) === false) {
                console.log(`[internalAutoJobDiscoveryAndApply] Skipping user ${uid}: job_assistant not enabled or autoApply disabled.`);
                continue;
            }
            // 2. Must have uploaded a Master Resume or at least one Resume Profile
            let hasResume = !!(((_c = data.masterResume) === null || _c === void 0 ? void 0 : _c.base64) || ((_d = data.masterResume) === null || _d === void 0 ? void 0 : _d.base64Data));
            if (!hasResume) {
                const profilesSnap = await firebase_1.db.collection("users").doc(uid).collection("resume_profiles").limit(1).get();
                if (!profilesSnap.empty) {
                    hasResume = true;
                }
            }
            if (!hasResume) {
                const resumeDoc = await firebase_1.db.collection("users").doc(uid).collection("job_profiles").doc("master_resume").get();
                hasResume = !!(((_e = resumeDoc.data()) === null || _e === void 0 ? void 0 : _e.base64Data) || ((_f = resumeDoc.data()) === null || _f === void 0 ? void 0 : _f.base64));
            }
            if (!hasResume) {
                console.log(`[internalAutoJobDiscoveryAndApply] Skipping user ${uid}: Master Resume or Resume Profile PDF not uploaded.`);
                continue;
            }
            // 3. Must have Gmail & App Password configured
            const emailConfig = data.emailConfig || data.jobEmailConfig || {};
            if (!emailConfig.email || !emailConfig.appPassword) {
                console.log(`[internalAutoJobDiscoveryAndApply] Skipping user ${uid}: Gmail & App Password not configured.`);
                continue;
            }
            eligibleUids.push(uid);
        }
        console.log(`[internalAutoJobDiscoveryAndApply] Found ${eligibleUids.length} eligible user(s) with configured resumes:`, eligibleUids);
        if (eligibleUids.length === 0) {
            return;
        }
        const nowUnix = moment().tz('Asia/Kolkata').unix();
        for (let i = 0; i < eligibleUids.length; i++) {
            const uid = eligibleUids[i];
            const etaUnix = nowUnix + (i * 30); // Stagger by 30s for safe AI + email throughput
            const taskId = await (0, cloudTasksHelper_1.enqueueUserCloudTask)("processAutoApplyUserTask", "processAutoApplyUserTask", { uid }, etaUnix);
            // Fallback: If Cloud Tasks queue enqueue fails, process directly with safe delay
            if (!taskId) {
                console.warn(`[internalAutoJobDiscoveryAndApply] Cloud Tasks queue unavailable for ${uid}. Running directly as fallback...`);
                try {
                    await discoverAndApplyForUser(uid, { isManualTrigger: false });
                }
                catch (e) {
                    console.error(`[internalAutoJobDiscoveryAndApply] Error in fallback execution for ${uid}:`, e.message || e);
                }
                await new Promise((r) => setTimeout(r, 5000));
            }
        }
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
            excludedCompanies: data.excludedCompanies,
            minExpYears: data.minExpYears,
            maxExpYears: data.maxExpYears,
            maxApplications: data.maxApplications || 4,
            isManualTrigger: true
        });
        if (!result.success) {
            throw new functions.https.HttpsError('failed-precondition', result.message);
        }
        return result;
    }
    catch (error) {
        console.error(`triggerAutoJobDiscoveryAndApply failed for ${uid}:`, error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', error.message || 'Failed to discover and apply to jobs.');
    }
});
//# sourceMappingURL=jobDiscoveryAI.js.map