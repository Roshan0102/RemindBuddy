"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.importSharedJob = void 0;
const functions = require("firebase-functions");
const firebase_1 = require("../../config/firebase");
const geminiHelper_1 = require("../../utils/geminiHelper");
const featureLogger_1 = require("../../utils/featureLogger");
const emailFormatter_1 = require("../../utils/emailFormatter");
const nodemailer = require("nodemailer");
const axios_1 = require("axios");
const cheerio = require("cheerio");
/**
 * HTTP Webhook specifically designed for Apple Shortcuts and external share targets.
 * Enables 1-tap background sharing of LinkedIn jobs, post URLs, or text from iOS iPhones
 * directly into the user's SmartBuddy account without opening Safari.
 */
exports.importSharedJob = functions.runWith({
    timeoutSeconds: 300,
    memory: "1GB"
}).https.onRequest(async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m;
    // 1. Enable CORS
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    try {
        // 2. Extract User Identifier & Payload
        const rawUserId = (req.query.userId || req.query.uid || ((_a = req.body) === null || _a === void 0 ? void 0 : _a.userId) || ((_b = req.body) === null || _b === void 0 ? void 0 : _b.uid) || "").toString().trim();
        const rawEmail = (req.query.email || ((_c = req.body) === null || _c === void 0 ? void 0 : _c.email) || "").toString().trim().toLowerCase();
        const sharedText = (req.query.text || req.query.url || ((_d = req.body) === null || _d === void 0 ? void 0 : _d.text) || ((_e = req.body) === null || _e === void 0 ? void 0 : _e.url) || ((_f = req.body) === null || _f === void 0 ? void 0 : _f.sharedText) || ((_g = req.body) === null || _g === void 0 ? void 0 : _g.jobUrl) || "").toString().trim();
        if (!sharedText) {
            res.status(400).json({
                success: false,
                error: "No text or job URL provided. Please provide 'text' or 'url'."
            });
            return;
        }
        // 3. Resolve User Document
        let targetUid = rawUserId;
        let userData = null;
        if (targetUid) {
            const userSnap = await firebase_1.db.collection("users").doc(targetUid).get();
            if (userSnap.exists) {
                userData = userSnap.data();
            }
        }
        if (!userData && rawEmail) {
            const querySnap = await firebase_1.db.collection("users").where("email", "==", rawEmail).limit(1).get();
            if (!querySnap.empty) {
                targetUid = querySnap.docs[0].id;
                userData = querySnap.docs[0].data();
            }
        }
        if (!userData || !targetUid) {
            res.status(404).json({
                success: false,
                error: "User not found. Please provide a valid userId or registered email."
            });
            return;
        }
        console.log(`[SharedJobWebhook] Received job share for user ${targetUid} (${userData.email || "No email"}). Payload: ${sharedText.slice(0, 100)}...`);
        // Check if Job Assistant is enabled
        const enabledModules = userData.enabledModules || [];
        if (Array.isArray(enabledModules) && enabledModules.length > 0 && !enabledModules.includes("job_assistant")) {
            res.status(403).json({
                success: false,
                error: "Job Assistant module is currently disabled for this account in Settings."
            });
            return;
        }
        // 4. Extract URL and Scrape Job Information
        const urlMatch = sharedText.match(/https?:\/\/[^\s]+/);
        let targetUrl = urlMatch ? urlMatch[0] : "";
        let pageTitle = "";
        let pageDescription = "";
        let extractedBodyText = sharedText;
        if (targetUrl) {
            try {
                // Expand shortened URLs like lnkd.in
                const headRes = await axios_1.default.get(targetUrl, {
                    maxRedirects: 5,
                    timeout: 10000,
                    headers: {
                        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
                    }
                });
                if ((_j = (_h = headRes.request) === null || _h === void 0 ? void 0 : _h.res) === null || _j === void 0 ? void 0 : _j.responseUrl) {
                    targetUrl = headRes.request.res.responseUrl;
                }
                const $ = cheerio.load(headRes.data);
                pageTitle = $('meta[property="og:title"]').attr("content") || $("title").text() || "";
                pageDescription = $('meta[property="og:description"]').attr("content") || $('meta[name="description"]').attr("content") || "";
                // Remove scripts and style tags to extract clean text
                $("script, style, nav, footer, header").remove();
                const bodyText = $("body").text().replace(/\s+/g, " ").trim().slice(0, 4000);
                extractedBodyText = `URL: ${targetUrl}\nPage Title: ${pageTitle}\nSummary: ${pageDescription}\nPage Content: ${bodyText}\nOriginal Shared Text: ${sharedText}`;
            }
            catch (scrapeErr) {
                console.warn(`[SharedJobWebhook] URL scrape note: ${scrapeErr.message}. Falling back to raw text.`);
                extractedBodyText = `Target URL: ${targetUrl}\nShared Text: ${sharedText}`;
            }
        }
        // 5. Load User Base Resume
        let resumePdfBase64 = (((_k = userData.masterResume) === null || _k === void 0 ? void 0 : _k.base64) || ((_l = userData.masterResume) === null || _l === void 0 ? void 0 : _l.base64Data) || "").toString().trim();
        if (!resumePdfBase64) {
            const profilesSnap = await firebase_1.db.collection("users").doc(targetUid).collection("resume_profiles").limit(1).get();
            if (!profilesSnap.empty) {
                resumePdfBase64 = (profilesSnap.docs[0].data().base64 || "").toString().trim();
            }
        }
        const cleanResumeB64 = resumePdfBase64.replace(/^data:application\/pdf;base64,/, "");
        // 6. User Specific API Keys (Zero Leakage)
        const userApiKeys = userData.userApiKeys || {};
        const geminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();
        const groqKey = (userApiKeys.groqApiKey || userData.groqApiKey || "").trim();
        const candidateName = (userData.applicantName || userData.displayName || userData.fullName || "Candidate").trim();
        // 7. Parse with Gemini AI
        const prompt = `You are an elite Executive Recruiter and ATS Application Specialist.
A user shared a job post or hiring update from iOS Share Sheet:

--- SHARED CONTENT ---
${extractedBodyText.slice(0, 5000)}
----------------------

CANDIDATE NAME: "${candidateName}"

TASK:
1. Identify the Company Name and Job Title. If company cannot be identified with certainty, use the most plausible employer or poster name.
2. Check if a recruiter or hiring manager contact email is mentioned anywhere in the content.
3. Extract 4-8 core required skills, tools, and technical keywords.
4. Craft an attention-grabbing email subject line: "${candidateName} - Application for [Job Title]".
5. Write a persuasive, highly customized 3-4 paragraph cover letter pitching the candidate for this exact role. Ground it solidly in candidate's skills and experience.

OUTPUT STRICT JSON FORMAT ONLY:
{
  "companyName": "Company Name",
  "jobTitle": "Job Title",
  "recipientEmail": "recruiter@company.com or empty string if not found",
  "extractedSkills": ["Skill 1", "Skill 2", "Skill 3"],
  "location": "Location or Remote",
  "generatedSubject": "${candidateName} - Application for Job Title",
  "generatedCoverLetter": "Dear Hiring Team,\\n\\n..."
}`;
        const inlineParts = [];
        if (cleanResumeB64) {
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
            generationConfig: {
                temperature: 0.2,
                responseMimeType: "application/json"
            }
        };
        const geminiResponse = await (0, geminiHelper_1.callGeminiAPI)(payload, {
            apiKey: geminiKey,
            groqApiKey: groqKey
        });
        const rawText = geminiResponse.text || "{}";
        const cleanedJson = rawText.replace(/```json/g, "").replace(/```/g, "").trim();
        let parsed = {};
        try {
            parsed = JSON.parse(cleanedJson);
        }
        catch (_o) {
            parsed = {
                companyName: pageTitle || "Target Company",
                jobTitle: "Open Position",
                recipientEmail: "",
                extractedSkills: [],
                generatedSubject: `${candidateName} - Application`,
                generatedCoverLetter: "Please find my resume attached for your review."
            };
        }
        const companyName = (parsed.companyName || "Target Company").trim();
        const jobTitle = (parsed.jobTitle || "Job Opportunity").trim();
        const recipientEmail = (parsed.recipientEmail || "").trim();
        const extractedSkills = Array.isArray(parsed.extractedSkills) ? parsed.extractedSkills : [];
        const location = (parsed.location || "Remote / On-site").trim();
        const generatedSubject = (parsed.generatedSubject || `${candidateName} - ${jobTitle}`).trim();
        const generatedCoverLetter = (parsed.generatedCoverLetter || "").trim();
        const emailConfig = userData.emailConfig || {};
        const userEmail = (emailConfig.email || "").toString().trim();
        const appPassword = (emailConfig.appPassword || "").toString().trim();
        // 8. Auto-send email application if recruiter email and user Gmail are configured
        let isSent = false;
        let emailMessageId = null;
        let emailSendError = null;
        if (recipientEmail && userEmail && appPassword) {
            try {
                const cleanPassword = appPassword.replace(/\s+/g, "");
                const transporter = nodemailer.createTransport({
                    service: "gmail",
                    auth: {
                        user: userEmail,
                        pass: cleanPassword
                    }
                });
                const attachments = [];
                if (cleanResumeB64) {
                    attachments.push({
                        filename: `${candidateName.replace(/[^a-zA-Z0-9]/g, "_")}_Resume.pdf`,
                        content: Buffer.from(cleanResumeB64, "base64"),
                        contentType: "application/pdf"
                    });
                }
                const formatted = (0, emailFormatter_1.formatEmailContent)(generatedCoverLetter);
                const mailOptions = {
                    from: `"${candidateName}" <${userEmail}>`,
                    to: recipientEmail,
                    subject: generatedSubject,
                    text: formatted.text,
                    html: formatted.html,
                    attachments
                };
                const info = await transporter.sendMail(mailOptions);
                console.log(`[SharedJobWebhook] Sent job application email to ${recipientEmail} for user ${targetUid}:`, info.messageId);
                isSent = true;
                emailMessageId = info.messageId;
            }
            catch (err) {
                console.error(`[SharedJobWebhook] Failed to send email to ${recipientEmail}:`, err);
                emailSendError = err.message || "Failed to deliver email.";
            }
        }
        // 9. Save into Firestore
        const isLinkedIn = (targetUrl + " " + sharedText).toLowerCase().includes("linkedin");
        const source = isLinkedIn ? "linkedin_share" : "ios_share_sheet";
        const sourcePlatform = isLinkedIn ? "LinkedIn Post (iOS Share)" : "iOS Share Sheet (iPhone)";
        const status = isSent
            ? "sent"
            : (recipientEmail ? (userEmail && appPassword ? "needs_review" : "extracted") : "needs_review");
        const isAutoApplied = isSent;
        const appId = `ios_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
        await firebase_1.db.collection("users").doc(targetUid).collection("job_applications").doc(appId).set({
            id: appId,
            jobTitle,
            companyName,
            recipientEmail,
            location,
            extractedSkills,
            generatedSubject,
            generatedCoverLetter,
            status,
            isAutoApplied,
            appliedAt: firebase_1.admin.firestore.FieldValue.serverTimestamp(),
            createdAt: firebase_1.admin.firestore.FieldValue.serverTimestamp(),
            sourcePlatform,
            source,
            sourceUrl: targetUrl || sharedText,
            messageId: emailMessageId || null,
            errorMessage: isSent
                ? null
                : (!recipientEmail
                    ? "No recruiter email detected in post. Saved in Drafts ready for portal submission."
                    : (!userEmail || !appPassword
                        ? "Recruiter email found, but Gmail App Password is not configured in Settings to auto-send."
                        : `Email delivery error: ${emailSendError}`))
        });
        // 10. Log Feature Execution
        await (0, featureLogger_1.logFeatureExecution)(targetUid, {
            feature: "shared_intent",
            featureTitle: "iOS Share Sheet Auto-Import",
            status: "success",
            count: 1,
            message: isSent
                ? `Auto-applied and emailed "${jobTitle}" at "${companyName}" (${recipientEmail}).`
                : `Imported "${jobTitle}" at "${companyName}" from iPhone Share Sheet.`
        });
        // 11. Send Push Notification to User Phone / Web
        try {
            const userTokenDoc = await firebase_1.db.collection("usernames").where("uid", "==", targetUid).limit(1).get();
            if (!userTokenDoc.empty) {
                const fcmToken = (_m = userTokenDoc.docs[0].data()) === null || _m === void 0 ? void 0 : _m.fcmToken;
                if (fcmToken) {
                    const notifTitle = isSent
                        ? `🚀 Application Sent: ${jobTitle} at ${companyName}`
                        : `⚡ iOS Share: ${jobTitle} at ${companyName}`;
                    const notifBody = isSent
                        ? `Direct email with your resume was sent to ${recipientEmail}!`
                        : (recipientEmail
                            ? `Recruiter email (${recipientEmail}) identified! Saved to drafts.`
                            : `Job details extracted and saved to your Job Assistant drafts!`);
                    await firebase_1.admin.messaging().send({
                        token: fcmToken,
                        notification: { title: notifTitle, body: notifBody },
                        webpush: {
                            notification: {
                                title: notifTitle,
                                body: notifBody,
                                icon: "/icons/Icon-192.png",
                                badge: "/icons/Icon-192.png",
                                tag: `ios_share_${appId}`
                            },
                            fcmOptions: { link: "/?feature=JOB_APPLICATION" }
                        },
                        android: {
                            notification: {
                                channelId: "job_assistant_channel",
                                tag: `ios_share_${appId}`
                            }
                        }
                    });
                }
            }
        }
        catch (notifErr) {
            console.warn(`[SharedJobWebhook] FCM notification note: ${notifErr.message}`);
        }
        // 11. Return Success Response to Apple Shortcut
        res.status(200).json({
            success: true,
            message: `SmartBuddy: Application drafted for ${jobTitle} at ${companyName}!`,
            company: companyName,
            role: jobTitle,
            hasEmail: Boolean(recipientEmail),
            appId
        });
    }
    catch (err) {
        console.error("[SharedJobWebhook] Fatal error:", err);
        res.status(500).json({
            success: false,
            error: err.message || "Internal server error"
        });
    }
});
//# sourceMappingURL=sharedJobWebhook.js.map