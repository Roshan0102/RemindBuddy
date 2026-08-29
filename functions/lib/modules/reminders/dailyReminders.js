"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.internalCheckDailyReminders = internalCheckDailyReminders;
const moment = require("moment-timezone");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
async function internalCheckDailyReminders() {
    const nowKolkata = moment().tz('Asia/Kolkata');
    const timeStr = nowKolkata.format('HH:mm');
    console.log(`Running checkDailyReminders at ${nowKolkata.format()} (Search Time: ${timeStr})`);
    const users = await firebase_1.db.collection('usernames').get();
    for (const u of users.docs) {
        const userData = u.data();
        if (!userData.fcmToken || !userData.uid)
            continue;
        try {
            // Check if user has daily_reminders module enabled and not turned off reminders notifications
            const userProfileDoc = await firebase_1.db.collection("users").doc(userData.uid).get();
            if (userProfileDoc.exists) {
                const uData = userProfileDoc.data();
                const enabledModules = (uData === null || uData === void 0 ? void 0 : uData.enabledModules) || [];
                const notifPrefs = (uData === null || uData === void 0 ? void 0 : uData.notificationPreferences) || {};
                if (!enabledModules.includes("daily_reminders") || notifPrefs.daily_reminders === false) {
                    console.log(`Skipping daily reminders for user ${userData.uid}: disabled in modules or preferences.`);
                    continue;
                }
            }
            else {
                continue;
            }
            const rs = await firebase_1.db.collection('users').doc(userData.uid).collection('daily_reminders').where('isActive', '==', true).get();
            const todayDateStr = nowKolkata.format('YYYY-MM-DD');
            const currentTimeStr = nowKolkata.format('HH:mm');
            for (const r of rs.docs) {
                const rData = r.data();
                const reminderId = r.id;
                const scheduledTime = rData.time; // HH:mm format
                const lastCompletedDate = rData.lastCompletedDate;
                const lastTriggeredDate = rData.lastTriggeredDate;
                const lastTriggeredTime = rData.lastTriggeredTime;
                const snoozeEnabled = rData.snoozeEnabled === true;
                const snoozeIntervalMinutes = rData.snoozeIntervalMinutes || 15;
                const maxSnoozeCount = rData.maxSnoozeCount || 3;
                const currentSnoozeCount = rData.currentSnoozeCount || 0;
                // 1. Skip if completed today
                if (lastCompletedDate === todayDateStr) {
                    continue;
                }
                let shouldTrigger = false;
                let nextSnoozeCount = currentSnoozeCount;
                let markCompleted = false;
                if (lastTriggeredDate !== todayDateStr) {
                    // Has not triggered today yet
                    if (currentTimeStr === scheduledTime) {
                        shouldTrigger = true;
                        nextSnoozeCount = 1;
                        if (!snoozeEnabled || maxSnoozeCount <= 1) {
                            markCompleted = true;
                        }
                    }
                }
                else {
                    // Has triggered today already, check if we need to snooze
                    if (snoozeEnabled && lastTriggeredTime) {
                        const lastTriggeredDateTime = moment.tz(`${todayDateStr} ${lastTriggeredTime}`, 'YYYY-MM-DD HH:mm', 'Asia/Kolkata');
                        const diffMinutes = nowKolkata.diff(lastTriggeredDateTime, 'minutes');
                        if (diffMinutes >= snoozeIntervalMinutes) {
                            shouldTrigger = true;
                            nextSnoozeCount = currentSnoozeCount + 1;
                            if (nextSnoozeCount >= maxSnoozeCount) {
                                markCompleted = true;
                            }
                        }
                    }
                }
                if (shouldTrigger) {
                    const title = rData.title;
                    const body = rData.description || "Reminder";
                    console.log(`Sending daily reminder: ${title} to ${userData.uid}. Snooze count: ${nextSnoozeCount}/${maxSnoozeCount}`);
                    await firebase_1.admin.messaging().send({
                        token: userData.fcmToken,
                        notification: { title, body },
                        android: {
                            notification: {
                                channelId: 'daily_reminder_channel',
                                tag: `daily_reminder_${reminderId}`
                            }
                        },
                        data: {
                            type: "daily_reminder",
                            reminderId: reminderId,
                            uid: userData.uid
                        }
                    });
                    await (0, logger_1.logNotification)(userData.uid, title, body, "DAILY_REMINDER");
                    // Update Firestore status
                    const updateData = {
                        lastTriggeredDate: todayDateStr,
                        lastTriggeredTime: currentTimeStr,
                        currentSnoozeCount: nextSnoozeCount
                    };
                    if (markCompleted) {
                        updateData.lastCompletedDate = todayDateStr;
                    }
                    await r.ref.update(updateData);
                }
            }
        }
        catch (error) {
            console.error(`Failed to send daily reminders for user ${userData.uid}:`, error);
        }
    }
}
//# sourceMappingURL=dailyReminders.js.map