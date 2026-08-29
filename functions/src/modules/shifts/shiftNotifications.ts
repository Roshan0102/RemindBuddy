import * as moment from "moment-timezone";
import { admin, db } from "../../config/firebase";
import { logNotification } from "../../utils/logger";

export async function internalDailyShiftReminder() {
    const nowKolkata = moment().tz('Asia/Kolkata');
    const tom = nowKolkata.clone().add(1, 'day');
    console.log(`Running dailyShiftReminder at ${nowKolkata.format()}. Target date: ${tom.format('YYYY-MM-DD')}`);
    
    const users = await db.collection('usernames').get();
    console.log(`Found ${users.size} users for shift reminders.`);

    for (const u of users.docs) {
        const userData = u.data();
        if (!userData.fcmToken || !userData.uid) {
            console.log(`Skipping user ${u.id}: Missing token or UID.`);
            continue;
        }

        try {
            // Check if user has shift module enabled and not turned off shift notifications
            const userDoc = await db.collection('users').doc(userData.uid).get();
            if (userDoc.exists) {
                const uData = userDoc.data();
                const enabledModules = uData?.enabledModules || [];
                const notifPrefs = uData?.notificationPreferences || {};
                
                if (!enabledModules.includes("shifts") || notifPrefs.shifts === false) {
                    console.log(`Skipping shift reminder for user ${userData.uid}: disabled in modules or preferences.`);
                    continue;
                }
            } else {
                console.log(`Skipping user ${userData.uid}: No user doc found.`);
                continue;
            }

            const s = await db.collection('users').doc(userData.uid).collection('shifts').doc(tom.format('YYYY-MM')).collection('daily_shifts').doc(tom.format('YYYY-MM-DD')).get();
            if (s.exists) {
                console.log(`Sending shift reminder to user ${userData.uid} (Token: ${userData.fcmToken.substring(0, 10)}...)`);
                const title = "Tomorrow's Shift";
                const body = s.data()?.shift_type || "Day Off";
                await admin.messaging().send({
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
                await logNotification(userData.uid, title, body, "SHIFT_REMINDER");
            }
        } catch (error) {
            console.error(`Failed to send shift reminder for user ${userData.uid}:`, error);
        }
    }
}
