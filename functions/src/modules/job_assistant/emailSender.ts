import * as functions from "firebase-functions";
import * as nodemailer from "nodemailer";
import { db } from "../../config/firebase";

export const sendJobApplicationEmail = functions.runWith({ timeoutSeconds: 60, memory: "512MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const uid = context.auth.uid;
    const { recipientEmail, subject, body, resumeBase64, resumeFileName } = data;

    if (!recipientEmail || !subject || !body) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing recipientEmail, subject, or body.');
    }

    try {
        const userDoc = await db.collection("users").doc(uid).get();
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User profile not found.');
        }

        const userData = userDoc.data() || {};
        const emailConfig = userData.emailConfig || {};
        const userEmail = emailConfig.email;
        const appPassword = emailConfig.appPassword;

        if (!userEmail || !appPassword) {
            throw new functions.https.HttpsError(
                'failed-precondition',
                'Your Gmail App Password is not configured. Please enter your Gmail & App Password in Job Assistant Settings.'
            );
        }

        const cleanPassword = appPassword.replace(/\s+/g, '');

        const transporter = nodemailer.createTransport({
            service: 'gmail',
            auth: {
                user: userEmail,
                pass: cleanPassword
            }
        });

        const attachments: any[] = [];
        if (resumeBase64) {
            const cleanB64 = resumeBase64.replace(/^data:application\/pdf;base64,/, '');
            attachments.push({
                filename: resumeFileName || 'Resume.pdf',
                content: Buffer.from(cleanB64, 'base64'),
                contentType: 'application/pdf'
            });
        }

        const mailOptions = {
            from: `"${userData.displayName || 'Job Applicant'}" <${userEmail}>`,
            to: recipientEmail,
            subject: subject,
            text: body,
            attachments: attachments
        };

        const info = await transporter.sendMail(mailOptions);
        console.log(`Job application email sent by ${uid} to ${recipientEmail}:`, info.messageId);

        return {
            success: true,
            messageId: info.messageId
        };
    } catch (error: any) {
        console.error(`Failed to send job application email for user ${uid}:`, error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to send email.');
    }
});
