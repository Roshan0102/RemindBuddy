import * as functions from "firebase-functions";
import * as moment from "moment-timezone";
import { internalCheckDailyReminders } from "../modules/reminders/dailyReminders";
import { internalCheckRecurringBillNotifications } from "../modules/reminders/recurringBills";
import { internalCheckPendingGoldChitNotifications, internalPerformGoldFetch } from "../modules/gold/goldFunctions";
import { runGoldAIPredictionInternal } from "../modules/gold/goldAI";
import { internalDailyAstroNotifier } from "../modules/astro/astroNotifications";
import { internalCheckInterestedTechEventsNotifications, internalDailyTechEventsFetcher } from "../modules/events/techEvents";
import { internalCheckInterestedWalkinsNotifications, internalDailyWalkInsFetcher } from "../modules/events/walkinDrives";
import { internalDailyShiftReminder } from "../modules/shifts/shiftNotifications";
import { internalDailyUntaggedExpenseNotifier } from "../modules/finance/nightlyExpenseNotifier";
import { internalAutoJobDiscoveryAndApply } from "../modules/job_assistant/jobDiscoveryAI";
import { internalCheckAllJobReplies } from "../modules/job_assistant/replyTracker";
import { internalNetworkingDiscoveryDispatcher } from "../modules/job_assistant/networkingDiscoveryAI";

// --- CONSOLIDATED MASTER SCHEDULERS (2 Schedulers total for 100% Free GCP Tier) ---

// 1. Minute Master Runner (Replaces checkDailyReminders, checkPendingGoldChitNotifications, and handles targeted minute notifications)
export const masterMinuteRunner = functions.pubsub.schedule('* * * * *')
    .timeZone('Asia/Kolkata')
    .onRun(async () => {
        const nowKolkata = moment().tz('Asia/Kolkata');
        const hour = nowKolkata.hour();
        const minute = nowKolkata.minute();

        try {
            await internalCheckDailyReminders();
        } catch (err) {
            console.error("Error in internalCheckDailyReminders inside masterMinuteRunner:", err);
        }

        try {
            await internalCheckPendingGoldChitNotifications();
        } catch (err) {
            console.error("Error in internalCheckPendingGoldChitNotifications inside masterMinuteRunner:", err);
        }

        try {
            await internalCheckRecurringBillNotifications();
        } catch (err) {
            console.error("Error in internalCheckRecurringBillNotifications inside masterMinuteRunner:", err);
        }

        // 07:05 PM IST (19:05): Check & send interested Tech Events push notification for tomorrow (5 mins after 7 PM fetch)
        if (hour === 19 && minute === 5) {
            try {
                console.log("[masterMinuteRunner] Executing 07:05 PM task: Interested Tech Events Notifications for tomorrow...");
                await internalCheckInterestedTechEventsNotifications();
            } catch (err) {
                console.error("Error in internalCheckInterestedTechEventsNotifications inside masterMinuteRunner:", err);
            }
        }

        // 08:05 PM IST (20:05): Check & send interested Walk-in Drives push notification for tomorrow (5 mins after 8 PM fetch)
        if (hour === 20 && minute === 5) {
            try {
                console.log("[masterMinuteRunner] Executing 08:05 PM task: Interested Walk-in Drives Notifications for tomorrow...");
                await internalCheckInterestedWalkinsNotifications();
            } catch (err) {
                console.error("Error in internalCheckInterestedWalkinsNotifications inside masterMinuteRunner:", err);
            }
        }
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

            // 10:00 AM IST (Hour 10): Automated AI Job Discovery & Email Applicant Agent + Reply Check
            if (hour === 10) {
                console.log("[masterHalfHourlyRunner] Executing 10:00 AM tasks: Automated Job Discovery & Outreach...");
                try {
                    await internalAutoJobDiscoveryAndApply();
                } catch (err) {
                    console.error("Error in internalAutoJobDiscoveryAndApply inside masterHalfHourlyRunner:", err);
                }
                try {
                    await internalCheckAllJobReplies();
                } catch (err) {
                    console.error("Error in internalCheckAllJobReplies at 10:00 inside masterHalfHourlyRunner:", err);
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

            // 02:00 PM IST (Hour 14): Midday Recruiter Reply & Assessment Check
            if (hour === 14) {
                console.log("[masterHalfHourlyRunner] Executing 02:00 PM tasks: Recruiter Reply & Status Check...");
                try {
                    await internalCheckAllJobReplies();
                } catch (err) {
                    console.error("Error in internalCheckAllJobReplies at 14:00 inside masterHalfHourlyRunner:", err);
                }
            }

            // 06:00 PM IST (Hour 18): End of Business Day Recruiter Reply Check
            if (hour === 18) {
                console.log("[masterHalfHourlyRunner] Executing 06:00 PM tasks: End-of-Day Recruiter Reply Check...");
                try {
                    await internalCheckAllJobReplies();
                } catch (err) {
                    console.error("Error in internalCheckAllJobReplies at 18:00 inside masterHalfHourlyRunner:", err);
                }
            }

            // 07:00 PM IST (Hour 19): Tech Events Fetcher (Next 60 Days) & Evening Gold Fetch
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

            // 08:00 PM IST (Hour 20): Walk-Ins Fetcher (Next 60 Days)
            if (hour === 20) {
                console.log("[masterHalfHourlyRunner] Executing 08:00 PM tasks: Walk-In Drives Fetcher...");
                try {
                    await internalDailyWalkInsFetcher();
                } catch (err) {
                    console.error("Error in internalDailyWalkInsFetcher inside masterHalfHourlyRunner:", err);
                }
            }

            // 10:00 PM IST (Hour 22): Automated AI Job Discovery & Reply Check & Shift Reminders
            if (hour === 22) {
                console.log("[masterHalfHourlyRunner] Executing 10:00 PM tasks: Job Discovery & Shift Reminders...");
                try {
                    await internalAutoJobDiscoveryAndApply();
                } catch (err) {
                    console.error("Error in internalAutoJobDiscoveryAndApply inside masterHalfHourlyRunner:", err);
                }
                try {
                    await internalCheckAllJobReplies();
                } catch (err) {
                    console.error("Error in internalCheckAllJobReplies at 22:00 inside masterHalfHourlyRunner:", err);
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
            // 11:30 AM IST (Hour 11, Minute 30): Daily Cold Outreach & Leadership Networking Discovery
            if (hour === 11) {
                console.log("[masterHalfHourlyRunner] Executing 11:30 AM tasks: Cold Outreach & Leadership Discovery...");
                try {
                    await internalNetworkingDiscoveryDispatcher();
                } catch (err) {
                    console.error("Error in internalNetworkingDiscoveryDispatcher inside masterHalfHourlyRunner:", err);
                }
            }

            // 09:30 PM IST (Hour 21, Minute 30): Daily Bank Tracker & Untagged Expense Tagging Notifier
            if (hour === 21) {
                console.log("[masterHalfHourlyRunner] Executing 09:30 PM tasks: Daily Bank Tracker & Untagged Expense Notification...");
                try {
                    await internalDailyUntaggedExpenseNotifier();
                } catch (err) {
                    console.error("Error in internalDailyUntaggedExpenseNotifier inside masterHalfHourlyRunner:", err);
                }
            }
            console.log(`[masterHalfHourlyRunner] Half-hour check completed for ${timeStr} IST.`);
        }
    });
