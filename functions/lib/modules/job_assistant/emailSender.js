"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendJobApplicationEmail = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const firebase_1 = require("../../config/firebase");
const emailFormatter_1 = require("../../utils/emailFormatter");
exports.sendJobApplicationEmail = functions.runWith({ timeoutSeconds: 60, memory: "512MB" }).https.onCall(async (data, context) => {
    var _a;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    const uid = context.auth.uid;
    const { recipientEmail, subject, body, resumeBase64, resumeFileName } = data;
    if (!recipientEmail || !subject || !body) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing recipientEmail, subject, or body.');
    }
    const cleanRecipient = recipientEmail.toLowerCase().trim();
    try {
        // Check central bounced / undeliverable blacklist to protect user reputation
        const bouncedDoc = await firebase_1.db.collection("system_bounced_emails").doc(encodeURIComponent(cleanRecipient)).get();
        if (bouncedDoc.exists) {
            const bounceInfo = bouncedDoc.data() || {};
            const reason = bounceInfo.reason || 'Address Not Found (550 / mailbox unavailable)';
            console.warn(`[EmailSender] Blocked email to ${cleanRecipient} - centrally blacklisted (${reason})`);
            throw new functions.https.HttpsError('failed-precondition', `CENTRAL_BLOCKED: Recipient email "${recipientEmail}" is flagged in the Central Verification Hub (${reason}). Delivery prevented to protect sender reputation.`);
        }
        const userDoc = await firebase_1.db.collection("users").doc(uid).get();
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User profile not found.');
        }
        const userData = userDoc.data() || {};
        const enabledModules = userData.enabledModules || [];
        if (!enabledModules.includes("job_assistant")) {
            throw new functions.https.HttpsError('permission-denied', 'The AI Job Assistant module is disabled for your account.');
        }
        const emailConfig = userData.emailConfig || {};
        const userEmail = emailConfig.email;
        const appPassword = emailConfig.appPassword;
        if (!userEmail || !appPassword) {
            throw new functions.https.HttpsError('failed-precondition', 'Your Gmail App Password is not configured. Please enter your Gmail & App Password in Job Assistant Settings.');
        }
        const cleanPassword = appPassword.replace(/\s+/g, '');
        const transporter = nodemailer.createTransport({
            service: 'gmail',
            auth: {
                user: userEmail,
                pass: cleanPassword
            }
        });
        const attachments = [];
        if (resumeBase64) {
            const cleanB64 = resumeBase64.replace(/^data:application\/pdf;base64,/, '');
            attachments.push({
                filename: resumeFileName || 'Resume.pdf',
                content: Buffer.from(cleanB64, 'base64'),
                contentType: 'application/pdf'
            });
        }
        const formatted = (0, emailFormatter_1.formatEmailContent)(body);
        const mailOptions = {
            from: `"${userData.displayName || userData.applicantName || 'Job Applicant'}" <${userEmail}>`,
            to: recipientEmail,
            subject: subject,
            text: formatted.text,
            html: formatted.html,
            attachments: attachments
        };
        const info = await transporter.sendMail(mailOptions);
        console.log(`Job application email sent by ${uid} to ${recipientEmail}:`, info.messageId);
        return {
            success: true,
            messageId: info.messageId
        };
    }
    catch (error) {
        console.error(`Failed to send job application email for user ${uid}:`, error);
        const errStr = (error.message || '').toLowerCase();
        if (errStr.includes("550") ||
            errStr.includes("5.1.1") ||
            errStr.includes("user unknown") ||
            errStr.includes("address not found") ||
            errStr.includes("mailbox unavailable") ||
            errStr.includes("recipient rejected") ||
            errStr.includes("invalid recipient") ||
            errStr.includes("does not exist") ||
            errStr.includes("no such user")) {
            try {
                await firebase_1.db.collection("system_bounced_emails").doc(encodeURIComponent(cleanRecipient)).set({
                    email: cleanRecipient,
                    bouncedAt: admin.firestore.FieldValue.serverTimestamp(),
                    reason: ((_a = error.message) === null || _a === void 0 ? void 0 : _a.substring(0, 300)) || "Address Not Found (550 / invalid recipient)",
                    reportedByUid: uid,
                    source: "smtp_delivery_error"
                }, { merge: true });
                console.log(`[EmailSender] Centrally blacklisted '${cleanRecipient}' in system_bounced_emails after SMTP failure.`);
            }
            catch (bErr) {
                console.warn("[EmailSender] Failed to record bounced email in blacklist:", bErr.message);
            }
        }
        throw new functions.https.HttpsError('internal', error.message || 'Failed to send email.');
    }
});
//# sourceMappingURL=emailSender.js.map