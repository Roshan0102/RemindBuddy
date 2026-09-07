import * as functions from "firebase-functions";
import { ImapFlow } from "imapflow";
import { simpleParser } from "mailparser";
import { admin, db } from "../../config/firebase";
import { callGeminiAPI } from "../../utils/geminiHelper";
import { logNotification } from "../../utils/logger";

const GENERIC_DOMAINS = new Set([
    "gmail.com",
    "yahoo.com",
    "hotmail.com",
    "outlook.com",
    "icloud.com",
    "protonmail.com",
    "zoho.com",
    "live.com"
]);

interface ReplyAnalysisResult {
    isLegitimateResponse: boolean;
    responseType: "interview_invite" | "assessment" | "hr_query" | "acknowledgment" | "rejection" | "other";
    confidence: number;
    summary: string;
    actionRequired: string;
}

/**
 * Checks incoming emails for a specific user to detect legitimate recruiter replies,
 * interview invitations, coding assessments, or status updates for sent job applications.
 * Automatically filters out newsletters, automated job alert digests, and marketing spam.
 */
export async function checkUserJobReplies(uid: string): Promise<{ checked: number; repliesFound: number }> {
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
        return { checked: 0, repliesFound: 0 };
    }

    const userData = userDoc.data() || {};
    const emailConfig = userData.emailConfig || {};
    const userEmail = emailConfig.email;
    const appPassword = emailConfig.appPassword;

    if (!userEmail || !appPassword) {
        console.log(`[ReplyTracker] User ${uid} has not configured emailConfig. Skipping.`);
        return { checked: 0, repliesFound: 0 };
    }

    // Retrieve active sent job applications
    const appsSnap = await db.collection("users").doc(uid).collection("job_applications")
        .where("status", "==", "sent")
        .get();

    // Also retrieve active networking leads where cold email was dispatched
    const leadsSnap = await db.collection("users").doc(uid).collection("networking_leads")
        .where("emailSent", "==", true)
        .where("status", "in", ["email_sent", "note_sent", "discovered"])
        .get();

    if (appsSnap.empty && leadsSnap.empty) {
        console.log(`[ReplyTracker] User ${uid} has 0 pending 'sent' applications or startup pitches.`);
        return { checked: 0, repliesFound: 0 };
    }

    const sentApps = [
        ...appsSnap.docs.map(d => ({
            id: d.id,
            ref: d.ref,
            isNetworkingLead: false,
            ...d.data()
        })),
        ...leadsSnap.docs.map(d => {
            const data = d.data();
            return {
                id: d.id,
                ref: d.ref,
                isNetworkingLead: true,
                jobTitle: data.currentRole || "Technology Leader",
                companyName: data.companyName,
                recipientEmail: data.email,
                appliedAt: data.emailSentAt || data.discoveredAt,
                messageId: data.messageId,
                ...data
            };
        })
    ] as any[];

    // Determine search start date (earliest applied date, capped at 30 days ago)
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    let earliestDate = thirtyDaysAgo;
    for (const app of sentApps) {
        let appDate: Date | null = null;
        if (app.appliedAt) {
            if (app.appliedAt.toDate) {
                appDate = app.appliedAt.toDate();
            } else if (app.appliedAt instanceof Date) {
                appDate = app.appliedAt;
            } else if (typeof app.appliedAt === "string") {
                appDate = new Date(app.appliedAt);
            }
        }
        if (appDate && !isNaN(appDate.getTime()) && appDate > thirtyDaysAgo && appDate < earliestDate) {
            earliestDate = appDate;
        }
    }

    // Prepare indexing maps for fast candidate matching
    const appsByMessageId = new Map<string, any>();
    const appsByRecipient = new Map<string, any>();
    const appsByDomain = new Map<string, any[]>();
    const appsByCompany = new Map<string, any[]>();

    for (const app of sentApps) {
        if (app.messageId) {
            const cleanMid = app.messageId.toLowerCase().trim().replace(/[<>]/g, "");
            if (cleanMid) appsByMessageId.set(cleanMid, app);
        }

        const recEmail = (app.recipientEmail || "").toLowerCase().trim();
        if (recEmail) {
            appsByRecipient.set(recEmail, app);
            const atIdx = recEmail.indexOf("@");
            if (atIdx !== -1) {
                const domain = recEmail.substring(atIdx + 1);
                if (domain && !GENERIC_DOMAINS.has(domain)) {
                    const list = appsByDomain.get(domain) || [];
                    list.push(app);
                    appsByDomain.set(domain, list);
                }
            }
        }

        const compName = (app.companyName || "").toLowerCase().trim();
        if (compName && compName.length > 2) {
            const list = appsByCompany.get(compName) || [];
            list.push(app);
            appsByCompany.set(compName, list);
        }
    }

    const cleanAppPassword = appPassword.replace(/\s+/g, "");
    const client = new ImapFlow({
        host: "imap.gmail.com",
        port: 993,
        secure: true,
        auth: {
            user: userEmail,
            pass: cleanAppPassword
        },
        logger: false
    });

    let repliesFound = 0;
    let checkedCount = 0;

    try {
        await client.connect();
        const lock = await client.getMailboxLock("INBOX");

        try {
            // Search emails received since the earliest application date
            const searchResult = await client.search({ since: earliestDate }, { uid: true });
            if (!Array.isArray(searchResult) || searchResult.length === 0) {
                console.log(`[ReplyTracker] No emails found since ${earliestDate.toISOString()}`);
                return { checked: 0, repliesFound: 0 };
            }
            checkedCount = searchResult.length;

            console.log(`[ReplyTracker] Scanning ${checkedCount} recent emails for replies to ${sentApps.length} applications...`);

            // Fetch candidate envelopes & raw headers
            const fetchIterator = client.fetch(searchResult, {
                uid: true,
                envelope: true,
                headers: [
                    "in-reply-to",
                    "references",
                    "list-unsubscribe",
                    "precedence",
                    "auto-submitted",
                    "x-auto-response-suppress"
                ],
                source: true
            });

            for await (const msg of fetchIterator) {
                const envelope = msg.envelope;
                if (!envelope) continue;

                const fromList = envelope.from || [];
                if (fromList.length === 0) continue;
                const sender = fromList[0];
                const senderAddress = (sender.address || "").toLowerCase().trim();
                const senderName = sender.name || "";
                const subject = envelope.subject || "";
                const subjectLower = subject.toLowerCase();

                // Self-sent email check
                if (senderAddress === userEmail.toLowerCase().trim()) {
                    continue;
                }

                // 1. HARD FILTER: Automated Newsletters & Subscriptions
                // If the user subscribed to company job postings (e.g. TCS alerts), headers will have List-Unsubscribe or Precedence: bulk
                let hasUnsubscribeHeader = false;
                let hasBulkPrecedence = false;
                let hasAutoSubmitted = false;

                if (msg.headers) {
                    const headersStr = msg.headers.toString("utf8").toLowerCase();
                    if (headersStr.includes("list-unsubscribe:")) hasUnsubscribeHeader = true;
                    if (headersStr.includes("precedence: bulk") || headersStr.includes("precedence: list")) hasBulkPrecedence = true;
                    if (headersStr.includes("auto-submitted: auto-generated")) hasAutoSubmitted = true;
                }

                if (hasUnsubscribeHeader || hasBulkPrecedence) {
                    // Definite automated newsletter or subscription digest
                    continue;
                }

                // Automated sender address patterns
                if (
                    senderAddress.includes("noreply") ||
                    senderAddress.includes("no-reply") ||
                    senderAddress.includes("newsletter") ||
                    senderAddress.includes("marketing") ||
                    senderAddress.includes("alerts@") ||
                    senderAddress.includes("digest") ||
                    senderAddress.includes("donotreply")
                ) {
                    continue;
                }

                // Automated subject patterns for job alerts & digests
                if (
                    subjectLower.includes("new job alert") ||
                    subjectLower.includes("weekly jobs digest") ||
                    subjectLower.includes("jobs matching your profile") ||
                    subjectLower.includes("newsletter") ||
                    subjectLower.includes("daily digest") ||
                    (hasAutoSubmitted && subjectLower.includes("job"))
                ) {
                    continue;
                }

                // 2. CANDIDATE MATCHING
                let matchedApp: any = null;

                // Match Method A: Direct Thread (In-Reply-To / References matching our sent messageId)
                const inReplyTo = (envelope.inReplyTo || "").toLowerCase().replace(/[<>]/g, "").trim();
                if (inReplyTo && appsByMessageId.has(inReplyTo)) {
                    matchedApp = appsByMessageId.get(inReplyTo);
                }

                // Match Method B: Exact Recruiter Email Address
                if (!matchedApp && appsByRecipient.has(senderAddress)) {
                    matchedApp = appsByRecipient.get(senderAddress);
                }

                // Match Method C: Same Company Domain (e.g. hr.john@tcs.com when we applied to careers@tcs.com)
                if (!matchedApp) {
                    const senderAt = senderAddress.indexOf("@");
                    if (senderAt !== -1) {
                        const senderDomain = senderAddress.substring(senderAt + 1);
                        if (!GENERIC_DOMAINS.has(senderDomain) && appsByDomain.has(senderDomain)) {
                            const domainApps = appsByDomain.get(senderDomain) || [];
                            // Find the best matching application for this domain
                            matchedApp = domainApps.find(a => 
                                subjectLower.includes(a.jobTitle.toLowerCase()) ||
                                subjectLower.includes("interview") ||
                                subjectLower.includes("application") ||
                                subjectLower.includes("profile") ||
                                subjectLower.includes("shortlist")
                            ) || domainApps[0];
                        }
                    }
                }

                // Match Method D: Company Name Mention in Subject (Cross-thread from HR recruiter)
                if (!matchedApp) {
                    for (const [comp, compApps] of appsByCompany.entries()) {
                        if (subjectLower.includes(comp) || senderName.toLowerCase().includes(comp)) {
                            matchedApp = compApps.find(a => 
                                subjectLower.includes(a.jobTitle.toLowerCase()) ||
                                subjectLower.includes("interview") ||
                                subjectLower.includes("application") ||
                                subjectLower.includes("candidature")
                            ) || compApps[0];
                            if (matchedApp) break;
                        }
                    }
                }

                if (!matchedApp) {
                    continue;
                }

                // 3. PARSE MESSAGE BODY & SNIPPET
                let bodyText = "";
                try {
                    if (msg.source) {
                        const parsed = await simpleParser(msg.source);
                        bodyText = parsed.text || parsed.html || "";
                    }
                } catch (parseErr) {
                    console.warn(`[ReplyTracker] Could not parse email body for message ${msg.uid}:`, parseErr);
                }

                const cleanBodySnippet = bodyText
                    .replace(/\s+/g, " ")
                    .replace(/https?:\/\/\S+/g, "[link]")
                    .trim()
                    .substring(0, 1500);

                // 4. GEMINI AI VERIFICATION & CLASSIFICATION (The Ultimate Arbiter)
                // Ensures that even if TCS sent an email, if it's a promotional/job alert digest, it will NOT be marked as reply.
                let analysis: ReplyAnalysisResult | null = null;
                try {
                    const aiPrompt = `You are an elite AI Recruiter Assistant analyzing incoming candidate emails.
Job Application Context:
- Target Job: "${matchedApp.jobTitle}"
- Target Company: "${matchedApp.companyName}"
- Recipient Email Applied To: "${matchedApp.recipientEmail}"

Incoming Email:
- Sender: "${senderName} <${senderAddress}>"
- Subject: "${subject}"
- Date: "${envelope.date ? envelope.date.toISOString() : ''}"
- Body Snippet:
"${cleanBodySnippet}"

CRITICAL TASK:
1. Determine if this email is a GENUINE response to the candidate's job application (e.g., direct recruiter reply, invitation to interview, technical round schedule, coding assessment link, candidate rejection, request for availability/documents, HR acknowledgment).
2. OR if it is an AUTOMATED subscription newsletter, marketing broadcast, periodic job alerts digest, webinar invitation, or promotional email (e.g., "10 new jobs at TCS found for you", "Register for TCS event").

Return ONLY valid JSON in this exact structure:
{
  "isLegitimateResponse": true or false,
  "responseType": "interview_invite" | "assessment" | "hr_query" | "acknowledgment" | "rejection" | "other",
  "confidence": 0.0 to 1.0,
  "summary": "1 concise sentence summarizing what the recruiter/company is communicating",
  "actionRequired": "Concise next action for the job seeker (e.g., 'Schedule technical round', 'Take online assessment', 'Reply with portfolio', 'None')"
}`;

                    const aiPayload = {
                        contents: [
                            {
                                parts: [{ text: aiPrompt }]
                            }
                        ],
                        generationConfig: {
                            responseMimeType: "application/json"
                        }
                    };

                    const aiResponse = await callGeminiAPI(aiPayload, {
                        apiKey: userData.geminiApiKey || undefined
                    });

                    if (aiResponse && aiResponse.text) {
                        analysis = JSON.parse(aiResponse.text.trim()) as ReplyAnalysisResult;
                    }
                } catch (aiErr: any) {
                    console.warn(`[ReplyTracker] Gemini classification error: ${aiErr.message}. Using heuristic fallback.`);
                    // Heuristic fallback if AI fails
                    const isDefiniteReply = inReplyTo.length > 0 || subjectLower.startsWith("re:");
                    analysis = {
                        isLegitimateResponse: isDefiniteReply,
                        responseType: subjectLower.includes("interview") ? "interview_invite" : (subjectLower.includes("assessment") ? "assessment" : "hr_query"),
                        confidence: isDefiniteReply ? 0.9 : 0.5,
                        summary: `${senderName || matchedApp.companyName} replied regarding "${subject}"`,
                        actionRequired: "Review email response in Gmail"
                    };
                }

                if (!analysis || !analysis.isLegitimateResponse || (analysis.confidence !== undefined && analysis.confidence < 0.6)) {
                    console.log(`[ReplyTracker] AI filtered out non-application email from '${senderAddress}' ('${subject}'). isLegit=${analysis?.isLegitimateResponse}, conf=${analysis?.confidence}`);
                    continue;
                }

                console.log(`[ReplyTracker] 🎯 Verified legitimate reply for '${matchedApp.jobTitle}' at '${matchedApp.companyName}' from ${senderAddress} (Type: ${analysis.responseType})`);

                // 5. UPDATE FIRESTORE APPLICATION RECORD
                const replyTime = envelope.date || new Date();
                const updateData: any = {
                    status: matchedApp.isNetworkingLead ? "replied" : "reply_received",
                    responseType: analysis.responseType || (matchedApp.isNetworkingLead ? "founder_chat" : "hr_query"),
                    replyReceivedAt: admin.firestore.Timestamp.fromDate(replyTime),
                    replySender: senderName ? `${senderName} <${senderAddress}>` : senderAddress,
                    replySubject: subject,
                    replySnippet: analysis.summary || "Recruiter/Founder replied to your outreach.",
                    replyBodyPreview: cleanBodySnippet.substring(0, 500),
                    actionRequired: analysis.actionRequired || "None",
                    replyMessageId: envelope.messageId || "",
                    updatedAt: admin.firestore.FieldValue.serverTimestamp()
                };

                await matchedApp.ref.update(updateData);
                repliesFound++;

                // Remove from local tracking sets so subsequent emails don't overwrite with older ones
                if (matchedApp.messageId) appsByMessageId.delete(matchedApp.messageId.toLowerCase().trim().replace(/[<>]/g, ""));
                appsByRecipient.delete((matchedApp.recipientEmail || "").toLowerCase().trim());

                // 6. DISPATCH INSTANT PUSH NOTIFICATION (FCM)
                try {
                    let fcmToken = userData.fcmToken;
                    if (!fcmToken) {
                        const tokenDoc = await db.collection("usernames").where("uid", "==", uid).limit(1).get();
                        if (!tokenDoc.empty) {
                            fcmToken = tokenDoc.docs[0].data()?.fcmToken;
                        }
                    }

                    if (fcmToken) {
                        let notifTitle = matchedApp.isNetworkingLead
                            ? `🚀 Founder Replied: ${matchedApp.name || matchedApp.companyName}!`
                            : `📬 Reply from ${matchedApp.companyName}!`;
                        if (analysis.responseType === "interview_invite") {
                            notifTitle = `🎉 Interview Invitation: ${matchedApp.companyName}!`;
                        } else if (analysis.responseType === "assessment") {
                            notifTitle = `📝 Coding Assessment: ${matchedApp.companyName}!`;
                        } else if (analysis.responseType === "hr_query") {
                            notifTitle = matchedApp.isNetworkingLead
                                ? `💬 Founder Message: ${matchedApp.companyName}!`
                                : `💬 Recruiter Message: ${matchedApp.companyName}!`;
                        } else if (analysis.responseType === "rejection") {
                            notifTitle = `Update on Application: ${matchedApp.companyName}`;
                        }

                        const notifBody = `${analysis.summary} • Action: ${analysis.actionRequired}`;

                        await admin.messaging().send({
                            token: fcmToken,
                            notification: {
                                title: notifTitle,
                                body: notifBody
                            },
                            android: {
                                notification: {
                                    channelId: "job_assistant_channel",
                                    tag: `job_reply_${matchedApp.id}`
                                }
                            },
                            data: {
                                type: "JOB_APPLICATION_REPLY",
                                applicationId: matchedApp.id,
                                companyName: matchedApp.companyName || "",
                                jobTitle: matchedApp.jobTitle || ""
                            }
                        });

                        await logNotification(uid, notifTitle, notifBody, "JOB_ASSISTANT_REPLY");
                    }
                } catch (notifErr: any) {
                    console.error(`[ReplyTracker] Error sending push notification to user ${uid}:`, notifErr.message);
                }
            }
        } finally {
            lock.release();
        }
    } catch (imapErr: any) {
        console.error(`[ReplyTracker] IMAP connection / scan error for user ${uid}:`, imapErr.message);
    } finally {
        try {
            await client.logout();
        } catch (_) {}
        try {
            await db.collection("users").doc(uid).set({
                lastJobRepliesCheckedAt: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
        } catch (_) {}
    }

    return { checked: checkedCount, repliesFound };
}

/**
 * Scheduled runner for all users with configured email accounts.
 * Called at 10 AM, 2 PM, 6 PM, and 10 PM IST.
 */
export async function internalCheckAllJobReplies(): Promise<void> {
    console.log("[ReplyTracker] Starting scheduled job application reply check across all users...");
    try {
        const usersSnap = await db.collection("users").get();
        for (const doc of usersSnap.docs) {
            const data = doc.data() || {};
            const emailConfig = data.emailConfig || {};
            if (emailConfig.email && emailConfig.appPassword) {
                try {
                    const result = await checkUserJobReplies(doc.id);
                    if (result.repliesFound > 0) {
                        console.log(`[ReplyTracker] Found ${result.repliesFound} new recruiter replies for user ${doc.id}`);
                    }
                } catch (uErr: any) {
                    console.error(`[ReplyTracker] Error checking replies for user ${doc.id}:`, uErr.message);
                }
            }
        }
    } catch (err: any) {
        console.error("[ReplyTracker] Error in internalCheckAllJobReplies:", err.message);
    }
}

/**
 * Callable endpoint for on-demand manual check from the Flutter app.
 */
export const checkJobRepliesCallable = functions
    .runWith({ timeoutSeconds: 120, memory: "512MB" })
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
        }
        const uid = context.auth.uid;
        try {
            const res = await checkUserJobReplies(uid);
            return {
                success: true,
                checked: res.checked,
                repliesFound: res.repliesFound
            };
        } catch (err: any) {
            console.error(`[ReplyTracker] checkJobRepliesCallable error for ${uid}:`, err);
            throw new functions.https.HttpsError("internal", err.message || "Failed to check email replies.");
        }
    });
