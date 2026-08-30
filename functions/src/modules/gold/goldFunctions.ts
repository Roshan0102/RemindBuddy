import * as functions from "firebase-functions";
import * as moment from "moment-timezone";
import { admin, db } from "../../config/firebase";
import { logNotification } from "../../utils/logger";
import { fetchGoldPriceFromLiveChennai, fetchGoldPriceFromBankBazaar, fetchLatestGoldNews, notifyAllUsers } from "./goldScrapers";
import { generateGoldChitRecommendation, runGoldAIPredictionInternal } from "./goldAI";

export async function internalPerformGoldFetch(force: boolean = false) {
    const results = [await fetchGoldPriceFromLiveChennai(), await fetchGoldPriceFromBankBazaar()];
    const currentPrice = results[0] || results[1];
    if (!currentPrice) return { success: false, error: "No price retrieved from scrapers." };

    const nowIST = moment().tz('Asia/Kolkata');
    const todayStr = nowIST.format('YYYY-MM-DD');
    const currentHour = nowIST.hour();
    const slotKey = currentHour === 11 ? '11am' : (currentHour === 19 ? '07pm' : `${currentHour}h`);

    // Fetch existing gold price records for today to check deduplication & scheduling rules
    const todayPricesSnap = await db.collection("global_gold_prices")
        .where("date", "==", todayStr)
        .get();

    // Check scheduling rules unless force is true
    if (!force) {
        // Rule 1: Strict deduplication for 11:00 AM runs (Hour 11) - max ONCE per day
        if (currentHour === 11) {
            let alreadyProcessedAt11 = false;
            todayPricesSnap.forEach(doc => {
                const data = doc.data();
                if (data.slot === '11am') {
                    alreadyProcessedAt11 = true;
                } else if (data.timestamp) {
                    const docHour = moment(data.timestamp).tz('Asia/Kolkata').hour();
                    if (docHour === 11) {
                        alreadyProcessedAt11 = true;
                    }
                }
            });

            if (alreadyProcessedAt11) {
                console.log(`[GoldFetch] 11:00 AM gold price already recorded for today (${todayStr}). Skipping duplicate run.`);
                return { success: true, status: 'already_executed', price: currentPrice };
            }
        } 
        // Rule 2: Strict deduplication for 7:00 PM runs (Hour 19) - max ONCE per day
        else if (currentHour === 19) {
            let alreadyProcessedAt19 = false;
            let priceAt11: number | null = null;

            todayPricesSnap.forEach(doc => {
                const data = doc.data();
                if (data.timestamp) {
                    const docHour = moment(data.timestamp).tz('Asia/Kolkata').hour();
                    if (docHour === 19) {
                        alreadyProcessedAt19 = true;
                    }
                    if (docHour === 11 && priceAt11 === null) {
                        priceAt11 = data.price;
                    }
                }
                if (data.slot === '11am' && priceAt11 === null) {
                    priceAt11 = data.price;
                }
            });

            if (alreadyProcessedAt19) {
                console.log(`[GoldFetch] 7:00 PM gold price already processed for today (${todayStr}). Skipping duplicate run.`);
                return { success: true, status: 'already_executed', price: currentPrice };
            }

            // Fallback: use first price of today if 11:00 AM price was not found
            if (priceAt11 === null && !todayPricesSnap.empty) {
                priceAt11 = todayPricesSnap.docs[0].data().price;
            }

            if (priceAt11 !== null && currentPrice === priceAt11) {
                console.log(`[GoldFetch] 7:00 PM price (${currentPrice}) is same as 11:00 AM price (${priceAt11}). Skipping insert and notifications.`);
                return { success: true, status: 'no_change', price: currentPrice };
            }
        } 
        // Rule 3: Any other hour safeguard to prevent rapid duplicates (within 15 minutes)
        else {
            const lastDocs = await db.collection("global_gold_prices").orderBy("timestamp", "desc").limit(1).get();
            if (!lastDocs.empty) {
                const lastDocData = lastDocs.docs[0].data();
                if (lastDocData.timestamp) {
                    const lastTime = moment(lastDocData.timestamp);
                    if (nowIST.diff(lastTime, 'minutes') < 15) {
                        console.log(`[GoldFetch] Unscheduled run within 15 minutes of last update. Skipping.`);
                        return { success: true, status: 'too_recent', price: currentPrice };
                    }
                }
            }
        }
    }

    // Get recent price overall to compute priceChange
    const lastDocsOverall = await db.collection("global_gold_prices").orderBy("timestamp", "desc").limit(1).get();
    const lastPrice = lastDocsOverall.empty ? null : lastDocsOverall.docs[0].data().price;

    const timestampStr = nowIST.toISOString();
    await db.collection("global_gold_prices").doc(timestampStr.replace(/[:.]/g, '-')).set({
        date: todayStr,
        slot: slotKey,
        price: currentPrice,
        priceChange: lastPrice ? currentPrice - lastPrice : 0,
        timestamp: timestampStr,
        source: results[0] ? "LiveChennai" : "BankBazaar"
    });
    await notifyAllUsers(currentPrice, lastPrice);

    return { success: true, status: 'changed', price: currentPrice };
}

export const checkGoldSources = functions.https.onCall(async () => {
    const r = [await fetchGoldPriceFromLiveChennai(), await fetchGoldPriceFromBankBazaar()];
    return { timestamp: moment().tz('Asia/Kolkata').format('hh:mm:ss A'), live_chennai: r[0], bank_bazaar: r[1] };
});

export const forceGoldFetch = functions.https.onCall(() => internalPerformGoldFetch(true));

export const onGoldPriceCreated = functions.runWith({ timeoutSeconds: 300, memory: "512MB" }).firestore
    .document('global_gold_prices/{docId}')
    .onCreate(async (snap, context) => {
        console.log(`onGoldPriceCreated: Waiting 1 minute before running analysis for doc ${context.params.docId}...`);
        await new Promise(resolve => setTimeout(resolve, 60000));

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
            const newsItems = await fetchLatestGoldNews();

            // -- PART A: GOLD CHIT ASSISTANT --
            try {
                const advice = await generateGoldChitRecommendation(priceHistory, newsItems);
                
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
            } catch (chitErr) {
                console.error("Error in onGoldPriceCreated chit advice generation:", chitErr);
            }

            // -- PART B: MARKET FORECAST (AI INSIGHTS) --
            try {
                await runGoldAIPredictionInternal();
                console.log("onGoldPriceCreated: Gold AI Insights generated successfully.");
            } catch (forecastErr: any) {
                console.error("Error in onGoldPriceCreated market forecast generation:", forecastErr);
            }

        } catch (e) {
            console.error("Error in onGoldPriceCreated:", e);
        }
    });

export async function hasPaidAllChitsForCurrentMonth(uid: string): Promise<boolean> {
    try {
        const nowIST = moment().tz('Asia/Kolkata');
        const currentMonthKey = nowIST.format('YYYY-MM'); // e.g. "2026-07"

        // Find plans owned by user
        const ownedPlans = await db.collection("gold_chits")
            .where("ownerId", "==", uid)
            .get();

        // Find plans shared with user
        const sharedPlans = await db.collection("gold_chits")
            .where("sharedWith", "array-contains", uid)
            .get();

        const allPlans = [...ownedPlans.docs, ...sharedPlans.docs].filter(planDoc => {
            const data = planDoc.data();
            if (data.status === "completed" || data.status === "inactive") {
                return false;
            }

            // Check if current month is within the plan's duration
            const startMonth = data.startMonth; // e.g. "2026-01"
            const endMonth = data.endMonth;     // e.g. "2026-12"

            if (startMonth && currentMonthKey < startMonth) {
                return false; // Plan hasn't started yet
            }
            if (endMonth && currentMonthKey > endMonth) {
                return false; // Plan has already ended
            }

            return true;
        });

        if (allPlans.length === 0) {
            return false;
        }

        // Check each plan's current month installment
        for (const planDoc of allPlans) {
            const installmentDoc = await planDoc.ref
                .collection("installments")
                .doc(currentMonthKey)
                .get();

            if (!installmentDoc.exists || installmentDoc.data()?.status !== "paid") {
                return false;
            }
        }

        return true;
    } catch (err) {
        console.error(`Error in hasPaidAllChitsForCurrentMonth for user ${uid}:`, err);
        return false;
    }
}

export async function sendChitNotificationToAllUsers(recommendation: string, message: string) {
    const snap = await db.collection("usernames").get();
    const tokens: string[] = [];
    const targetUids: string[] = [];
    for (const d of snap.docs) {
        const udata = d.data();
        if (udata.fcmToken && udata.uid) {
            try {
                const userDoc = await db.collection("users").doc(udata.uid).get();
                if (userDoc.exists) {
                    const uData = userDoc.data();
                    const enabledModules = uData?.enabledModules || [];
                    const notifPrefs = uData?.notificationPreferences || {};
                    if (enabledModules.includes("gold") && notifPrefs.gold_advice !== false) {
                        const hasPaid = await hasPaidAllChitsForCurrentMonth(udata.uid);
                        if (hasPaid) {
                            console.log(`[GoldChitAdvice] Skipping notification for user ${udata.uid} as they have paid all chits for this month.`);
                            continue;
                        }
                        tokens.push(udata.fcmToken);
                        targetUids.push(udata.uid);
                    }
                }
            } catch (err) {
                console.error(`Error checking notification preferences for ${udata.uid}:`, err);
            }
        }
    }
    if (tokens.length > 0) {
        const title = recommendation === 'BUY' ? '💰 Gold Chit: Perfect Day to Pay!' : '⏳ Gold Chit: Hold Payments';
        await admin.messaging().sendEachForMulticast({
            tokens,
            notification: { title, body: message },
            android: { 
                notification: { 
                    channelId: "gold_price_channel",
                    tag: "gold_chit"
                } 
            },
            data: { type: "GOLD_CHIT_ADVICE", recommendation }
        });
        for (const uid of targetUids) {
            await logNotification(uid, title, message, "GOLD_CHIT_ADVICE");
        }
    }
}

export const onInstallmentUpdated = functions.firestore
    .document('gold_chits/{planId}/installments/{monthKey}')
    .onUpdate(async (change, context) => {
        const before = change.before.data();
        const after = change.after.data();

        if (after.status === 'paid' && before.status !== 'paid') {
            const planId = context.params.planId;
            const monthKey = context.params.monthKey;
            
            // Calculate target send time: 10 minutes from now
            const sendAt = moment().tz('Asia/Kolkata').add(10, 'minutes').toDate();
            
            // Save to pending_gold_chit_notifications collection
            await db.collection('pending_gold_chit_notifications').add({
                planId,
                monthKey,
                updatedBy: after.updatedBy || '',
                sendAt: admin.firestore.Timestamp.fromDate(sendAt),
                status: 'pending',
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            });
            console.log(`Scheduled delayed notification for plan ${planId}, month ${monthKey} at ${sendAt.toISOString()}`);
        } else if (after.status !== 'paid' && before.status === 'paid') {
            const planId = context.params.planId;
            const monthKey = context.params.monthKey;
            
            const pendingSnap = await db.collection('pending_gold_chit_notifications')
                .where('planId', '==', planId)
                .where('monthKey', '==', monthKey)
                .where('status', '==', 'pending')
                .get();
                
            const batch = db.batch();
            pendingSnap.docs.forEach(doc => batch.delete(doc.ref));
            await batch.commit();
            console.log(`Cancelled/deleted pending notifications for plan ${planId}, month ${monthKey} because status is no longer paid.`);
        }
    });

export async function internalCheckPendingGoldChitNotifications() {
    const now = admin.firestore.Timestamp.now();
    const pendingSnap = await db.collection('pending_gold_chit_notifications')
        .where('status', '==', 'pending')
        .where('sendAt', '<=', now)
        .get();

    if (pendingSnap.empty) {
        return;
    }

    for (const doc of pendingSnap.docs) {
        const data = doc.data();
        const { planId, monthKey, updatedBy } = data;

        try {
            // Get plan details
            const planDoc = await db.collection('gold_chits').doc(planId).get();
            if (!planDoc.exists) {
                await doc.ref.update({ status: 'failed', error: 'Plan document not found' });
                continue;
            }

            const planData = planDoc.data()!;
            const planName = planData.name || 'Gold Chit Plan';
            const ownerId = planData.ownerId;
            const sharedWith = planData.sharedWith || [];

            // Collect all UIDs to notify (owner + shared users)
            const uids = new Set<string>();
            if (ownerId) uids.add(ownerId);
            for (const uid of sharedWith) {
                uids.add(uid);
            }

            // Remove updater so they don't notify themselves
            if (updatedBy) {
                uids.delete(updatedBy);
            }

            if (uids.size === 0) {
                await doc.ref.update({ status: 'sent', info: 'No other users to notify' });
                continue;
            }

            // Format month name (e.g. "2026-07" -> "July 2026")
            let formattedMonth = monthKey;
            try {
                const dateVal = moment(`${monthKey}-01`, 'YYYY-MM-DD');
                if (dateVal.isValid()) {
                    formattedMonth = dateVal.format('MMMM YYYY');
                }
            } catch (_) {}

            const uidsList = Array.from(uids);
            const usernamesSnap = await db.collection('usernames').where('uid', 'in', uidsList).get();
            
            const tokens: string[] = [];
            const targetUids: string[] = [];

            for (const uDoc of usernamesSnap.docs) {
                const uData = uDoc.data();
                if (uData.fcmToken && uData.uid) {
                    tokens.push(uData.fcmToken);
                    targetUids.push(uData.uid);
                }
            }

            if (tokens.length > 0) {
                // Calculate total accumulated grams across paid installments for this plan
                let totalGrams = 0;
                try {
                    const instSnap = await db.collection('gold_chits').doc(planId).collection('installments').get();
                    instSnap.docs.forEach(iDoc => {
                        const iData = iDoc.data();
                        if (iData.status === 'paid') {
                            const grams = parseFloat(iData.gramsAccumulated || iData.goldGrams || '0') || 0;
                            totalGrams += grams;
                        }
                    });
                } catch (gErr) {
                    console.error(`Error calculating total grams for plan ${planId}:`, gErr);
                }

                const gramsFormatted = totalGrams > 0 ? `${totalGrams.toFixed(3)} grams` : '0 grams';

                const title = `💰 Gold Chit Payment Confirmed`;
                const body = `You have paid the ${formattedMonth} gold installment. Currently, you have ${gramsFormatted} of gold in plan "${planName}".`;

                await admin.messaging().sendEachForMulticast({
                    tokens,
                    notification: { title, body },
                    android: {
                        notification: {
                            channelId: 'gold_price_channel',
                            tag: `gold_chit_update_${planId}_${monthKey}`
                        }
                    },
                    data: {
                        type: 'GOLD_CHIT_UPDATE',
                        planId,
                        monthKey
                    }
                });

                for (const targetUid of targetUids) {
                    await logNotification(targetUid, title, body, 'GOLD_CHIT_UPDATE');
                }
            }

            await doc.ref.update({ status: 'sent', notifiedUids: targetUids });
        } catch (err: any) {
            console.error(`Error sending delayed notification for pending doc ${doc.id}:`, err);
            await doc.ref.update({ status: 'failed', error: err.message || err.toString() });
        }
    }
}
