"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.runLinkedInAutoApplyNow = void 0;
exports.processLinkedInAutoApplyForUser = processLinkedInAutoApplyForUser;
exports.internalLinkedInPostAutoApplyDispatcher = internalLinkedInPostAutoApplyDispatcher;
const functions = require("firebase-functions");
const nodemailer = require("nodemailer");
const moment = require("moment-timezone");
const firebase_1 = require("../../config/firebase");
const apifyLinkedInPosts_1 = require("./apifyLinkedInPosts");
const geminiHelper_1 = require("../../utils/geminiHelper");
const featureLogger_1 = require("../../utils/featureLogger");
const logger_1 = require("../../utils/logger");
const emailFormatter_1 = require("../../utils/emailFormatter");
function normalizeJobRole(role) {
    return (role || "").toLowerCase()
        .replace(/[^a-z0-9]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}
function isForeignOnsite(detectedLocation, targetLocations, isRemote, postContent) {
    if (isRemote)
        return false;
    if (!detectedLocation && !postContent)
        return false;
    const locText = `${detectedLocation} ${postContent}`.toLowerCase();
    const explicitOnsite = locText.includes('onsite') || locText.includes('on-site') || locText.includes('in-office') || locText.includes('in office') || locText.includes('hybrid');
    // If candidate's target locations explicitly match, it is acceptable
    const matchesTarget = targetLocations.some(tl => {
        const normTL = tl.toLowerCase().trim();
        if (!normTL)
            return false;
        if (normTL === 'remote')
            return true;
        return locText.includes(normTL);
    });
    if (matchesTarget)
        return false;
    // Known foreign indicators
    const foreignIndicators = [
        'morristown', 'new jersey', ' nj', ', nj', 'new york', ' ny', ', ny',
        'california', ' ca', ', ca', 'texas', ' tx', ', tx', 'florida', ' fl', ', fl',
        'london', 'united kingdom', ' uk', ', uk', 'canada', 'toronto', 'vancouver',
        'australia', 'sydney', 'melbourne', 'germany', 'berlin', 'munich',
        'singapore', 'dubai', 'uae', 'netherlands', 'amsterdam'
    ];
    const isForeign = foreignIndicators.some(fi => locText.includes(fi));
    if (isForeign && explicitOnsite)
        return true;
    if (isForeign && !locText.includes('remote') && !locText.includes('wfh'))
        return true;
    return false;
}
/**
 * Executes real-time LinkedIn recruiter post scraping via Apify, checks unified applied job history
 * across all Job Assistant modules (Auto-Apply, Portals, Cold Outreach), evaluates experience/role/location
 * fit with Gemini, and auto-applies via Gmail.
 */
async function processLinkedInAutoApplyForUser(uid, options) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s;
    const isManual = (_a = options === null || options === void 0 ? void 0 : options.isManual) !== null && _a !== void 0 ? _a : false;
    const scheduledSlot = isManual ? "Manual Run" : "Scheduled Run (Apify)";
    try {
        const userDoc = await firebase_1.db.collection("users").doc(uid).get();
        if (!userDoc.exists) {
            return { success: false, appliedCount: 0, message: "User profile not found.", jobs: [] };
        }
        const userData = userDoc.data() || {};
        const enabledModules = userData.enabledModules || [];
        const jobSubPerms = userData.jobAssistantSubPermissions || {};
        // 1. Admin Module Control: Must be enabled for user
        const isLinkedInEnabled = (enabledModules.includes("job_assistant") || enabledModules.includes("linkedin_auto_apply"))
            && jobSubPerms.linkedin_auto_apply !== false;
        if (!isLinkedInEnabled) {
            console.log(`[LinkedInAutoApply] User ${uid} does NOT have 'linkedin_auto_apply' module enabled by admin. Skipping.`);
            if (isManual) {
                throw new functions.https.HttpsError('permission-denied', 'LinkedIn Auto-Apply is currently disabled by administrator for your account.');
            }
            return {
                success: false,
                appliedCount: 0,
                message: "LinkedIn Auto-Apply is disabled by administrator.",
                jobs: []
            };
        }
        // 2. Gmail & App Password Check
        const emailConfig = userData.emailConfig || userData.jobEmailConfig || {};
        const userEmail = (emailConfig.email || "").trim();
        const appPassword = (emailConfig.appPassword || "").trim();
        if (!userEmail || !appPassword) {
            const msg = "Gmail & App Password not configured in Job Assistant Settings.";
            console.log(`[LinkedInAutoApply] User ${uid}: ${msg}`);
            await (0, featureLogger_1.logFeatureExecution)(uid, {
                feature: 'linkedin_auto_apply',
                featureTitle: 'LinkedIn Auto-Apply (Apify)',
                status: 'skipped',
                count: 0,
                message: msg,
                scheduledSlot,
                isManual
            });
            return { success: false, appliedCount: 0, message: msg, jobs: [] };
        }
        // 3. User Apify Tokens (Multi-Token Rotation up to 3 tokens)
        const linkedinSettings = userData.linkedinAutoApplySettings || {};
        const userApiKeys = userData.userApiKeys || {};
        const configuredTokens = [];
        if (Array.isArray(linkedinSettings.apifyTokens)) {
            for (const t of linkedinSettings.apifyTokens) {
                const s = String(t || "").trim();
                if (s && !configuredTokens.includes(s))
                    configuredTokens.push(s);
            }
        }
        if (linkedinSettings.apifyToken1)
            configuredTokens.push(String(linkedinSettings.apifyToken1).trim());
        if (linkedinSettings.apifyToken2)
            configuredTokens.push(String(linkedinSettings.apifyToken2).trim());
        if (linkedinSettings.apifyToken3)
            configuredTokens.push(String(linkedinSettings.apifyToken3).trim());
        if (userApiKeys.apifyApiKey)
            configuredTokens.push(String(userApiKeys.apifyApiKey).trim());
        if (userData.apifyApiKey)
            configuredTokens.push(String(userData.apifyApiKey).trim());
        // Deduplicate tokens
        const apifyTokens = Array.from(new Set(configuredTokens.filter(t => t.length > 5)));
        // Fallback default token from environment if user has not yet populated their own in UI
        if (apifyTokens.length === 0 && process.env.APIFY_API_KEY) {
            apifyTokens.push(process.env.APIFY_API_KEY.trim());
        }
        // 4. Target Roles, Locations & Experience Range (Limited to max 4 roles, max 5 locations)
        let targetRoles = (options === null || options === void 0 ? void 0 : options.roles) || linkedinSettings.targetRoles || ((_b = userData.autoApplySettings) === null || _b === void 0 ? void 0 : _b.targetRoles) || [];
        if (typeof targetRoles === 'string') {
            targetRoles = targetRoles.split(',').map(s => s.trim()).filter(Boolean);
        }
        if (targetRoles.length === 0) {
            targetRoles = ["DevOps Engineer", "Cloud Engineer", "Site Reliability Engineer"];
        }
        targetRoles = targetRoles.slice(0, 4);
        let targetLocations = (options === null || options === void 0 ? void 0 : options.locations) ||
            linkedinSettings.targetLocations ||
            linkedinSettings.locations ||
            ((_c = userData.autoApplySettings) === null || _c === void 0 ? void 0 : _c.locations) ||
            ((_d = userData.autoApplySettings) === null || _d === void 0 ? void 0 : _d.targetLocations) ||
            userData.targetLocations ||
            userData.locations ||
            [];
        if (typeof targetLocations === 'string') {
            targetLocations = targetLocations.split(',').map(s => s.trim()).filter(Boolean);
        }
        targetLocations = targetLocations.slice(0, 5);
        const excludedCompanies = (((_e = userData.autoApplySettings) === null || _e === void 0 ? void 0 : _e.excludedCompanies) ||
            userData.excludedCompanies ||
            linkedinSettings.excludedCompanies ||
            []).map((s) => s.trim().toLowerCase()).filter(Boolean);
        const minExp = (_j = (_g = (_f = options === null || options === void 0 ? void 0 : options.minExpYears) !== null && _f !== void 0 ? _f : linkedinSettings.minExpYears) !== null && _g !== void 0 ? _g : (_h = userData.autoApplySettings) === null || _h === void 0 ? void 0 : _h.minExpYears) !== null && _j !== void 0 ? _j : 1;
        const maxExp = (_o = (_l = (_k = options === null || options === void 0 ? void 0 : options.maxExpYears) !== null && _k !== void 0 ? _k : linkedinSettings.maxExpYears) !== null && _l !== void 0 ? _l : (_m = userData.autoApplySettings) === null || _m === void 0 ? void 0 : _m.maxExpYears) !== null && _o !== void 0 ? _o : 3;
        const experienceFilter = `${minExp}-${maxExp} years`;
        // 5. Load Candidate Resume Profile
        const resumeProfiles = [];
        try {
            const profilesSnap = await firebase_1.db.collection("users").doc(uid).collection("resume_profiles").get();
            profilesSnap.forEach((doc) => {
                const p = doc.data() || {};
                if (p.base64) {
                    resumeProfiles.push({
                        id: doc.id,
                        title: p.title || p.name || "Targeted Resume",
                        targetRoles: Array.isArray(p.targetRoles) ? p.targetRoles : [],
                        fileName: p.fileName || "Resume.pdf",
                        base64: p.base64,
                        isDefault: p.isDefault === true
                    });
                }
            });
        }
        catch (e) {
            console.warn(`[LinkedInAutoApply] Error loading resume profiles:`, e.message);
        }
        const masterResume = userData.masterResume || {};
        if (resumeProfiles.length === 0 && masterResume.base64) {
            resumeProfiles.push({
                id: "master_resume",
                title: "Master Resume",
                targetRoles: targetRoles,
                fileName: masterResume.fileName || "Resume.pdf",
                base64: masterResume.base64,
                isDefault: true
            });
        }
        if (resumeProfiles.length === 0) {
            const msg = "Please upload at least one Resume PDF in Job Assistant Settings.";
            console.log(`[LinkedInAutoApply] User ${uid}: ${msg}`);
            await (0, featureLogger_1.logFeatureExecution)(uid, {
                feature: 'linkedin_auto_apply',
                featureTitle: 'LinkedIn Auto-Apply (Apify)',
                status: 'skipped',
                count: 0,
                message: msg,
                scheduledSlot,
                isManual
            });
            return { success: false, appliedCount: 0, message: msg, jobs: [] };
        }
        // 6. Check UNIFIED APPLIED JOB HISTORY across ALL modules (job_applications, networking_leads, career_portal_jobs, system_bounced_emails)
        const appliedEmails = new Set();
        const appliedUrls = new Set();
        const appliedEmailRoles = new Set();
        // 6a. job_applications (Auto-Apply Agent & LinkedIn)
        try {
            const existingAppsSnap = await firebase_1.db.collection("users").doc(uid).collection("job_applications").get();
            existingAppsSnap.forEach((doc) => {
                const d = doc.data();
                const email = (d.recipientEmail || "").toLowerCase().trim();
                const role = normalizeJobRole(d.jobTitle || "");
                const url = (d.sourceUrl || "").toLowerCase().trim();
                if (email)
                    appliedEmails.add(email);
                if (url)
                    appliedUrls.add(url);
                if (email && role)
                    appliedEmailRoles.add(`${email}|${role}`);
            });
        }
        catch (e) {
            console.warn(`[LinkedInAutoApply] Error loading job_applications: ${e.message}`);
        }
        // 6b. networking_leads (Cold Outreach to Founders / Recruiters)
        try {
            const networkingSnap = await firebase_1.db.collection("users").doc(uid).collection("networking_leads").get();
            networkingSnap.forEach((doc) => {
                const d = doc.data();
                const email = (d.email || d.recipientEmail || "").toLowerCase().trim();
                const pUrl = (d.linkedinUrl || d.postUrl || "").toLowerCase().trim();
                if (email)
                    appliedEmails.add(email);
                if (pUrl)
                    appliedUrls.add(pUrl);
            });
        }
        catch (e) {
            console.warn(`[LinkedInAutoApply] Error loading networking_leads: ${e.message}`);
        }
        // 6c. career_portal_jobs (Career Portals ATS)
        try {
            const portalSnap = await firebase_1.db.collection("users").doc(uid).collection("career_portal_jobs").get();
            portalSnap.forEach((doc) => {
                const d = doc.data();
                const email = (d.recipientEmail || "").toLowerCase().trim();
                const jUrl = (d.jobUrl || d.applyUrl || "").toLowerCase().trim();
                if (email)
                    appliedEmails.add(email);
                if (jUrl)
                    appliedUrls.add(jUrl);
            });
        }
        catch (e) {
            console.warn(`[LinkedInAutoApply] Error loading career_portal_jobs: ${e.message}`);
        }
        // 6d. system_bounced_emails (Bounced addresses to avoid spam flags)
        try {
            const bouncedSnap = await firebase_1.db.collection("system_bounced_emails").limit(500).get();
            bouncedSnap.forEach((doc) => {
                var _a;
                const bEmail = (((_a = doc.data()) === null || _a === void 0 ? void 0 : _a.email) || doc.id || "").toLowerCase().trim();
                if (bEmail)
                    appliedEmails.add(bEmail);
            });
        }
        catch (e) {
            console.warn(`[LinkedInAutoApply] Error loading system_bounced_emails: ${e.message}`);
        }
        console.log(`[LinkedInAutoApply] User ${uid} has ${appliedEmails.size} previously contacted email(s) and ${appliedUrls.size} processed post URL(s) in unified history.`);
        // 7. Scrape Real-Time LinkedIn Posts via Apify (Multi-role & Location Filtered)
        let searchResult;
        try {
            searchResult = await (0, apifyLinkedInPosts_1.searchLinkedInPostsViaApify)({
                apiTokens: apifyTokens,
                roles: targetRoles,
                locations: targetLocations,
                experienceFilter,
                datePosted: "past-24h",
                maxPosts: 25
            });
        }
        catch (apifyErr) {
            console.error(`[LinkedInAutoApply] Apify scraping error for user ${uid}:`, apifyErr.message);
            await (0, featureLogger_1.logFeatureExecution)(uid, {
                feature: 'linkedin_auto_apply',
                featureTitle: 'LinkedIn Auto-Apply (Apify)',
                status: 'error',
                count: 0,
                message: `Apify Search Failed: ${apifyErr.message}`,
                scheduledSlot,
                isManual
            });
            return {
                success: false,
                appliedCount: 0,
                message: `Apify Search Failed: ${apifyErr.message}`,
                jobs: []
            };
        }
        const posts = searchResult.posts || [];
        console.log(`[LinkedInAutoApply] Retrieved ${posts.length} LinkedIn posts. Posts with contact emails: ${searchResult.postsWithEmails}`);
        if (posts.length === 0 || searchResult.postsWithEmails === 0) {
            const msg = "No real-time LinkedIn recruiter posts with hiring emails found in the past 24h.";
            await (0, featureLogger_1.logFeatureExecution)(uid, {
                feature: 'linkedin_auto_apply',
                featureTitle: 'LinkedIn Auto-Apply (Apify)',
                status: 'no_results',
                count: 0,
                message: msg,
                scheduledSlot,
                isManual
            });
            return { success: true, appliedCount: 0, message: msg, jobs: [] };
        }
        // 8. Filter Posts against Unified History, Blacklist & Experience Restrictions
        const candidatePosts = [];
        const seniorKeywords = ["5+ years", "6+ years", "7+ years", "8+ years", "10+ years", "minimum 5 years", "principal", "staff engineer", "engineering manager", "director"];
        for (const post of posts) {
            if (!post.hasEmail || post.emails.length === 0)
                continue;
            const postUrl = (post.url || "").toLowerCase().trim();
            if (postUrl && appliedUrls.has(postUrl)) {
                console.log(`[LinkedInAutoApply] DEDUPLICATED: Post URL ${postUrl} was already applied to previously. Skipping.`);
                continue;
            }
            const postContentLower = post.content.toLowerCase();
            // Check company blacklist / excluded companies
            if (excludedCompanies.some(comp => comp && postContentLower.includes(comp))) {
                console.log(`[LinkedInAutoApply] Skipping post ${post.id}: Mentions excluded company.`);
                continue;
            }
            // Experience sanity check: if user is 0-3 years and post asks for 5+ / 7+ / 8+ years, skip
            if (maxExp <= 4) {
                const hasHighExpRequirement = seniorKeywords.some(kw => postContentLower.includes(kw));
                if (hasHighExpRequirement) {
                    console.log(`[LinkedInAutoApply] Skipping post ${post.id}: Requires high/senior experience.`);
                    continue;
                }
            }
            for (const email of post.emails) {
                const normEmail = email.toLowerCase().trim();
                if (appliedEmails.has(normEmail)) {
                    console.log(`[LinkedInAutoApply] DEDUPLICATED: Email ${normEmail} was already contacted previously across unified modules. Skipping.`);
                    continue;
                }
                candidatePosts.push({ post, email: normEmail });
                // Only take one unique email per post to prevent multiple emails to same post
                break;
            }
        }
        console.log(`[LinkedInAutoApply] Found ${candidatePosts.length} fresh, uncontacted candidate post(s).`);
        if (candidatePosts.length === 0) {
            const msg = "All recruiter emails from the latest LinkedIn posts have already been contacted across unified history.";
            await (0, featureLogger_1.logFeatureExecution)(uid, {
                feature: 'linkedin_auto_apply',
                featureTitle: 'LinkedIn Auto-Apply (Apify)',
                status: 'success',
                count: 0,
                message: msg,
                scheduledSlot,
                isManual
            });
            return { success: true, appliedCount: 0, message: msg, jobs: [] };
        }
        // 9. Process Applications with Gemini Verification & Nodemailer Sending
        const maxPerRun = Math.min((_q = (_p = options === null || options === void 0 ? void 0 : options.maxApplications) !== null && _p !== void 0 ? _p : linkedinSettings.maxPerRun) !== null && _q !== void 0 ? _q : 5, 8);
        const postsToProcess = candidatePosts.slice(0, maxPerRun);
        let applicantName = (userData.applicantName || userData.displayName || "").trim();
        if (!applicantName) {
            try {
                const authUser = await firebase_1.admin.auth().getUser(uid);
                applicantName = authUser.displayName || ((_r = authUser.email) === null || _r === void 0 ? void 0 : _r.split('@')[0]) || "Applicant";
            }
            catch (_t) {
                applicantName = "Applicant";
            }
        }
        const cleanPassword = appPassword.replace(/\s+/g, '');
        const transporter = nodemailer.createTransport({
            service: 'gmail',
            auth: {
                user: userEmail,
                pass: cleanPassword
            }
        });
        const successfullyApplied = [];
        const todayStr = moment().tz('Asia/Kolkata').format('YYYY-MM-DD');
        for (const item of postsToProcess) {
            const { post, email: recipientEmail } = item;
            // Pick matching resume profile
            const matchedProfile = resumeProfiles.find(p => p.targetRoles.some((r) => post.content.toLowerCase().includes(r.toLowerCase()))) || resumeProfiles.find(p => p.isDefault) || resumeProfiles[0];
            // Use Gemini to verify role alignment, location & remote policy, and draft tailored cover letter
            let generatedApplication = null;
            try {
                const prompt = `You are an elite career advisor and executive recruiter.
Analyze this real-time LinkedIn recruiter hiring post:
"${post.content}"
Author: "${post.authorName}" (${post.authorTitle})

Candidate Profile:
- Name: "${applicantName}"
- Experience: ${minExp}-${maxExp} years
- Target Roles: ${targetRoles.join(', ')}
- Target Locations: ${targetLocations.length > 0 ? targetLocations.join(', ') : 'Remote / India'}
- Excluded Companies: ${excludedCompanies.length > 0 ? excludedCompanies.join(', ') : 'None'}

CRITICAL MATCHING RULES (MUST FOLLOW STRICTLY):
1. ROLE MATCH: The post must genuinely be hiring for at least one of the candidate's target roles (${targetRoles.join(', ')}).
2. EXPERIENCE FIT: Must fit within ${minExp}-${maxExp} years experience. If the post explicitly requires 5+, 6+, 7+, 8+, 10+, Senior, Lead, Staff, or Principal years and candidate has <= 4 years, set isMatch: false.
3. LOCATION & WORK MODE POLICY (CRITICAL):
   - Candidate Target Locations: ${targetLocations.length > 0 ? targetLocations.join(', ') : 'Any'}.
   - Identify the job location and work mode (Remote, Hybrid, Onsite) from the post content.
   - If the job is located in an unselected/foreign city, state, or country (e.g. USA, New Jersey, Morristown, UK, Europe, etc.):
     * It is ONLY acceptable if it is EXPLICITLY marked as REMOTE / Work From Home.
     * If it is ONSITE or HYBRID in an unselected country/city (such as Morristown NJ, Dallas TX, London, etc.), you MUST REJECT IT (set isMatch: false).
   - If the job is located in one of the candidate's target locations (${targetLocations.join(', ')}), it is acceptable whether Onsite, Hybrid, or Remote.
   - If the job is explicitly REMOTE, it is acceptable.
4. EXCLUDED COMPANIES: If the hiring company or recruitment agency matches any excluded company (${excludedCompanies.join(', ')}), set isMatch: false.
5. If rejected, set isMatch: false and provide a clear "rejectionReason".
6. If matching, extract:
   - "companyName": Name of the hiring company or recruitment agency.
   - "jobTitle": Clear title of the job matching candidate's target roles.
   - "detectedLocation": The city/country and work mode (e.g. "Bengaluru (Hybrid)", "Remote (India)", "Chennai (Onsite)").
   - "isRemote": boolean (true if work from home / remote is allowed).
   - "subject": Tailored email subject line (e.g. "Application: [Job Title] - ${applicantName}").
   - "coverLetter": A punchy, compelling 2-3 paragraph application email tailored to this post. Highlight relevant tools matching the role (e.g. AWS, Docker, Kubernetes, CI/CD, Terraform). Sign off with:
"Best regards,
${applicantName}"

Respond ONLY with valid JSON:
{
  "isMatch": boolean,
  "rejectionReason": string,
  "companyName": string,
  "jobTitle": string,
  "detectedLocation": string,
  "isRemote": boolean,
  "subject": string,
  "coverLetter": string
}`;
                const geminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();
                const geminiResp = await (0, geminiHelper_1.callGeminiAPI)({
                    apiKey: geminiKey || undefined,
                    payload: {
                        contents: [{ parts: [{ text: prompt }] }],
                        generationConfig: { responseMimeType: "application/json" }
                    }
                });
                const rawText = geminiResp.text || "{}";
                generatedApplication = JSON.parse(rawText.replace(/```json/g, '').replace(/```/g, '').trim());
            }
            catch (aiErr) {
                console.warn(`[LinkedInAutoApply] Gemini post analysis error:`, aiErr.message);
                // Fallback application format if Gemini JSON parsing fails
                generatedApplication = {
                    isMatch: true,
                    companyName: post.authorTitle || "Hiring Team",
                    jobTitle: targetRoles[0],
                    detectedLocation: targetLocations[0] || "Remote",
                    isRemote: true,
                    subject: `Application for ${targetRoles[0]} - ${applicantName}`,
                    coverLetter: `Dear Hiring Team,\n\nI am writing to express my enthusiastic interest in the ${targetRoles[0]} position shared on LinkedIn. With hands-on experience in cloud infrastructure, automation, and modern DevOps practices, I am confident in my ability to deliver immediate value.\n\nPlease find my resume attached for your consideration. I welcome the opportunity to connect and discuss how my background aligns with your team's goals.\n\nBest regards,\n${applicantName}`
                };
            }
            if (!generatedApplication || generatedApplication.isMatch === false) {
                console.log(`[LinkedInAutoApply] Rejected post ${post.id}: ${(generatedApplication === null || generatedApplication === void 0 ? void 0 : generatedApplication.rejectionReason) || 'Did not meet role/location criteria'}`);
                continue;
            }
            // Code-level safety check on location
            const detectedLoc = (generatedApplication.detectedLocation || "").trim();
            const isRemoteJob = generatedApplication.isRemote === true || post.content.toLowerCase().includes('remote') || post.content.toLowerCase().includes('wfh');
            if (isForeignOnsite(detectedLoc, targetLocations, isRemoteJob, post.content)) {
                console.log(`[LinkedInAutoApply] Safety check rejected post ${post.id}: Location "${detectedLoc}" is onsite outside target locations.`);
                continue;
            }
            const finalTitle = generatedApplication.jobTitle || targetRoles[0];
            const finalCompany = generatedApplication.companyName || post.authorName || "Hiring Partner";
            const finalSubject = generatedApplication.subject || `Application for ${finalTitle} - ${applicantName}`;
            const finalBody = generatedApplication.coverLetter;
            // Prepare attachments
            const cleanB64 = (matchedProfile.base64 || "").replace(/^data:application\/pdf;base64,/, '');
            const attachments = cleanB64 ? [{
                    filename: matchedProfile.fileName || "Resume.pdf",
                    content: Buffer.from(cleanB64, 'base64'),
                    contentType: 'application/pdf'
                }] : [];
            // Send via Nodemailer
            try {
                const formatted = (0, emailFormatter_1.formatEmailContent)(finalBody);
                const info = await transporter.sendMail({
                    from: `"${applicantName}" <${userEmail}>`,
                    to: recipientEmail,
                    subject: finalSubject,
                    text: formatted.text,
                    html: formatted.html,
                    attachments
                });
                console.log(`[LinkedInAutoApply] Application email sent to ${recipientEmail} (${finalCompany}): ${info.messageId}`);
                // Save to UNIFIED job_applications collection
                const finalLocation = detectedLoc || (isRemoteJob ? "Remote" : (targetLocations.length > 0 ? targetLocations.join(' / ') : "Remote"));
                const applicationRecord = {
                    jobTitle: finalTitle,
                    companyName: finalCompany,
                    recipientEmail: recipientEmail,
                    location: finalLocation,
                    experienceRequired: `${minExp}-${maxExp} Years`,
                    sourcePlatform: "LinkedIn Post (Apify)",
                    source: "linkedin_post_apify",
                    sourceUrl: post.url || "",
                    subject: finalSubject,
                    generatedSubject: finalSubject,
                    coverLetter: finalBody,
                    generatedCoverLetter: finalBody,
                    appliedAt: firebase_1.admin.firestore.FieldValue.serverTimestamp(),
                    status: "sent",
                    messageId: info.messageId || "",
                    isAutoApplied: true,
                    appliedDateStr: todayStr,
                    resumeProfileName: matchedProfile.title,
                    authorName: post.authorName,
                    authorTitle: post.authorTitle,
                    postExcerpt: post.content.substring(0, 300)
                };
                const docRef = await firebase_1.db.collection("users").doc(uid).collection("job_applications").add(applicationRecord);
                // Add to in-memory sets immediately to prevent any subsequent post sending duplicate
                appliedEmails.add(recipientEmail);
                if (post.url)
                    appliedUrls.add(post.url.toLowerCase().trim());
                appliedEmailRoles.add(`${recipientEmail}|${normalizeJobRole(finalTitle)}`);
                successfullyApplied.push(Object.assign({ id: docRef.id }, applicationRecord));
            }
            catch (mailErr) {
                console.error(`[LinkedInAutoApply] Error sending email to ${recipientEmail}:`, mailErr);
            }
        }
        // 10. Update User Document Timestamps
        const userUpdate = {
            linkedinAutoApplyLastRan: firebase_1.admin.firestore.FieldValue.serverTimestamp(),
            jobsLastRan: firebase_1.admin.firestore.FieldValue.serverTimestamp()
        };
        if (successfullyApplied.length > 0) {
            userUpdate.jobsLastApplied = firebase_1.admin.firestore.FieldValue.serverTimestamp();
            userUpdate.linkedinAutoApplyLastApplied = firebase_1.admin.firestore.FieldValue.serverTimestamp();
        }
        await firebase_1.db.collection("users").doc(uid).set(userUpdate, { merge: true });
        // 11. Push Notification & Feature Execution Log
        if (successfullyApplied.length > 0) {
            try {
                const userTokenDoc = await firebase_1.db.collection("usernames").where("uid", "==", uid).limit(1).get();
                if (!userTokenDoc.empty) {
                    const fcmToken = (_s = userTokenDoc.docs[0].data()) === null || _s === void 0 ? void 0 : _s.fcmToken;
                    if (fcmToken) {
                        const compNames = successfullyApplied.map(j => j.companyName).slice(0, 3).join(', ');
                        const notifTitle = `⚡ Auto-Applied to ${successfullyApplied.length} LinkedIn Post${successfullyApplied.length > 1 ? 's' : ''}!`;
                        const notifBody = `Applied to recruiter posts from: ${compNames}. Tap to view sent applications.`;
                        await firebase_1.admin.messaging().send({
                            token: fcmToken,
                            notification: { title: notifTitle, body: notifBody },
                            webpush: {
                                notification: {
                                    title: notifTitle,
                                    body: notifBody,
                                    icon: '/icons/Icon-192.png',
                                    badge: '/icons/Icon-192.png',
                                    tag: `linkedin_apply_${Date.now()}`
                                },
                                fcmOptions: { link: '/' }
                            },
                            android: {
                                notification: {
                                    channelId: "job_assistant_channel",
                                    tag: `linkedin_apply_${Date.now()}`
                                }
                            },
                            data: {
                                type: "JOB_ASSISTANT",
                                appliedCount: String(successfullyApplied.length)
                            }
                        });
                        await (0, logger_1.logNotification)(uid, notifTitle, notifBody, "JOB_ASSISTANT");
                    }
                }
            }
            catch (pushErr) {
                console.error("[LinkedInAutoApply] Push notification dispatch error:", pushErr);
            }
            await (0, featureLogger_1.logFeatureExecution)(uid, {
                feature: 'linkedin_auto_apply',
                featureTitle: 'LinkedIn Auto-Apply (Apify)',
                status: 'success',
                count: successfullyApplied.length,
                message: `Successfully applied to ${successfullyApplied.length} real-time LinkedIn recruiter post(s).`,
                scheduledSlot,
                details: successfullyApplied.map(j => `${j.jobTitle} at ${j.companyName} (${j.recipientEmail})`),
                isManual
            });
        }
        else {
            await (0, featureLogger_1.logFeatureExecution)(uid, {
                feature: 'linkedin_auto_apply',
                featureTitle: 'LinkedIn Auto-Apply (Apify)',
                status: 'no_results',
                count: 0,
                message: 'No eligible fresh LinkedIn posts matched your experience range.',
                scheduledSlot,
                isManual
            });
        }
        return {
            success: true,
            appliedCount: successfullyApplied.length,
            message: successfullyApplied.length > 0
                ? `Successfully applied to ${successfullyApplied.length} LinkedIn hiring post(s)!`
                : "No new unapplied posts matched your experience range.",
            jobs: successfullyApplied
        };
    }
    catch (error) {
        console.error(`[LinkedInAutoApply] Unhandled error for user ${uid}:`, error);
        await (0, featureLogger_1.logFeatureExecution)(uid, {
            feature: 'linkedin_auto_apply',
            featureTitle: 'LinkedIn Auto-Apply (Apify)',
            status: 'error',
            count: 0,
            message: `Execution Error: ${error.message || "Unknown error"}`,
            scheduledSlot,
            isManual
        });
        return {
            success: false,
            appliedCount: 0,
            message: error.message || "Failed to process LinkedIn auto-apply.",
            jobs: []
        };
    }
}
/**
 * Scheduled Dispatcher for LinkedIn Auto-Apply.
 * Called at 10:30 AM IST and 8:30 PM IST by masterHalfHourlyRunner.
 */
async function internalLinkedInPostAutoApplyDispatcher() {
    console.log("[LinkedInAutoApply] Starting scheduled LinkedIn Auto-Apply dispatcher...");
    try {
        const usersSnap = await firebase_1.db.collection("users").get();
        let dispatchedCount = 0;
        for (const userDoc of usersSnap.docs) {
            const userData = userDoc.data() || {};
            const enabledModules = userData.enabledModules || [];
            const jobSubPerms = userData.jobAssistantSubPermissions || {};
            // Admin module check: must be enabled in enabledModules or sub-permissions
            const isLinkedInEnabled = (enabledModules.includes("job_assistant") || enabledModules.includes("linkedin_auto_apply"))
                && jobSubPerms.linkedin_auto_apply !== false;
            if (!isLinkedInEnabled) {
                continue;
            }
            // User preference toggle (if user opted out in their own settings)
            const linkedinSettings = userData.linkedinAutoApplySettings || {};
            if (linkedinSettings.enabled === false) {
                console.log(`[LinkedInAutoApply] User ${userDoc.id} has disabled LinkedIn Auto-Apply in their settings. Skipping.`);
                continue;
            }
            dispatchedCount++;
            console.log(`[LinkedInAutoApply] Dispatching LinkedIn Auto-Apply for user ${userDoc.id}...`);
            // Execute safely without crashing dispatcher
            processLinkedInAutoApplyForUser(userDoc.id, { isManual: false }).catch(err => {
                console.error(`[LinkedInAutoApply] Background dispatch error for user ${userDoc.id}:`, err);
            });
        }
        console.log(`[LinkedInAutoApply] Dispatcher completed. Triggered for ${dispatchedCount} enabled user(s).`);
    }
    catch (e) {
        console.error("[LinkedInAutoApply] Error in scheduled dispatcher:", e);
    }
}
/**
 * Callable Cloud Function: Allows users to trigger LinkedIn Auto-Apply on-demand from the UI.
 */
exports.runLinkedInAutoApplyNow = functions.runWith({ timeoutSeconds: 300, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    const uid = context.auth.uid;
    console.log(`[LinkedInAutoApply] Manual on-demand run triggered by user ${uid}`);
    const result = await processLinkedInAutoApplyForUser(uid, {
        isManual: true,
        roles: data === null || data === void 0 ? void 0 : data.roles,
        locations: data === null || data === void 0 ? void 0 : data.locations,
        minExpYears: data === null || data === void 0 ? void 0 : data.minExpYears,
        maxExpYears: data === null || data === void 0 ? void 0 : data.maxExpYears,
        maxApplications: data === null || data === void 0 ? void 0 : data.maxApplications
    });
    return result;
});
//# sourceMappingURL=linkedinAutoApply.js.map