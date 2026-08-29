"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getTodayLunarPhase = getTodayLunarPhase;
exports.internalDailyAstroNotifier = internalDailyAstroNotifier;
const moment = require("moment-timezone");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
function getTodayLunarPhase(targetMoment) {
    // Epoch: Known New Moon on Jan 6, 2000 18:14 UTC
    const epochUtcMs = Date.UTC(2000, 0, 6, 18, 14, 0);
    const synodicMs = 29.530588853 * 86400 * 1000;
    // Check target date in IST (start of day to end of day in IST)
    const startOfDayIst = targetMoment.clone().startOf('day');
    const endOfDayIst = targetMoment.clone().endOf('day');
    const diffMsStart = startOfDayIst.valueOf() - epochUtcMs;
    const diffMsEnd = endOfDayIst.valueOf() - epochUtcMs;
    const startCycle = diffMsStart / synodicMs;
    const endCycle = diffMsEnd / synodicMs;
    for (let k = Math.floor(startCycle) - 1; k <= Math.ceil(endCycle) + 1; k++) {
        const newMoonMs = epochUtcMs + k * synodicMs;
        if (newMoonMs >= startOfDayIst.valueOf() && newMoonMs <= endOfDayIst.valueOf()) {
            return "new_moon";
        }
        const fullMoonMs = epochUtcMs + (k + 0.5) * synodicMs;
        if (fullMoonMs >= startOfDayIst.valueOf() && fullMoonMs <= endOfDayIst.valueOf()) {
            return "full_moon";
        }
    }
    return null;
}
async function internalDailyAstroNotifier() {
    const nowKolkata = moment().tz('Asia/Kolkata');
    console.log(`Starting internalDailyAstroNotifier at ${nowKolkata.format()} IST`);
    const phase = getTodayLunarPhase(nowKolkata);
    if (!phase) {
        console.log("[internalDailyAstroNotifier] Today is neither New Moon nor Full Moon. Skipping notifications.");
        return;
    }
    const isNewMoon = phase === "new_moon";
    const title = isNewMoon ? "🌑 New Moon Today (Amavasai)" : "🌕 Full Moon Today (Pournami)";
    const body = `Today (${nowKolkata.format('MMM D, YYYY')}) is ${isNewMoon ? "Amavasai (New Moon)" : "Pournami (Full Moon)"}. Check auspicious timings in your Astro Calendar.`;
    console.log(`[internalDailyAstroNotifier] Phase detected: ${phase}. Preparing to notify users...`);
    try {
        const usersSnap = await firebase_1.db.collection("users").get();
        console.log(`[internalDailyAstroNotifier] Found ${usersSnap.size} total user documents.`);
        for (const userDoc of usersSnap.docs) {
            const uid = userDoc.id;
            const uData = userDoc.data();
            const enabledModules = (uData === null || uData === void 0 ? void 0 : uData.enabledModules) || [];
            const notifPrefs = (uData === null || uData === void 0 ? void 0 : uData.notificationPreferences) || {};
            if (enabledModules.includes("astro_calendar") && notifPrefs.astro_calendar !== false) {
                const usernameDoc = await firebase_1.db.collection("usernames").where("uid", "==", uid).limit(1).get();
                if (!usernameDoc.empty) {
                    const token = usernameDoc.docs[0].data().fcmToken;
                    if (token) {
                        try {
                            await firebase_1.admin.messaging().send({
                                token,
                                notification: { title, body },
                                android: {
                                    notification: {
                                        channelId: "astro_reminder_channel",
                                        tag: "astro_lunar_phase"
                                    }
                                },
                                data: { type: "astro_reminder" }
                            });
                            await (0, logger_1.logNotification)(uid, title, body, "ASTRO_CALENDAR");
                            console.log(`Sent Astro notification to user ${uid}`);
                        }
                        catch (err) {
                            console.error(`Failed to send Astro notification to user ${uid}:`, err.message || err);
                        }
                    }
                }
            }
        }
    }
    catch (e) {
        console.error("Error in internalDailyAstroNotifier:", e.message || e);
    }
}
//# sourceMappingURL=astroNotifications.js.map