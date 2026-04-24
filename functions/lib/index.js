"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios_1 = require("axios");
const cheerio = require("cheerio");
const moment = require("moment-timezone");
admin.initializeApp();
const db = admin.firestore();
// ----------------------------------------------------------------------------
// SCRAPERS
// ----------------------------------------------------------------------------
async function fetchGoldPriceFromLiveChennai() {
    try {
        const url = 'https://www.livechennai.com/gold_silverrate.asp';
        const response = await axios_1.default.get(url, {
            headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            },
            timeout: 10000
        });
        const $ = cheerio.load(response.data);
        let finalPrice = null;
        // Using CSS selector found via browser inspection
        $('.today-gold-rate td:nth-child(2)').each((i, el) => {
            const text = $(el).text().trim();
            // Match the first number (e.g., 14,250)
            const match = text.match(/\d{1,3}(,\d{3})+|\d{4,}/);
            if (match) {
                const num = parseInt(match[0].replace(/[^0-9]/g, ''), 10);
                if (num > 1000 && !finalPrice) {
                    finalPrice = num;
                }
            }
        });
        if (!finalPrice)
            throw new Error("Price element not found in LiveChennai");
        return finalPrice;
    }
    catch (e) {
        console.error("LiveChennai Error:", e);
        return null;
    }
}
async function fetchGoldPriceFromTOI() {
    try {
        const url = 'https://timesofindia.indiatimes.com/business/gold-rates-today/gold-price-in-chennai';
        const response = await axios_1.default.get(url, {
            headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Accept': 'text/html,application/xhtml+xml',
            },
            timeout: 10000
        });
        const $ = cheerio.load(response.data);
        let finalPrice = null;
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
                    const firstRow = rows.first();
                    const cells = firstRow.find('.Gy41U');
                    if (cells.length > 1) {
                        const weight = $(cells[0]).text().trim();
                        const priceText = $(cells[1]).text().trim();
                        if (weight.includes('1')) {
                            // Split by decimal point to avoid including cents/paise as extra digits
                            const basePrice = priceText.split('.')[0];
                            const num = parseInt(basePrice.replace(/[^0-9]/g, ''), 10);
                            if (num > 1000)
                                finalPrice = num;
                        }
                    }
                }
            }
        });
        if (!finalPrice)
            throw new Error("Price element not found in TOI");
        return finalPrice;
    }
    catch (e) {
        console.error("TOI Error:", e);
        return null;
    }
}
async function fetchGoldPriceFromBankBazaar() {
    try {
        const url = 'https://www.bankbazaar.com/gold-rate-chennai.html';
        const response = await axios_1.default.get(url, {
            headers: {
                'User-Agent': 'Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36',
            },
            timeout: 10000
        });
        const $ = cheerio.load(response.data);
        let finalPrice = null;
        $('.white-space-nowrap').each((i, el) => {
            const text = $(el).text().trim();
            if ((text.includes('₹') || text.includes('Rs')) && text.match(/\d{1,3}(,\d{3})+|\d{4,}/)) {
                const num = parseInt(text.replace(/[^0-9]/g, ''), 10);
                if (num > 1000 && !finalPrice) {
                    finalPrice = num;
                }
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
// NOTIFICATION SENDER
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
    try {
        // Find everyone with an fcmToken in the 'usernames' collection
        const usernamesSnapshot = await db.collection("usernames").get();
        const tokens = [];
        usernamesSnapshot.forEach(doc => {
            const data = doc.data();
            if (data.fcmToken)
                tokens.push(data.fcmToken);
        });
        if (tokens.length > 0) {
            // Modern FCM HTTP v1 Multicast Payload
            const response = await admin.messaging().sendEachForMulticast({
                tokens: tokens,
                notification: {
                    title: `Gold Price Update (₹${price})`,
                    body: `Current: ₹${price} | ${diffText}`,
                },
                data: {
                    type: "GOLD_PRICE",
                    click_action: "GOLD_SCREEN",
                    price: String(price)
                },
                android: {
                    priority: "high",
                    notification: {
                        channelId: "gold_price_channel",
                        clickAction: "FLUTTER_NOTIFICATION_CLICK",
                        sound: "default",
                        ticker: "Gold Rate Update",
                        visibility: "public"
                    }
                }
            });
            console.log(`✅ Sent logically to ${tokens.length} users. Success: ${response.successCount}, Failure: ${response.failureCount}`);
        }
        else {
            console.log(`⚠️ No users with FCM tokens found.`);
        }
    }
    catch (e) {
        console.error(`❌ Failed to send notifications:`, e);
    }
}
// ----------------------------------------------------------------------------
// DIAGNOSTICS & MANUAL TRIGGERS
// ----------------------------------------------------------------------------
exports.checkGoldSources = functions.https.onCall(async (data, context) => {
    console.log("🔍 Manual Source Check Triggered...");
    const results = await Promise.all([
        fetchGoldPriceFromLiveChennai(),
        fetchGoldPriceFromBankBazaar(),
        fetchGoldPriceFromTOI()
    ]);
    return {
        timestamp: moment().tz('Asia/Kolkata').format('hh:mm:ss A'),
        live_chennai: results[0] || "Failed",
        bank_bazaar: results[1] || "Failed",
        times_of_india: results[2] || "Failed"
    };
});
// ----------------------------------------------------------------------------
// INTERNALS
// ----------------------------------------------------------------------------
async function internalPerformGoldFetch(force = false) {
    console.log("-----------------------------------------");
    console.log(`⏰ Gold Fetch Triggered (Force: ${force})`);
    let currentPrice = null;
    let sourceName = "";
    const lcPrice = await fetchGoldPriceFromLiveChennai();
    if (lcPrice) {
        currentPrice = lcPrice;
        sourceName = "LiveChennai";
    }
    else {
        const bbPrice = await fetchGoldPriceFromBankBazaar();
        if (bbPrice) {
            currentPrice = bbPrice;
            sourceName = "BankBazaar";
        }
        else {
            const toiPrice = await fetchGoldPriceFromTOI();
            if (toiPrice) {
                currentPrice = toiPrice;
                sourceName = "Times of India";
            }
        }
    }
    if (!currentPrice) {
        await db.collection("gold_fetch_logs").doc("latest").set({
            timestamp: new Date().toISOString(),
            status: "FAILED",
            logs: [`LiveChennai: ❌`, `BankBazaar: ❌`, `TOI: ❌`]
        });
        return { success: false, error: "Scraping failed" };
    }
    const nowIST = moment().tz('Asia/Kolkata');
    const hour = nowIST.hour();
    const todayDateStr = nowIST.format('YYYY-MM-DD');
    const timestampStr = nowIST.toISOString();
    const lastDocs = await db.collection("global_gold_prices").orderBy("timestamp", "desc").limit(1).get();
    let lastPrice = null;
    if (!lastDocs.empty)
        lastPrice = lastDocs.docs[0].data().price;
    if (!force && hour === 19 && lastPrice !== null && lastPrice === currentPrice) {
        return { success: true, status: "skipped" };
    }
    const priceChange = lastPrice ? (currentPrice - lastPrice) : 0;
    const docId = timestampStr.replace(/[:.]/g, '-');
    await db.collection("global_gold_prices").doc(docId).set({
        date: todayDateStr,
        price: currentPrice,
        priceChange: priceChange,
        fetchedTime: nowIST.format('hh:mm A'),
        timestamp: timestampStr,
        source: sourceName
    });
    await db.collection("gold_fetch_logs").doc("latest").set({
        timestamp: timestampStr,
        status: "SUCCESS",
        sourceUsed: sourceName,
        price: currentPrice,
        lastPrice: lastPrice,
        logs: [
            `LiveChennai: ${lcPrice ? "✅ " + lcPrice : "❌"}`,
            `BankBazaar: ${sourceName !== "LiveChennai" ? "Attempted" : "Skipped"}`,
            `TOI: ${sourceName === "Times of India" ? "Attempted" : "Skipped"}`
        ]
    });
    await notifyAllUsers(currentPrice, lastPrice);
    return { success: true, price: currentPrice, source: sourceName };
}
exports.scheduledGoldFetch = functions.pubsub.schedule('0 11,19 * * *')
    .timeZone('Asia/Kolkata')
    .onRun(async (context) => {
    return await internalPerformGoldFetch();
});
exports.forceGoldFetch = functions.https.onCall(async (data, context) => {
    console.log("🚀 Forced Gold Fetch via App...");
    return await internalPerformGoldFetch(true);
});
// ----------------------------------------------------------------------------
// DAILY SHIFT REMINDER - Runs at 10:00 PM IST (22:00)
// ----------------------------------------------------------------------------
exports.dailyShiftReminder = functions.pubsub.schedule('0 22 * * *')
    .timeZone('Asia/Kolkata')
    .onRun(async (context) => {
    console.log("-----------------------------------------");
    console.log("⏰ Daily Shift Reminder Triggered (10 PM IST)");
    // 1. Calculate Tomorrow's Date and Month
    const nowIST = moment().tz('Asia/Kolkata');
    const tomorrow = nowIST.clone().add(1, 'day');
    const tomorrowDate = tomorrow.format('YYYY-MM-DD');
    const tomorrowMonth = tomorrow.format('YYYY-MM');
    console.log(`   📅 Checking shifts for: ${tomorrowDate}`);
    // 2. Fetch all users with FCM tokens
    const usersSnap = await db.collection('usernames').get();
    if (usersSnap.empty) {
        console.log("   ⚠️ No users found in database.");
        return null;
    }
    console.log(`   👥 Found ${usersSnap.size} users to check.`);
    const notificationPromises = [];
    for (const userDoc of usersSnap.docs) {
        const userData = userDoc.data();
        const uid = userData.uid;
        const fcmToken = userData.fcmToken;
        if (!uid || !fcmToken)
            continue;
        // 3. Check for tomorrow's shift in the new nested structure
        const shiftRef = db.collection('users').doc(uid)
            .collection('shifts').doc(tomorrowMonth)
            .collection('daily_shifts').doc(tomorrowDate);
        const shiftDoc = await shiftRef.get();
        if (shiftDoc.exists) {
            const shift = shiftDoc.data();
            const shiftType = (shift === null || shift === void 0 ? void 0 : shift.shift_type) || "Unknown";
            // Format shift type for display (e.g., morning -> Morning Shift)
            let shiftDisplay = shiftType.split('_').map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join(' ');
            if (!shiftDisplay.toLowerCase().includes('shift') && !shiftDisplay.toLowerCase().includes('off')) {
                shiftDisplay += " Shift";
            }
            console.log(`   🔔 Notifying ${userData.lower} (UID: ${uid}) about ${shiftDisplay}`);
            const message = {
                token: fcmToken,
                notification: {
                    title: "📅 Tomorrow's Shift",
                    body: `👋 Tomorrow's Shift: ${shiftDisplay}`
                },
                android: {
                    priority: 'high',
                    notification: {
                        channelId: 'shift_reminder_channel',
                        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
                    }
                },
                data: {
                    type: 'shift_reminder',
                    date: tomorrowDate,
                    shift: shiftDisplay
                }
            };
            notificationPromises.push(admin.messaging().send(message)
                .catch(err => console.error(`   ❌ Failed to notify ${uid}:`, err)));
        }
    }
    if (notificationPromises.length > 0) {
        await Promise.all(notificationPromises);
        console.log(`   ✅ Sent ${notificationPromises.length} notifications.`);
    }
    else {
        console.log("   ℹ️ No shifts found for tomorrow for any user.");
    }
    console.log("-----------------------------------------");
    return null;
});
// ----------------------------------------------------------------------------
// DAILY REMINDERS CHECK - Runs every 15 minutes
// ----------------------------------------------------------------------------
exports.checkDailyReminders = functions.pubsub.schedule('*/15 * * * *')
    .timeZone('Asia/Kolkata')
    .onRun(async (context) => {
    const nowIST = moment().tz('Asia/Kolkata');
    const currentTime = nowIST.format('HH:mm'); // Matches "18:00" format in DB
    console.log(`⏰ Checking daily reminders for: ${currentTime} IST`);
    // 1. Fetch all users
    const usersSnap = await db.collection('usernames').get();
    if (usersSnap.empty)
        return null;
    const notificationPromises = [];
    for (const userDoc of usersSnap.docs) {
        const userData = userDoc.data();
        const uid = userData.uid;
        const fcmToken = userData.fcmToken;
        if (!uid || !fcmToken)
            continue;
        // 2. Fetch specific reminders for this user at this exact time
        const remindersRef = db.collection('users').doc(uid).collection('daily_reminders');
        const matchingReminders = await remindersRef
            .where('time', '==', currentTime)
            .where('isActive', '==', true)
            .get();
        matchingReminders.forEach(reminderDoc => {
            const reminder = reminderDoc.data();
            console.log(`   🔔 Notifying ${userData.lower} about: ${reminder.title}`);
            const message = {
                token: fcmToken,
                notification: {
                    title: reminder.title,
                    body: reminder.description || "You have a daily reminder!",
                },
                android: {
                    priority: 'high',
                    notification: {
                        channelId: 'remindbuddy_channel',
                        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
                    }
                },
                data: {
                    type: 'daily_reminder',
                    reminderId: reminderDoc.id,
                    isAnnoying: String(reminder.isAnnoying || false)
                }
            };
            notificationPromises.push(admin.messaging().send(message)
                .catch(err => console.error(`   ❌ Failed to notify uid ${uid}:`, err)));
        });
    }
    if (notificationPromises.length > 0) {
        await Promise.all(notificationPromises);
        console.log(`   ✅ Sent ${notificationPromises.length} daily reminder notifications.`);
    }
    return null;
});
//# sourceMappingURL=index.js.map