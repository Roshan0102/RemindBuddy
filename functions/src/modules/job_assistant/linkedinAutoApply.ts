import * as functions from "firebase-functions";
import * as nodemailer from "nodemailer";
import * as moment from "moment-timezone";
import { admin, db } from "../../config/firebase";
import { searchLinkedInPostsViaApify, LinkedInPostItem } from "./apifyLinkedInPosts";
import { callGeminiAPI } from "../../utils/geminiHelper";
import { logFeatureExecution } from "../../utils/featureLogger";
import { logNotification } from "../../utils/logger";
import { formatEmailContent } from "../../utils/emailFormatter";
import { isExperienceExceeded } from "../../utils/experienceMatcher";
import { enqueueUserCloudTask } from "../../utils/cloudTasksHelper";

function normalizeJobRole(role: string): string {
    return (role || "").toLowerCase()
        .replace(/[^a-z0-9]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}

export interface LinkedInAutoApplyOptions {
    isManual?: boolean;
    maxApplications?: number;
    roles?: string[];
    locations?: string[];
    minExpYears?: number;
    maxExpYears?: number;
}

function isForeignOnsite(
    detectedLocation: string,
    targetLocations: string[],
    isRemote: boolean,
    postContent: string
): boolean {
    if (isRemote) return false;
    if (!detectedLocation && !postContent) return false;

    const locText = `${detectedLocation} ${postContent}`.toLowerCase();
    const explicitOnsite = locText.includes('onsite') || locText.includes('on-site') || locText.includes('in-office') || locText.includes('in office') || locText.includes('hybrid');

    // If candidate's target locations explicitly match, it is acceptable
    const matchesTarget = targetLocations.some(tl => {
        const normTL = tl.toLowerCase().trim();
        if (!normTL) return false;
        if (normTL === 'remote') return true;
        return locText.includes(normTL);
    });

    if (matchesTarget) return false;

    // Known foreign indicators
    const foreignIndicators = [
        'morristown', 'new jersey', ' nj', ', nj', 'new york', ' ny', ', ny',
        'california', ' ca', ', ca', 'texas', ' tx', ', tx', 'florida', ' fl', ', fl',
        'london', 'united kingdom', ' uk', ', uk', 'canada', 'toronto', 'vancouver',
        'australia', 'sydney', 'melbourne', 'germany', 'berlin', 'munich',
        'singapore', 'dubai', 'uae', 'netherlands', 'amsterdam'
    ];

    const isForeign = foreignIndicators.some(fi => locText.includes(fi));
    if (isForeign && explicitOnsite) return true;
    if (isForeign && !locText.includes('remote') && !locText.includes('wfh')) return true;

    return false;
}

/**
 * Executes real-time LinkedIn recruiter post scraping via Apify, checks unified applied job history
 * across all Job Assistant modules (Auto-Apply, Portals, Cold Outreach), evaluates experience/role/location
 * fit with Gemini, and auto-applies via Gmail.
 */
export async function processLinkedInAutoApplyForUser(
    uid: string,
    options?: LinkedInAutoApplyOptions
): Promise<{ success: boolean; appliedCount: number; message: string; jobs: any[] }> {
    const isManual = options?.isManual ?? false;
    const scheduledSlot = isManual ? "Manual Run" : "Scheduled Run (Apify)";

    try {
        const userDoc = await db.collection("users").doc(uid).get();
        if (!userDoc.exists) {
            return { success: false, appliedCount: 0, message: "User profile not found.", jobs: [] };
        }

        const userData = userDoc.data() || {};
        const enabledModules: string[] = userData.enabledModules || [];
        const jobSubPerms = userData.jobAssistantSubPermissions || {};

        // Distributed Lock: Prevent duplicate concurrent executions for the same user
        const nowMs = Date.now();
        const lastLockTime = userData.linkedinAutoApplyLock?.toMillis?.() || 0;
        if (nowMs - lastLockTime < 6 * 60 * 1000) {
            const msg = "LinkedIn Auto-Apply is currently in progress for your account. Please wait for the current run to finish.";
            console.log(`[LinkedInAutoApply] User ${uid} locked: another instance is currently running.`);
            return { success: false, appliedCount: 0, message: msg, jobs: [] };
        }
        await db.collection("users").doc(uid).set({
            linkedinAutoApplyLock: admin.firestore.FieldValue.serverTimestamp(),
            linkedinAutoApplyLastRan: admin.firestore.FieldValue.serverTimestamp(),
            jobsLastRan: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        // 1. Admin Module Control: Must be enabled for user
        const isLinkedInEnabled = (enabledModules.includes("job_assistant") || enabledModules.includes("linkedin_auto_apply"))
            && jobSubPerms.linkedin_auto_apply !== false;

        if (!isLinkedInEnabled) {
            console.log(`[LinkedInAutoApply] User ${uid} does NOT have 'linkedin_auto_apply' module enabled by admin. Skipping.`);
            if (isManual) {
                throw new functions.https.HttpsError(
                    'permission-denied',
                    'LinkedIn Auto-Apply is currently disabled by administrator for your account.'
                );
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
            await logFeatureExecution(uid, {
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
        
        const configuredTokens: string[] = [];
        if (Array.isArray(linkedinSettings.apifyTokens)) {
            for (const t of linkedinSettings.apifyTokens) {
                const s = String(t || "").trim();
                if (s && !configuredTokens.includes(s)) configuredTokens.push(s);
            }
        }
        if (linkedinSettings.apifyToken1) configuredTokens.push(String(linkedinSettings.apifyToken1).trim());
        if (linkedinSettings.apifyToken2) configuredTokens.push(String(linkedinSettings.apifyToken2).trim());
        if (linkedinSettings.apifyToken3) configuredTokens.push(String(linkedinSettings.apifyToken3).trim());
        if (userApiKeys.apifyApiKey) configuredTokens.push(String(userApiKeys.apifyApiKey).trim());
        if (userData.apifyApiKey) configuredTokens.push(String(userData.apifyApiKey).trim());

        // Deduplicate tokens
        const apifyTokens = Array.from(new Set(configuredTokens.filter(t => t.length > 5)));

        // Fallback default token from environment if user has not yet populated their own in UI
        if (apifyTokens.length === 0 && process.env.APIFY_API_KEY) {
            apifyTokens.push(process.env.APIFY_API_KEY.trim());
        }

        // 4. Target Roles, Locations & Experience Range (Limited to max 4 roles, max 5 locations)
        let targetRoles: string[] = options?.roles || linkedinSettings.targetRoles || userData.autoApplySettings?.targetRoles || [];
        if (typeof targetRoles === 'string') {
            targetRoles = (targetRoles as string).split(',').map(s => s.trim()).filter(Boolean);
        }
        if (targetRoles.length === 0 && userData.targetRoles) {
            targetRoles = Array.isArray(userData.targetRoles) ? userData.targetRoles : [userData.targetRoles];
        }
        if (targetRoles.length === 0 && userData.targetRole) {
            targetRoles = [userData.targetRole];
        }
        if (targetRoles.length === 0) {
            targetRoles = ["Software Engineer", "Developer"];
        }
        targetRoles = targetRoles.slice(0, 4);

        let targetLocations: string[] = options?.locations ||
            linkedinSettings.targetLocations ||
            linkedinSettings.locations ||
            userData.autoApplySettings?.locations ||
            userData.autoApplySettings?.targetLocations ||
            userData.targetLocations ||
            userData.locations ||
            [];
        if (typeof targetLocations === 'string') {
            targetLocations = (targetLocations as string).split(',').map(s => s.trim()).filter(Boolean);
        }
        targetLocations = targetLocations.slice(0, 5);

        const excludedCompanies: string[] = (
            userData.autoApplySettings?.excludedCompanies ||
            userData.excludedCompanies ||
            linkedinSettings.excludedCompanies ||
            []
        ).map((s: string) => s.trim().toLowerCase()).filter(Boolean);

        const minExp = options?.minExpYears ?? linkedinSettings.minExpYears ?? userData.autoApplySettings?.minExpYears ?? 1;
        const maxExp = options?.maxExpYears ?? linkedinSettings.maxExpYears ?? userData.autoApplySettings?.maxExpYears ?? 3;
        const experienceFilter = `${minExp}-${maxExp} years`;

        // 5. Load Candidate Resume Profile
        const resumeProfiles: any[] = [];
        try {
            const profilesSnap = await db.collection("users").doc(uid).collection("resume_profiles").get();
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
        } catch (e: any) {
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
            await logFeatureExecution(uid, {
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
        // Applications contacted >30 days ago are eligible for re-applying
        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

        const appliedEmails = new Set<string>();
        const appliedUrls = new Set<string>();
        const appliedEmailRoles = new Set<string>();

        // 6a. job_applications (Auto-Apply Agent & LinkedIn)
        try {
            const existingAppsSnap = await db.collection("users").doc(uid).collection("job_applications").get();
            existingAppsSnap.forEach((doc) => {
                const d = doc.data();
                const appliedTime = d.appliedAt?.toDate ? d.appliedAt.toDate() : (d.appliedAt ? new Date(d.appliedAt) : null);
                if (appliedTime && appliedTime < thirtyDaysAgo) {
                    // Applied more than 30 days ago -> eligible to re-apply!
                    return;
                }
                const email = (d.recipientEmail || "").toLowerCase().trim();
                const role = normalizeJobRole(d.jobTitle || "");
                const url = (d.sourceUrl || "").toLowerCase().trim();
                if (email) appliedEmails.add(email);
                if (url) appliedUrls.add(url);
                if (email && role) appliedEmailRoles.add(`${email}|${role}`);
            });
        } catch (e: any) {
            console.warn(`[LinkedInAutoApply] Error loading job_applications: ${e.message}`);
        }

        // 6b. networking_leads (Cold Outreach to Founders / Recruiters)
        try {
            const networkingSnap = await db.collection("users").doc(uid).collection("networking_leads").get();
            networkingSnap.forEach((doc) => {
                const d = doc.data();
                const leadTime = d.emailSentAt?.toDate ? d.emailSentAt.toDate() : (d.discoveredAt?.toDate ? d.discoveredAt.toDate() : null);
                if (leadTime && leadTime < thirtyDaysAgo) {
                    // Contacted more than 30 days ago -> eligible to re-contact!
                    return;
                }
                const email = (d.email || d.recipientEmail || "").toLowerCase().trim();
                const pUrl = (d.linkedinUrl || d.postUrl || "").toLowerCase().trim();
                if (email) appliedEmails.add(email);
                if (pUrl) appliedUrls.add(pUrl);
            });
        } catch (e: any) {
            console.warn(`[LinkedInAutoApply] Error loading networking_leads: ${e.message}`);
        }

        // 6c. career_portal_jobs (Career Portals ATS)
        try {
            const portalSnap = await db.collection("users").doc(uid).collection("career_portal_jobs").get();
            portalSnap.forEach((doc) => {
                const d = doc.data();
                const portalTime = d.appliedAt?.toDate ? d.appliedAt.toDate() : (d.discoveredAt?.toDate ? d.discoveredAt.toDate() : null);
                if (portalTime && portalTime < thirtyDaysAgo) {
                    return;
                }
                const email = (d.recipientEmail || "").toLowerCase().trim();
                const jUrl = (d.jobUrl || d.applyUrl || "").toLowerCase().trim();
                if (email) appliedEmails.add(email);
                if (jUrl) appliedUrls.add(jUrl);
            });
        } catch (e: any) {
            console.warn(`[LinkedInAutoApply] Error loading career_portal_jobs: ${e.message}`);
        }

        // 6d. system_bounced_emails (Bounced addresses to avoid spam flags)
        try {
            const bouncedSnap = await db.collection("system_bounced_emails").limit(500).get();
            bouncedSnap.forEach((doc) => {
                const bEmail = (doc.data()?.email || doc.id || "").toLowerCase().trim();
                if (bEmail) appliedEmails.add(bEmail);
            });
        } catch (e: any) {
            console.warn(`[LinkedInAutoApply] Error loading system_bounced_emails: ${e.message}`);
        }

        console.log(`[LinkedInAutoApply] User ${uid} has ${appliedEmails.size} previously contacted email(s) and ${appliedUrls.size} processed post URL(s) within the last 30 days in unified history.`);

        // 7. Scrape Real-Time LinkedIn Posts via Apify (Multi-role & Location Filtered)
        let searchResult;
        try {
            searchResult = await searchLinkedInPostsViaApify({
                apiTokens: apifyTokens,
                roles: targetRoles,
                locations: targetLocations,
                experienceFilter,
                datePosted: "past-24h",
                maxPosts: 25
            });
        } catch (apifyErr: any) {
            console.error(`[LinkedInAutoApply] Apify scraping error for user ${uid}:`, apifyErr.message);
            await logFeatureExecution(uid, {
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
            await logFeatureExecution(uid, {
                feature: 'linkedin_auto_apply',
                featureTitle: 'LinkedIn Auto-Apply (Apify)',
                status: 'no_results',
                count: 0,
                message: msg,
                scheduledSlot,
                isManual
            });
            await db.collection("users").doc(uid).set({
                linkedinAutoApplyLastRan: admin.firestore.FieldValue.serverTimestamp(),
                jobsLastRan: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
            return { success: true, appliedCount: 0, message: msg, jobs: [] };
        }

        // 8. Filter Posts against Unified History, Blacklist & Experience Restrictions
        const candidatePosts: { post: LinkedInPostItem; email: string }[] = [];

        for (const post of posts) {
            if (!post.hasEmail || post.emails.length === 0) continue;

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

            // Strict Experience check: if post requires experience exceeding candidate maxExp (e.g. 5 to 8 years, 5+ yrs), skip immediately
            const expCheck = isExperienceExceeded(post.content, maxExp, minExp);
            if (expCheck.exceeded) {
                console.log(`[LinkedInAutoApply] Pre-filter skipped post ${post.id}: ${expCheck.reason}`);
                continue;
            }

            for (const email of post.emails) {
                const normEmail = email.toLowerCase().trim();
                if (appliedEmails.has(normEmail)) {
                    console.log(`[LinkedInAutoApply] DEDUPLICATED: Email ${normEmail} was already contacted or queued in this batch. Skipping.`);
                    continue;
                }

                candidatePosts.push({ post, email: normEmail });
                // Register immediately so no subsequent post in this batch picks the same recipient email or post URL
                appliedEmails.add(normEmail);
                if (postUrl) appliedUrls.add(postUrl);
                break;
            }
        }

        console.log(`[LinkedInAutoApply] Found ${candidatePosts.length} fresh, uncontacted candidate post(s).`);

        if (candidatePosts.length === 0) {
            const msg = "All recruiter emails from the latest LinkedIn posts have already been contacted across unified history.";
            await logFeatureExecution(uid, {
                feature: 'linkedin_auto_apply',
                featureTitle: 'LinkedIn Auto-Apply (Apify)',
                status: 'success',
                count: 0,
                message: msg,
                scheduledSlot,
                isManual
            });
            await db.collection("users").doc(uid).set({
                linkedinAutoApplyLastRan: admin.firestore.FieldValue.serverTimestamp(),
                jobsLastRan: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
            return { success: true, appliedCount: 0, message: msg, jobs: [] };
        }

        // 9. Process Applications with Gemini Verification & Nodemailer Sending
        const maxPerRun = Math.min(options?.maxApplications ?? linkedinSettings.maxPerRun ?? 5, 8);
        const postsToProcess = candidatePosts.slice(0, maxPerRun);

        let applicantName = (userData.applicantName || userData.displayName || "").trim();
        if (!applicantName) {
            try {
                const authUser = await admin.auth().getUser(uid);
                applicantName = authUser.displayName || authUser.email?.split('@')[0] || "Applicant";
            } catch {
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

        const successfullyApplied: any[] = [];
        const todayStr = moment().tz('Asia/Kolkata').format('YYYY-MM-DD');
        const alreadySentEmailsThisRun = new Set<string>();
        let lastEmailSentTimestamp = 0;

        for (const item of postsToProcess) {
            const { post, email: recipientEmail } = item;

            // In-run deduplication guard: never email the same recipient twice in one run
            if (alreadySentEmailsThisRun.has(recipientEmail)) {
                console.log(`[LinkedInAutoApply] DEDUPLICATED: Email ${recipientEmail} was already contacted in this run. Skipping.`);
                continue;
            }

            // Fresh database duplicate check to prevent race conditions
            try {
                const dupCheck = await db.collection("users").doc(uid).collection("job_applications")
                    .where("recipientEmail", "==", recipientEmail)
                    .limit(1)
                    .get();
                if (!dupCheck.empty) {
                    console.log(`[LinkedInAutoApply] DEDUPLICATED: Recipient ${recipientEmail} already found in Firestore job_applications. Skipping.`);
                    alreadySentEmailsThisRun.add(recipientEmail);
                    appliedEmails.add(recipientEmail);
                    continue;
                }
            } catch (dupErr: any) {
                console.warn(`[LinkedInAutoApply] Duplicate check warning:`, dupErr.message);
            }

            // Pick matching resume profile
            const matchedProfile = resumeProfiles.find(p => 
                p.targetRoles.some((r: string) => post.content.toLowerCase().includes(r.toLowerCase()))
            ) || resumeProfiles.find(p => p.isDefault) || resumeProfiles[0];

            const cleanResumeB64 = (matchedProfile?.base64 || "").replace(/^data:application\/pdf;base64,/, '').trim();

            // Use Gemini to verify role alignment, location & remote policy, and draft tailored cover letter
            let generatedApplication: any = null;
            try {
                const prompt = `You are an elite career advisor and executive recruiter.
Analyze this real-time LinkedIn recruiter hiring post against the candidate's ATTACHED RESUME PDF:
"${post.content}"
Author: "${post.authorName}" (${post.authorTitle})

Candidate Profile:
- Name: "${applicantName}"
- Experience: ${minExp}-${maxExp} years
- Target Roles: ${targetRoles.join(', ')}
- Target Locations: ${targetLocations.length > 0 ? targetLocations.join(', ') : 'Remote / India'}
- Excluded Companies: ${excludedCompanies.length > 0 ? excludedCompanies.join(', ') : 'None'}

CRITICAL MATCHING & GROUND-TRUTH RULES (MUST FOLLOW STRICTLY):
1. ROLE MATCH: The post must genuinely be hiring for at least one of the candidate's target roles (${targetRoles.join(', ')}).
2. EXPERIENCE FIT (CRITICAL HARD DISQUALIFIER):
   - Candidate has ${minExp} to ${maxExp} years of experience.
   - Detect the required years of experience from the post (e.g. "5 to 8 years", "5-8 yrs", "4+ years", "5+ years", "3-5 years", "min 5 years", etc.).
   - If the post explicitly requires experience exceeding the candidate's maximum (${maxExp} years, allowing at most a 1-year stretch, e.g. candidate has ${minExp}-${maxExp} years but post requires 4+, 5+, 5-8 years, 6+, 7+, 8+, 10+, Senior, Lead, Staff, Principal, Architect), you MUST IMMEDIATELY DISQUALIFY THE POST: set "isMatch": false and "rejectionReason": "Experience mismatch: post requires [detected experience], exceeding candidate's configured ${minExp}-${maxExp} years".
   - DO NOT apply or attempt to bridge large experience gaps. Recruiters reject candidates who do not meet their experience requirements.
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
   - "detectedExperience": Extracted experience required by the job (e.g. "0-2 years", "1-3 years", "Fresher").
   - "detectedLocation": The city/country and work mode (e.g. "Bengaluru (Hybrid)", "Remote (India)", "Chennai (Onsite)").
   - "isRemote": boolean (true if work from home / remote is allowed).
   - "subject": Tailored email subject line (format: "Application for [Job Title] - ${applicantName}").
   - "coverLetter": A comprehensive, compelling, and highly personalized application email tailored specifically to this hiring post.
     CRITICAL STRUCTURE & HIGH-CONVERSION MANDATES:
     1. PROFESSIONAL GREETING: e.g. "Dear Hiring Team," or "Dear [Author Name]," if available.
     2. COMPELLING OPENING: Express keen, enthusiastic interest in the specific [Job Title] role at [Company], referencing details or focus areas mentioned in their post.
     3. VALUE PROPOSITION & RELEVANCE: Directly reference the job requirements and technologies highlighted in the post, and articulate how the candidate's real verified experience from their resume solves them.
     4. KEY CONTRIBUTIONS PREPARED TO DELIVER (MANDATORY):
        Include a dedicated bulleted section:
        "Key contributions I am prepared to deliver include:"
        Provide 3-4 concrete, impactful bullet points (using "•") directly derived from the candidate's attached resume PDF (quantified project deliverables, architectures built, optimizations achieved, and verified technical proficiencies).
     5. EXPERIENCE ALIGNMENT: Articulate the candidate's verified hands-on project mastery and immediate readiness to deliver value from Day 1 without overpromising.
     6. CALL TO ACTION & RESUME REFERENCE: Respectfully mention the attached resume for review and propose a brief 10-15 minute discussion.
     7. SIGN-OFF:
"Sincerely,
${applicantName}"

     CRITICAL RESUME GROUNDING INSTRUCTION:
     - You MUST ground all technical skills, programming languages, frameworks, and past achievements SOLELY on the candidate's attached resume PDF.
     - NEVER hallucinate, invent, or assume skills that are NOT in the candidate's resume (e.g. DO NOT mention DevOps, AWS, Kubernetes, Terraform, Cloud, or CI/CD unless they are explicitly written in the candidate's attached resume).
     - Focus strictly on the candidate's actual stack and experience as documented in their resume.
     - STRICT PROHIBITION ON REPETITIVE BOILERPLATE: DO NOT use repetitive generic template sentences like "I am writing to express my enthusiastic interest in the ... position shared on LinkedIn. With hands-on experience in ..., I am confident in my ability to deliver immediate value." Every single application email MUST be uniquely customized, substantive, and authentically tailored.

Respond ONLY with valid JSON:
{
  "isMatch": boolean,
  "rejectionReason": string,
  "detectedExperience": string,
  "companyName": string,
  "jobTitle": string,
  "detectedLocation": string,
  "isRemote": boolean,
  "subject": string,
  "coverLetter": string
}`;

                const geminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();
                const groqKey = (userApiKeys.groqApiKey || userData.groqApiKey || "").trim();
                const geminiParts: any[] = [];
                if (cleanResumeB64) {
                    geminiParts.push({
                        inlineData: {
                            mimeType: "application/pdf",
                            data: cleanResumeB64
                        }
                    });
                }
                geminiParts.push({ text: prompt });

                const geminiPayload = {
                    contents: [{ parts: geminiParts }],
                    generationConfig: { responseMimeType: "application/json" }
                };
                const geminiResp = await callGeminiAPI(geminiPayload, {
                    apiKey: geminiKey || undefined,
                    groqApiKey: groqKey || undefined,
                    timeout: 45000
                });

                const rawText = geminiResp.text || "{}";
                generatedApplication = JSON.parse(rawText.replace(/```json/g, '').replace(/```/g, '').trim());
            } catch (aiErr: any) {
                console.warn(`[LinkedInAutoApply] Gemini post analysis error for post ${post.id}:`, aiErr.message);
                generatedApplication = {
                    isMatch: false,
                    rejectionReason: `AI parsing failed: ${aiErr.message}`
                };
            }

            if (!generatedApplication || generatedApplication.isMatch === false) {
                console.log(`[LinkedInAutoApply] Rejected post ${post.id}: ${generatedApplication?.rejectionReason || 'Did not meet role/location/experience criteria'}`);
                continue;
            }

            // Post-AI safety check on experience
            if (generatedApplication.detectedExperience) {
                const aiExpCheck = isExperienceExceeded(generatedApplication.detectedExperience, maxExp, minExp);
                if (aiExpCheck.exceeded) {
                    console.log(`[LinkedInAutoApply] Safety check rejected post ${post.id}: AI detected experience "${generatedApplication.detectedExperience}" exceeding candidate max of ${maxExp} years.`);
                    continue;
                }
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
            const finalSubject = generatedApplication.subject || `Application for ${finalTitle} - ${finalCompany} - ${applicantName}`;
            const finalBody = generatedApplication.coverLetter;

            // Prepare attachments
            const cleanB64 = (matchedProfile.base64 || "").replace(/^data:application\/pdf;base64,/, '');
            const attachments = cleanB64 ? [{
                filename: matchedProfile.fileName || "Resume.pdf",
                content: Buffer.from(cleanB64, 'base64'),
                contentType: 'application/pdf'
            }] : [];

            // Pacing Guard: Ensure at least 60 seconds (1 minute) has elapsed since the previous email was sent
            // to prevent Gmail / Google spam & bot detection
            if (lastEmailSentTimestamp > 0) {
                const elapsedMs = Date.now() - lastEmailSentTimestamp;
                const minWaitMs = 60000; // 60 seconds
                if (elapsedMs < minWaitMs) {
                    const remainingWaitMs = minWaitMs - elapsedMs;
                    console.log(`[LinkedInAutoApply] Rate-limiting guard: waiting ${Math.round(remainingWaitMs / 1000)}s before sending next application email to ${recipientEmail} to prevent Google bot/spam flags...`);
                    await new Promise(resolve => setTimeout(resolve, remainingWaitMs));
                }
            }

            // Send via Nodemailer
            try {
                const formatted = formatEmailContent(finalBody);
                const info = await transporter.sendMail({
                    from: `"${applicantName}" <${userEmail}>`,
                    to: recipientEmail,
                    subject: finalSubject,
                    text: formatted.text,
                    html: formatted.html,
                    attachments
                });

                lastEmailSentTimestamp = Date.now();
                alreadySentEmailsThisRun.add(recipientEmail);
                appliedEmails.add(recipientEmail);

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
                    appliedAt: admin.firestore.FieldValue.serverTimestamp(),
                    status: "sent",
                    messageId: info.messageId || "",
                    isAutoApplied: true,
                    appliedDateStr: todayStr,
                    resumeProfileName: matchedProfile.title,
                    authorName: post.authorName,
                    authorTitle: post.authorTitle,
                    postExcerpt: post.content.substring(0, 300)
                };

                const docRef = await db.collection("users").doc(uid).collection("job_applications").add(applicationRecord);

                if (post.url) appliedUrls.add(post.url.toLowerCase().trim());
                appliedEmailRoles.add(`${recipientEmail}|${normalizeJobRole(finalTitle)}`);

                successfullyApplied.push({
                    id: docRef.id,
                    ...applicationRecord
                });
            } catch (mailErr: any) {
                console.error(`[LinkedInAutoApply] Error sending email to ${recipientEmail}:`, mailErr);
            }
        }

        // 10. Update User Document Timestamps
        const userUpdate: any = {
            linkedinAutoApplyLastRan: admin.firestore.FieldValue.serverTimestamp(),
            jobsLastRan: admin.firestore.FieldValue.serverTimestamp()
        };
        if (successfullyApplied.length > 0) {
            userUpdate.jobsLastApplied = admin.firestore.FieldValue.serverTimestamp();
            userUpdate.linkedinAutoApplyLastApplied = admin.firestore.FieldValue.serverTimestamp();
        }
        await db.collection("users").doc(uid).set(userUpdate, { merge: true });

        // 11. Push Notification & Feature Execution Log
        if (successfullyApplied.length > 0) {
            try {
                const userTokenDoc = await db.collection("usernames").where("uid", "==", uid).limit(1).get();
                if (!userTokenDoc.empty) {
                    const fcmToken = userTokenDoc.docs[0].data()?.fcmToken;
                    if (fcmToken) {
                        const compNames = successfullyApplied.map(j => j.companyName).slice(0, 3).join(', ');
                        const notifTitle = `⚡ Auto-Applied to ${successfullyApplied.length} LinkedIn Post${successfullyApplied.length > 1 ? 's' : ''}!`;
                        const notifBody = `Applied to recruiter posts from: ${compNames}. Tap to view sent applications.`;

                        await admin.messaging().send({
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

                        await logNotification(uid, notifTitle, notifBody, "JOB_ASSISTANT");
                    }
                }
            } catch (pushErr) {
                console.error("[LinkedInAutoApply] Push notification dispatch error:", pushErr);
            }

            await logFeatureExecution(uid, {
                feature: 'linkedin_auto_apply',
                featureTitle: 'LinkedIn Auto-Apply (Apify)',
                status: 'success',
                count: successfullyApplied.length,
                message: `Successfully applied to ${successfullyApplied.length} real-time LinkedIn recruiter post(s).`,
                scheduledSlot,
                details: successfullyApplied.map(j => `${j.jobTitle} at ${j.companyName} (${j.recipientEmail})`),
                isManual
            });
        } else {
            await logFeatureExecution(uid, {
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

    } catch (error: any) {
        console.error(`[LinkedInAutoApply] Unhandled error for user ${uid}:`, error);
        await logFeatureExecution(uid, {
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
    } finally {
        try {
            await db.collection("users").doc(uid).set({
                linkedinAutoApplyLock: null
            }, { merge: true });
        } catch (lockErr: any) {
            console.warn(`[LinkedInAutoApply] Error clearing lock for user ${uid}:`, lockErr.message);
        }
    }
}

/**
 * Scheduled Dispatcher for LinkedIn Auto-Apply.
 * Called at 10:30 AM IST and 8:30 PM IST by masterHalfHourlyRunner.
 */
export async function internalLinkedInPostAutoApplyDispatcher(): Promise<void> {
    console.log("[LinkedInAutoApply] Starting scheduled LinkedIn Auto-Apply dispatcher...");
    try {
        const usersSnap = await db.collection("users").get();
        let dispatchedCount = 0;

        for (const userDoc of usersSnap.docs) {
            const userData = userDoc.data() || {};
            const enabledModules: string[] = userData.enabledModules || [];
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
            
            // Try enqueuing to Cloud Tasks for background isolated execution
            const taskId = await enqueueUserCloudTask(
                "processLinkedInAutoApplyUserTask",
                "processLinkedInAutoApplyUserTask",
                { uid: userDoc.id }
            );

            // Sequential fallback if Cloud Tasks is not configured (must await so Cloud Functions container does not terminate pending execution)
            if (!taskId) {
                console.log(`[LinkedInAutoApply] Cloud Tasks queue not available for user ${userDoc.id}. Running directly with await fallback...`);
                try {
                    await processLinkedInAutoApplyForUser(userDoc.id, { isManual: false });
                } catch (err) {
                    console.error(`[LinkedInAutoApply] Background execution error for user ${userDoc.id}:`, err);
                }
            }
        }

        console.log(`[LinkedInAutoApply] Dispatcher completed. Triggered for ${dispatchedCount} enabled user(s).`);
    } catch (e: any) {
        console.error("[LinkedInAutoApply] Error in scheduled dispatcher:", e);
    }
}

/**
 * Cloud Task HTTP Handler: processLinkedInAutoApplyUserTask
 */
export const processLinkedInAutoApplyUserTask = functions
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onRequest(async (req, res) => {
        try {
            const bodyData = req.body?.data || req.body || {};
            const uid = bodyData.uid;
            if (!uid) {
                res.status(400).send("Missing uid in task payload.");
                return;
            }

            console.log(`[processLinkedInAutoApplyUserTask] Executing LinkedIn auto-apply task for user ${uid}`);
            const result = await processLinkedInAutoApplyForUser(uid, { isManual: false });
            res.status(200).json(result);
        } catch (err: any) {
            console.error("[processLinkedInAutoApplyUserTask] Fatal task execution error:", err);
            res.status(500).send(err.message || "Internal server error");
        }
    });

/**
 * Callable Cloud Function: Allows users to trigger LinkedIn Auto-Apply on-demand from the UI.
 */
export const runLinkedInAutoApplyNow = functions.runWith({ timeoutSeconds: 540, memory: "1GB" }).https.onCall(
    async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
        }

        const uid = context.auth.uid;
        console.log(`[LinkedInAutoApply] Manual on-demand run triggered by user ${uid}`);

        const result = await processLinkedInAutoApplyForUser(uid, {
            isManual: true,
            roles: data?.roles,
            locations: data?.locations,
            minExpYears: data?.minExpYears,
            maxExpYears: data?.maxExpYears,
            maxApplications: data?.maxApplications
        });

        return result;
    }
);
