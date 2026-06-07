"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios_1 = require("axios");
const cheerio = require("cheerio");
const moment = require("moment-timezone");
const tasks_1 = require("@google-cloud/tasks");
admin.initializeApp();
const db = admin.firestore();
const tasksClient = new tasks_1.CloudTasksClient();
// ----------------------------------------------------------------------------
// SCRAPERS
// ----------------------------------------------------------------------------
async function fetchGoldPriceFromLiveChennai() {
    try {
        const url = 'https://www.livechennai.com/gold_silverrate.asp';
        const response = await axios_1.default.get(url, {
            headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
            timeout: 10000
        });
        const $ = cheerio.load(response.data);
        let finalPrice = null;
        $('.today-gold-rate td:nth-child(2)').each((i, el) => {
            const text = $(el).text().trim();
            const match = text.match(/\d{1,3}(,\d{3})+|\d{4,}/);
            if (match) {
                const num = parseInt(match[0].replace(/[^0-9]/g, ''), 10);
                if (num > 1000 && !finalPrice)
                    finalPrice = num;
            }
        });
        return finalPrice;
    }
    catch (e) {
        console.error("LiveChennai Error:", e);
        return null;
    }
}
async function fetchGoldPriceFromBankBazaar() {
    try {
        const url = 'https://www.bankbazaar.com/gold-rate-chennai.html';
        const response = await axios_1.default.get(url, {
            headers: { 'User-Agent': 'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36' },
            timeout: 10000
        });
        const $ = cheerio.load(response.data);
        let finalPrice = null;
        $('.white-space-nowrap').each((i, el) => {
            const text = $(el).text().trim();
            if ((text.includes('₹') || text.includes('Rs')) && text.match(/\d{1,3}(,\d{3})+|\d{4,}/)) {
                const num = parseInt(text.replace(/[^0-9]/g, ''), 10);
                if (num > 1000 && !finalPrice)
                    finalPrice = num;
            }
        });
        return finalPrice;
    }
    catch (e) {
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
        if (!reminderDoc.exists)
            return;
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
    }
    catch (error) {
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
        }
        catch (error) {
            console.error("Failed to delete scheduled task:", error);
        }
    }
});
exports.onCalendarReminderCreated = functions.firestore
    .document('users/{uid}/calendar_reminders/{reminderId}')
    .onCreate(async (snapshot, context) => {
    const data = snapshot.data();
    if (!data)
        return;
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
        const queuePath = tasksClient.queuePath(project, location, queue);
        const url = `https://${location}-${project}.cloudfunctions.net/processCalendarReminderTask`;
        const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;
        const taskRequest = {
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
    }
    catch (error) {
        console.error("Scheduling failed:", error);
        return snapshot.ref.update({ status: "error", error: String(error) });
    }
});
// ----------------------------------------------------------------------------
// MISC (Gold, Shifts, etc.)
// ----------------------------------------------------------------------------
async function notifyAllUsers(price, oldPrice) {
    let diffText = 'Latest Update';
    if (oldPrice) {
        const diff = price - oldPrice;
        if (diff > 0)
            diffText = `📈 Up by ₹${Math.abs(diff)}`;
        else if (diff < 0)
            diffText = `📉 Down by ₹${Math.abs(diff)}`;
        else
            diffText = `➖ No change`;
    }
    const snap = await db.collection("usernames").get();
    const tokens = [];
    snap.forEach(d => { if (d.data().fcmToken)
        tokens.push(d.data().fcmToken); });
    if (tokens.length > 0) {
        await admin.messaging().sendEachForMulticast({
            tokens,
            notification: { title: `Gold Rate: ₹${price}`, body: diffText },
            android: { notification: { channelId: "gold_price_channel" } },
            data: { type: "GOLD_PRICE" }
        });
    }
}
async function internalPerformGoldFetch(force = false) {
    const results = [await fetchGoldPriceFromLiveChennai(), await fetchGoldPriceFromBankBazaar()];
    const currentPrice = results[0] || results[1];
    if (!currentPrice)
        return { success: false, error: "No price retrieved from scrapers." };
    const nowIST = moment().tz('Asia/Kolkata');
    const lastDocs = await db.collection("global_gold_prices").orderBy("timestamp", "desc").limit(1).get();
    const lastPrice = lastDocs.empty ? null : lastDocs.docs[0].data().price;
    if (lastPrice === currentPrice) {
        return { success: true, status: 'no_change', price: currentPrice };
    }
    const timestampStr = nowIST.toISOString();
    await db.collection("global_gold_prices").doc(timestampStr.replace(/[:.]/g, '-')).set({
        date: nowIST.format('YYYY-MM-DD'),
        price: currentPrice,
        priceChange: lastPrice ? currentPrice - lastPrice : 0,
        timestamp: timestampStr,
        source: results[0] ? "LiveChennai" : "BankBazaar"
    });
    await notifyAllUsers(currentPrice, lastPrice);
    return { success: true, status: 'changed', price: currentPrice };
}
exports.checkGoldSources = functions.https.onCall(async () => {
    const r = [await fetchGoldPriceFromLiveChennai(), await fetchGoldPriceFromBankBazaar()];
    return { timestamp: moment().tz('Asia/Kolkata').format('hh:mm:ss A'), live_chennai: r[0], bank_bazaar: r[1] };
});
exports.scheduledGoldFetch = functions.pubsub.schedule('0 11,19 * * *').timeZone('Asia/Kolkata').onRun(() => internalPerformGoldFetch());
exports.forceGoldFetch = functions.https.onCall(() => internalPerformGoldFetch(true));
exports.dailyShiftReminder = functions.pubsub.schedule('0 22 * * *').timeZone('Asia/Kolkata').onRun(async () => {
    var _a;
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
                    notification: { title: "Tomorrow's Shift", body: ((_a = s.data()) === null || _a === void 0 ? void 0 : _a.shift_type) || "Day Off" },
                    android: { notification: { channelId: 'shift_reminder_channel' } },
                    data: { type: "shift_reminder" }
                });
            }
        }
        catch (error) {
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
        if (!userData.fcmToken || !userData.uid)
            continue;
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
        }
        catch (error) {
            console.error(`Failed to send daily reminders for user ${userData.uid}:`, error);
        }
    }
});
exports.analyzeRosterImage = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    // Ensure user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const { image, employeeName } = data;
    if (!image || !employeeName) {
        throw new functions.https.HttpsError('invalid-argument', 'Image and employeeName are required.');
    }
    // 1. Fetch the Gemini API key from Firestore admin_creds/gemini_config
    const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
    let apiKey = "";
    if (configDoc.exists) {
        apiKey = ((_a = configDoc.data()) === null || _a === void 0 ? void 0 : _a.apiKey) || "";
    }
    if (!apiKey) {
        throw new functions.https.HttpsError('failed-precondition', 'Gemini API key is not configured in admin console.');
    }
    // 2. Prepare payload for Gemini API
    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
    const prompt = `Analyze the work roster image. Extract the shift schedule for employee "${employeeName}".
The output MUST be a JSON object matching this schema. If a shift date is unclear or missing, mark it as "week_off".

Shift Types in roster:
- M or morning: Morning shift (06:00 - 14:00)
- A or afternoon: Afternoon shift (14:00 - 22:00)
- N or night: Night shift (22:00 - 06:00)
- L or holiday: Holiday / Week Off (is_week_off: true, shift_type: 'week_off')
- Empty box: Week Off (is_week_off: true, shift_type: 'week_off')

Required JSON format:
{
  "employee_name": "${employeeName}",
  "month": "Month Year (e.g. March 2026)",
  "shifts": [
    {
      "date": "YYYY-MM-DD",
      "shift_type": "morning|afternoon|night|week_off",
      "start_time": "HH:MM or null",
      "end_time": "HH:MM or null",
      "is_week_off": true|false
    }
  ]
}`;
    const payload = {
        contents: [
            {
                parts: [
                    { text: prompt },
                    {
                        inlineData: {
                            mimeType: "image/jpeg",
                            data: image // Base64 string without data:image/jpeg;base64 prefix
                        }
                    }
                ]
            }
        ],
        generationConfig: {
            responseMimeType: "application/json",
            responseSchema: {
                type: "OBJECT",
                properties: {
                    employee_name: { type: "STRING" },
                    month: { type: "STRING" },
                    shifts: {
                        type: "ARRAY",
                        items: {
                            type: "OBJECT",
                            properties: {
                                date: { type: "STRING", description: "Date formatted as YYYY-MM-DD" },
                                shift_type: { type: "STRING", description: "morning, afternoon, night, or week_off" },
                                start_time: { type: "STRING", nullable: true, description: "HH:MM format" },
                                end_time: { type: "STRING", nullable: true, description: "HH:MM format" },
                                is_week_off: { type: "BOOLEAN" }
                            },
                            required: ["date", "shift_type", "is_week_off"]
                        }
                    }
                },
                required: ["employee_name", "month", "shifts"]
            }
        }
    };
    try {
        const response = await axios_1.default.post(url, payload, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 60000
        });
        const candidates = (_b = response.data) === null || _b === void 0 ? void 0 : _b.candidates;
        if (!candidates || candidates.length === 0) {
            throw new functions.https.HttpsError('internal', 'No response candidates returned from Gemini API.');
        }
        const textResponse = (_d = (_c = candidates[0].content) === null || _c === void 0 ? void 0 : _c.parts[0]) === null || _d === void 0 ? void 0 : _d.text;
        if (!textResponse) {
            throw new functions.https.HttpsError('internal', 'Empty content returned from Gemini API.');
        }
        // Return parsed JSON object
        return JSON.parse(textResponse);
    }
    catch (error) {
        console.error("Gemini API Error:", ((_e = error === null || error === void 0 ? void 0 : error.response) === null || _e === void 0 ? void 0 : _e.data) || error.message);
        throw new functions.https.HttpsError('internal', `Error calling Gemini API: ${((_h = (_g = (_f = error === null || error === void 0 ? void 0 : error.response) === null || _f === void 0 ? void 0 : _f.data) === null || _g === void 0 ? void 0 : _g.error) === null || _h === void 0 ? void 0 : _h.message) || error.message}`);
    }
});
//# sourceMappingURL=index.js.map