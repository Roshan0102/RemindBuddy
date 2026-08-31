"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.internalDailyUntaggedExpenseNotifier = internalDailyUntaggedExpenseNotifier;
const moment = require("moment-timezone");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
async function internalDailyUntaggedExpenseNotifier() {
    const nowKolkata = moment().tz('Asia/Kolkata');
    const todayStr = nowKolkata.format('YYYY-MM-DD');
    console.log(`Running internalDailyUntaggedExpenseNotifier at ${nowKolkata.format()} for date ${todayStr}`);
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
            if (!enabledModules.includes("finance") || notifPrefs.finance === false || notifPrefs.finance_nightly_tagging === false) {
                continue;
            }
            // Query today's sms_transactions
            const startOfDay = nowKolkata.clone().startOf('day').toDate();
            const endOfDay = nowKolkata.clone().endOf('day').toDate();
            const txSnap = await firebase_1.db.collection('users')
                .doc(userData.uid)
                .collection('sms_transactions')
                .where('timestamp', '>=', startOfDay.toISOString())
                .where('timestamp', '<=', endOfDay.toISOString())
                .get();
            let untaggedCount = 0;
            for (const doc of txSnap.docs) {
                const data = doc.data();
                const cat = (data.category || '').toString();
                if (cat === 'Uncategorized' || cat === 'Action Needed' || cat === 'UPI Transfer' || cat === '' || !data.category) {
                    untaggedCount++;
                }
            }
            if (untaggedCount > 0) {
                console.log(`Sending nightly untagged expense reminder to user ${userData.uid} (${untaggedCount} untagged).`);
                const title = "📋 Today's Expense Tagging";
                const body = `You have ${untaggedCount} untagged expense${untaggedCount > 1 ? 's' : ''} for today. Please tag them!`;
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
        }
        catch (error) {
            console.error(`Failed to send nightly expense reminder for user ${userData.uid}:`, error);
        }
    }
}
//# sourceMappingURL=nightlyExpenseNotifier.js.map