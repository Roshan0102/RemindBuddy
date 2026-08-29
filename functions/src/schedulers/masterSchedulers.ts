import * as functions from "firebase-functions";
import * as moment from "moment-timezone";
import { internalCheckDailyReminders } from "../modules/reminders/dailyReminders";
import { internalCheckRecurringBillNotifications } from "../modules/reminders/recurringBills";
import { internalCheckPendingGoldChitNotifications, internalPerformGoldFetch } from "../modules/gold/goldFunctions";
import { runGoldAIPredictionInternal } from "../modules/gold/goldAI";
import { internalDailyAstroNotifier } from "../modules/astro/astroNotifications";
import { internalCheckInterestedEventsNotifications, internalDailyTechEventsFetcher } from "../modules/events/techEvents";
import { internalDailyWalkInsFetcher } from "../modules/events/walkinDrives";
import { internalDailyShiftReminder } from "../modules/shifts/shiftNotifications";
import { internalAutoJobDiscoveryAndApply } from "../modules/job_assistant/jobDiscoveryAI";

// --- CONSOLIDATED MASTER SCHEDULERS (2 Schedulers total for 100% Free GCP Tier) ---

// 1. Minute Master Runner (Replaces checkDailyReminders & checkPendingGoldChitNotifications)
export const masterMinuteRunner = functions.pubsub.schedule('* * * * *')
    .timeZone('Asia/Kolkata')
    .onRun(async () => {
        await internalCheckDailyReminders();
        await internalCheckPendingGoldChitNotifications();
        await internalCheckRecurringBillNotifications();
    });

// 2. Periodic Master Runner (Runs every 30 minutes at :00 and :30, supporting any hourly or half-hourly scheduled task)
export const masterHalfHourlyRunner = functions.runWith({ timeoutSeconds: 300, memory: "1GB" })
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
                    await internalDailyAstroNotifier();
                } catch (err) {
                    console.error("Error in internalDailyAstroNotifier inside masterHalfHourlyRunner:", err);
                }
            }

            // 10:00 AM IST (Hour 10): Automated AI Job Discovery & Email Applicant Agent (Morning Run)
            if (hour === 10) {
                console.log("[masterHalfHourlyRunner] Executing 10:00 AM tasks: Automated Job Discovery & Outreach...");
                try {
                    await internalAutoJobDiscoveryAndApply();
                } catch (err) {
                    console.error("Error in internalAutoJobDiscoveryAndApply inside masterHalfHourlyRunner:", err);
                }
            }

            // 11:00 AM IST (Hour 11): Gold Fetch & Market Forecast
            if (hour === 11) {
                console.log("[masterHalfHourlyRunner] Executing 11:00 AM tasks: Gold Fetch & AI Market Forecast...");
                try {
                    await internalPerformGoldFetch();
                } catch (err) {
                    console.error("Error in internalPerformGoldFetch inside masterHalfHourlyRunner:", err);
                }
                try {
                    await runGoldAIPredictionInternal();
                } catch (err) {
                    console.error("Error in scheduledMarketForecast inside masterHalfHourlyRunner:", err);
                }
            }

            // 06:00 PM IST (Hour 18): Interested Events Notifications
            if (hour === 18) {
                console.log("[masterHalfHourlyRunner] Executing 06:00 PM tasks: Interested Events Notifications...");
                try {
                    await internalCheckInterestedEventsNotifications();
                } catch (err) {
                    console.error("Error in internalCheckInterestedEventsNotifications inside masterHalfHourlyRunner:", err);
                }
            }

            // 07:00 PM IST (Hour 19): Tech Events Fetcher & Evening Gold Fetch
            if (hour === 19) {
                console.log("[masterHalfHourlyRunner] Executing 07:00 PM tasks: Tech Events Fetcher & Evening Gold Fetch...");
                try {
                    await internalPerformGoldFetch();
                } catch (err) {
                    console.error("Error in internalPerformGoldFetch inside masterHalfHourlyRunner:", err);
                }
                try {
                    await internalDailyTechEventsFetcher();
                } catch (err) {
                    console.error("Error in internalDailyTechEventsFetcher inside masterHalfHourlyRunner:", err);
                }
            }

            // 08:00 PM IST (Hour 20): Walk-Ins Fetcher
            if (hour === 20) {
                console.log("[masterHalfHourlyRunner] Executing 08:00 PM tasks: Walk-In Drives Fetcher...");
                try {
                    await internalDailyWalkInsFetcher();
                } catch (err) {
                    console.error("Error in internalDailyWalkInsFetcher inside masterHalfHourlyRunner:", err);
                }
            }

            // 10:00 PM IST (Hour 22): Automated AI Job Discovery & Email Applicant Agent (Night Run) & Daily Shift Reminders
            if (hour === 22) {
                console.log("[masterHalfHourlyRunner] Executing 10:00 PM tasks: Automated Job Discovery & Daily Shift Reminders...");
                try {
                    await internalAutoJobDiscoveryAndApply();
                } catch (err) {
                    console.error("Error in internalAutoJobDiscoveryAndApply inside masterHalfHourlyRunner:", err);
                }
                try {
                    await internalDailyShiftReminder();
                } catch (err) {
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
