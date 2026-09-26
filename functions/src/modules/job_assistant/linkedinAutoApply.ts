import * as functions from "firebase-functions";
import * as nodemailer from "nodemailer";
import * as moment from "moment-timezone";
import { admin, db } from "../../config/firebase";
import { searchLinkedInPostsViaApify, LinkedInPostItem } from "./apifyLinkedInPosts";
import { callGeminiAPI } from "../../utils/geminiHelper";
import { logFeatureExecution } from "../../utils/featureLogger";
import { logNotification } from "../../utils/logger";

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
    minExpYears?: number;
    maxExpYears?: number;
}

/**
 * Executes real-time LinkedIn recruiter post scraping via Apify, checks unified applied job history
 * to ensure zero duplicate emails, evaluates experience/role fit with Gemini, and auto-applies via Gmail.
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

        // 1. Admin Module Control: Must be enabled for user
        if (!enabledModules.includes("linkedin_auto_apply")) {
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

        // 4. Target Roles & Experience Range
        let targetRoles: string[] = options?.roles || linkedinSettings.targetRoles || userData.autoApplySettings?.targetRoles || [];
        if (typeof targetRoles === 'string') {
            targetRoles = (targetRoles as string).split(',').map(s => s.trim()).filter(Boolean);
        }
        if (targetRoles.length === 0) {
            targetRoles = ["DevOps Engineer", "Cloud Engineer", "Site Reliability Engineer"];
        }

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

        // 6. Check UNIFIED APPLIED JOB HISTORY to prevent duplicate emails
        const existingAppsSnap = await db.collection("users").doc(uid).collection("job_applications").get();
        const appliedEmails = new Set<string>();
        const appliedEmailRoles = new Set<string>();

        existingAppsSnap.forEach((doc) => {
            const d = doc.data();
            const email = (d.recipientEmail || "").toLowerCase().trim();
            const role = normalizeJobRole(d.jobTitle || "");
            if (email) {
                appliedEmails.add(email);
            }
            if (email && role) {
                appliedEmailRoles.add(`${email}|${role}`);
            }
        });

        console.log(`[LinkedInAutoApply] User ${uid} has ${appliedEmails.size} previously applied email(s) in unified history.`);

        // 7. Scrape Real-Time LinkedIn Posts via Apify (Single Run, No Retries)
        let searchResult;
        try {
            searchResult = await searchLinkedInPostsViaApify({
                apiTokens: apifyTokens,
                roles: targetRoles,
                experienceFilter,
                datePosted: "past-24h",
                maxPosts: 20
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
            return { success: true, appliedCount: 0, message: msg, jobs: [] };
        }

        // 8. Filter Posts against Unified History & Experience Restrictions
        const candidatePosts: { post: LinkedInPostItem; email: string }[] = [];
        const seniorKeywords = ["5+ years", "6+ years", "7+ years", "8+ years", "10+ years", "minimum 5 years", "principal", "staff engineer", "engineering manager", "director"];

        for (const post of posts) {
            if (!post.hasEmail || post.emails.length === 0) continue;

            const postContentLower = post.content.toLowerCase();
            
            // Experience sanity check: if user is 1-3 years and post asks for 5+ / 7+ / 8+ years, skip
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
                    console.log(`[LinkedInAutoApply] DEDUPLICATED: Email ${normEmail} was already contacted previously. Skipping.`);
                    continue;
                }

                candidatePosts.push({ post, email: normEmail });
                // Only take one unique email per post to prevent multiple emails to same post
                break;
            }
        }

        console.log(`[LinkedInAutoApply] Found ${candidatePosts.length} fresh, uncontacted candidate post(s).`);

        if (candidatePosts.length === 0) {
            const msg = "All recruiter emails from the latest LinkedIn posts have already been applied to (unified history deduped).";
            await logFeatureExecution(uid, {
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

        for (const item of postsToProcess) {
            const { post, email: recipientEmail } = item;

            // Pick matching resume profile
            const matchedProfile = resumeProfiles.find(p => 
                p.targetRoles.some((r: string) => post.content.toLowerCase().includes(r.toLowerCase()))
            ) || resumeProfiles.find(p => p.isDefault) || resumeProfiles[0];

            // Use Gemini to verify role alignment, extract metadata, and draft tailored cover letter
            let generatedApplication: any = null;
            try {
                const prompt = `You are an elite career advisor and executive recruiter.
Analyze this real-time LinkedIn recruiter hiring post:
"${post.content}"
Author: "${post.authorName}" (${post.authorTitle})

The candidate "${applicantName}" is applying with experience ${minExp}-${maxExp} years targeting roles: ${targetRoles.join(', ')}.

Requirements:
1. Determine if this post is a genuine job opening that fits within candidate's target roles and experience (${minExp}-${maxExp} years).
2. If it requires 5+ or senior years or is completely unrelated, set isMatch: false.
3. If it matches, extract:
   - "companyName": Name of the hiring company or recruitment agency.
   - "jobTitle": Clear title of the job.
   - "subject": Tailored email subject line (e.g. "Application: [Job Title] - ${applicantName}").
   - "coverLetter": A punchy, compelling 2-3 paragraph application email tailored to this post. Highlight relevant tools (e.g. AWS, Docker, Kubernetes, CI/CD, Terraform). Sign off with:
"Best regards,
${applicantName}"

Respond ONLY with valid JSON:
{
  "isMatch": boolean,
  "companyName": string,
  "jobTitle": string,
  "subject": string,
  "coverLetter": string
}`;

                const geminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();
                const geminiResp = await callGeminiAPI({
                    apiKey: geminiKey || undefined,
                    payload: {
                        contents: [{ parts: [{ text: prompt }] }],
                        generationConfig: { responseMimeType: "application/json" }
                    }
                });

                const rawText = geminiResp.text || "{}";
                generatedApplication = JSON.parse(rawText.replace(/```json/g, '').replace(/```/g, '').trim());
            } catch (aiErr: any) {
                console.warn(`[LinkedInAutoApply] Gemini post analysis error:`, aiErr.message);
                // Fallback application format if Gemini JSON parsing fails
                generatedApplication = {
                    isMatch: true,
                    companyName: post.authorTitle || "Hiring Team",
                    jobTitle: targetRoles[0],
                    subject: `Application for ${targetRoles[0]} - ${applicantName}`,
                    coverLetter: `Dear Hiring Team,\n\nI am writing to express my enthusiastic interest in the ${targetRoles[0]} position shared on LinkedIn. With hands-on experience in cloud infrastructure, automation, and modern DevOps practices, I am confident in my ability to deliver immediate value.\n\nPlease find my resume attached for your consideration. I welcome the opportunity to connect and discuss how my background aligns with your team's goals.\n\nBest regards,\n${applicantName}`
                };
            }

            if (!generatedApplication || generatedApplication.isMatch === false) {
                console.log(`[LinkedInAutoApply] Gemini marked post as non-matching. Skipping.`);
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
                const info = await transporter.sendMail({
                    from: `"${applicantName}" <${userEmail}>`,
                    to: recipientEmail,
                    subject: finalSubject,
                    text: finalBody,
                    attachments
                });

                console.log(`[LinkedInAutoApply] Application email sent to ${recipientEmail} (${finalCompany}): ${info.messageId}`);

                // Save to UNIFIED job_applications collection
                const applicationRecord = {
                    jobTitle: finalTitle,
                    companyName: finalCompany,
                    recipientEmail: recipientEmail,
                    location: "India / Remote",
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

                // Add to in-memory set immediately to prevent any subsequent post sending duplicate
                appliedEmails.add(recipientEmail);
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

            // Admin module check: must be explicitly enabled by admin
            if (!enabledModules.includes("linkedin_auto_apply")) {
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
    } catch (e: any) {
        console.error("[LinkedInAutoApply] Error in scheduled dispatcher:", e);
    }
}

/**
 * Callable Cloud Function: Allows users to trigger LinkedIn Auto-Apply on-demand from the UI.
 */
export const runLinkedInAutoApplyNow = functions.runWith({ timeoutSeconds: 300, memory: "1GB" }).https.onCall(
    async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
        }

        const uid = context.auth.uid;
        console.log(`[LinkedInAutoApply] Manual on-demand run triggered by user ${uid}`);

        const result = await processLinkedInAutoApplyForUser(uid, {
            isManual: true,
            roles: data?.roles,
            minExpYears: data?.minExpYears,
            maxExpYears: data?.maxExpYears,
            maxApplications: data?.maxApplications
        });

        return result;
    }
);
