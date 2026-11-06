import * as functions from "firebase-functions";
import * as nodemailer from "nodemailer";
import * as moment from "moment-timezone";
import * as dns from "dns";
import { admin, db } from "../../config/firebase";
import { logFeatureExecution } from "../../utils/featureLogger";
import { callGeminiAPI } from "../../utils/geminiHelper";
import { searchTavily, TavilySearchResult } from "../../utils/tavilyHelper";
import { formatEmailContent } from "../../utils/emailFormatter";
import { UserResumeProfile, getBestMatchingResumeProfile } from "./jobDiscoveryAI";

export interface DiscoveredWFHJob {
    jobTitle: string;
    companyName: string;
    recipientEmail: string;
    location: string;
    experienceRequired: string;
    sourcePlatform: string;
    sourceUrl?: string;
    generatedSubject: string;
    generatedCoverLetter: string;
    keySkills?: string[];
}

/**
 * Validates email format and filters placeholder/dummy emails.
 */
function isValidEmail(email: string): boolean {
    if (!email || typeof email !== "string") return false;
    const clean = email.trim();
    const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
    if (
        clean.includes("example.com") ||
        clean.includes("yourcompany.com") ||
        clean.includes("test.com") ||
        clean.includes("dummy") ||
        clean.includes("sample.com")
    ) {
        return false;
    }
    return emailRegex.test(clean);
}

/**
 * Verifies email domain has active MX DNS records to avoid bouncebacks.
 */
async function verifyEmailDomainMx(email: string): Promise<boolean> {
    try {
        const domain = email.split("@")[1]?.trim();
        if (!domain) return false;
        const records = await dns.promises.resolveMx(domain);
        return records && records.length > 0;
    } catch {
        return false;
    }
}

/**
 * Normalizes job title strings for robust deduplication.
 */
function normalizeJobRole(role: string): string {
    return (role || "")
        .toLowerCase()
        .replace(/[^a-z0-9]/g, " ")
        .replace(/\s+/g, " ")
        .trim();
}

/**
 * Job aggregator domains to exclude so search prioritizes direct recruiter postings.
 */
const AGGREGATOR_DOMAINS_TO_EXCLUDE = [
    "naukri.com",
    "indeed.com",
    "glassdoor.com",
    "glassdoor.co.in",
    "shine.com",
    "expertini.com",
    "internshala.com",
    "foundit.in",
    "ownyourcareer.in",
    "quikr.com",
    "freshersworld.com",
    "unstop.com",
    "timesjobs.com",
    "apna.co",
    "ambitionbox.com",
    "jobleads.com"
];

/**
 * Discovers and applies to Work From Home / Remote jobs matching user's target roles and custom location.
 */
export async function discoverAndApplyWFHForUser(
    uid: string,
    options: {
        customLocation?: string;
        maxApplications?: number;
    }
): Promise<{ success: boolean; appliedCount: number; jobs: any[]; message: string }> {
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
        return { success: false, appliedCount: 0, jobs: [], message: "User not found." };
    }

    const userData = userDoc.data() || {};
    const jobSubPerms = userData.jobAssistantSubPermissions || {};

    if (jobSubPerms.wfh_remote === false) {
        return {
            success: false,
            appliedCount: 0,
            jobs: [],
            message: "WFH Remote Job Hunter is disabled by your administrator."
        };
    }

    // Dynamic resolution of candidate details - Universal Generalization
    let applicantName = (userData.applicantName || userData.displayName || "").trim();
    if (!applicantName) {
        try {
            const authUser = await admin.auth().getUser(uid);
            applicantName = (authUser.displayName || "").trim();
            if (!applicantName && authUser.email) {
                applicantName = authUser.email.split("@")[0];
            }
        } catch (_) {}
    }
    if (!applicantName) {
        applicantName = "Candidate";
    }

    const emailConfig = userData.emailConfig || {};
    const userEmail = emailConfig.email;
    const appPassword = emailConfig.appPassword;

    if (!userEmail || !appPassword) {
        await logFeatureExecution(uid, {
            feature: "wfh_remote",
            featureTitle: "WFH Remote Job Hunter",
            status: "skipped",
            count: 0,
            message: "Skipped: Gmail & App Password not configured in Job Assistant Settings.",
            isManual: true
        });
        return {
            success: false,
            appliedCount: 0,
            jobs: [],
            message: "Gmail & App Password not configured in Job Assistant Settings. Please configure them in Settings."
        };
    }

    // Resolve target roles and experience from general settings
    const autoApplySettings = userData.autoApplySettings || userData.autoApply || userData.jobPreferences || {};
    let targetRoles: string[] = autoApplySettings.targetRoles || userData.targetRoles || userData.techDomains || [];
    if (typeof targetRoles === "string") {
        targetRoles = (targetRoles as string)
            .split(",")
            .map((s: string) => s.trim())
            .filter((s: string) => s.length > 0);
    }

    if (targetRoles.length === 0) {
        await logFeatureExecution(uid, {
            feature: "wfh_remote",
            featureTitle: "WFH Remote Job Hunter",
            status: "skipped",
            count: 0,
            message: "Skipped: No target job roles configured in Job Assistant Settings.",
            isManual: true
        });
        return {
            success: false,
            appliedCount: 0,
            jobs: [],
            message: "Please enter your Target Job Roles (e.g. Software Engineer, React Developer) in Job Assistant Settings before running WFH Job Hunter."
        };
    }

    // Load multi-resume profiles or master resume
    const resumeProfiles: UserResumeProfile[] = [];
    try {
        const profilesSnap = await db.collection("users").doc(uid).collection("resume_profiles").get();
        profilesSnap.forEach((doc) => {
            const p = doc.data() || {};
            if (p.base64) {
                resumeProfiles.push({
                    id: doc.id,
                    title: (p.title || p.name || "Targeted Resume").toString(),
                    targetRoles: Array.isArray(p.targetRoles)
                        ? p.targetRoles.map((s: any) => s.toString().trim()).filter(Boolean)
                        : (typeof p.targetRoles === "string" ? p.targetRoles.split(",").map((s: string) => s.trim()).filter(Boolean) : []),
                    fileName: (p.fileName || "Resume.pdf").toString(),
                    base64: p.base64.toString(),
                    isDefault: p.isDefault === true
                });
            }
        });
    } catch (profErr: any) {
        console.warn(`[WFHJobDiscovery] Could not load resume_profiles for ${uid}:`, profErr.message);
    }

    const masterResume = userData.masterResume || {};
    const resumeBase64 = masterResume.base64 || userData.resumeBase64 || "";
    const resumeFileName = masterResume.fileName || userData.resumeFileName || "Resume.pdf";

    if (resumeProfiles.length === 0 && resumeBase64) {
        resumeProfiles.push({
            id: "master_resume",
            title: "Master Resume",
            targetRoles: targetRoles,
            fileName: resumeFileName,
            base64: resumeBase64,
            isDefault: true
        });
    }

    if (resumeProfiles.length === 0 && !resumeBase64) {
        await logFeatureExecution(uid, {
            feature: "wfh_remote",
            featureTitle: "WFH Remote Job Hunter",
            status: "skipped",
            count: 0,
            message: "Skipped: Resume PDF not uploaded in Job Assistant Settings.",
            isManual: true
        });
        return {
            success: false,
            appliedCount: 0,
            jobs: [],
            message: "Please upload your resume PDF in Job Assistant Settings before searching for WFH jobs."
        };
    }

    // Resolve customized location preference
    const customLocation = (options.customLocation || userData.wfhLocationPreference || "India").trim();
    // Persist user's WFH location preference for subsequent runs
    await db.collection("users").doc(uid).set({
        wfhLocationPreference: customLocation
    }, { merge: true });

    const minExp = autoApplySettings.minExpYears !== undefined ? Number(autoApplySettings.minExpYears) : Number(userData.minExperience ?? 0);
    const maxExp = autoApplySettings.maxExpYears !== undefined ? Number(autoApplySettings.maxExpYears) : Number(userData.maxExperience ?? 3);
    const maxApplications = Math.min(Math.max(1, options.maxApplications || 4), 8);

    // Resolve API keys (BYOK)
    const userApiKeys = userData.userApiKeys || {};
    const userTavilyKey = userApiKeys.tavilyApiKey || userData.tavilyApiKey || process.env.TAVILY_API_KEY;
    const userTavilyKey2 = userApiKeys.tavilyApiKey2 || userData.tavilyApiKey2;
    const userGeminiKey = userApiKeys.geminiApiKey || userData.geminiApiKey;
    const userGroqKey = userApiKeys.groqApiKey || userData.groqApiKey;

    if (!userTavilyKey) {
        return {
            success: false,
            appliedCount: 0,
            jobs: [],
            message: "Tavily Search API key is missing. Please add your free Tavily API key in Job Assistant Settings -> AI & Search Keys."
        };
    }

    if (!userGeminiKey && !userGroqKey) {
        return {
            success: false,
            appliedCount: 0,
            jobs: [],
            message: "Gemini / Groq API key is missing. Please add your free API key in Job Assistant Settings -> AI & Search Keys."
        };
    }

    // Deduplication (30 days) and Blacklists
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const appliedEmailRoles = new Set<string>();
    const appliedCompanyRoles = new Set<string>();
    const blockedFakeEmails = new Set<string>();

    try {
        const blockedSnap = await db.collection("users").doc(uid).collection("blocked_fake_jobs").get();
        blockedSnap.forEach((doc) => {
            const bEmail = (doc.data()?.email || doc.id || "").toLowerCase().trim();
            if (bEmail) blockedFakeEmails.add(bEmail);
            try {
                const decoded = decodeURIComponent(bEmail);
                if (decoded) blockedFakeEmails.add(decoded);
            } catch (_) {}
        });
    } catch (e: any) {
        console.warn(`[WFHJobDiscovery] Error loading blocked_fake_jobs: ${e.message}`);
    }

    try {
        const existingAppsSnap = await db.collection("users").doc(uid).collection("job_applications").get();
        existingAppsSnap.forEach((doc) => {
            const d = doc.data();
            const email = (d.recipientEmail || "").toLowerCase().trim();
            if (d.isFake === true || d.status === "fake") {
                if (email) blockedFakeEmails.add(email);
                return;
            }
            const appliedTime = d.appliedAt?.toDate ? d.appliedAt.toDate() : (d.appliedAt ? new Date(d.appliedAt) : null);
            if (appliedTime && appliedTime < thirtyDaysAgo) return;

            const role = normalizeJobRole(d.jobTitle || "");
            const comp = (d.companyName || "").toLowerCase().trim();
            if (email && role) appliedEmailRoles.add(`${email}|${role}`);
            if (comp && role) appliedCompanyRoles.add(`${comp}|${role}`);
        });
    } catch (e: any) {
        console.warn(`[WFHJobDiscovery] Error loading job_applications: ${e.message}`);
    }

    // Load global bounce blacklist
    const globalBouncedSet = new Set<string>();
    try {
        const bouncedSnap = await db.collection("system_bounced_emails").get();
        bouncedSnap.forEach((d) => {
            const data = d.data() || {};
            if (data.email) globalBouncedSet.add(data.email.toLowerCase().trim());
            globalBouncedSet.add(d.id.toLowerCase().trim());
            try {
                globalBouncedSet.add(decodeURIComponent(d.id).toLowerCase().trim());
            } catch (_) {}
        });
    } catch (bErr: any) {
        console.warn(`[WFHJobDiscovery] Error loading system_bounced_emails:`, bErr.message);
    }

    // Excluded companies from settings
    let excludedCompanies: string[] = autoApplySettings.excludedCompanies || userData.excludedCompanies || [];
    if (typeof excludedCompanies === "string") {
        excludedCompanies = (excludedCompanies as string).split(",").map((s) => s.trim()).filter(Boolean);
    }

    // Formulate WFH search queries for Tavily
    const isWorldwide = customLocation.toLowerCase().includes("world") || customLocation.toLowerCase().includes("any");
    const locSnippet = isWorldwide ? '("worldwide" OR "anywhere" OR "global" OR "remote-first")' : `("${customLocation}")`;
    const wfhPhrases = '("work from home" OR "remote" OR "wfh" OR "100% remote")';
    const recruiterPhrases = '("hiring" OR "we are hiring" OR "looking for") ("send resume" OR "share CV" OR "email resume" OR "email CV" OR "apply at" OR "drop your resume")';

    const allTavilyResults: TavilySearchResult[] = [];
    const seenUrls = new Set<string>();
    let lastTavilyError = "";

    for (const role of targetRoles.slice(0, 4)) {
        try {
            const query = `"${role}" ${wfhPhrases} ${locSnippet} ${recruiterPhrases} "@" -site:facebook.com/groups`;
            console.log(`[WFHJobDiscovery] Tavily querying WFH openings for user ${uid} (Role: "${role}", Location: "${customLocation}")...`);

            const tavilyResp = await searchTavily({
                apiKey: userTavilyKey,
                secondaryApiKey: userTavilyKey2,
                query,
                searchDepth: "advanced",
                maxResults: 6,
                days: 30,
                excludeDomains: AGGREGATOR_DOMAINS_TO_EXCLUDE
            });

            for (const item of tavilyResp.results) {
                if (item.url && !seenUrls.has(item.url)) {
                    seenUrls.add(item.url);
                    allTavilyResults.push(item);
                }
            }
        } catch (tavilyErr: any) {
            console.warn(`[WFHJobDiscovery] Tavily error for WFH role "${role}":`, tavilyErr.message);
            lastTavilyError = tavilyErr.message || String(tavilyErr);
        }
    }

    if (allTavilyResults.length === 0) {
        const message = lastTavilyError
            ? `Tavily Search Error: ${lastTavilyError}. Please check your Tavily API key and plan limits in Settings.`
            : `No fresh Work-From-Home / Remote job postings with verified recruiter emails found in "${customLocation}".`;
        await logFeatureExecution(uid, {
            feature: "wfh_remote",
            featureTitle: "WFH Remote Job Hunter",
            status: lastTavilyError ? "error" : "no_results",
            count: 0,
            message,
            isManual: true
        });
        return { success: !lastTavilyError, appliedCount: 0, jobs: [], message };
    }

    const searchResultsSummary = allTavilyResults
        .map((r, i) => `[Live WFH Job Post ${i + 1}]\nTitle: ${r.title}\nSource: ${r.url}\nPost Details: ${r.content}`)
        .join("\n\n");

    const formattedRolesList = targetRoles.map((role, idx) => `   ${idx + 1}. "${role}"`).join("\n");
    const todayStr = moment().tz("Asia/Kolkata").format("YYYY-MM-DD");

    const prompt = `You are an elite automated Work-From-Home (WFH) & Remote Job Recruiter Outreach AI Agent.
Below are real-time, live web search results for open remote / work-from-home job postings and recruiter hiring calls:

${searchResultsSummary}

Candidate Name: "${applicantName}"
Target Roles to Search:
${formattedRolesList}
Preferred Location: "${customLocation}" (Remote / Work-From-Home)
Candidate Experience Target: ${minExp} to ${maxExp} Years Experience

CRITICAL VERIFICATION & EXTRACTION MANDATES:
1. STRICT MANDATE — RECRUITER EMAIL MUST BE VERBATIM IN SNIPPET:
   - Every single job item MUST contain a verified recruiter / HR / hiring contact email address that is EXPLICITLY and VERBATIM printed in the post details or source snippet text.
   - NEVER guess, synthesize, or invent email addresses (e.g. jobs@company.com, careers@company.com). If the post does NOT explicitly provide an email address in the snippet text, DO NOT INCLUDE THAT JOB.

2. WORK-FROM-HOME / REMOTE REQUIREMENT:
   - The opening MUST explicitly support Work-From-Home (WFH) or Remote work for candidates located in "${customLocation}" (or worldwide/anywhere remote).
   - STRICTLY EXCLUDE pure on-site / in-office jobs that do not support remote.

3. EXPERIENCE REQUIREMENT (${minExp} TO ${maxExp} YEARS):
   - ONLY include roles suitable for ${minExp} to ${maxExp} years experience.
   - EXCLUDE senior / staff / principal roles requiring > ${maxExp} years.

4. HUMAN-WRITTEN, HIGH-CONVERSION, MOBILE-OPTIMIZED APPLICATION EMAIL (STRICT 4-5 LINES TOTAL):
   - Write a sharp, authentic, and punchy application email strictly 4–5 sentences total, formatted into exactly TWO short paragraphs with a single blank line between them.
   - ABSOLUTELY NO BULLET POINTS ("•", "-", "*") OR LENGTHY LISTS.
   - AVOID ROBOTIC CLICHÉS: Never use "I am writing to express my strong interest...", "I am eager to contribute...", or "Key contributions include:".
   - Paragraph 1: Direct hook expressing enthusiasm for the specific remote [Job Title] role at [Company]. Highlight candidate's core strengths aligned with the position.
   - Paragraph 2: Mention candidate's proven remote delivery track record and note that their resume is attached for review. Invite for a brief 10–15 minute call to discuss contributions.
   - Sign-off: "Sincerely,\n${applicantName}"
   - Subject line format: "Application for [Job Title] (Remote) - ${applicantName}"

Respond ONLY with a JSON array matching this schema:
[
  {
    "jobTitle": "string",
    "companyName": "string",
    "recipientEmail": "string (MUST be a valid email address)",
    "location": "${customLocation} (Remote)",
    "experienceRequired": "string",
    "sourcePlatform": "string",
    "sourceUrl": "string",
    "keySkills": ["string"],
    "generatedSubject": "string",
    "generatedCoverLetter": "string"
  }
]
If no matching WFH jobs with verified emails and remote eligibility are found, respond with an empty JSON array: [].`;

    let rawText = "";
    let modelUsed = "";

    try {
        const geminiResult = await callGeminiAPI({
            prompt,
            apiKey: userGeminiKey,
            groqApiKey: userGroqKey
        });
        rawText = geminiResult.text || "";
        modelUsed = geminiResult.modelUsed || "";
    } catch (apiErr: any) {
        console.error("[WFHJobDiscovery] Gemini analysis failed:", apiErr.message);
        const errMsg = `Gemini API Error: ${apiErr.message || apiErr}. Check your API keys in Settings.`;
        await logFeatureExecution(uid, {
            feature: "wfh_remote",
            featureTitle: "WFH Remote Job Hunter",
            status: "error",
            count: 0,
            message: errMsg,
            isManual: true
        });
        return { success: false, appliedCount: 0, jobs: [], message: errMsg };
    }

    let discoveredJobs: DiscoveredWFHJob[] = [];
    try {
        const jsonMatch = rawText.match(/\[[\s\S]*\]/);
        if (jsonMatch) {
            discoveredJobs = JSON.parse(jsonMatch[0]);
        } else {
            discoveredJobs = JSON.parse(rawText);
        }
    } catch (parseErr) {
        console.error("[WFHJobDiscovery] Failed to parse JSON from search result:", parseErr, rawText);
        return { success: false, appliedCount: 0, jobs: [], message: "Failed to parse AI job discoveries." };
    }

    if (!Array.isArray(discoveredJobs) || discoveredJobs.length === 0) {
        await logFeatureExecution(uid, {
            feature: "wfh_remote",
            featureTitle: "WFH Remote Job Hunter",
            status: "no_results",
            count: 0,
            message: `0 fresh WFH / Remote jobs with recruiter emails found in ${customLocation}.`,
            isManual: true
        });
        return {
            success: true,
            appliedCount: 0,
            jobs: [],
            message: `No fresh Work-From-Home openings with verified recruiter emails found in "${customLocation}".`
        };
    }

    // Filter valid jobs
    const validFilteredJobs: DiscoveredWFHJob[] = [];
    for (const job of discoveredJobs) {
        const email = (job.recipientEmail || "").trim();
        if (!isValidEmail(email)) continue;

        const emailLower = email.toLowerCase();
        if (blockedFakeEmails.has(emailLower)) {
            console.log(`[WFHJobDiscovery] Skipping permanently blocked fake email: ${emailLower}`);
            continue;
        }

        const normRole = normalizeJobRole(job.jobTitle || "");
        const emailRoleKey = `${emailLower}|${normRole}`;
        const compRoleKey = `${(job.companyName || "").toLowerCase().trim()}|${normRole}`;

        if (appliedEmailRoles.has(emailRoleKey) || appliedCompanyRoles.has(compRoleKey)) {
            console.log(`[WFHJobDiscovery] Skipping duplicate application: already applied to ${job.companyName} (${emailLower})`);
            continue;
        }

        if (globalBouncedSet.has(emailLower) || globalBouncedSet.has(encodeURIComponent(emailLower))) {
            console.log(`[WFHJobDiscovery] Skipping blacklisted bounced email: ${emailLower}`);
            continue;
        }

        // Verbatim in snippet check
        const isVerbatim = allTavilyResults.some((r) => {
            const cLower = (r.content || "").toLowerCase();
            const tLower = (r.title || "").toLowerCase();
            const uLower = (r.url || "").toLowerCase();
            return cLower.includes(emailLower) || tLower.includes(emailLower) || uLower.includes(emailLower);
        });
        if (!isVerbatim) {
            console.log(`[WFHJobDiscovery] Email ${emailLower} was not found verbatim in search snippets. Skipping.`);
            continue;
        }

        // Excluded companies check
        if (excludedCompanies.length > 0) {
            const compLower = (job.companyName || "").toLowerCase().trim();
            const isExcluded = excludedCompanies.some((ex) => compLower.includes(ex.toLowerCase().trim()));
            if (isExcluded) {
                console.log(`[WFHJobDiscovery] Skipping job from excluded company: ${job.companyName}`);
                continue;
            }
        }

        // MX DNS check
        const hasMx = await verifyEmailDomainMx(email);
        if (!hasMx) {
            console.log(`[WFHJobDiscovery] Skipping email ${email} due to invalid domain MX records.`);
            continue;
        }

        validFilteredJobs.push(job);
        if (validFilteredJobs.length >= maxApplications) break;
    }

    if (validFilteredJobs.length === 0) {
        await logFeatureExecution(uid, {
            feature: "wfh_remote",
            featureTitle: "WFH Remote Job Hunter",
            status: "no_results",
            count: 0,
            message: `All found openings in ${customLocation} were filtered out (duplicates, invalid MX, or blacklisted).`,
            isManual: true
        });
        return {
            success: true,
            appliedCount: 0,
            jobs: [],
            message: `Found WFH openings in "${customLocation}" were already applied to or invalid.`
        };
    }

    // Configure Nodemailer transporter with candidate's Gmail credentials
    const cleanPassword = appPassword.replace(/\s+/g, "");
    const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
            user: userEmail,
            pass: cleanPassword
        }
    });

    const successfullyAppliedJobs: any[] = [];

    for (let i = 0; i < validFilteredJobs.length; i++) {
        const job = validFilteredJobs[i];
        if (i > 0) {
            const delayMs = 15000 + Math.floor(Math.random() * 10000);
            console.log(`[WFHJobDiscovery] Pacing WFH application sending: waiting ${Math.round(delayMs / 1000)}s...`);
            await new Promise((res) => setTimeout(res, delayMs));
        }

        try {
            const matchedProfile = getBestMatchingResumeProfile(job.jobTitle, job.keySkills, resumeProfiles);
            const cleanPdfB64 = (matchedProfile.base64 || resumeBase64 || "").replace(/^data:application\/pdf;base64,/, "");
            const jobAttachments = cleanPdfB64
                ? [
                      {
                          filename: matchedProfile.fileName || resumeFileName || "Resume.pdf",
                          content: Buffer.from(cleanPdfB64, "base64"),
                          contentType: "application/pdf"
                      }
                  ]
                : [];

            const formatted = formatEmailContent(job.generatedCoverLetter);
            const mailOptions = {
                from: `"${applicantName}" <${userEmail}>`,
                to: job.recipientEmail.trim(),
                subject: job.generatedSubject || `Application for ${job.jobTitle} (Remote) - ${applicantName}`,
                text: formatted.text,
                html: formatted.html,
                attachments: jobAttachments
            };

            const info = await transporter.sendMail(mailOptions);
            console.log(`[WFHJobDiscovery] Sent WFH email to ${job.recipientEmail} (${job.companyName}): ${info.messageId}`);

            const applicationRecord = {
                jobTitle: job.jobTitle,
                companyName: job.companyName,
                recipientEmail: job.recipientEmail.trim(),
                location: `${customLocation} (Remote)`,
                isRemote: true,
                wfhLocation: customLocation,
                experienceRequired: job.experienceRequired || `${minExp}-${maxExp} Years`,
                source: "wfh_remote",
                sourcePlatform: "WFH Remote Job Hunter 🏠",
                sourceUrl: job.sourceUrl || "",
                subject: job.generatedSubject,
                generatedSubject: job.generatedSubject,
                coverLetter: job.generatedCoverLetter,
                generatedCoverLetter: job.generatedCoverLetter,
                appliedAt: admin.firestore.FieldValue.serverTimestamp(),
                status: "sent",
                messageId: info.messageId || "",
                isAutoApplied: true,
                appliedDateStr: todayStr,
                modelUsed: modelUsed || "gemini-flash",
                resumeProfileName: matchedProfile.title
            };

            const appDocRef = await db.collection("users").doc(uid).collection("job_applications").add(applicationRecord);

            const appliedEmailKey = `${job.recipientEmail.toLowerCase().trim()}|${normalizeJobRole(job.jobTitle || "")}`;
            const appliedCompKey = `${(job.companyName || "").toLowerCase().trim()}|${normalizeJobRole(job.jobTitle || "")}`;
            appliedEmailRoles.add(appliedEmailKey);
            appliedCompanyRoles.add(appliedCompKey);

            successfullyAppliedJobs.push({
                id: appDocRef.id,
                ...applicationRecord
            });
        } catch (mailErr: any) {
            console.error(`[WFHJobDiscovery] Failed sending email to ${job.recipientEmail}:`, mailErr);
            const errStr = (mailErr.message || "").toLowerCase();
            if (
                errStr.includes("550") ||
                errStr.includes("5.1.1") ||
                errStr.includes("user unknown") ||
                errStr.includes("address not found") ||
                errStr.includes("mailbox unavailable") ||
                errStr.includes("recipient rejected") ||
                errStr.includes("invalid recipient")
            ) {
                try {
                    const cleanRecip = job.recipientEmail.toLowerCase().trim();
                    await db.collection("system_bounced_emails").doc(encodeURIComponent(cleanRecip)).set({
                        email: cleanRecip,
                        companyName: job.companyName || "",
                        bouncedAt: admin.firestore.FieldValue.serverTimestamp(),
                        reason: mailErr.message?.substring(0, 300) || "Invalid recipient / 550 bounce",
                        reportedByUid: uid,
                        source: "wfh_discovery_smtp_failure"
                    }, { merge: true });
                } catch (bErr: any) {
                    console.warn("[WFHJobDiscovery] Failed to record bounced email in blacklist:", bErr.message);
                }
            }
        }
    }

    const userDocUpdate: any = {
        jobsLastRan: admin.firestore.FieldValue.serverTimestamp()
    };
    if (successfullyAppliedJobs.length > 0) {
        userDocUpdate.jobsLastApplied = admin.firestore.FieldValue.serverTimestamp();
    }
    await db.collection("users").doc(uid).set(userDocUpdate, { merge: true });

    // Send push notification if applications were sent
    if (successfullyAppliedJobs.length > 0) {
        try {
            const userTokenDoc = await db.collection("usernames").where("uid", "==", uid).limit(1).get();
            if (!userTokenDoc.empty) {
                const fcmToken = userTokenDoc.docs[0].data()?.fcmToken;
                if (fcmToken) {
                    const compNames = successfullyAppliedJobs.map((j) => j.companyName).filter(Boolean).slice(0, 3).join(", ");
                    const notifTitle = `🏠 WFH Applied to ${successfullyAppliedJobs.length} Remote Job${successfullyAppliedJobs.length > 1 ? "s" : ""}!`;
                    const notifBody = `Sent tailored applications for remote roles at: ${compNames} in ${customLocation}.`;

                    await admin.messaging().send({
                        token: fcmToken,
                        notification: {
                            title: notifTitle,
                            body: notifBody
                        },
                        data: {
                            type: "JOB_ASSISTANT",
                            appliedCount: String(successfullyAppliedJobs.length)
                        }
                    });
                }
            }
        } catch (notifErr: any) {
            console.warn(`[WFHJobDiscovery] Could not send push notification:`, notifErr.message);
        }
    }

    const summaryMsg = successfullyAppliedJobs.length > 0
        ? `Successfully discovered and applied to ${successfullyAppliedJobs.length} WFH Remote job(s) in ${customLocation}.`
        : `Found WFH openings in ${customLocation}, but email dispatch could not complete.`;

    await logFeatureExecution(uid, {
        feature: "wfh_remote",
        featureTitle: "WFH Remote Job Hunter",
        status: successfullyAppliedJobs.length > 0 ? "success" : "no_results",
        count: successfullyAppliedJobs.length,
        message: summaryMsg,
        isManual: true
    });

    return {
        success: true,
        appliedCount: successfullyAppliedJobs.length,
        jobs: successfullyAppliedJobs,
        message: summaryMsg
    };
}

/**
 * Callable Firebase Cloud Function to trigger WFH Job Discovery on demand.
 */
export const runWFHJobDiscoveryCallable = functions
    .runWith({ timeoutSeconds: 540, memory: "1GB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
        }
        const uid = context.auth.uid;
        const customLocation = (data.customLocation || "India").toString().trim();
        const maxApplications = Number(data.maxApplications || 4);

        try {
            const result = await discoverAndApplyWFHForUser(uid, {
                customLocation,
                maxApplications
            });
            if (!result.success) {
                throw new functions.https.HttpsError("failed-precondition", result.message);
            }
            return result;
        } catch (error: any) {
            console.error(`runWFHJobDiscoveryCallable failed for ${uid}:`, error);
            if (error instanceof functions.https.HttpsError) {
                throw error;
            }
            throw new functions.https.HttpsError("internal", error.message || "Failed to discover and apply to WFH jobs.");
        }
    });
