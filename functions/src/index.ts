
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

async function fetchGoldPriceFromTOI(): Promise<number | null> {
    try {
        const url = 'https://timesofindia.indiatimes.com/business/gold-rates-today/gold-price-in-chennai';
        const response = await axios.get(url, {
            headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
            timeout: 10000
        });
        const $ = cheerio.load(response.data);
        let finalPrice: number | null = null;
        $("h2").each((i, el) => {
            if ($(el).text().toLowerCase().includes("22k gold price trend")) {
                let wrapper = $(el).parent();
                while (wrapper.length && !wrapper.next().hasClass('custom-table')) {
                    wrapper = wrapper.parent();
                    if (wrapper.next().find('.custom-table').length > 0) {
                        wrapper = wrapper.next();
                        break;
                    }
                }
                const rows = wrapper.find('.custom-table .Ge2sP .fCMra');
                if (rows.length > 0) {
                    const cells = rows.first().find('.Gy41U');
                    if (cells.length > 1 && $(cells[0]).text().trim().includes('1')) {
                        const basePrice = $(cells[1]).text().trim().split('.')[0];
                        const num = parseInt(basePrice.replace(/[^0-9]/g, ''), 10);
                        if (num > 1000) finalPrice = num;
                    }
                }
            }
        });
        return finalPrice;
    } catch (e) {
        console.error("TOI Error:", e);
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
        const scheduledTime = moment.tz(`${data.date} ${data.time}`, "YYYY-MM-DD HH:mm", "Asia/Kolkata");
        if (!scheduledTime.isValid() || scheduledTime.isBefore(moment().subtract(30, 'seconds'))) {
            return snapshot.ref.update({ status: "expired" });
        }
        try {
            const project = "remindbuddy-b68f9";
            const location = "us-central1";
            const queue = "processCalendarReminderTask";
            const queuePath = tasksClient.queuePath(project, location, queue);
            const url = `https://${location}-${project}.cloudfunctions.net/processCalendarReminderTask`;
            const task: any = {
                httpRequest: {
                    httpMethod: 'POST',
                    url,
                    body: Buffer.from(JSON.stringify({ uid, reminderId, title: data.title, body: data.description })).toString('base64'),
                    headers: { 'Content-Type': 'application/json' },
                },
                scheduleTime: { seconds: scheduledTime.unix() },
            };
            await tasksClient.createTask({ parent: queuePath, task });
            return snapshot.ref.update({
                status: "scheduled",
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
            data: { type: "GOLD_PRICE" } // Added tag for auto-tab switching
        });
    }
}

async function internalPerformGoldFetch(force: boolean = false) {
    const results = [await fetchGoldPriceFromLiveChennai(), await fetchGoldPriceFromBankBazaar(), await fetchGoldPriceFromTOI()];
    const currentPrice = results[0] || results[1] || results[2];
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
        source: results[0] ? "LiveChennai" : results[1] ? "BankBazaar" : "TOI"
    });
    await notifyAllUsers(currentPrice, lastPrice);
    return { success: true };
}

exports.checkGoldSources = functions.https.onCall(async () => {
    const r = [await fetchGoldPriceFromLiveChennai(), await fetchGoldPriceFromBankBazaar(), await fetchGoldPriceFromTOI()];
    return { timestamp: moment().tz('Asia/Kolkata').format('hh:mm:ss A'), live_chennai: r[0], bank_bazaar: r[1], TOI: r[2] };
});

exports.scheduledGoldFetch = functions.pubsub.schedule('0 11,19 * * *').timeZone('Asia/Kolkata').onRun(() => internalPerformGoldFetch());
exports.forceGoldFetch = functions.https.onCall(() => internalPerformGoldFetch(true));

exports.dailyShiftReminder = functions.pubsub.schedule('0 22 * * *').timeZone('Asia/Kolkata').onRun(async () => {
    const tom = moment().tz('Asia/Kolkata').add(1, 'day');
    const users = await db.collection('usernames').get();
    for (const u of users.docs) {
        const s = await db.collection('users').doc(u.data().uid).collection('shifts').doc(tom.format('YYYY-MM')).collection('daily_shifts').doc(tom.format('YYYY-MM-DD')).get();
        if (s.exists) {
            await admin.messaging().send({
                token: u.data().fcmToken,
                notification: { title: "Tomorrow's Shift", body: s.data()?.shift_type || "Day Off" },
                android: { notification: { channelId: 'shift_reminder_channel' } },
                data: { type: "shift_reminder" } // Added tag for auto-tab switching
            });
        }
    }
});

exports.checkDailyReminders = functions.pubsub.schedule('*/15 * * * *').timeZone('Asia/Kolkata').onRun(async () => {
    const now = moment().tz('Asia/Kolkata').format('HH:mm');
    const users = await db.collection('usernames').get();
    for (const u of users.docs) {
        const rs = await db.collection('users').doc(u.data().uid).collection('daily_reminders').where('time', '==', now).where('isActive', '==', true).get();
        for (const r of rs.docs) {
            await admin.messaging().send({
                token: u.data().fcmToken,
                notification: { title: r.data().title, body: r.data().description || "Reminder" },
                android: { notification: { channelId: 'remindbuddy_channel' } },
                data: { type: "daily_reminder" } // Added tag for direct navigation
            });
        }
    }
});
