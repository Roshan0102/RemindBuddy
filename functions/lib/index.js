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
                            const num = parseInt(priceText.replace(/[^0-9]/g, ''), 10);
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
    const payload = {
        notification: {
            title: `Gold Price Update (₹${price})`,
            body: `Current: ₹${price} | ${diffText}`,
        },
        data: {
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            type: "GOLD_PRICE"
        }
    };
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
            await admin.messaging().sendToDevice(tokens, payload);
            console.log(`✅ Sent notification to ${tokens.length} users.`);
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
// CRON JOB
// ----------------------------------------------------------------------------
exports.scheduledGoldFetch = functions.pubsub.schedule('0 * * * *')
    .timeZone('Asia/Kolkata')
    .onRun(async (context) => {
    var _a, _b;
    console.log("-----------------------------------------");
    console.log("⏰ Hourly Gold Fetch Triggered");
    // 1. Fetch Price
    let currentPrice = await fetchGoldPriceFromTOI();
    console.log(`   > TOI Price: ${currentPrice}`);
    if (!currentPrice) {
        console.log(`   > Priority fetch failed. Falling back to BankBazaar...`);
        currentPrice = await fetchGoldPriceFromBankBazaar();
        console.log(`   > BankBazaar Price: ${currentPrice}`);
    }
    if (!currentPrice) {
        console.error("   ❌ Failed to fetch gold price from both sources.");
        return null;
    }
    // 2. Determine Time in IST
    const nowIST = moment().tz('Asia/Kolkata');
    const hour = nowIST.hour();
    const todayDateStr = nowIST.format('YYYY-MM-DD');
    // 3. Keep a track of the last global price for difference calculation
    const globalRef = db.collection("global_gold_prices").doc(todayDateStr);
    const latestDoc = await globalRef.get();
    let oldPriceStr = null;
    if (latestDoc.exists) {
        oldPriceStr = (_a = latestDoc.data()) === null || _a === void 0 ? void 0 : _a.price;
    }
    else {
        // Check yesterday if today is empty
        const yesterdayDateStr = nowIST.clone().subtract(1, 'days').format('YYYY-MM-DD');
        const yesterdayDoc = await db.collection("global_gold_prices").doc(yesterdayDateStr).get();
        if (yesterdayDoc.exists)
            oldPriceStr = (_b = yesterdayDoc.data()) === null || _b === void 0 ? void 0 : _b.price;
    }
    // 4. Update the DB only twice a day (11 AM and 7 PM / 19:00)
    // FOR TESTING: Bypassing the specific hour check!
    if (true || hour === 11 || hour === 19) {
        console.log(`   💾 Scheduled Saving Time (${hour}:00 IST). Writing to DB...`);
        const priceChange = oldPriceStr ? (currentPrice - oldPriceStr) : 0;
        await globalRef.set({
            date: todayDateStr,
            price: currentPrice,
            priceChange: priceChange,
            fetchedTime: nowIST.format('hh:mm A'),
            timestamp: nowIST.toISOString(),
            source: "Cloud Function"
        }, { merge: true }); // Merge true so 7 PM overwrites 11 AM peacefully without deleting other data
    }
    else {
        console.log(`   ⏩ Not 11 AM or 7 PM (Current: ${hour}:00). Skipping DB write.`);
    }
    // 5. Always Send Push Notification
    console.log(`   📤 Sending Push Notification...`);
    await notifyAllUsers(currentPrice, oldPriceStr);
    console.log("✅ Execution Complete");
    return null;
});
//# sourceMappingURL=index.js.map