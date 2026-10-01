import * as functions from "firebase-functions";
import * as nodemailer from "nodemailer";
import { admin, db } from "../../config/firebase";
import { callGroqAPI } from "../../utils/groqHelper";
import { callGeminiAPI } from "../../utils/geminiHelper";

export interface VoiceCallSessionData {
    id: string;
    status: "ringing" | "in_call" | "completed" | "declined" | "missed";
    companyName: string;
    jobTitle: string;
    recruiterName: string;
    recruiterEmail: string;
    subject: string;
    emailSnippet: string;
    emailBody: string;
    actionRequired: string;
    applicationId: string;
    candidateName: string;
    replySent?: boolean;
    replyBody?: string;
    createdAt: admin.firestore.FieldValue | admin.firestore.Timestamp;
    updatedAt?: admin.firestore.FieldValue | admin.firestore.Timestamp;
}

/**
 * Creates an active voice call session in Firestore and dispatches a high-priority FCM call signal.
 */
export async function triggerRecruiterVoiceCallSession(params: {
    uid: string;
    companyName: string;
    jobTitle: string;
    recruiterName: string;
    recruiterEmail: string;
    subject: string;
    emailSnippet: string;
    emailBody: string;
    actionRequired: string;
    applicationId: string;
    candidateName: string;
}): Promise<string> {
    const { uid } = params;
    const sessionRef = db.collection("users").doc(uid).collection("voice_call_sessions").doc();
    const sessionId = sessionRef.id;

    const sessionData: VoiceCallSessionData = {
        id: sessionId,
        status: "ringing",
        companyName: params.companyName || "Recruiter",
        jobTitle: params.jobTitle || "Job Opportunity",
        recruiterName: params.recruiterName || "Recruiter",
        recruiterEmail: params.recruiterEmail || "",
        subject: params.subject || "",
        emailSnippet: params.emailSnippet || "",
        emailBody: params.emailBody || "",
        actionRequired: params.actionRequired || "Respond to recruiter inquiry",
        applicationId: params.applicationId || "",
        candidateName: params.candidateName || "Candidate",
        createdAt: admin.firestore.FieldValue.serverTimestamp()
    };

    await sessionRef.set(sessionData);

    // Send high-priority FCM notification
    try {
        const userDoc = await db.collection("users").doc(uid).get();
        const userData = userDoc.data() || {};
        let fcmToken = userData.fcmToken;
        if (!fcmToken) {
            const tokenDoc = await db.collection("usernames").where("uid", "==", uid).limit(1).get();
            if (!tokenDoc.empty) {
                fcmToken = tokenDoc.docs[0].data()?.fcmToken;
            }
        }

        if (fcmToken) {
            await admin.messaging().send({
                token: fcmToken,
                data: {
                    type: "INCOMING_VOICE_CALL",
                    sessionId: sessionId,
                    callerName: "SmartBuddy Recruiter Call",
                    companyName: params.companyName || "Recruiter",
                    jobTitle: params.jobTitle || "Job Opportunity",
                    recruiterName: params.recruiterName || "Recruiter",
                    actionRequired: params.actionRequired || ""
                },
                android: {
                    priority: "high",
                    notification: {
                        title: `📞 Incoming Call: ${params.companyName || "Recruiter"}`,
                        body: `Sarah asked: ${params.actionRequired || "Notice period & availability"}. Tap to answer.`,
                        channelId: "smartbuddy_call_channel",
                        priority: "max"
                    }
                }
            });
            console.log(`[VoiceCall] Successfully dispatched FCM call alert to user ${uid} (Session: ${sessionId})`);
        }
    } catch (fcmErr: any) {
        console.warn(`[VoiceCall] FCM dispatch note for user ${uid}:`, fcmErr.message);
    }

    return sessionId;
}

/**
 * Callable endpoint to simulate an incoming recruiter call for interactive testing.
 */
export const simulateRecruiterVoiceCall = functions.runWith({ timeoutSeconds: 30, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
    }
    const uid = context.auth.uid;
    const userDoc = await db.collection("users").doc(uid).get();
    const userData = userDoc.data() || {};
    const jobSubPerms = userData.jobAssistantSubPermissions || {};
    if (jobSubPerms.ai_recruiter_call !== true) {
        throw new functions.https.HttpsError("permission-denied", "AI Recruiter Call feature is disabled by Administrator for your account.");
    }
    const candidateName = userData.displayName || userData.name || "Candidate";

    const companyName = data?.companyName || "Google Cloud";
    const jobTitle = data?.jobTitle || "Senior Flutter Engineer";
    const recruiterName = data?.recruiterName || "Sarah Jenkins (HR Lead)";
    const question = data?.question || "Could you please confirm your current notice period and expected CTC?";

    const sessionId = await triggerRecruiterVoiceCallSession({
        uid,
        companyName,
        jobTitle,
        recruiterName,
        recruiterEmail: "sarah.recruiter.test@gmail.com",
        subject: `Re: Application for ${jobTitle} - ${candidateName}`,
        emailSnippet: question,
        emailBody: `Hi ${candidateName}, thank you for applying to ${companyName}. We were impressed by your profile. ${question} We look forward to hearing from you!`,
        actionRequired: question,
        applicationId: "simulated_test_app",
        candidateName
    });

    return {
        success: true,
        sessionId,
        message: "Incoming voice call simulated successfully."
    };
});

/**
 * Process a conversational speech turn during the active call.
 * Uses Groq LPU as Primary (<200ms) with Gemini Flash as Secondary Fallback.
 */
export const voiceCallChatTurn = functions.runWith({ timeoutSeconds: 30, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
    }
    const uid = context.auth.uid;
    const { sessionId, userSpeech, conversationHistory } = data;

    if (!sessionId || !userSpeech) {
        throw new functions.https.HttpsError("invalid-argument", "sessionId and userSpeech are required.");
    }

    let session: VoiceCallSessionData;
    const sessionRef = db.collection("users").doc(uid).collection("voice_call_sessions").doc(sessionId);
    const sessionDoc = await sessionRef.get();
    if (sessionDoc.exists) {
        session = sessionDoc.data() as VoiceCallSessionData;
    } else {
        const userDoc = await db.collection("users").doc(uid).get();
        const userData = userDoc.data() || {};
        session = {
            id: sessionId,
            status: "in_call",
            companyName: data.companyName || "Google Cloud",
            jobTitle: data.jobTitle || "Senior Flutter Engineer",
            recruiterName: data.recruiterName || "Sarah Jenkins (HR Lead)",
            recruiterEmail: data.recruiterEmail || "sarah.recruiter.test@gmail.com",
            subject: data.subject || `Application for ${data.jobTitle || "Job Opportunity"}`,
            emailSnippet: data.question || "Could you please confirm your notice period and expected CTC?",
            emailBody: data.emailBody || data.question || "Could you please confirm your notice period and expected CTC?",
            actionRequired: data.question || "Notice period & salary expectations",
            applicationId: data.applicationId || "simulated_test_app",
            candidateName: userData.displayName || userData.name || data.candidateName || "Candidate",
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        };
        try {
            await sessionRef.set(session);
        } catch (saveErr) {
            console.warn("[VoiceCall] Note saving fallback session:", saveErr);
        }
    }

    // Fetch user API keys
    const userDoc = await db.collection("users").doc(uid).get();
    const userData = userDoc.data() || {};
    const userApiKeys = userData.userApiKeys || {};
    const groqApiKey = userApiKeys.groqApiKey || userData.groqApiKey || process.env.GROQ_API_KEY || "";
    const geminiApiKey = userApiKeys.geminiApiKey || userData.geminiApiKey || process.env.GEMINI_API_KEY || "";

    const systemPrompt = `You are SmartBuddy, an AI Voice Calling Assistant acting on behalf of ${session.candidateName}.
You are on an active voice phone call with ${session.candidateName}.
Context:
- Company: ${session.companyName}
- Job Title: ${session.jobTitle}
- Recruiter Name: ${session.recruiterName}
- Recruiter's Email Question: "${session.emailBody || session.actionRequired}"

Your Objective:
1. Converse naturally in SHORT, conversational sentences suitable for speech (1-2 sentences max).
2. Answer any doubts the candidate asks (about company, salary, interview dates).
3. Extract their preferred response (notice period, expected salary, availability).
4. When they confirm what to reply (e.g. "Yes, send it", "Tell them 30 days and 20 LPA", "Go ahead"), explicitly ask for final confirmation: "Should I go ahead and email this reply to ${session.recruiterName}?"
5. When they say YES or confirm to send, end your message with the exact phrase: "[SEND_CONFIRMED]" followed by a brief sign-off ("Sending your email now. Have a great day!").`;

    const formattedHistory = Array.isArray(conversationHistory)
        ? conversationHistory.map((h: any) => `${h.role === "assistant" ? "AI" : "Candidate"}: ${h.text}`).join("\n")
        : "";

    const fullPrompt = `${formattedHistory}\nCandidate: ${userSpeech}\nAI:`;

    // 1. Try Groq Primary
    if (groqApiKey) {
        try {
            const groqRes = await callGroqAPI({
                apiKey: groqApiKey,
                systemPrompt,
                prompt: fullPrompt,
                temperature: 0.3,
                maxTokens: 150
            });

            const replyText = groqRes.text || "";
            const isConfirmed = replyText.includes("[SEND_CONFIRMED]");
            const cleanText = replyText.replace("[SEND_CONFIRMED]", "").trim();

            return {
                replyText: cleanText,
                isConfirmed,
                engineUsed: `Groq (${groqRes.modelUsed})`
            };
        } catch (groqErr: any) {
            console.warn(`[VoiceCall] Groq failed, falling back to Gemini Flash:`, groqErr.message);
        }
    }

    // 2. Fallback to Gemini Flash
    try {
        const geminiRes = await callGeminiAPI(
            {
                contents: [
                    {
                        role: "user",
                        parts: [{ text: `${systemPrompt}\n\n${fullPrompt}` }]
                    }
                ],
                generationConfig: {
                    temperature: 0.3,
                    maxOutputTokens: 150
                }
            },
            {
                apiKey: geminiApiKey,
                timeout: 10000
            }
        );

        const replyText = geminiRes.text || "I understand. Would you like me to send this reply to the recruiter?";
        const isConfirmed = replyText.includes("[SEND_CONFIRMED]");
        const cleanText = replyText.replace("[SEND_CONFIRMED]", "").trim();

        return {
            replyText: cleanText,
            isConfirmed,
            engineUsed: "Gemini Flash (Fallback)"
        };
    } catch (geminiErr: any) {
        console.error(`[VoiceCall] Both Groq and Gemini failed:`, geminiErr);
        // Smart fallback to maintain conversational flow and speak back
        return {
            replyText: `Got it! Would you like me to send this response to ${session.recruiterName}?`,
            isConfirmed: false,
            engineUsed: "SmartBuddy Assistant"
        };
    }
});

/**
 * Callable endpoint to send the approved recruiter email once the user completes the voice call.
 */
export const sendVoiceCallApprovedReply = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be logged in.");
    }
    const uid = context.auth.uid;
    const { sessionId, finalReplyText } = data;

    if (!sessionId || !finalReplyText) {
        throw new functions.https.HttpsError("invalid-argument", "sessionId and finalReplyText are required.");
    }

    let session: VoiceCallSessionData;
    const sessionRef = db.collection("users").doc(uid).collection("voice_call_sessions").doc(sessionId);
    const sessionDoc = await sessionRef.get();
    if (sessionDoc.exists) {
        session = sessionDoc.data() as VoiceCallSessionData;
    } else {
        const userDoc = await db.collection("users").doc(uid).get();
        const userData = userDoc.data() || {};
        session = {
            id: sessionId,
            status: "in_call",
            companyName: data.companyName || "Google Cloud",
            jobTitle: data.jobTitle || "Senior Flutter Engineer",
            recruiterName: data.recruiterName || "Sarah Jenkins (HR Lead)",
            recruiterEmail: data.recruiterEmail || "sarah.recruiter.test@gmail.com",
            subject: data.subject || "Re: Job Application",
            emailSnippet: "",
            emailBody: "",
            actionRequired: "",
            applicationId: data.applicationId || "simulated_test_app",
            candidateName: userData.displayName || userData.name || data.candidateName || "Candidate",
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        };
    }

    // Fetch user email credentials
    const userDoc = await db.collection("users").doc(uid).get();
    const userData = userDoc.data() || {};
    const emailSettings = userData.emailSettings || userData.jobAssistantSettings || {};
    const senderEmail = emailSettings.userEmail || emailSettings.email || userData.email;
    const appPassword = emailSettings.appPassword || emailSettings.emailPassword;

    if (!senderEmail || !appPassword) {
        throw new functions.https.HttpsError("failed-precondition", "User email or App Password not configured.");
    }

    const cleanAppPassword = appPassword.replace(/\s+/g, "");
    const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
            user: senderEmail,
            pass: cleanAppPassword
        }
    });

    const replySubject = session.subject.toLowerCase().startsWith("re:")
        ? session.subject
        : `Re: ${session.subject || `Application for ${session.jobTitle}`}`;

    const formattedBody = `Dear ${session.recruiterName || "Hiring Team"},\n\n` +
        `${finalReplyText}\n\n` +
        `Best regards,\n` +
        `${session.candidateName}\n` +
        `${senderEmail}`;

    await transporter.sendMail({
        from: `"${session.candidateName}" <${senderEmail}>`,
        to: session.recruiterEmail,
        subject: replySubject,
        text: formattedBody
    });

    // Update session status
    await sessionRef.update({
        status: "completed",
        replySent: true,
        replyBody: formattedBody,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });

    // Update job application record if linked
    if (session.applicationId && session.applicationId !== "simulated_test_app") {
        try {
            await db.collection("users").doc(uid).collection("job_applications").doc(session.applicationId).update({
                status: "replied",
                replySentAt: admin.firestore.FieldValue.serverTimestamp(),
                lastVoiceCallSessionId: sessionId
            });
        } catch (appErr: any) {
            console.warn(`[VoiceCall] Note updating application ${session.applicationId}:`, appErr.message);
        }
    }

    return {
        success: true,
        message: `Email reply successfully delivered to ${session.recruiterEmail}`
    };
});
