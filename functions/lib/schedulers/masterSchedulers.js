"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.masterHalfHourlyRunner = exports.masterMinuteRunner = void 0;
const functions = require("firebase-functions");
const moment = require("moment-timezone");
const dailyReminders_1 = require("../modules/reminders/dailyReminders");
const recurringBills_1 = require("../modules/reminders/recurringBills");
const goldFunctions_1 = require("../modules/gold/goldFunctions");
const goldAI_1 = require("../modules/gold/goldAI");
const astroNotifications_1 = require("../modules/astro/astroNotifications");
const techEvents_1 = require("../modules/events/techEvents");
const walkinDrives_1 = require("../modules/events/walkinDrives");
const shiftNotifications_1 = require("../modules/shifts/shiftNotifications");
// --- CONSOLIDATED MASTER SCHEDULERS (2 Schedulers total for 100% Free GCP Tier) ---
// 1. Minute Master Runner (Replaces checkDailyReminders & checkPendingGoldChitNotifications)
exports.masterMinuteRunner = functions.pubsub.schedule('* * * * *')
    .timeZone('Asia/Kolkata')
    .onRun(async () => {
    await (0, dailyReminders_1.internalCheckDailyReminders)();
    await (0, goldFunctions_1.internalCheckPendingGoldChitNotifications)();
    await (0, recurringBills_1.internalCheckRecurringBillNotifications)();
});
// 2. Periodic Master Runner (Runs every 30 minutes at :00 and :30, supporting any hourly or half-hourly scheduled task)
exports.masterHalfHourlyRunner = functions.runWith({ timeoutSeconds: 300, memory: "1GB" })
    .pubsub.schedule('0,30 * * * *')
    .timeZone('Asia/Kolkata')
    .onRun(async () => {
    const nowKolkata = moment().tz('Asia/Kolkata');
    const hour = nowKolkata.hour();
    const minute = nowKolkata.minute();
    const timeStr = nowKolkata.format('HH:mm');
    console.log(`[masterHalfHourlyRunner] Triggered check at ${timeStr} IST`);
    // Check if running near the top of the hour (:00)
    if (minute < 15) {
        // 07:00 AM IST (Hour 7): Astro Calendar (New Moon / Full Moon) Alerts
        if (hour === 7) {
            console.log("[masterHalfHourlyRunner] Executing 07:00 AM tasks: Astro Calendar Lunar Phase Check...");
            try {
                await (0, astroNotifications_1.internalDailyAstroNotifier)();
            }
            catch (err) {
                console.error("Error in internalDailyAstroNotifier inside masterHalfHourlyRunner:", err);
            }
        }
        // 11:00 AM IST (Hour 11): Gold Fetch & Market Forecast
        if (hour === 11) {
            console.log("[masterHalfHourlyRunner] Executing 11:00 AM tasks: Gold Fetch & AI Market Forecast...");
            try {
                await (0, goldFunctions_1.internalPerformGoldFetch)();
            }
            catch (err) {
                console.error("Error in internalPerformGoldFetch inside masterHalfHourlyRunner:", err);
            }
            try {
                await (0, goldAI_1.runGoldAIPredictionInternal)();
            }
            catch (err) {
                console.error("Error in scheduledMarketForecast inside masterHalfHourlyRunner:", err);
            }
        }
        // 06:00 PM IST (Hour 18): Interested Events Notifications
        if (hour === 18) {
            console.log("[masterHalfHourlyRunner] Executing 06:00 PM tasks: Interested Events Notifications...");
            try {
                await (0, techEvents_1.internalCheckInterestedEventsNotifications)();
            }
            catch (err) {
                console.error("Error in internalCheckInterestedEventsNotifications inside masterHalfHourlyRunner:", err);
            }
        }
        // 07:00 PM IST (Hour 19): Tech Events Fetcher & Evening Gold Fetch
        if (hour === 19) {
            console.log("[masterHalfHourlyRunner] Executing 07:00 PM tasks: Tech Events Fetcher & Evening Gold Fetch...");
            try {
                await (0, goldFunctions_1.internalPerformGoldFetch)();
            }
            catch (err) {
                console.error("Error in internalPerformGoldFetch inside masterHalfHourlyRunner:", err);
            }
            try {
                await (0, techEvents_1.internalDailyTechEventsFetcher)();
            }
            catch (err) {
                console.error("Error in internalDailyTechEventsFetcher inside masterHalfHourlyRunner:", err);
            }
        }
        // 08:00 PM IST (Hour 20): Walk-Ins Fetcher
        if (hour === 20) {
            console.log("[masterHalfHourlyRunner] Executing 08:00 PM tasks: Walk-In Drives Fetcher...");
            try {
                await (0, walkinDrives_1.internalDailyWalkInsFetcher)();
            }
            catch (err) {
                console.error("Error in internalDailyWalkInsFetcher inside masterHalfHourlyRunner:", err);
            }
        }
        // 10:00 PM IST (Hour 22): Daily Shift Reminder
        if (hour === 22) {
            console.log("[masterHalfHourlyRunner] Executing 10:00 PM tasks: Daily Shift Reminders...");
            try {
                await (0, shiftNotifications_1.internalDailyShiftReminder)();
            }
            catch (err) {
                console.error("Error in internalDailyShiftReminder inside masterHalfHourlyRunner:", err);
            }
        }
    }
    // Check if running near the half hour (:30)
    if (minute >= 15 && minute < 45) {
        // Future 30-minute scheduled tasks can be placed here
        console.log(`[masterHalfHourlyRunner] Half-hour check completed for ${timeStr} IST.`);
    }
});
//# sourceMappingURL=masterSchedulers.js.map