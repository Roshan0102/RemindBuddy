import * as functions from "firebase-functions";
import { admin, db } from "../../config/firebase";
import { callGeminiAPI } from "../../utils/geminiHelper";
import { logFeatureExecution } from "../../utils/featureLogger";
import axios from "axios";
import * as cheerio from "cheerio";

/**
 * HTTP Webhook specifically designed for Apple Shortcuts and external share targets.
 * Enables 1-tap background sharing of LinkedIn jobs, post URLs, or text from iOS iPhones
 * directly into the user's SmartBuddy account without opening Safari.
 */
export const importSharedJob = functions.runWith({
    timeoutSeconds: 300,
    memory: "1GB"
}).https.onRequest(async (req, res) => {
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
        const rawUserId = (req.query.userId || req.query.uid || req.body?.userId || req.body?.uid || "").toString().trim();
        const rawEmail = (req.query.email || req.body?.email || "").toString().trim().toLowerCase();
        const sharedText = (req.query.text || req.query.url || req.body?.text || req.body?.url || req.body?.sharedText || req.body?.jobUrl || "").toString().trim();

        if (!sharedText) {
            res.status(400).json({
                success: false,
                error: "No text or job URL provided. Please provide 'text' or 'url'."
            });
            return;
        }

        // 3. Resolve User Document
        let targetUid = rawUserId;
        let userData: any = null;

        if (targetUid) {
            const userSnap = await db.collection("users").doc(targetUid).get();
            if (userSnap.exists) {
                userData = userSnap.data();
            }
        }

        if (!userData && rawEmail) {
            const querySnap = await db.collection("users").where("email", "==", rawEmail).limit(1).get();
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
                const headRes = await axios.get(targetUrl, {
                    maxRedirects: 5,
                    timeout: 10000,
                    headers: {
                        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
                    }
                });

                if (headRes.request?.res?.responseUrl) {
                    targetUrl = headRes.request.res.responseUrl;
                }

                const $ = cheerio.load(headRes.data);
                pageTitle = $('meta[property="og:title"]').attr("content") || $("title").text() || "";
                pageDescription = $('meta[property="og:description"]').attr("content") || $('meta[name="description"]').attr("content") || "";

                // Remove scripts and style tags to extract clean text
                $("script, style, nav, footer, header").remove();
                const bodyText = $("body").text().replace(/\s+/g, " ").trim().slice(0, 4000);

                extractedBodyText = `URL: ${targetUrl}\nPage Title: ${pageTitle}\nSummary: ${pageDescription}\nPage Content: ${bodyText}\nOriginal Shared Text: ${sharedText}`;
            } catch (scrapeErr: any) {
                console.warn(`[SharedJobWebhook] URL scrape note: ${scrapeErr.message}. Falling back to raw text.`);
                extractedBodyText = `Target URL: ${targetUrl}\nShared Text: ${sharedText}`;
            }
        }

        // 5. Load User Base Resume
        let resumePdfBase64 = (userData.masterResume?.base64 || userData.masterResume?.base64Data || "").toString().trim();
        if (!resumePdfBase64) {
            const profilesSnap = await db.collection("users").doc(targetUid).collection("resume_profiles").limit(1).get();
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

        const inlineParts: any[] = [];
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

        const geminiResponse = await callGeminiAPI(payload, {
            apiKey: geminiKey,
            groqApiKey: groqKey
        });

        const rawText = geminiResponse.text || "{}";
        const cleanedJson = rawText.replace(/```json/g, "").replace(/```/g, "").trim();
        let parsed: any = {};
        try {
            parsed = JSON.parse(cleanedJson);
        } catch {
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

        // 8. Save into Firestore
        const appId = `ios_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
        await db.collection("users").doc(targetUid).collection("job_applications").doc(appId).set({
            id: appId,
            jobTitle,
            companyName,
            recipientEmail,
            location,
            extractedSkills,
            generatedSubject,
            generatedCoverLetter,
            status: recipientEmail ? "extracted" : "needs_review",
            appliedAt: admin.firestore.FieldValue.serverTimestamp(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            sourcePlatform: "iOS Share Sheet (iPhone)",
            source: "ios_share_sheet",
            sourceUrl: targetUrl || sharedText,
            errorMessage: recipientEmail ? null : "No recruiter email detected in post. Saved in Drafts ready for portal submission."
        });

        // 9. Log Feature Execution
        await logFeatureExecution(targetUid, {
            feature: "shared_intent",
            featureTitle: "iOS Share Sheet Auto-Import",
            status: "success",
            count: 1,
            message: `Imported "${jobTitle}" at "${companyName}" from iPhone Share Sheet.`
        });

        // 10. Send Push Notification to User Phone / Web
        try {
            const userTokenDoc = await db.collection("usernames").where("uid", "==", targetUid).limit(1).get();
            if (!userTokenDoc.empty) {
                const fcmToken = userTokenDoc.docs[0].data()?.fcmToken;
                if (fcmToken) {
                    const notifTitle = `⚡ iOS Share: ${jobTitle} at ${companyName}`;
                    const notifBody = recipientEmail
                        ? `Recruiter email (${recipientEmail}) identified! Application drafted.`
                        : `Job details extracted and saved to your Job Assistant drafts!`;

                    await admin.messaging().send({
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
        } catch (notifErr: any) {
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
    } catch (err: any) {
        console.error("[SharedJobWebhook] Fatal error:", err);
        res.status(500).json({
            success: false,
            error: err.message || "Internal server error"
        });
    }
});
