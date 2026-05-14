import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import axios from "axios";
import * as cheerio from "cheerio";
import * as moment from "moment-timezone";
import { CloudTasksClient } from "@google-cloud/tasks";

admin.initializeApp();
const db = admin.firestore();
const tasksClient = new CloudTasksClient();

// ----------------------------------------------------------------------------
// SCRAPERS
// ----------------------------------------------------------------------------
async function fetchGoldPriceFromLiveChennai(): Promise<number | null> {
    try {
        const url = 'https://www.livechennai.com/gold_silverrate.asp';
        const response = await axios.get(url, {
            headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
            timeout: 10000
        });
        const $ = cheerio.load(response.data);
        let finalPrice: number | null = null;
        $('.today-gold-rate td:nth-child(2)').each((i, el) => {
            const text = $(el).text().trim();
            const match = text.match(/\d{1,3}(,\d{3})+|\d{4,}/);
            if (match) {
                const num = parseInt(match[0].replace(/[^0-9]/g, ''), 10);
                if (num > 1000 && !finalPrice) finalPrice = num;
            }
        });
        return finalPrice;
    } catch (e) {
        console.error("LiveChennai Error:", e);
        return null;
    }
}


async function fetchGoldPriceFromBankBazaar(): Promise<number | null> {
    try {
        const url = 'https://www.bankbazaar.com/gold-rate-chennai.html';
        const response = await axios.get(url, {
            headers: { 'User-Agent': 'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36' },
            timeout: 10000
        });
        const $ = cheerio.load(response.data);
        let finalPrice: number | null = null;
        $('.white-space-nowrap').each((i, el) => {
            const text = $(el).text().trim();
            if ((text.includes('₹') || text.includes('Rs')) && text.match(/\d{1,3}(,\d{3})+|\d{4,}/)) {
                const num = parseInt(text.replace(/[^0-9]/g, ''), 10);
                if (num > 1000 && !finalPrice) finalPrice = num;
            }
        });
        return finalPrice;
    } catch (e) {
        console.error("BankBazaar Error:", e);
        return null;
    }
}

// ----------------------------------------------------------------------------
// CALENDAR REMINDERS (Cloud Tasks)
// ----------------------------------------------------------------------------

/**
 * Task Handler: Called by Cloud Task queue. 
 */
exports.processCalendarReminderTask = functions.tasks
    .taskQueue({
        retryConfig: { maxAttempts: 3 },
        rateLimits: { maxConcurrentDispatches: 10 },
    })
    .onDispatch(async (data) => {
        const { uid, reminderId, title, body } = data;
        try {
            const reminderRef = db.collection("users").doc(uid).collection("calendar_reminders").doc(reminderId);
            const reminderDoc = await reminderRef.get();
            if (!reminderDoc.exists) return;

            const userDoc = await db.collection("usernames").where("uid", "==", uid).limit(1).get();
            if (!userDoc.empty) {
                const token = userDoc.docs[0].data().fcmToken;
                if (token) {
                    await admin.messaging().send({
                        token,
                        notification: { title, body },
                        android: { notification: { channelId: "calendar_reminder_channel" } },
                        data: { type: "CALENDAR_REMINDER", reminderId }
                    });
                }
            }

            const expireAt = new Date();
            expireAt.setDate(expireAt.getDate() + 30);
            await reminderRef.update({
                status: "completed",
                notifiedAt: admin.firestore.FieldValue.serverTimestamp(),
                expireAt: admin.firestore.Timestamp.fromDate(expireAt)
            });
        } catch (error) {
            console.error("Task execution failed:", error);
            throw error;
        }
    });

exports.onCalendarReminderDeleted = functions.firestore
    .document('users/{uid}/calendar_reminders/{reminderId}')
    .onDelete(async (snapshot, context) => {
        const data = snapshot.data();
        if (data && data.taskId && data.status === "scheduled") {
            try {
                await tasksClient.deleteTask({ name: data.taskId });
            } catch (error) {
                console.error("Failed to delete scheduled task:", error);
            }
        }
    });

exports.onCalendarReminderCreated = functions.firestore
    .document('users/{uid}/calendar_reminders/{reminderId}')
    .onCreate(async (snapshot, context) => {
        const data = snapshot.data();
        if (!data) return;
        const { uid, reminderId } = context.params;
        
        // Use Asia/Kolkata for all calculations
        const nowKolkata = moment().tz('Asia/Kolkata');
        const scheduledTime = moment.tz(`${data.date} ${data.time}`, "YYYY-MM-DD HH:mm", "Asia/Kolkata");
        
        console.log(`Scheduling reminder for ${uid}/${reminderId} at ${scheduledTime.format()} (Now: ${nowKolkata.format()})`);

        if (!scheduledTime.isValid() || scheduledTime.isBefore(nowKolkata.subtract(30, 'seconds'))) {
            console.log(`Reminder ${reminderId} is invalid or in the past. Marking as expired.`);
            return snapshot.ref.update({ status: "expired" });
        }
        
        try {
            const project = process.env.GCLOUD_PROJECT || admin.app().options.projectId;
            const location = 'us-central1';
            const queue = 'processCalendarReminderTask';
            const queuePath = tasksClient.queuePath(project!, location, queue);
            const url = `https://${location}-${project}.cloudfunctions.net/processCalendarReminderTask`;
            const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;

            const taskRequest: any = {
                parent: queuePath,
                task: {
                    httpRequest: {
                        httpMethod: 'POST',
                        url,
                        body: Buffer.from(JSON.stringify({ data: { uid, reminderId, title: data.title, body: data.description } })).toString('base64'),
                        headers: { 'Content-Type': 'application/json' },
                        oidcToken: {
                            serviceAccountEmail,
                        },
                    },
                    scheduleTime: {
                        seconds: scheduledTime.unix(),
                    },
                },
            };

            const [response] = await tasksClient.createTask(taskRequest);
            const taskId = response.name;
            
            console.log(`Successfully enqueued task ${taskId} for reminder ${reminderId}`);

            return snapshot.ref.update({
                status: "scheduled",
                taskId: taskId, 
                scheduledAtTimestamp: admin.firestore.Timestamp.fromMillis(scheduledTime.valueOf())
            });
        } catch (error) {
            console.error("Scheduling failed:", error);
            return snapshot.ref.update({ status: "error", error: String(error) });
        }
    });

// ----------------------------------------------------------------------------
// MISC (Gold, Shifts, etc.)
// ----------------------------------------------------------------------------

async function notifyAllUsers(price: number, oldPrice: number | null) {
    let diffText = 'Latest Update';
    if (oldPrice) {
        const diff = price - oldPrice;
        if (diff > 0) diffText = `📈 Up by ₹${Math.abs(diff)}`;
        else if (diff < 0) diffText = `📉 Down by ₹${Math.abs(diff)}`;
        else diffText = `➖ No change`;
    }
    const snap = await db.collection("usernames").get();
    const tokens: string[] = [];
    snap.forEach(d => { if (d.data().fcmToken) tokens.push(d.data().fcmToken); });
    if (tokens.length > 0) {
        await admin.messaging().sendEachForMulticast({
            tokens,
            notification: { title: `Gold Rate: ₹${price}`, body: diffText },
            android: { notification: { channelId: "gold_price_channel" } },
            data: { type: "GOLD_PRICE" }
        });
    }
}

async function internalPerformGoldFetch(force: boolean = false) {
    const results = [await fetchGoldPriceFromLiveChennai(), await fetchGoldPriceFromBankBazaar()];
    const currentPrice = results[0] || results[1];
    if (!currentPrice) return { success: false };

    const nowIST = moment().tz('Asia/Kolkata');
    const lastDocs = await db.collection("global_gold_prices").orderBy("timestamp", "desc").limit(1).get();
    const lastPrice = lastDocs.empty ? null : lastDocs.docs[0].data().price;

    if (!force && nowIST.hour() === 19 && lastPrice === currentPrice) return { success: true };

    const timestampStr = nowIST.toISOString();
    await db.collection("global_gold_prices").doc(timestampStr.replace(/[:.]/g, '-')).set({
        date: nowIST.format('YYYY-MM-DD'),
        price: currentPrice,
        priceChange: lastPrice ? currentPrice - lastPrice : 0,
        timestamp: timestampStr,
        source: results[0] ? "LiveChennai" : "BankBazaar"
    });
    await notifyAllUsers(currentPrice, lastPrice);
    return { success: true };
}

exports.checkGoldSources = functions.https.onCall(async () => {
    const r = [await fetchGoldPriceFromLiveChennai(), await fetchGoldPriceFromBankBazaar()];
    return { timestamp: moment().tz('Asia/Kolkata').format('hh:mm:ss A'), live_chennai: r[0], bank_bazaar: r[1] };
});

exports.scheduledGoldFetch = functions.pubsub.schedule('0 11,19 * * *').timeZone('Asia/Kolkata').onRun(() => internalPerformGoldFetch());
exports.forceGoldFetch = functions.https.onCall(() => internalPerformGoldFetch(true));

exports.dailyShiftReminder = functions.pubsub.schedule('0 22 * * *').timeZone('Asia/Kolkata').onRun(async () => {
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
            const s = await db.collection('users').doc(userData.uid).collection('shifts').doc(tom.format('YYYY-MM')).collection('daily_shifts').doc(tom.format('YYYY-MM-DD')).get();
            if (s.exists) {
                console.log(`Sending shift reminder to user ${userData.uid} (Token: ${userData.fcmToken.substring(0, 10)}...)`);
                await admin.messaging().send({
                    token: userData.fcmToken,
                    notification: { title: "Tomorrow's Shift", body: s.data()?.shift_type || "Day Off" },
                    android: { notification: { channelId: 'shift_reminder_channel' } },
                    data: { type: "shift_reminder" }
                });
            }
        } catch (error) {
            console.error(`Failed to send shift reminder for user ${userData.uid}:`, error);
        }
    }
});

exports.checkDailyReminders = functions.pubsub.schedule('* * * * *').timeZone('Asia/Kolkata').onRun(async () => {
    const nowKolkata = moment().tz('Asia/Kolkata');
    const timeStr = nowKolkata.format('HH:mm');
    console.log(`Running checkDailyReminders at ${nowKolkata.format()} (Search Time: ${timeStr})`);
    
    const users = await db.collection('usernames').get();
    for (const u of users.docs) {
        const userData = u.data();
        if (!userData.fcmToken || !userData.uid) continue;

        try {
            const rs = await db.collection('users').doc(userData.uid).collection('daily_reminders').where('time', '==', timeStr).where('isActive', '==', true).get();
            if (!rs.empty) {
                console.log(`Found ${rs.size} daily reminders for user ${userData.uid} at ${timeStr}`);
            }
            for (const r of rs.docs) {
                console.log(`Sending daily reminder: ${r.data().title} to ${userData.uid}`);
                await admin.messaging().send({
                    token: userData.fcmToken,
                    notification: { title: r.data().title, body: r.data().description || "Reminder" },
                    android: { notification: { channelId: 'daily_reminder_channel' } },
                    data: { type: "daily_reminder" }
                });
            }
        } catch (error) {
            console.error(`Failed to send daily reminders for user ${userData.uid}:`, error);
        }
    }
});

