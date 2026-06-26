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

async function runGoldAIPredictionInternal(): Promise<any> {
    // 1. Fetch Gemini API key from Firestore
    const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
    let apiKey = "";
    if (configDoc.exists) {
        apiKey = configDoc.data()?.apiKey || "";
    }
    if (!apiKey) {
        throw new Error('Gemini API key is not configured in admin console.');
    }

    // 2. Fetch recent gold prices (last 15 records)
    const priceSnap = await db.collection("global_gold_prices").orderBy("timestamp", "desc").limit(15).get();
    const priceHistory: any[] = [];
    priceSnap.forEach(d => {
        const val = d.data();
        priceHistory.push({
            date: val.date,
            price: val.price,
            priceChange: val.priceChange,
            source: val.source
        });
    });

    // 3. Fetch latest news from Google News RSS
    const newsUrl = 'https://news.google.com/rss/search?q=gold+price+india&hl=en-IN&gl=IN&ceid=IN:en';
    let newsItems: any[] = [];
    try {
        const newsResponse = await axios.get(newsUrl, {
            headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
            timeout: 10000
        });
        const $ = cheerio.load(newsResponse.data, { xmlMode: true });
        $('item').slice(0, 8).each((i, el) => {
            const title = $(el).find('title').text();
            const link = $(el).find('link').text();
            const pubDate = $(el).find('pubDate').text();
            const source = $(el).find('source').text();
            newsItems.push({ title, link, pubDate, source });
        });
    } catch (newsErr) {
        console.error("Error fetching news in runGoldAIPredictionInternal:", newsErr);
    }

    // 4. Prepare prompt for Gemini
    const currentPriceInfo = priceHistory.length > 0 ? priceHistory[0] : null;
    const prompt = `You are a financial analyst specializing in precious metals, especially Gold rates in India.
Analyze the following recent historical 22K gold prices (per 2 grams or current units) and the latest gold market news headlines.
Specifically, make sure to consider:
- American and global economic news (such as US Federal Reserve interest rates).
- Geopolitical events or war news related to gold (which typically increases gold's appeal as a safe haven).
- Tax and import/export duty changes in India as well as other countries that affect the gold price in India.
- Any general news affecting demand/supply in the Indian gold market.

Your output must be written in very simple, plain, and easy-to-understand English. 
CRITICAL: Do NOT use difficult financial jargon (like 'bearish', 'bullish', 'consolidation', 'correction') without immediately explaining them in extremely simple terms. For example, instead of 'market is bearish', write 'prices are likely to fall (bearish)'. Keep explanations very simple.

Provide:
1. Market Sentiment: "bullish" (upward trend/prices rising), "bearish" (downward trend/prices dropping), or "neutral".
2. Sentiment Score: An integer from -100 (extremely bearish/falling) to 100 (extremely bullish/rising).
3. Sentiment Summary: A concise, 1-2 sentence summary of what is driving this sentiment using simple English.
4. Predicted Trend: "upward", "downward", or "stable" for the next 1-3 days.
5. Predicted Price Range: A realistic price range (e.g. "13,100 - 13,300") in the same format/currency unit as the input price (the current latest price is ${currentPriceInfo ? currentPriceInfo.price : 'unknown'}).
6. Prediction Rationale: A detailed bullet-pointed explanation of why you predict this trend, referencing recent price trends, US/global news, geopolitics/war news, or tax updates.

Input Data:
Recent Price History (latest first):
${JSON.stringify(priceHistory, null, 2)}

Latest Gold News Headlines:
${JSON.stringify(newsItems, null, 2)}

Respond ONLY with a JSON object matching this schema:
{
  "sentiment": "bullish" | "bearish" | "neutral",
  "sentimentScore": number,
  "sentimentSummary": "string",
  "predictedTrend": "upward" | "downward" | "stable",
  "predictedPriceRange": "string",
  "predictionRationale": "string"
}`;

    // 5. Call Gemini API
    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
    const payload = {
        contents: [
            {
                parts: [
                    { text: prompt }
                ]
            }
        ],
        generationConfig: {
            responseMimeType: "application/json",
            responseSchema: {
                type: "OBJECT",
                properties: {
                    sentiment: { type: "STRING", description: "bullish, bearish, or neutral" },
                    sentimentScore: { type: "INTEGER", description: "-100 to 100 score" },
                    sentimentSummary: { type: "STRING" },
                    predictedTrend: { type: "STRING", description: "upward, downward, or stable" },
                    predictedPriceRange: { type: "STRING" },
                    predictionRationale: { type: "STRING", description: "Clear, detailed reasoning text" }
                },
                required: ["sentiment", "sentimentScore", "sentimentSummary", "predictedTrend", "predictedPriceRange", "predictionRationale"]
            }
        }
    };

    const response = await axios.post(url, payload, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 60000
    });

    const candidates = response.data?.candidates;
    if (!candidates || candidates.length === 0) {
        throw new Error('No response candidates returned from Gemini API.');
    }

    const textResponse = candidates[0].content?.parts[0]?.text;
    if (!textResponse) {
        throw new Error('Empty content returned from Gemini API.');
    }

    const parsedResult = JSON.parse(textResponse);
    
    // 6. Store the result in Firestore
    const nowIST = moment().tz('Asia/Kolkata');
    const timestampStr = nowIST.toISOString();
    const docId = timestampStr.replace(/[:.]/g, '-');
    
    const insightData = {
        ...parsedResult,
        news: newsItems,
        priceHistoryAnalyzed: priceHistory,
        timestamp: timestampStr,
        createdAt: admin.firestore.FieldValue.serverTimestamp()
    };

    await db.collection("gold_ai_insights").doc(docId).set(insightData);
    await db.collection("gold_ai_insights").doc("latest").set(insightData);

    return insightData;
}

async function internalPerformGoldFetch(force: boolean = false) {
    const results = [await fetchGoldPriceFromLiveChennai(), await fetchGoldPriceFromBankBazaar()];
    const currentPrice = results[0] || results[1];
    if (!currentPrice) return { success: false, error: "No price retrieved from scrapers." };

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

    // Auto-trigger prediction when the gold price changes
    try {
        await runGoldAIPredictionInternal();
    } catch (aiErr) {
        console.error("Auto AI Prediction failed during gold fetch:", aiErr);
    }

    return { success: true, status: 'changed', price: currentPrice };
}

exports.generateGoldAIInsights = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    try {
        return await runGoldAIPredictionInternal();
    } catch (error: any) {
        console.error("generateGoldAIInsights Error:", error.message);
        throw new functions.https.HttpsError('internal', error.message || "Failed to generate gold AI insights.");
    }
});


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

exports.analyzeRosterImage = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
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
        apiKey = configDoc.data()?.apiKey || "";
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
        const response = await axios.post(url, payload, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 60000
        });

        const candidates = response.data?.candidates;
        if (!candidates || candidates.length === 0) {
            throw new functions.https.HttpsError('internal', 'No response candidates returned from Gemini API.');
        }

        const textResponse = candidates[0].content?.parts[0]?.text;
        if (!textResponse) {
            throw new functions.https.HttpsError('internal', 'Empty content returned from Gemini API.');
        }

        // Return parsed JSON object
        return JSON.parse(textResponse);
    } catch (error: any) {
        console.error("Gemini API Error:", error?.response?.data || error.message);
        throw new functions.https.HttpsError('internal', `Error calling Gemini API: ${error?.response?.data?.error?.message || error.message}`);
    }
});

async function generateGoldChitRecommendation(apiKey: string, priceHistory: any[], newsItems: any[]): Promise<{ recommendation: string, shortReason: string, fullAnalysis: string }> {
    const nowIST = moment().tz('Asia/Kolkata');
    const dayOfMonth = nowIST.date();
    const currentMonthName = nowIST.format('MMMM YYYY');
    const currentPriceStr = priceHistory.length > 0 ? `₹${priceHistory[0].price}` : 'unknown';

    // Override advice if it is between 26th and the end of the month
    if (dayOfMonth >= 26) {
        return {
            recommendation: "WAIT",
            shortReason: "Chit payment window closed. Next month-uku 1st lendhu pay pannunga.",
            fullAnalysis: "Monthly gold chit payment cycle (1st - 25th) ippo closed. Next month window 1st date thaan open aagum. Adhuvarai wait pannunga."
        };
    }

    const prompt = `You are a financial advisor helping an investor who deposits ₹10,000 monthly in a gold chit.
The chit payment must be made between the 1st and the 25th of every month. The chit company purchases gold on the exact day the payment is received.
Your goal is to recommend whether the investor should pay today to lock in today's gold rate, or wait for a potentially lower rate later in the month (up to the 25th).

Current Date: ${nowIST.format('YYYY-MM-DD')} (Day ${dayOfMonth} of ${currentMonthName})
Current Gold Price: ${currentPriceStr}

Recent Price History (latest first):
${JSON.stringify(priceHistory, null, 2)}

Latest Gold News Headlines:
${JSON.stringify(newsItems, null, 2)}

Task:
Determine if today is a good day to buy (i.e. we are at or near a short-term low, or prices are expected to rise significantly before the 25th) or if they should wait.
Write the 'shortReason' and 'fullAnalysis' in clear, friendly Tanglish (Tamil language written using the English/Latin alphabet, mixing Tamil and English naturally. E.g., 'Iniku gold price romba low-ah iruku, pay pannalam!' or 'Price inum kuraiyuradhuku chance iruku, so waiting list la irunga.').
Do NOT use Tamil script (characters like தமிழ்), only use English letters.

Respond ONLY with a JSON object matching this schema:
{
  "recommendation": "BUY" | "WAIT",
  "shortReason": "string (A concise notification/alert message in Tanglish, max 80 characters, summarizing the recommendation. E.g., 'Iniku rate low-ah iruku, pay pannunga!' or 'Price high-ah iruku, konjam wait pannalam.')",
  "fullAnalysis": "string (A detailed 2-3 sentence analysis in Tanglish explaining why, referencing the trend or news.)"
}`;

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
    const payload = {
        contents: [
            {
                parts: [
                    { text: prompt }
                ]
            }
        ],
        generationConfig: {
            responseMimeType: "application/json",
            responseSchema: {
                type: "OBJECT",
                properties: {
                    recommendation: { type: "STRING" },
                    shortReason: { type: "STRING" },
                    fullAnalysis: { type: "STRING" }
                },
                required: ["recommendation", "shortReason", "fullAnalysis"]
            }
        }
    };

    const response = await axios.post(url, payload, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 60000
    });

    const candidates = response.data?.candidates;
    if (!candidates || candidates.length === 0) {
        throw new Error('No response candidates returned from Gemini API.');
    }

    const textResponse = candidates[0].content?.parts[0]?.text;
    if (!textResponse) {
        throw new Error('Empty content returned from Gemini API.');
    }

    return JSON.parse(textResponse);
}

async function sendChitNotificationToAllUsers(recommendation: string, message: string) {
    const snap = await db.collection("usernames").get();
    const tokens: string[] = [];
    snap.forEach(d => { if (d.data().fcmToken) tokens.push(d.data().fcmToken); });
    if (tokens.length > 0) {
        const title = recommendation === 'BUY' ? '💰 Gold Chit: Perfect Day to Pay!' : '⏳ Gold Chit: Hold Payments';
        await admin.messaging().sendEachForMulticast({
            tokens,
            notification: { title, body: message },
            android: { notification: { channelId: "gold_price_channel" } },
            data: { type: "GOLD_CHIT_ADVICE", recommendation }
        });
    }
}

exports.generateGoldChitAdvice = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    try {
        const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
        let apiKey = "";
        if (configDoc.exists) {
            apiKey = configDoc.data()?.apiKey || "";
        }
        if (!apiKey) {
            throw new Error('Gemini API key is not configured in admin console.');
        }

        // 1. Fetch prices
        const priceSnap = await db.collection("global_gold_prices").orderBy("timestamp", "desc").limit(15).get();
        const priceHistory: any[] = [];
        priceSnap.forEach(d => {
            const val = d.data();
            priceHistory.push({
                date: val.date,
                price: val.price,
                priceChange: val.priceChange,
                source: val.source
            });
        });

        // 2. Fetch news
        const newsUrl = 'https://news.google.com/rss/search?q=gold+price+india&hl=en-IN&gl=IN&ceid=IN:en';
        let newsItems: any[] = [];
        try {
            const newsResponse = await axios.get(newsUrl, {
                headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
                timeout: 10000
            });
            const $ = cheerio.load(newsResponse.data, { xmlMode: true });
            $('item').slice(0, 8).each((i, el) => {
                newsItems.push({
                    title: $(el).find('title').text(),
                    link: $(el).find('link').text(),
                    pubDate: $(el).find('pubDate').text(),
                    source: $(el).find('source').text()
                });
            });
        } catch (newsErr) {
            console.error("Error fetching news in generateGoldChitAdvice:", newsErr);
        }

        const advice = await generateGoldChitRecommendation(apiKey, priceHistory, newsItems);
        
        const nowIST = moment().tz('Asia/Kolkata');
        const timestampStr = nowIST.toISOString();
        const docData = {
            ...advice,
            timestamp: timestampStr,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        };

        await db.collection("gold_chit_advice").doc("latest").set(docData);
        await db.collection("gold_chit_advice").doc(timestampStr.replace(/[:.]/g, '-')).set(docData);

        return docData;
    } catch (error: any) {
        console.error("generateGoldChitAdvice Error:", error.message);
        throw new functions.https.HttpsError('internal', error.message || "Failed to generate gold chit advice.");
    }
});

exports.scheduledGoldChitAdvice = functions.pubsub.schedule('1 11 * * *').timeZone('Asia/Kolkata').onRun(async () => {
    try {
        const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
        let apiKey = "";
        if (configDoc.exists) {
            apiKey = configDoc.data()?.apiKey || "";
        }
        if (!apiKey) return;

        // 1. Fetch prices
        const priceSnap = await db.collection("global_gold_prices").orderBy("timestamp", "desc").limit(15).get();
        const priceHistory: any[] = [];
        priceSnap.forEach(d => {
            const val = d.data();
            priceHistory.push({
                date: val.date,
                price: val.price,
                priceChange: val.priceChange,
                source: val.source
            });
        });

        // 2. Fetch news
        const newsUrl = 'https://news.google.com/rss/search?q=gold+price+india&hl=en-IN&gl=IN&ceid=IN:en';
        let newsItems: any[] = [];
        try {
            const newsResponse = await axios.get(newsUrl, {
                headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
                timeout: 10000
            });
            const $ = cheerio.load(newsResponse.data, { xmlMode: true });
            $('item').slice(0, 8).each((i, el) => {
                newsItems.push({
                    title: $(el).find('title').text(),
                    link: $(el).find('link').text(),
                    pubDate: $(el).find('pubDate').text(),
                    source: $(el).find('source').text()
                });
            });
        } catch (e) {}

        const advice = await generateGoldChitRecommendation(apiKey, priceHistory, newsItems);
        
        const nowIST = moment().tz('Asia/Kolkata');
        const timestampStr = nowIST.toISOString();
        const docData = {
            ...advice,
            timestamp: timestampStr,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        };

        await db.collection("gold_chit_advice").doc("latest").set(docData);
        await db.collection("gold_chit_advice").doc(timestampStr.replace(/[:.]/g, '-')).set(docData);

        // Send push notification
        await sendChitNotificationToAllUsers(advice.recommendation, advice.shortReason);
    } catch (e) {
        console.error("Error in scheduledGoldChitAdvice:", e);
    }
});

exports.adminCreateUser = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const username = (data.username || "").trim().toLowerCase();
    const password = (data.password || "").trim();

    if (!username || !password) {
        throw new functions.https.HttpsError('invalid-argument', 'Username and password are required.');
    }
    if (password.length < 6) {
        throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters.');
    }

    try {
        const usernameDoc = await db.collection('usernames').doc(username).get();
        if (usernameDoc.exists) {
            throw new functions.https.HttpsError('already-exists', 'Username is already taken.');
        }

        const email = `${username}@remindbuddy.com`;
        
        const userRecord = await admin.auth().createUser({
            email: email,
            password: password,
            displayName: username,
            emailVerified: true
        });

        const uid = userRecord.uid;

        await db.collection('usernames').doc(username).set({
            email: email,
            uid: uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        });

        await db.collection('users').doc(uid).set({
            enabledModules: ['gold', 'reminders', 'notes', 'shifts', 'checklist'],
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        });

        return { success: true, uid: uid, username: username };
    } catch (error: any) {
        console.error("Error creating user:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to create user.');
    }
});

exports.adminChangePassword = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const username = (data.username || "").trim().toLowerCase();
    const newPassword = (data.password || "").trim();

    if (!username || !newPassword) {
        throw new functions.https.HttpsError('invalid-argument', 'Username and new password are required.');
    }
    if (newPassword.length < 6) {
        throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters.');
    }

    try {
        const usernameDoc = await db.collection('usernames').doc(username).get();
        if (!usernameDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Username not found.');
        }

        const uid = usernameDoc.data()?.uid;
        if (!uid) {
            throw new functions.https.HttpsError('not-found', 'UID not found for username.');
        }

        await admin.auth().updateUser(uid, {
            password: newPassword
        });

        return { success: true, username: username };
    } catch (error: any) {
        console.error("Error updating password:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to change password.');
    }
});

exports.adminDeleteUser = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const username = (data.username || "").trim().toLowerCase();

    if (!username) {
        throw new functions.https.HttpsError('invalid-argument', 'Username is required.');
    }

    try {
        const usernameDoc = await db.collection('usernames').doc(username).get();
        if (!usernameDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Username not found.');
        }

        const uid = usernameDoc.data()?.uid;
        if (!uid) {
            throw new functions.https.HttpsError('not-found', 'UID not found for username.');
        }

        try {
            await admin.auth().deleteUser(uid);
        } catch (authErr: any) {
            console.warn("Auth user deletion warning:", authErr.message);
        }

        await db.collection('usernames').doc(username).delete();
        await db.collection('users').doc(uid).delete();

        return { success: true, username: username };
    } catch (error: any) {
        console.error("Error deleting user:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to delete user.');
    }
});

exports.adminUpdateUserModules = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const targetUid = data.userId;
    const enabledModules = data.enabledModules;
    
    if (!targetUid || !Array.isArray(enabledModules)) {
        throw new functions.https.HttpsError('invalid-argument', 'userId and enabledModules array are required.');
    }
    
    try {
        await db.collection('users').doc(targetUid).set({
            enabledModules: enabledModules
        }, { merge: true });
        
        return { success: true };
    } catch (error: any) {
        console.error("Error updating user modules:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to update modules.');
    }
});

