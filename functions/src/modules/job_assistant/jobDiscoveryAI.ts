import * as functions from "firebase-functions";
import * as nodemailer from "nodemailer";
import * as moment from "moment-timezone";
import * as dns from "dns";
import { admin, db } from "../../config/firebase";
import { logNotification } from "../../utils/logger";
import { callGeminiAPI } from "../../utils/geminiHelper";
import { enqueueUserCloudTask } from "../../utils/cloudTasksHelper";

interface DiscoveredJob {
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
 * Helper to validate email strings
 */
function isValidEmail(email: string): boolean {
    if (!email || typeof email !== 'string') return false;
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
async function verifyEmailDomainMx(email: string): Promise<boolean> {
    try {
        const domain = email.split('@')[1]?.trim();
        if (!domain) return false;
        const records = await dns.promises.resolveMx(domain);
        return records && records.length > 0;
    } catch (e) {
        console.warn(`[JobDiscovery] MX DNS validation failed for domain in '${email}':`, e);
        return false;
    }
}

/**
 * Searches and automatically applies to matching jobs for a specific user
 */
export async function discoverAndApplyForUser(
    uid: string,
    options?: {
        targetRoles?: string[];
        locations?: string[];
        minExpYears?: number;
        maxExpYears?: number;
        maxApplications?: number;
        isManualTrigger?: boolean;
    }
): Promise<{ success: boolean; appliedCount: number; jobs: any[]; message: string }> {
    const userDoc = await db.collection("users").doc(uid).get();
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
        return { success: false, appliedCount: 0, jobs: [], message: "Gmail & App Password not configured in Job Assistant Settings." };
    }

    if (!resumeBase64) {
        console.log(`[JobDiscovery] User ${uid} has not uploaded a Master Resume. Skipping.`);
        return { success: false, appliedCount: 0, jobs: [], message: "Master Resume PDF not uploaded in Job Assistant Settings." };
    }

    // Record jobsLastRan timestamp immediately
    await db.collection("users").doc(uid).set({
        jobsLastRan: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    // Resolve roles & locations from options or user profile
    const autoApplySettings = userData.autoApplySettings || {};
    let targetRoles: string[] = options?.targetRoles || autoApplySettings.targetRoles || [
        "Flutter Developer",
        "Mobile Application Developer",
        "DevOps Engineer",
        "Cloud Engineer",
        "Site Reliability Engineer"
    ];
    if (typeof targetRoles === 'string') {
        targetRoles = (targetRoles as string).split(',').map((s: string) => s.trim()).filter((s: string) => s.length > 0);
    }
    if (targetRoles.length === 0) {
        targetRoles = ["Flutter Developer", "DevOps Engineer", "Cloud Engineer"];
    }

    let targetLocations: string[] = options?.locations || autoApplySettings.locations || [
        "Bengaluru",
        "India",
        "Remote"
    ];
    if (typeof targetLocations === 'string') {
        targetLocations = (targetLocations as string).split(',').map((s: string) => s.trim()).filter((s: string) => s.length > 0);
    }
    if (targetLocations.length === 0) {
        targetLocations = ["Bengaluru", "India", "Remote"];
    }

    const minExp = options?.minExpYears !== undefined ? Number(options.minExpYears) : Number(autoApplySettings.minExpYears ?? 0);
    const maxExp = options?.maxExpYears !== undefined ? Number(options.maxExpYears) : Number(autoApplySettings.maxExpYears ?? 3);

    const maxApplyLimit = options?.maxApplications || autoApplySettings.maxPerRun || 6;

    // Fetch previously applied emails/companies to avoid duplicate applications
    const existingAppsSnap = await db.collection("users").doc(uid).collection("job_applications").get();
    const appliedEmails = new Set<string>();
    const appliedCompanyRoles = new Set<string>();

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
    const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
    let apiKey = "";
    if (configDoc.exists) {
        apiKey = configDoc.data()?.apiKey || "";
    }
    if (!apiKey) {
        throw new Error("Gemini API key is not configured in admin_creds.");
    }

    const formattedRolesList = targetRoles.map((role, idx) => `   ${idx + 1}. "${role}"`).join("\n");
    const locQuery = targetLocations.join(" OR ");
    const todayStr = moment().tz("Asia/Kolkata").format("YYYY-MM-DD");

    const isFresherCandidate = (minExp === 0 && maxExp === 0);
    const expTargetStr = isFresherCandidate
        ? "Seeking FRESHER / ENTRY-LEVEL / 0 YEARS EXPERIENCE roles ONLY."
        : `Seeking ${minExp} to ${maxExp} Years Experience / Junior / Associate / Mid-level roles.`;

    const expMandateStr = isFresherCandidate
        ? "3. EXPERIENCE REQUIREMENT (FRESHERS / 0 YEARS ONLY): ONLY include openings explicitly accepting Freshers, Entry-Level candidates, Trainees, or 0 Years Experience. STRICTLY EXCLUDE any roles requiring > 0 years prior work experience."
        : `3. EXPERIENCE REQUIREMENT (${minExp} TO ${maxExp} YEARS ONLY): ONLY include roles requiring between ${minExp} and ${maxExp} years experience (or Freshers/Entry-level if min is 0). EXCLUDE any roles requiring > ${maxExp} years experience (e.g. Senior, Lead, Staff, Principal).`;

    const prompt = `You are an elite automated job discovery and recruiter outreach AI agent.
Target Roles to Search:
${formattedRolesList}

Target Locations: ${locQuery}
Candidate Name: "${applicantName}"
Candidate Experience Target: ${expTargetStr}

CRITICAL SEARCH & EXTRACTION MANDATES:
1. INDIVIDUAL SEARCH PER TARGET ROLE: You MUST perform dedicated web search grounding for EACH specific role listed above individually:
${formattedRolesList}
   - First, search for active postings specifically for role #1 across all platforms.
   - Next, search for active postings specifically for role #2 across all platforms.
   - Continue searching for each specified target role individually.
   - Your final output list MUST contain matching job openings for EVERY role specified by the candidate (aiming for 1-2 fresh job openings per target role, up to 6 total jobs).

2. RECRUITER EMAIL IS MANDATORY: Every single job item MUST contain a verified recruiter / HR / hiring contact email address (e.g. hr@company.com, careers@company.com, hiring@company.com, jobs@company.com, talent@company.com, or specific recruiter email). If NO valid email address is mentioned in the job posting/snippet, DO NOT INCLUDE THAT JOB.

${expMandateStr}

4. HUMAN-WRITTEN, HIGH-CONVERTING APPLICATION EMAIL:
   - For each matching job, write a highly authentic, natural, and engaging cover letter tailored specifically to that job title and company.
   - Read the candidate's attached Resume PDF to extract concrete accomplishments, technical skills (e.g., Flutter, Dart, State Management, REST APIs, Firebase, Cloud/DevOps, Docker, CI/CD), and align them specifically with the company's domain and job requirements.
   - Structure:
     a) Enthusiastic opening identifying the specific role and company.
     b) Value Proposition: Clear explanation of what direct value and expertise the candidate brings based on real resume highlights.
     c) Key Relevant Skills: 3-4 bullet points matching the exact requirements of the job.
     d) Professional closing & Call to Action proposing a brief discussion, mentioning the attached resume.
     e) Sign-off: "Sincerely,\\n${applicantName}" (Never use placeholders like [Your Name]).
   - Subject line format: "Application for [Job Title] - ${applicantName}"

5. LOCATION & WORK MODE MATCHING:
   - Candidate Target Locations: ${targetLocations.join(', ')}.
   - On-Site / Hybrid Roles: City names (e.g. Bengaluru, Chennai, Hyderabad, Noida, Pune) or "India" target On-Site, In-Office, and Hybrid openings in those hubs across India.
   - Remote / WFH Roles: "Remote" targets Fully Remote / Work-From-Home (WFH) openings.
   - Match both On-Site/Hybrid roles in target Indian cities/India AND Remote/WFH openings when specified.

Respond ONLY with a JSON array matching this schema:
[
  {
    "jobTitle": "string",
    "companyName": "string",
    "recipientEmail": "string (MUST be a valid email address)",
    "location": "string",
    "experienceRequired": "string (e.g. ${minExp}-${maxExp} years)",
    "sourcePlatform": "string (e.g. LinkedIn, Wellfound, Google Jobs, Company Careers)",
    "sourceUrl": "string",
    "keySkills": ["string"],
    "generatedSubject": "string",
    "generatedCoverLetter": "string"
  }
]
If no matching jobs with verified emails and ${minExp}-${maxExp} years experience are found, respond with an empty JSON array: [].`;

    const inlineParts: any[] = [];
    if (resumeBase64) {
        const cleanResumeB64 = resumeBase64.replace(/^data:application\/pdf;base64,/, '');
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
        tools: [
            {
                googleSearch: {}
            }
        ]
    };

    console.log(`[JobDiscovery] Running Gemini Search Grounding for user ${uid} (Roles: ${targetRoles.join(', ')})...`);
    let rawText = "";
    let modelUsed = "";
    try {
        const geminiResult = await callGeminiAPI(payload, { timeout: 240000 });
        rawText = geminiResult.text || "";
        modelUsed = geminiResult.modelUsed || "";
    } catch (apiErr: any) {
        console.error("[JobDiscovery] Gemini search failed:", apiErr.message);
        return { success: false, appliedCount: 0, jobs: [], message: `Job Search AI temporarily busy: ${apiErr.message}` };
    }

    if (!rawText) {
        return { success: true, appliedCount: 0, jobs: [], message: "Empty response from search agent." };
    }

    // Extract JSON from response
    let discoveredJobs: DiscoveredJob[] = [];
    try {
        const jsonMatch = rawText.match(/\[[\s\S]*\]/);
        if (jsonMatch) {
            discoveredJobs = JSON.parse(jsonMatch[0]);
        } else {
            discoveredJobs = JSON.parse(rawText);
        }
    } catch (parseErr) {
        console.error("[JobDiscovery] Failed to parse JSON from search result:", parseErr, rawText);
        return { success: false, appliedCount: 0, jobs: [], message: "Failed to parse AI job discoveries." };
    }

    if (!Array.isArray(discoveredJobs) || discoveredJobs.length === 0) {
        console.log(`[JobDiscovery] 0 matching jobs found with recruiter emails for user ${uid}.`);
        return { success: true, appliedCount: 0, jobs: [], message: "No fresh matching openings with recruiter emails found today." };
    }

    // Filter valid jobs with active MX record validation
    const validFilteredJobs: DiscoveredJob[] = [];
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
        console.log(`[JobDiscovery] All discovered jobs were either duplicates, lacked valid emails, or had unreachable domains.`);
        return { success: true, appliedCount: 0, jobs: [], message: "Discovered openings were already applied to or had unreachable domains." };
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

    const successfullyAppliedJobs: any[] = [];

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
                generatedSubject: job.generatedSubject,
                coverLetter: job.generatedCoverLetter,
                generatedCoverLetter: job.generatedCoverLetter,
                appliedAt: admin.firestore.FieldValue.serverTimestamp(),
                status: "sent",
                messageId: info.messageId || "",
                isAutoApplied: true,
                appliedDateStr: todayStr,
                modelUsed: modelUsed || "gemini-3.7-flash"
            };

            const appDocRef = await db.collection("users").doc(uid).collection("job_applications").add(applicationRecord);

            appliedEmails.add(job.recipientEmail.toLowerCase().trim());
            successfullyAppliedJobs.push({
                id: appDocRef.id,
                ...applicationRecord
            });
        } catch (mailErr: any) {
            console.error(`[JobDiscovery] Failed sending email to ${job.recipientEmail}:`, mailErr);
        }
    }

    // Record jobsLastRan and jobsLastApplied on user document
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
                    const compNames = successfullyAppliedJobs.map(j => j.companyName).filter(Boolean).slice(0, 3).join(', ');
                    const notifTitle = `🚀 Auto-Applied to ${successfullyAppliedJobs.length} New Job${successfullyAppliedJobs.length > 1 ? 's' : ''}!`;
                    const notifBody = `Sent tailored resumes & cover letters to: ${compNames}. Tap to view sent applications.`;

                    await admin.messaging().send({
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

                    await logNotification(uid, notifTitle, notifBody, "JOB_ASSISTANT");
                }
            }
        } catch (notifErr) {
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
/**
 * Cloud Tasks queue handler for isolated sequential Auto-Apply processing per user.
 * maxConcurrentDispatches: 1 guarantees strictly 1 user at a time.
 */
export const processAutoApplyUserTask = functions.runWith({ timeoutSeconds: 300, memory: "1GB" }).tasks
    .taskQueue({
        retryConfig: { maxAttempts: 2 },
        rateLimits: { maxConcurrentDispatches: 1 },
    })
    .onDispatch(async (rawPayload: any, context?: any) => {
        const payload = (rawPayload && typeof rawPayload === 'object' && rawPayload.data) ? rawPayload.data : rawPayload;
        const uid = payload?.uid;
        if (!uid) {
            console.error("[processAutoApplyUserTask] Missing uid in payload:", rawPayload);
            return;
        }

        console.log(`[processAutoApplyUserTask] Processing automated job discovery & apply for user ${uid}`);
        try {
            const result = await discoverAndApplyForUser(uid, { isManualTrigger: false });
            console.log(`[processAutoApplyUserTask] Successfully finished auto-apply for user ${uid}:`, result);
        } catch (err: any) {
            console.error(`[processAutoApplyUserTask] Error in auto-apply for user ${uid}:`, err.message || err);
            throw err;
        }
    });

/**
 * Twice-Daily Automated Job Discovery & Auto-Apply Dispatcher (10 AM & 10 PM IST)
 */
export async function internalAutoJobDiscoveryAndApply(): Promise<void> {
    console.log("[internalAutoJobDiscoveryAndApply] Starting twice-daily automated job discovery & apply dispatcher (10 AM & 10 PM IST)...");
    try {
        const usersSnap = await db.collection("users").get();
        const eligibleUids: string[] = [];

        for (const doc of usersSnap.docs) {
            const uid = doc.id;
            const data = doc.data() || {};
            const enabledModules = data.enabledModules || [];

            // 1. Must have job_assistant enabled and autoApply not disabled
            const isModuleEnabled = enabledModules.includes("job_assistant") || data.autoApplySettings?.enabled === true;
            if (!isModuleEnabled || data.autoApplySettings?.enabled === false) {
                console.log(`[internalAutoJobDiscoveryAndApply] Skipping user ${uid}: job_assistant not enabled or autoApply disabled.`);
                continue;
            }

            // 2. Must have uploaded a Master Resume
            const resumeDoc = await db.collection("users").doc(uid).collection("job_profiles").doc("master_resume").get();
            const resumeBase64 = resumeDoc.data()?.base64Data;
            if (!resumeBase64) {
                console.log(`[internalAutoJobDiscoveryAndApply] Skipping user ${uid}: Master Resume PDF not uploaded.`);
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
            const taskId = await enqueueUserCloudTask(
                "processAutoApplyUserTask",
                "processAutoApplyUserTask",
                { uid },
                etaUnix
            );

            // Fallback: If Cloud Tasks queue enqueue fails, process directly with safe delay
            if (!taskId) {
                console.warn(`[internalAutoJobDiscoveryAndApply] Cloud Tasks queue unavailable for ${uid}. Running directly as fallback...`);
                try {
                    await discoverAndApplyForUser(uid, { isManualTrigger: false });
                } catch (e: any) {
                    console.error(`[internalAutoJobDiscoveryAndApply] Error in fallback execution for ${uid}:`, e.message || e);
                }
                await new Promise((r) => setTimeout(r, 5000));
            }
        }
    } catch (err) {
        console.error("[internalAutoJobDiscoveryAndApply] Error in scheduled job runner:", err);
    }
}

/**
 * On-Demand HTTPS Callable Function triggered from Flutter App
 */
export const triggerAutoJobDiscoveryAndApply = functions.runWith({ timeoutSeconds: 300, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    const uid = context.auth.uid;
    try {
        const result = await discoverAndApplyForUser(uid, {
            targetRoles: data.targetRoles,
            locations: data.locations,
            minExpYears: data.minExpYears,
            maxExpYears: data.maxExpYears,
            maxApplications: data.maxApplications || 4,
            isManualTrigger: true
        });
        if (!result.success) {
            throw new functions.https.HttpsError('failed-precondition', result.message);
        }
        return result;
    } catch (error: any) {
        console.error(`triggerAutoJobDiscoveryAndApply failed for ${uid}:`, error);
        if (error instanceof functions.https.HttpsError) {
            throw error;
        }
        throw new functions.https.HttpsError('internal', error.message || 'Failed to discover and apply to jobs.');
    }
});
