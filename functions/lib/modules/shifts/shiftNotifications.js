"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.internalDailyShiftReminder = internalDailyShiftReminder;
const moment = require("moment-timezone");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
async function internalDailyShiftReminder() {
    var _a;
    const nowKolkata = moment().tz('Asia/Kolkata');
    const tom = nowKolkata.clone().add(1, 'day');
    console.log(`Running dailyShiftReminder at ${nowKolkata.format()}. Target date: ${tom.format('YYYY-MM-DD')}`);
    const users = await firebase_1.db.collection('usernames').get();
    console.log(`Found ${users.size} users for shift reminders.`);
    for (const u of users.docs) {
        const userData = u.data();
        if (!userData.fcmToken || !userData.uid) {
            console.log(`Skipping user ${u.id}: Missing token or UID.`);
            continue;
        }
        try {
            // Check if user has shift module enabled and not turned off shift notifications
            const userDoc = await firebase_1.db.collection('users').doc(userData.uid).get();
            if (userDoc.exists) {
                const uData = userDoc.data();
                const enabledModules = (uData === null || uData === void 0 ? void 0 : uData.enabledModules) || [];
                const notifPrefs = (uData === null || uData === void 0 ? void 0 : uData.notificationPreferences) || {};
                if (!enabledModules.includes("shifts") || notifPrefs.shifts === false) {
                    console.log(`Skipping shift reminder for user ${userData.uid}: disabled in modules or preferences.`);
                    continue;
                }
            }
            else {
                console.log(`Skipping user ${userData.uid}: No user doc found.`);
                continue;
            }
            const s = await firebase_1.db.collection('users').doc(userData.uid).collection('shifts').doc(tom.format('YYYY-MM')).collection('daily_shifts').doc(tom.format('YYYY-MM-DD')).get();
            if (s.exists) {
                console.log(`Sending shift reminder to user ${userData.uid} (Token: ${userData.fcmToken.substring(0, 10)}...)`);
                const title = "Tomorrow's Shift";
                const body = ((_a = s.data()) === null || _a === void 0 ? void 0 : _a.shift_type) || "Day Off";
                await firebase_1.admin.messaging().send({
                    token: userData.fcmToken,
                    notification: { title, body },
                    android: {
                        notification: {
                            channelId: 'shift_reminder_channel',
                            tag: `shift_reminder_${tom.format('YYYY-MM-DD')}`
                        }
                    },
                    data: { type: "shift_reminder" }
                });
                await (0, logger_1.logNotification)(userData.uid, title, body, "SHIFT_REMINDER");
            }
        }
        catch (error) {
            console.error(`Failed to send shift reminder for user ${userData.uid}:`, error);
        }
    }
}
//# sourceMappingURL=shiftNotifications.js.map