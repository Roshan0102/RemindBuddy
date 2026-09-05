"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.triggerNightlyExpenseNotifier = void 0;
exports.internalDailyUntaggedExpenseNotifier = internalDailyUntaggedExpenseNotifier;
const functions = require("firebase-functions");
const moment = require("moment-timezone");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
async function internalDailyUntaggedExpenseNotifier() {
    const nowKolkata = moment().tz('Asia/Kolkata');
    const todayStr = nowKolkata.format('YYYY-MM-DD');
    console.log(`[NightlyExpenseNotifier] Running daily bank expense notifier at ${nowKolkata.format()} for date ${todayStr}`);
    const users = await firebase_1.db.collection('usernames').get();
    for (const u of users.docs) {
        const userData = u.data();
        if (!userData.fcmToken || !userData.uid)
            continue;
        try {
            const userDoc = await firebase_1.db.collection('users').doc(userData.uid).get();
            if (!userDoc.exists)
                continue;
            const uData = userDoc.data();
            const enabledModules = (uData === null || uData === void 0 ? void 0 : uData.enabledModules) || [];
            const notifPrefs = (uData === null || uData === void 0 ? void 0 : uData.notificationPreferences) || {};
            // Check if user has Finance enabled and hasn't disabled nightly tagging notifications
            if (!enabledModules.includes("finance") || notifPrefs.finance === false || notifPrefs.finance_nightly_tagging === false) {
                continue;
            }
            // Look for untagged transactions in the user's sms_transactions
            // We check the past 7 days to ensure any recent untagged bank expenses are surfaced
            const recentWindow = nowKolkata.clone().subtract(7, 'days').startOf('day').toDate();
            const txSnap = await firebase_1.db.collection('users')
                .doc(userData.uid)
                .collection('sms_transactions')
                .where('timestamp', '>=', recentWindow.toISOString())
                .get();
            let untaggedCount = 0;
            for (const doc of txSnap.docs) {
                const data = doc.data();
                const isVerified = data.isVerified === true;
                const cat = (data.category || '').toString().trim().toLowerCase();
                const isUntagged = !isVerified || cat === 'untagged' || cat === 'uncategorized' || cat === 'action needed' || cat === 'upi transfer' || cat === '';
                if (isUntagged) {
                    untaggedCount++;
                }
            }
            let title;
            let body;
            if (untaggedCount > 0) {
                console.log(`[NightlyExpenseNotifier] Sending untagged reminder to user ${userData.uid} (${untaggedCount} untagged).`);
                title = "📋 Untagged Transactions Reminder";
                body = `You have ${untaggedCount} untagged bank transaction${untaggedCount > 1 ? 's' : ''}. Tap to categorize your expenses!`;
            }
            else {
                console.log(`[NightlyExpenseNotifier] No untagged transactions found for user ${userData.uid}. Sending manual spend check-in.`);
                title = "💳 Daily Spend Check-in";
                body = "All transactions are tagged! Did you make any cash or UPI payments today that need to be recorded? Tap to log them.";
            }
            await firebase_1.admin.messaging().send({
                token: userData.fcmToken,
                notification: { title, body },
                android: {
                    notification: {
                        channelId: 'finance_reminder_channel',
                        tag: `untagged_expenses_${todayStr}`
                    }
                },
                data: {
                    type: "NIGHTLY_EXPENSE_TAG",
                    date: todayStr,
                    count: untaggedCount.toString()
                }
            });
            await (0, logger_1.logNotification)(userData.uid, title, body, "NIGHTLY_EXPENSE_TAG");
        }
        catch (error) {
            console.error(`[NightlyExpenseNotifier] Failed to send notification for user ${userData.uid}:`, error);
        }
    }
}
exports.triggerNightlyExpenseNotifier = functions.runWith({ timeoutSeconds: 120, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    await internalDailyUntaggedExpenseNotifier();
    return { success: true, message: "Nightly expense notifier triggered successfully." };
});
//# sourceMappingURL=nightlyExpenseNotifier.js.map