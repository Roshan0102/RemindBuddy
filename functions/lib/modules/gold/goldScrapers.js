"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.fetchGoldPriceFromLiveChennai = fetchGoldPriceFromLiveChennai;
exports.fetchGoldPriceFromBankBazaar = fetchGoldPriceFromBankBazaar;
exports.notifyAllUsers = notifyAllUsers;
exports.fetchLatestGoldNews = fetchLatestGoldNews;
const axios_1 = require("axios");
const cheerio = require("cheerio");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
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
    const snap = await firebase_1.db.collection("usernames").get();
    const tokens = [];
    const targetUids = [];
    for (const d of snap.docs) {
        const udata = d.data();
        if (udata.fcmToken && udata.uid) {
            try {
                const userDoc = await firebase_1.db.collection("users").doc(udata.uid).get();
                if (userDoc.exists) {
                    const uData = userDoc.data();
                    const enabledModules = (uData === null || uData === void 0 ? void 0 : uData.enabledModules) || [];
                    const notifPrefs = (uData === null || uData === void 0 ? void 0 : uData.notificationPreferences) || {};
                    if (enabledModules.includes("gold") && notifPrefs.gold_rates !== false) {
                        tokens.push(udata.fcmToken);
                        targetUids.push(udata.uid);
                    }
                }
            }
            catch (err) {
                console.error(`Error checking notification preferences for ${udata.uid}:`, err);
            }
        }
    }
    if (tokens.length > 0) {
        const title = `Gold Rate: ₹${price}/g`;
        const body = diffText;
        const diffNumber = oldPrice ? (price - oldPrice) : 0;
        await firebase_1.admin.messaging().sendEachForMulticast({
            tokens,
            notification: { title, body },
            android: {
                priority: "high",
                notification: {
                    channelId: "gold_price_channel",
                    tag: "gold_price"
                }
            },
            data: {
                type: "GOLD_PRICE",
                rate22k: String(price),
                sovereign22k: String(price * 8),
                changeToday: String(diffNumber),
                changeText: diffText,
                timestamp: new Date().toISOString()
            }
        });
        for (const uid of targetUids) {
            await (0, logger_1.logNotification)(uid, title, body, "GOLD_PRICE");
        }
    }
}
async function fetchLatestGoldNews() {
    const queries = [
        'gold price india',
        'gold price CPI inflation Federal Reserve US economy JPMorgan'
    ];
    const newsItems = [];
    const seenTitles = new Set();
    for (const query of queries) {
        try {
            const newsUrl = `https://news.google.com/rss/search?q=${encodeURIComponent(query)}&hl=en-IN&gl=IN&ceid=IN:en`;
            const newsResponse = await axios_1.default.get(newsUrl, {
                headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
                timeout: 10000
            });
            const $ = cheerio.load(newsResponse.data, { xmlMode: true });
            $('item').slice(0, 8).each((i, el) => {
                const title = $(el).find('title').text();
                const link = $(el).find('link').text();
                const pubDate = $(el).find('pubDate').text();
                const source = $(el).find('source').text();
                const normTitle = title.toLowerCase().trim();
                if (!seenTitles.has(normTitle)) {
                    seenTitles.add(normTitle);
                    newsItems.push({ title, link, pubDate, source });
                }
            });
        }
        catch (newsErr) {
            console.error(`Error fetching news for query "${query}":`, newsErr);
        }
    }
    return newsItems.slice(0, 15);
}
//# sourceMappingURL=goldScrapers.js.map