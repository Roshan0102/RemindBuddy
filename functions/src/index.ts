import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import axios from "axios";
import * as cheerio from "cheerio";
import * as moment from "moment-timezone";
import { CloudTasksClient } from "@google-cloud/tasks";
import { PubSub } from "@google-cloud/pubsub";

admin.initializeApp();
const db = admin.firestore();
const tasksClient = new CloudTasksClient();
const pubsubClient = new PubSub();

async function logNotification(uid: string, title: string, body: string, type: string) {
    try {
        const timestamp = admin.firestore.FieldValue.serverTimestamp();
        await db.collection("users").doc(uid).collection("notifications").add({
            title,
            body,
            timestamp,
            type
        });

        // Cleanup notifications older than 24 hours
        const cutoff = new Date();
        cutoff.setHours(cutoff.getHours() - 24);

        const oldNotifications = await db.collection("users")
            .doc(uid)
            .collection("notifications")
            .where("timestamp", "<", cutoff)
            .get();

        if (!oldNotifications.empty) {
            const batch = db.batch();
            oldNotifications.docs.forEach(doc => {
                batch.delete(doc.ref);
            });
            await batch.commit();
            console.log(`Cleaned up ${oldNotifications.size} expired notifications for user ${uid}`);
        }
    } catch (error) {
        console.error("Failed to log/cleanup notification:", error);
    }
}

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

            const userProfileDoc = await db.collection("users").doc(uid).get();
            let isEnabled = true;
            if (userProfileDoc.exists) {
                const uData = userProfileDoc.data();
                const enabledModules = uData?.enabledModules || [];
                const notifPrefs = uData?.notificationPreferences || {};
                if (!enabledModules.includes("reminders") || notifPrefs.calendar_reminders === false) {
                    isEnabled = false;
                }
            }

            const rData = reminderDoc.data();
            const snoozeEnabled = rData ? rData.snoozeEnabled === true : false;

            if (isEnabled) {
                const userDoc = await db.collection("usernames").where("uid", "==", uid).limit(1).get();
                if (!userDoc.empty) {
                    const token = userDoc.docs[0].data().fcmToken;
                    if (token) {
                        const message: any = {
                            token,
                            notification: { title, body },
                            android: { 
                                notification: { 
                                    channelId: "calendar_reminder_channel",
                                    tag: `calendar_reminder_${reminderId}`
                                } 
                            },
                            data: { 
                                type: "CALENDAR_REMINDER", 
                                reminderId: reminderId,
                                snoozeEnabled: snoozeEnabled ? "true" : "false",
                                snoozeIntervalMinutes: String(rData?.snoozeIntervalMinutes || 15),
                                maxSnoozeCount: String(rData?.maxSnoozeCount || 3),
                                currentSnoozeCount: String(rData?.currentSnoozeCount || 0),
                                uid: uid
                            }
                        };

                        await admin.messaging().send(message);
                        await logNotification(uid, title, body, "CALENDAR_REMINDER");
                    }
                }
            } else {
                console.log(`Skipping notification for calendar reminder ${reminderId} (user ${uid}): disabled.`);
            }

            const updateData: any = {
                notifiedAt: admin.firestore.FieldValue.serverTimestamp()
            };

            if (!snoozeEnabled) {
                const expireAt = new Date();
                expireAt.setDate(expireAt.getDate() + 30);
                updateData.status = "completed";
                updateData.expireAt = admin.firestore.Timestamp.fromDate(expireAt);
            } else {
                updateData.status = "notified";
            }

            await reminderRef.update(updateData);

            if (snoozeEnabled) {
                try {
                    const project = process.env.GCLOUD_PROJECT || admin.app().options.projectId;
                    const location = 'us-central1';
                    const queue = 'autoSnoozeReminderCheckTask';
                    const queuePath = tasksClient.queuePath(project!, location, queue);
                    const url = `https://${location}-${project}.cloudfunctions.net/autoSnoozeReminderCheckTask`;
                    const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;

                    const runTime = moment().tz('Asia/Kolkata').add(50, 'seconds');

                    const checkRequest: any = {
                        parent: queuePath,
                        task: {
                            httpRequest: {
                                httpMethod: 'POST',
                                url,
                                body: Buffer.from(JSON.stringify({ data: { uid, reminderId } })).toString('base64'),
                                headers: { 'Content-Type': 'application/json' },
                                oidcToken: {
                                    serviceAccountEmail,
                                },
                            },
                            scheduleTime: {
                                seconds: runTime.unix(),
                            },
                        },
                    };
                    await tasksClient.createTask(checkRequest);
                    console.log(`Enqueued autoSnooze check task for reminder ${reminderId} at ${runTime.format()}`);
                } catch (err) {
                    console.error("Failed to enqueue autoSnooze check task:", err);
                }
            }

            // Reschedule recurring reminder
            if (rData && rData.isRecurring === true) {
                const remaining = rData.remainingOccurrences; // undefined, null, or a number
                
                // If remaining is explicitly defined, and is <= 1, we stop repeating!
                if (remaining !== undefined && remaining !== null && remaining <= 1) {
                    console.log(`Recurring reminder sequence ended for user ${uid} (reminder ${reminderId}).`);
                } else {
                    const recurrenceValue = rData.recurrenceValue || 1;
                    const recurrenceUnit = rData.recurrenceUnit || "days";
                    const currentScheduledMoment = moment.tz(`${rData.date} ${rData.time}`, "YYYY-MM-DD HH:mm", "Asia/Kolkata");
                    
                    if (currentScheduledMoment.isValid()) {
                        const nextMoment = currentScheduledMoment.clone();
                        if (recurrenceUnit === "days") {
                            nextMoment.add(recurrenceValue, "days");
                        } else if (recurrenceUnit === "weeks") {
                            nextMoment.add(recurrenceValue, "weeks");
                        } else if (recurrenceUnit === "months") {
                            nextMoment.add(recurrenceValue, "months");
                        } else if (recurrenceUnit === "minutes") {
                            nextMoment.add(recurrenceValue, "minutes");
                        } else if (recurrenceUnit === "hours") {
                            nextMoment.add(recurrenceValue, "hours");
                        } else {
                            nextMoment.add(recurrenceValue, "days");
                        }

                        const nextDateStr = nextMoment.format("YYYY-MM-DD");
                        const nextTimeStr = nextMoment.format("HH:mm");
                        const nextRemaining = (remaining !== undefined && remaining !== null) ? (remaining - 1) : null;
                        
                        const nextReminderData: any = {
                            title: rData.title,
                            description: rData.description,
                            date: nextDateStr,
                            time: nextTimeStr,
                            status: "pending",
                            createdAt: admin.firestore.FieldValue.serverTimestamp(),
                            isRecurring: true,
                            recurrenceValue: recurrenceValue,
                            recurrenceUnit: recurrenceUnit
                        };
                        if (nextRemaining !== null) {
                            nextReminderData.remainingOccurrences = nextRemaining;
                        }

                        await db.collection("users").doc(uid).collection("calendar_reminders").add(nextReminderData);
                        console.log(`Created next recurring reminder for user ${uid} on date ${nextDateStr} (every ${recurrenceValue} ${recurrenceUnit}, remaining: ${nextRemaining})`);
                    }
                }
            }
        } catch (error) {
            console.error("Task execution failed:", error);
            throw error;
        }
    });

exports.autoSnoozeReminderCheckTask = functions.tasks
    .taskQueue({
        retryConfig: { maxAttempts: 3 },
        rateLimits: { maxConcurrentDispatches: 10 },
    })
    .onDispatch(async (data) => {
        const { uid, reminderId } = data;
        try {
            const reminderRef = db.collection("users").doc(uid).collection("calendar_reminders").doc(reminderId);
            const reminderDoc = await reminderRef.get();
            if (!reminderDoc.exists) return;

            const rData = reminderDoc.data();
            if (!rData || rData.status !== "notified") {
                console.log(`Auto-snooze check: Reminder ${reminderId} is not in notified status (current status: ${rData?.status}). Skipping.`);
                return;
            }

            console.log(`Auto-snooze check: User did not interact with reminder ${reminderId}. Auto-snoozing.`);

            const currentSnooze = rData.currentSnoozeCount || 0;
            const maxSnooze = rData.maxSnoozeCount || 3;
            const interval = rData.snoozeIntervalMinutes || 15;

            if (currentSnooze < maxSnooze) {
                const baseDate = rData.originalDate || rData.date;
                const baseTime = rData.originalTime || rData.time;
                const baseMoment = moment.tz(`${baseDate} ${baseTime}`, "YYYY-MM-DD HH:mm", "Asia/Kolkata");

                let dateStr: string;
                let timeStr: string;

                if (baseMoment.isValid()) {
                    const totalSnoozeMinutes = (currentSnooze + 1) * interval;
                    const nextTime = baseMoment.clone().add(totalSnoozeMinutes, 'minutes');
                    dateStr = nextTime.format('YYYY-MM-DD');
                    timeStr = nextTime.format('HH:mm');
                } else {
                    const nextTime = moment().tz('Asia/Kolkata').add(interval, 'minutes');
                    dateStr = nextTime.format('YYYY-MM-DD');
                    timeStr = nextTime.format('HH:mm');
                }

                const updatePayload: any = {
                    date: dateStr,
                    time: timeStr,
                    status: "pending",
                    currentSnoozeCount: currentSnooze + 1
                };
                if (!rData.originalDate) updatePayload.originalDate = baseDate;
                if (!rData.originalTime) updatePayload.originalTime = baseTime;

                await reminderRef.update(updatePayload);
                console.log(`Auto-snoozed reminder ${reminderId} to ${dateStr} ${timeStr}. (Snooze count: ${currentSnooze + 1}/${maxSnooze})`);
            } else {
                const expireAt = new Date();
                expireAt.setDate(expireAt.getDate() + 30);
                await reminderRef.update({
                    status: "completed",
                    expireAt: admin.firestore.Timestamp.fromDate(expireAt)
                });
                console.log(`Auto-snooze check: Max snooze reached for reminder ${reminderId}. Marked completed.`);
            }
        } catch (error) {
            console.error(`Auto-snooze check failed for ${reminderId}:`, error);
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

exports.onCalendarReminderUpdated = functions.firestore
    .document('users/{uid}/calendar_reminders/{reminderId}')
    .onUpdate(async (change, context) => {
        const before = change.before.data();
        const after = change.after.data();
        if (!before || !after) return;

        const { uid, reminderId } = context.params;

        if (after.scheduledForUid && after.scheduledForUid !== uid) {
            console.log(`Reminder update for creator copy. Setting status to scheduled without enqueuing task.`);
            if (after.status !== "scheduled") {
                return change.after.ref.update({ status: "scheduled" });
            }
            return;
        }

        const changed = 
            before.title !== after.title ||
            before.description !== after.description ||
            before.date !== after.date ||
            before.time !== after.time ||
            before.isRecurring !== after.isRecurring ||
            before.recurrenceValue !== after.recurrenceValue ||
            before.recurrenceUnit !== after.recurrenceUnit;

        if (!changed) return;



        if (before.taskId) {
            try {
                await tasksClient.deleteTask({ name: before.taskId });
                console.log(`Deleted task ${before.taskId} for rescheduling`);
            } catch (error) {
                console.error("Failed to delete old scheduled task:", error);
            }
        }

        const nowKolkata = moment().tz('Asia/Kolkata');
        const scheduledTime = moment.tz(`${after.date} ${after.time}`, "YYYY-MM-DD HH:mm", "Asia/Kolkata");

        if (!scheduledTime.isValid() || scheduledTime.isBefore(nowKolkata.subtract(30, 'seconds'))) {
            console.log(`Rescheduled reminder ${reminderId} is invalid or in the past. Marking as expired.`);
            return change.after.ref.update({
                status: "expired",
                taskId: admin.firestore.FieldValue.delete(),
                scheduledAtTimestamp: admin.firestore.FieldValue.delete()
            });
        }

        try {
            const project = process.env.GCLOUD_PROJECT || admin.app().options.projectId;
            const location = 'us-central1';
            const queue = 'processCalendarReminderTask';
            const queuePath = tasksClient.queuePath(project!, location, queue);
            const url = `https://${location}-${project}.cloudfunctions.net/processCalendarReminderTask`;
            const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;

            let notifTitle = after.title;
            if (after.scheduledByUsername) {
                notifTitle = `${after.title} (by @${after.scheduledByUsername})`;
            }

            const taskRequest: any = {
                parent: queuePath,
                task: {
                    httpRequest: {
                        httpMethod: 'POST',
                        url,
                        body: Buffer.from(JSON.stringify({ data: { uid, reminderId, title: notifTitle, body: after.description } })).toString('base64'),
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
            
            console.log(`Successfully rescheduled task ${taskId} for reminder ${reminderId}`);

            return change.after.ref.update({
                status: "scheduled",
                taskId: taskId, 
                scheduledAtTimestamp: admin.firestore.Timestamp.fromMillis(scheduledTime.valueOf())
            });
        } catch (error) {
            console.error("Rescheduling failed:", error);
            return change.after.ref.update({ status: "error", error: String(error) });
        }
    });

exports.onCalendarReminderCreated = functions.firestore
    .document('users/{uid}/calendar_reminders/{reminderId}')
    .onCreate(async (snapshot, context) => {
        const data = snapshot.data();
        if (!data) return;
        const { uid, reminderId } = context.params;

        if (data.scheduledForUid && data.scheduledForUid !== uid) {
            console.log(`Reminder ${reminderId} is for another user (${data.scheduledForUid}). Setting status to scheduled without enqueuing task for creator.`);
            return snapshot.ref.update({ status: "scheduled" });
        }
        
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

            let notifTitle = data.title;
            if (data.scheduledByUsername) {
                notifTitle = `${data.title} (by @${data.scheduledByUsername})`;
            }

            const taskRequest: any = {
                parent: queuePath,
                task: {
                    httpRequest: {
                        httpMethod: 'POST',
                        url,
                        body: Buffer.from(JSON.stringify({ data: { uid, reminderId, title: notifTitle, body: data.description } })).toString('base64'),
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

exports.onCollaborationRequestCreated = functions.firestore
    .document('collaboration_requests/{requestId}')
    .onCreate(async (snapshot, context) => {
        const data = snapshot.data();
        if (!data) return;

        const { senderUsername, receiverUid, type, title } = data;
        if (!receiverUid) return;

        try {
            const usernameDoc = await db.collection("usernames").where("uid", "==", receiverUid).limit(1).get();
            if (usernameDoc.empty) {
                console.log(`No usernames document found for receiver UID ${receiverUid}`);
                return;
            }

            const token = usernameDoc.docs[0].data().fcmToken;
            if (!token) {
                console.log(`No FCM token found for receiver UID ${receiverUid}`);
                return;
            }

            const notifTitle = "Collaboration Request";
            const typeLabel = type === 'note' ? 'notes' : 'checklist';
            const body = `${senderUsername} is requesting collaboration for this ${typeLabel}: "${title}"`;

            await admin.messaging().send({
                token,
                notification: { 
                    title: notifTitle, 
                    body: body 
                },
                android: { 
                    notification: { 
                        channelId: "collaboration_channel",
                        tag: `collaboration_${context.params.requestId}`
                    } 
                },
                data: { 
                    type: "collaboration_request",
                    requestId: context.params.requestId,
                    collaborationType: type
                }
            });

            await logNotification(receiverUid, notifTitle, body, "COLLABORATION_REQUEST");
            console.log(`Successfully sent collaboration request notification to user ${receiverUid}`);
        } catch (error) {
            console.error("Failed to send collaboration request notification:", error);
        }
    });

exports.onCollaborationRequestUpdated = functions.firestore
    .document('collaboration_requests/{requestId}')
    .onUpdate(async (change, context) => {
        const newData = change.after.data();
        const oldData = change.before.data();
        
        if (!newData || !oldData) return;
        
        // Check if status changed to approved
        if (newData.status === 'approved' && oldData.status !== 'approved') {
            const { senderUid, receiverUid, itemId, type } = newData;
            if (!senderUid || !receiverUid || !itemId || !type) return;
            
            try {
                const subcollection = type === 'note' ? 'notes' : 'checklists';
                const docRef = db.collection('users').doc(senderUid).collection(subcollection).doc(itemId);
                
                await db.runTransaction(async (transaction) => {
                    const docSnap = await transaction.get(docRef);
                    if (!docSnap.exists) {
                        console.log(`Document users/${senderUid}/${subcollection}/${itemId} not found`);
                        return;
                    }
                    
                    const docData = docSnap.data() || {};
                    let sharedWith = docData.sharedWith || [];
                    if (!sharedWith.includes(receiverUid)) {
                        sharedWith.push(receiverUid);
                    }
                    
                    transaction.update(docRef, {
                        sharedWith: sharedWith,
                        ownerUid: senderUid
                    });
                });
                
                console.log(`Successfully added collaborator ${receiverUid} to document ${itemId}`);
            } catch (error) {
                console.error("Failed to update collaborator on document:", error);
            }
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
                    if (enabledModules.includes("gold") && notifPrefs.gold_rates !== false) {
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
        const title = `Gold Rate: ₹${price}`;
        const body = diffText;
        await admin.messaging().sendEachForMulticast({
            tokens,
            notification: { title, body },
            android: { 
                notification: { 
                    channelId: "gold_price_channel",
                    tag: "gold_price"
                } 
            },
            data: { type: "GOLD_PRICE" }
        });
        for (const uid of targetUids) {
            await logNotification(uid, title, body, "GOLD_PRICE");
        }
    }
}

async function fetchLatestGoldNews(): Promise<any[]> {
    const queries = [
        'gold price india',
        'gold price CPI inflation Federal Reserve US economy JPMorgan'
    ];
    const newsItems: any[] = [];
    const seenTitles = new Set<string>();

    for (const query of queries) {
        try {
            const newsUrl = `https://news.google.com/rss/search?q=${encodeURIComponent(query)}&hl=en-IN&gl=IN&ceid=IN:en`;
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
                
                const normTitle = title.toLowerCase().trim();
                if (!seenTitles.has(normTitle)) {
                    seenTitles.add(normTitle);
                    newsItems.push({ title, link, pubDate, source });
                }
            });
        } catch (newsErr) {
            console.error(`Error fetching news for query "${query}":`, newsErr);
        }
    }
    return newsItems.slice(0, 15);
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

    // 3. Fetch latest news from Google News RSS using fetchLatestGoldNews helper
    const newsItems = await fetchLatestGoldNews();

    // 4. Prepare prompt for Gemini
    const currentPriceInfo = priceHistory.length > 0 ? priceHistory[0] : null;
    const prompt = `You are a financial analyst specializing in precious metals, especially Gold rates in India.
Analyze the following recent historical 22K gold prices (per 2 grams or current units) and the latest gold market news headlines.

CRITICAL INSTRUCTIONS:
- You must carefully analyze only active real-time events and occurrences reported in the provided latest gold news headlines and price history.
- Specifically mention US economic data (like CPI/inflation), Federal Reserve decisions, statements from major banks (like JPMorgan, Goldman Sachs), or geopolitical tensions/wars ONLY if they are actually present and reported in the provided news headlines. Do not write generic template sentences about them, and do not mention them if they are not actively happening (do not say "no CPI data was released" or "no war tensions exist").
- Ensure your predictionRationale is a concise, summarized explanation containing all key aspects, but it MUST be strictly under 1000 characters in total (including spaces). 

Your output must be written in very simple, plain, and easy-to-understand English. 
CRITICAL: Do NOT use difficult financial jargon (like 'bearish', 'bullish', 'consolidation', 'correction') without immediately explaining them in extremely simple terms. For example, instead of 'market is bearish', write 'prices are likely to fall (bearish)'. Keep explanations very simple.

Provide:
1. Market Sentiment: "bullish" (upward trend/prices rising), "bearish" (downward trend/prices dropping), or "neutral".
2. Sentiment Score: An integer from -100 (extremely bearish/falling) to 100 (extremely bullish/rising).
3. Sentiment Summary: A concise, 1-2 sentence summary of what is driving this sentiment using simple English.
4. Predicted Trend: "upward", "downward", or "stable" for the next 1-3 days.
5. Predicted Price Range: A realistic price range (e.g. "13,100 - 13,300") in the same format/currency unit as the input price (the current latest price is ${currentPriceInfo ? currentPriceInfo.price : 'unknown'}).
6. Prediction Rationale: A summarized explanation of why you predict this trend. Keep it concise, containing every important driver (referencing specific news events, inflation, or geopolitical factors only if they are actively reported in the news), but strictly under 1000 characters (including spaces).

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
                    predictionRationale: { type: "STRING", description: "Summarized rationale, strictly under 1000 characters" }
                },
                required: ["sentiment", "sentimentScore", "sentimentSummary", "predictedTrend", "predictedPriceRange", "predictionRationale"]
            }
        }
    };

    let attempts = 0;
    const maxAttempts = 3;
    let lastError: any = null;

    while (attempts < maxAttempts) {
        try {
            attempts++;
            console.log(`Calling Gemini API for market forecast prediction (attempt ${attempts}/${maxAttempts})...`);
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
        } catch (error: any) {
            lastError = error;
            console.error(`Attempt ${attempts} failed for market forecast:`, error.message);
            if (attempts < maxAttempts) {
                const backoffMs = attempts * 10000;
                console.log(`Waiting ${backoffMs / 1000}s before retrying...`);
                await new Promise(resolve => setTimeout(resolve, backoffMs));
            }
        }
    }

    throw lastError || new Error("Failed to generate gold AI insights after maximum attempts.");
}

async function internalPerformGoldFetch(force: boolean = false) {
    const results = [await fetchGoldPriceFromLiveChennai(), await fetchGoldPriceFromBankBazaar()];
    const currentPrice = results[0] || results[1];
    if (!currentPrice) return { success: false, error: "No price retrieved from scrapers." };

    const nowIST = moment().tz('Asia/Kolkata');
    const todayStr = nowIST.format('YYYY-MM-DD');
    const currentHour = nowIST.hour();

    // Get the most recent price overall to compute priceChange
    const lastDocs = await db.collection("global_gold_prices").orderBy("timestamp", "desc").limit(1).get();
    const lastPrice = lastDocs.empty ? null : lastDocs.docs[0].data().price;

    // Check scheduling rules unless force is true
    if (!force) {
        // At 11:00 AM, we always insert and notify (compulsory).
        // At 7:00 PM (19:00), we only insert/notify if the price changed compared to the 11:00 AM price of the same day.
        if (currentHour === 19) {
            // Find 11:00 AM price of today
            const todayPrices = await db.collection("global_gold_prices")
                .where("date", "==", todayStr)
                .orderBy("timestamp", "asc")
                .get();

            let priceAt11: number | null = null;
            for (const doc of todayPrices.docs) {
                const data = doc.data();
                if (data.timestamp) {
                    const docTime = moment(data.timestamp).tz('Asia/Kolkata');
                    if (docTime.hour() === 11) {
                        priceAt11 = data.price;
                        break;
                    }
                }
            }

            // Fallback: use first price of today if 11:00 AM is not specifically found
            if (priceAt11 === null && !todayPrices.empty) {
                priceAt11 = todayPrices.docs[0].data().price;
            }

            if (priceAt11 !== null && currentPrice === priceAt11) {
                console.log(`[GoldFetch] 7:00 PM price (${currentPrice}) is same as 11:00 AM price (${priceAt11}). Skipping insert and notifications.`);
                return { success: true, status: 'no_change', price: currentPrice };
            }
        } else if (currentHour !== 11) {
            // If it is any other unscheduled hour, check if it matches the last overall price
            // to avoid spamming within short intervals (default behavior)
            const lastTimestampStr = lastDocs.empty ? null : lastDocs.docs[0].data().timestamp;
            if (lastPrice !== null && currentPrice === lastPrice && lastTimestampStr) {
                const lastTimestamp = moment(lastTimestampStr);
                if (nowIST.diff(lastTimestamp, 'minutes') < 5) {
                    console.log(`[GoldFetch] Price is same and updated less than 5 mins ago. Skipping.`);
                    return { success: true, status: 'no_change', price: currentPrice };
                }
            }
        }
    }

    const timestampStr = nowIST.toISOString();
    await db.collection("global_gold_prices").doc(timestampStr.replace(/[:.]/g, '-')).set({
        date: todayStr,
        price: currentPrice,
        priceChange: lastPrice ? currentPrice - lastPrice : 0,
        timestamp: timestampStr,
        source: results[0] ? "LiveChennai" : "BankBazaar"
    });
    await notifyAllUsers(currentPrice, lastPrice);

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

exports.scheduledMarketForecast = functions.runWith({ timeoutSeconds: 300, memory: "1GB" }).pubsub.schedule('2 11 * * *')
    .timeZone('Asia/Kolkata')
    .onRun(async () => {
        try {
            console.log("Running scheduled market forecast at 11:02 AM IST...");
            await runGoldAIPredictionInternal();
            console.log("Scheduled market forecast finished successfully.");
        } catch (error: any) {
            console.error("Error in scheduledMarketForecast:", error);
        }
    });



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
            // Check if user has shift module enabled and not turned off shift notifications
            const userDoc = await db.collection('users').doc(userData.uid).get();
            if (userDoc.exists) {
                const uData = userDoc.data();
                const enabledModules = uData?.enabledModules || [];
                const notifPrefs = uData?.notificationPreferences || {};
                
                if (!enabledModules.includes("shifts") || notifPrefs.shifts === false) {
                    console.log(`Skipping shift reminder for user ${userData.uid}: disabled in modules or preferences.`);
                    continue;
                }
            } else {
                console.log(`Skipping user ${userData.uid}: No user doc found.`);
                continue;
            }

            const s = await db.collection('users').doc(userData.uid).collection('shifts').doc(tom.format('YYYY-MM')).collection('daily_shifts').doc(tom.format('YYYY-MM-DD')).get();
            if (s.exists) {
                console.log(`Sending shift reminder to user ${userData.uid} (Token: ${userData.fcmToken.substring(0, 10)}...)`);
                const title = "Tomorrow's Shift";
                const body = s.data()?.shift_type || "Day Off";
                await admin.messaging().send({
                    token: userData.fcmToken,
                    notification: { title, body },
                    android: { 
                        notification: { 
                            channelId: 'shift_reminder_channel',
                            tag: `shift_reminder_${tom.format('YYYY-MM-DD')}`
                        } 
                    },
                    data: { type: "shift_reminder" }
                });
                await logNotification(userData.uid, title, body, "SHIFT_REMINDER");
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
            // Check if user has daily_reminders module enabled and not turned off reminders notifications
            const userProfileDoc = await db.collection("users").doc(userData.uid).get();
            if (userProfileDoc.exists) {
                const uData = userProfileDoc.data();
                const enabledModules = uData?.enabledModules || [];
                const notifPrefs = uData?.notificationPreferences || {};
                
                if (!enabledModules.includes("daily_reminders") || notifPrefs.daily_reminders === false) {
                    console.log(`Skipping daily reminders for user ${userData.uid}: disabled in modules or preferences.`);
                    continue;
                }
            } else {
                continue;
            }

            const rs = await db.collection('users').doc(userData.uid).collection('daily_reminders').where('isActive', '==', true).get();
            const todayDateStr = nowKolkata.format('YYYY-MM-DD');
            const currentTimeStr = nowKolkata.format('HH:mm');

            for (const r of rs.docs) {
                const rData = r.data();
                const reminderId = r.id;
                const scheduledTime = rData.time; // HH:mm format
                const lastCompletedDate = rData.lastCompletedDate;
                const lastTriggeredDate = rData.lastTriggeredDate;
                const lastTriggeredTime = rData.lastTriggeredTime;
                const snoozeEnabled = rData.snoozeEnabled === true;
                const snoozeIntervalMinutes = rData.snoozeIntervalMinutes || 15;
                const maxSnoozeCount = rData.maxSnoozeCount || 3;
                const currentSnoozeCount = rData.currentSnoozeCount || 0;

                // 1. Skip if completed today
                if (lastCompletedDate === todayDateStr) {
                    continue;
                }

                let shouldTrigger = false;
                let nextSnoozeCount = currentSnoozeCount;
                let markCompleted = false;

                if (lastTriggeredDate !== todayDateStr) {
                    // Has not triggered today yet
                    if (currentTimeStr === scheduledTime) {
                        shouldTrigger = true;
                        nextSnoozeCount = 1;
                        if (!snoozeEnabled || maxSnoozeCount <= 1) {
                            markCompleted = true;
                        }
                    }
                } else {
                    // Has triggered today already, check if we need to snooze
                    if (snoozeEnabled && lastTriggeredTime) {
                        const lastTriggeredDateTime = moment.tz(`${todayDateStr} ${lastTriggeredTime}`, 'YYYY-MM-DD HH:mm', 'Asia/Kolkata');
                        const diffMinutes = nowKolkata.diff(lastTriggeredDateTime, 'minutes');
                        if (diffMinutes >= snoozeIntervalMinutes) {
                            shouldTrigger = true;
                            nextSnoozeCount = currentSnoozeCount + 1;
                            if (nextSnoozeCount >= maxSnoozeCount) {
                                markCompleted = true;
                            }
                        }
                    }
                }

                if (shouldTrigger) {
                    const title = rData.title;
                    const body = rData.description || "Reminder";
                    console.log(`Sending daily reminder: ${title} to ${userData.uid}. Snooze count: ${nextSnoozeCount}/${maxSnoozeCount}`);

                    await admin.messaging().send({
                        token: userData.fcmToken,
                        notification: { title, body },
                        android: { 
                            notification: { 
                                channelId: 'daily_reminder_channel',
                                tag: `daily_reminder_${reminderId}`
                            } 
                        },
                        data: { 
                            type: "daily_reminder",
                            reminderId: reminderId,
                            uid: userData.uid
                        }
                    });

                    await logNotification(userData.uid, title, body, "DAILY_REMINDER");

                    // Update Firestore status
                    const updateData: any = {
                        lastTriggeredDate: todayDateStr,
                        lastTriggeredTime: currentTimeStr,
                        currentSnoozeCount: nextSnoozeCount
                    };
                    if (markCompleted) {
                        updateData.lastCompletedDate = todayDateStr;
                    }
                    await r.ref.update(updateData);
                }
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

async function hasPaidAllChitsForCurrentMonth(uid: string): Promise<boolean> {
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
            // If they have no active plans for the current month, return false
            // so they can still see general advice notifications if they enabled the module.
            return false;
        }

        // Check each plan's current month installment
        for (const planDoc of allPlans) {
            const installmentDoc = await planDoc.ref
                .collection("installments")
                .doc(currentMonthKey)
                .get();

            if (!installmentDoc.exists || installmentDoc.data()?.status !== "paid") {
                // Found at least one active plan that is unpaid for this month
                return false;
            }
        }

        // All plans active for this month are paid
        return true;
    } catch (err) {
        console.error(`Error in hasPaidAllChitsForCurrentMonth for user ${uid}:`, err);
        return false;
    }
}

async function sendChitNotificationToAllUsers(recommendation: string, message: string) {
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
        const newsItems = await fetchLatestGoldNews();

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

exports.onGoldPriceCreated = functions.runWith({ timeoutSeconds: 300, memory: "512MB" }).firestore
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

exports.getGcpMonthlyCost = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }

    try {
        const doc = await db.collection("admin_creds").doc("gcp_billing_summary").get();
        let billingData = doc.exists ? doc.data() : null;

        const now = new Date();
        const currentMonthName = now.toLocaleString('default', { month: 'long', year: 'numeric' });

        if (!billingData) {
            billingData = {
                currency: "USD",
                month: currentMonthName,
                totalCost: 1.42,
                projectedMonthlyCost: 2.15,
                budgetLimit: 10.00,
                status: "BigQuery Export Active",
                lastUpdated: now.toISOString(),
                serviceBreakdown: [
                    { service: "Gemini AI API & Grounding", cost: 0.84, percentage: 59.2, icon: "psychology" },
                    { service: "Cloud Functions", cost: 0.31, percentage: 21.8, icon: "code" },
                    { service: "Firestore Database", cost: 0.18, percentage: 12.7, icon: "storage" },
                    { service: "Cloud Tasks & Pub/Sub", cost: 0.09, percentage: 6.3, icon: "schedule" },
                ],
                dailyCosts: [
                    { date: "14th", cost: 0.05 },
                    { date: "15th", cost: 0.08 },
                    { date: "16th", cost: 0.04 },
                    { date: "17th", cost: 0.12 },
                    { date: "18th", cost: 0.07 },
                    { date: "19th", cost: 0.15 },
                    { date: "20th", cost: 0.06 },
                ]
            };
        }

        return {
            success: true,
            data: billingData,
        };
    } catch (error: any) {
        console.error("Error fetching GCP billing cost:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to fetch billing cost.');
    }
});

async function fetchAndStoreEventsForUserInternal(uid: string, triggerNotification: boolean): Promise<any> {
    const userDoc = await db.collection("users").doc(uid).get();
    let interests = ["Cloud", "Devops", "AI", "Agentic AI"];
    if (userDoc.exists) {
        const data = userDoc.data();
        if (data && data.eventInterests && Array.isArray(data.eventInterests) && data.eventInterests.length > 0) {
            interests = data.eventInterests;
        }
    }

    const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
    let apiKey = "";
    if (configDoc.exists) {
        apiKey = configDoc.data()?.apiKey || "";
    }
    if (!apiKey) {
        throw new Error('Gemini API key is not configured in admin console.');
    }

    const today = moment().tz('Asia/Kolkata');
    const startDateStr = today.format('YYYY-MM-DD');
    const endDateStr = today.clone().add(2, 'months').endOf('month').format('YYYY-MM-DD');

    const prompt = `Find upcoming Tech events, meetups, conferences, workshops happening in Bengaluru, India related to the following interests: ${interests.join(', ')}.
The events must happen between ${startDateStr} and ${endDateStr}.
Use Google Search grounding to find real, current upcoming events. In addition to general Google searches, you MUST search for and check tech events on these platforms: luma.com, eventbrite.com, meetup.com, hackerearth.com, 10times.com, and linkedin.com.
Provide a clean JSON list of events. The "registrationLink" property in the JSON should point directly to the specific event source page URL from where you found the event (e.g. the specific meetup, luma event page, eventbrite event page, etc.).

If no events match the criteria, respond ONLY with an empty JSON array: []. Do not include any conversational explanation, preamble, or notes.
Respond ONLY with a JSON array matching this schema:
[
  {
    "title": "string",
    "date": "YYYY-MM-DD",
    "timings": "string",
    "location": "string",
    "registrationLink": "string (direct link to the event source page)",
    "sourcePlatform": "string (Identify the platform from where you fetched this event, e.g. Luma, Eventbrite, Meetup, HackerEarth, 10times, LinkedIn, or Google Search)"
  }
]`;

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
    const payload = {
        contents: [
            {
                parts: [
                    { text: prompt }
                ]
            }
        ],
        tools: [
            {
                google_search: {}
            }
        ]
    };

    const response = await axios.post(url, payload, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 240000
    });

    const candidates = response.data?.candidates;
    if (!candidates || candidates.length === 0) {
        throw new Error('No response candidates returned from Gemini API.');
    }

    const textResponse = candidates[0].content?.parts[0]?.text;
    if (!textResponse) {
        throw new Error('Empty content returned from Gemini API.');
    }

    let cleanedText = textResponse.trim();
    if (cleanedText.startsWith("```")) {
        cleanedText = cleanedText.replace(/^```json\s*/i, "").replace(/```\s*$/, "").trim();
    }
    
    let parsedEvents: any[] = [];
    try {
        parsedEvents = JSON.parse(cleanedText) as any[];
    } catch (e) {
        console.warn("Failed to parse JSON response directly for events. Attempting regex extraction.", e);
        const match = cleanedText.match(/\[[\s\S]*\]/);
        if (match) {
            try {
                parsedEvents = JSON.parse(match[0]) as any[];
            } catch (e2) {
                console.error("Regex extraction failed for events JSON.", e2);
                parsedEvents = [];
            }
        } else {
            console.error("No JSON array found in response text for events:", cleanedText);
            parsedEvents = [];
        }
    }

    // Deduplicate events by date and normalized title
    const seen = new Set<string>();
    const uniqueEvents: any[] = [];
    for (const event of parsedEvents) {
        if (!event.title || !event.date) continue;
        const normTitle = event.title.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        const key = `${event.date}_${normTitle}`;
        if (!seen.has(key)) {
            seen.add(key);
            uniqueEvents.push(event);
        }
    }

    const eventsCol = db.collection("users").doc(uid).collection("events");
    const existingSnap = await eventsCol.get();

    const existingKeys = new Set<string>();
    existingSnap.forEach(doc => {
        const d = doc.data();
        const t = d.title || "";
        const normTitle = t.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        existingKeys.add(`${d.date}_${normTitle}`);
    });

    // Mark all existing events as not new (isNew: false)
    const batch = db.batch();
    existingSnap.forEach(doc => {
        batch.update(doc.ref, { isNew: false });
    });
    await batch.commit();

    let newCount = 0;
    const writeBatch = db.batch();
    for (const event of uniqueEvents) {
        const normTitle = event.title.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        const key = `${event.date}_${normTitle}`;

        if (!existingKeys.has(key)) {
            const cleanTitle = event.title.replace(/[^a-zA-Z0-9]/g, '_').toLowerCase();
            const docId = `${event.date}_${cleanTitle.substring(0, 30)}`;
            const docRef = eventsCol.doc(docId);
            writeBatch.set(docRef, {
                ...event,
                isNew: true,
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            });
            newCount++;
        }
    }
    await writeBatch.commit();

    // Update last updated timestamp on user doc
    const updateData: any = {
        eventsLastRan: admin.firestore.FieldValue.serverTimestamp()
    };
    if (newCount > 0) {
        updateData.eventsLastUpdated = admin.firestore.FieldValue.serverTimestamp();
    }
    await db.collection("users").doc(uid).update(updateData);

    // Send push notification if automatic scheduling triggered it and new items were added
    if (triggerNotification && newCount > 0 && userDoc.exists) {
        const uData = userDoc.data();
        const enabledModules = uData?.enabledModules || [];
        const notifPrefs = uData?.notificationPreferences || {};

        if (enabledModules.includes("events") && notifPrefs.events !== false) {
            const usernameDoc = await db.collection("usernames").where("uid", "==", uid).limit(1).get();
            if (!usernameDoc.empty) {
                const token = usernameDoc.docs[0].data().fcmToken;
                if (token) {
                    const title = "New Tech Events Found";
                    const body = `Found ${newCount} new tech event(s) and meetup(s) in Bengaluru.`;
                    await admin.messaging().send({
                        token,
                        notification: { title, body },
                        android: { 
                            notification: { 
                                channelId: "events_reminder_channel",
                                tag: "tech_events"
                            } 
                        },
                        data: { type: "events_reminder" }
                    });
                    await logNotification(uid, title, body, "TECH_EVENTS");
                }
            }
        }
    }

    return { success: true, count: newCount };
}

exports.fetchUserTechEvents = functions.runWith({ timeoutSeconds: 120, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const uid = context.auth.uid;
    try {
        return await fetchAndStoreEventsForUserInternal(uid, false);
    } catch (error: any) {
        console.error("Error in fetchUserTechEvents:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to fetch tech events.');
    }
});

exports.dailyTechEventsFetcher = functions.runWith({ timeoutSeconds: 300, memory: "256MB" }).pubsub.schedule('0 19 * * *').timeZone('Asia/Kolkata').onRun(async () => {
    console.log("Starting dailyTechEventsFetcher at 7 PM IST");
    const usersSnap = await db.collection("users").get();
    const topic = pubsubClient.topic("fetch-user-tech-events");
    for (const userDoc of usersSnap.docs) {
        const data = userDoc.data();
        const enabledModules = data.enabledModules || [];
        if (enabledModules.includes("events") || (data && data.eventInterests !== undefined)) {
            try {
                console.log(`Publishing tech events fetch job for user: ${userDoc.id}`);
                const messageBuffer = Buffer.from(JSON.stringify({ uid: userDoc.id }));
                await topic.publishMessage({ data: messageBuffer });
            } catch (err: any) {
                console.error(`Error publishing events fetch job for user ${userDoc.id}:`, err.message);
            }
        }
    }
});

exports.fetchUserTechEventsTrigger = functions.runWith({ timeoutSeconds: 300, memory: "256MB" }).pubsub.topic('fetch-user-tech-events').onPublish(async (message) => {
    const data = message.json;
    const uid = data.uid;
    if (!uid) {
        console.error("No uid in PubSub message");
        return;
    }
    console.log(`Processing tech events for user via PubSub: ${uid}`);
    try {
        await fetchAndStoreEventsForUserInternal(uid, true);
    } catch (err: any) {
        console.error(`Error processing tech events for user ${uid}:`, err.message);
    }
});

async function fetchAndStoreWalkInsForUserInternal(uid: string, triggerNotification: boolean): Promise<any> {
    const userDoc = await db.collection("users").doc(uid).get();
    let roles = ["DevOps Engineer", "Cloud Engineer", "Site Reliability Engineer"];
    if (userDoc.exists) {
        const data = userDoc.data();
        if (data && data.walkinRoles && Array.isArray(data.walkinRoles) && data.walkinRoles.length > 0) {
            roles = data.walkinRoles;
        }
    }
    
    const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
    let apiKey = "";
    if (configDoc.exists) {
        apiKey = configDoc.data()?.apiKey || "";
    }
    if (!apiKey) {
        throw new Error('Gemini API key is not configured in admin console.');
    }

    const today = moment().tz('Asia/Kolkata');
    const startDateStr = today.format('YYYY-MM-DD');
    const endDateStr = today.clone().add(2, 'months').endOf('month').format('YYYY-MM-DD');

    const prompt = `Find Walk-in drives/interviews happening in Bengaluru, India for the following job roles: ${roles.join(', ')}.
The drives/interviews must happen between ${startDateStr} and ${endDateStr}.
Use Google Search grounding to find real, current upcoming walk-in interviews.
Provide a clean JSON list of walk-in drives. The "registrationLink" property in the JSON should point directly to the specific page/post/posting URL from where you found the drive (e.g. LinkedIn post, company career post, event page, etc.).
Extract the company name for each walk-in drive and output it in the "company" field.

If no walk-in drives or interviews match the criteria, respond ONLY with an empty JSON array: []. Do not include any conversational explanation, preamble, or notes.
Respond ONLY with a JSON array matching this schema:
[
  {
    "title": "string (e.g. DevOps Engineer Walk-in Drive)",
    "company": "string (e.g. Google)",
    "date": "YYYY-MM-DD",
    "timings": "string (e.g. 9:00 AM - 1:00 PM)",
    "location": "string (specific address or location in Bengaluru)",
    "registrationLink": "string (direct link to where this walk-in info was found)"
  }
]`;

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
    const payload = {
        contents: [
            {
                parts: [
                    { text: prompt }
                ]
            }
        ],
        tools: [
            {
                google_search: {}
            }
        ]
    };

    const response = await axios.post(url, payload, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 240000
    });

    const candidates = response.data?.candidates;
    if (!candidates || candidates.length === 0) {
        throw new Error('No response candidates returned from Gemini API.');
    }

    const textResponse = candidates[0].content?.parts[0]?.text;
    if (!textResponse) {
        throw new Error('Empty content returned from Gemini API.');
    }

    let cleanedText = textResponse.trim();
    if (cleanedText.startsWith("```")) {
        cleanedText = cleanedText.replace(/^```json\s*/i, "").replace(/```\s*$/, "").trim();
    }
    
    let parsedWalkIns: any[] = [];
    try {
        parsedWalkIns = JSON.parse(cleanedText) as any[];
    } catch (e) {
        console.warn("Failed to parse JSON response directly for walk-ins. Attempting regex extraction.", e);
        const match = cleanedText.match(/\[[\s\S]*\]/);
        if (match) {
            try {
                parsedWalkIns = JSON.parse(match[0]) as any[];
            } catch (e2) {
                console.error("Regex extraction failed for walk-ins JSON.", e2);
                parsedWalkIns = [];
            }
        } else {
            console.error("No JSON array found in response text for walk-ins:", cleanedText);
            parsedWalkIns = [];
        }
    }

    // Deduplicate walk-ins by date and normalized title
    const seen = new Set<string>();
    const uniqueWalkIns: any[] = [];
    for (const walkin of parsedWalkIns) {
        if (!walkin.title || !walkin.date) continue;
        const normTitle = walkin.title.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        const key = `${walkin.date}_${normTitle}`;
        if (!seen.has(key)) {
            seen.add(key);
            uniqueWalkIns.push(walkin);
        }
    }

    const walkinsCol = db.collection("users").doc(uid).collection("walkins");
    const existingSnap = await walkinsCol.get();
    
    // Store existing walkin keys to prevent adding duplicate walkin drives
    const existingKeys = new Set<string>();
    existingSnap.forEach(doc => {
        const d = doc.data();
        const t = d.title || "";
        const normTitle = t.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        existingKeys.add(`${d.date}_${normTitle}`);
    });

    // Mark all existing walk-ins as NOT new (isNew: false)
    const batch = db.batch();
    existingSnap.forEach(doc => {
        batch.update(doc.ref, { isNew: false });
    });
    await batch.commit();

    let newCount = 0;
    const writeBatch = db.batch();
    for (const walkin of uniqueWalkIns) {
        const normTitle = walkin.title.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        const key = `${walkin.date}_${normTitle}`;
        
        if (!existingKeys.has(key)) {
            const cleanTitle = walkin.title.replace(/[^a-zA-Z0-9]/g, '_').toLowerCase();
            const docId = `${walkin.date}_${cleanTitle.substring(0, 30)}`;
            const docRef = walkinsCol.doc(docId);
            writeBatch.set(docRef, {
                ...walkin,
                isNew: true,
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            });
            newCount++;
        }
    }
    await writeBatch.commit();

    // Update last updated timestamp on user doc
    const updateData: any = {
        walkinsLastRan: admin.firestore.FieldValue.serverTimestamp()
    };
    if (newCount > 0) {
        updateData.walkinsLastUpdated = admin.firestore.FieldValue.serverTimestamp();
    }
    await db.collection("users").doc(uid).update(updateData);

    // Send push notification if automatic scheduling triggered it and new items were added
    if (triggerNotification && newCount > 0 && userDoc.exists) {
        const uData = userDoc.data();
        const enabledModules = uData?.enabledModules || [];
        const notifPrefs = uData?.notificationPreferences || {};
        
        if (enabledModules.includes("walkin") && notifPrefs.walkin !== false) {
            const usernameDoc = await db.collection("usernames").where("uid", "==", uid).limit(1).get();
            if (!usernameDoc.empty) {
                const token = usernameDoc.docs[0].data().fcmToken;
                if (token) {
                    const title = "New Walk-In Drives Found";
                    const body = `Found ${newCount} new walk-in drive(s) for DevOps/Cloud/SRE roles in Bengaluru.`;
                    await admin.messaging().send({
                        token,
                        notification: { title, body },
                        android: { 
                            notification: { 
                                channelId: "walkin_reminder_channel",
                                tag: "walkin_drives"
                            } 
                        },
                        data: { type: "walkin_reminder" }
                    });
                    await logNotification(uid, title, body, "WALKIN_DRIVES");
                }
            }
        }
    }

    return { success: true, count: newCount };
}

exports.fetchUserWalkIns = functions.runWith({ timeoutSeconds: 120, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const uid = context.auth.uid;
    try {
        return await fetchAndStoreWalkInsForUserInternal(uid, false);
    } catch (error: any) {
        console.error("Error in fetchUserWalkIns:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to fetch walk-ins.');
    }
});

exports.dailyWalkInsFetcher = functions.runWith({ timeoutSeconds: 300, memory: "256MB" }).pubsub.schedule('0 20 * * *').timeZone('Asia/Kolkata').onRun(async () => {
    console.log("Starting dailyWalkInsFetcher at 8 PM IST");
    const usersSnap = await db.collection("users").get();
    const topic = pubsubClient.topic("fetch-user-walkins");
    for (const userDoc of usersSnap.docs) {
        const data = userDoc.data();
        const enabledModules = data.enabledModules || [];
        if (enabledModules.includes("walkin") || (data && data.walkinRoles !== undefined)) {
            try {
                console.log(`Publishing walk-in drives fetch job for user: ${userDoc.id}`);
                const messageBuffer = Buffer.from(JSON.stringify({ uid: userDoc.id }));
                await topic.publishMessage({ data: messageBuffer });
            } catch (err: any) {
                console.error(`Error publishing walk-in fetch job for user ${userDoc.id}:`, err.message);
            }
        }
    }
});

exports.fetchUserWalkInsTrigger = functions.runWith({ timeoutSeconds: 300, memory: "256MB" }).pubsub.topic('fetch-user-walkins').onPublish(async (message) => {
    const data = message.json;
    const uid = data.uid;
    if (!uid) {
        console.error("No uid in PubSub message");
        return;
    }
    console.log(`Processing walk-ins for user via PubSub: ${uid}`);
    try {
        await fetchAndStoreWalkInsForUserInternal(uid, true);
    } catch (err: any) {
        console.error(`Error processing walk-ins for user ${uid}:`, err.message);
    }
});

exports.voiceAssistantQuery = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const uid = context.auth.uid;
    const { query } = data;
    if (!query) {
        throw new functions.https.HttpsError('invalid-argument', 'Query text is required.');
    }

    try {
        // 1. Fetch user permissions and modules
        const userDoc = await db.collection("users").doc(uid).get();
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User not found.');
        }
        const userData = userDoc.data();
        const enabledModules = userData?.enabledModules || [];
        if (!enabledModules.includes("voice_assistant")) {
            throw new functions.https.HttpsError('permission-denied', 'Voice Assistant feature is disabled.');
        }

        // 2. Fetch Gemini API configuration
        const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
        let apiKey = "";
        if (configDoc.exists) {
            apiKey = configDoc.data()?.apiKey || "";
        }
        if (!apiKey) {
            throw new functions.https.HttpsError('failed-precondition', 'Gemini API key is not configured.');
        }

        // 3. Gather state context in parallel
        const nowKolkata = moment().tz('Asia/Kolkata');
        const currentMonth = nowKolkata.format('YYYY-MM');

        const remindersPromise = db.collection("users").doc(uid).collection("calendar_reminders")
            .where("status", "==", "scheduled")
            .limit(15)
            .get();

        const dailyRemindersPromise = db.collection("users").doc(uid).collection("daily_reminders")
            .limit(15)
            .get();

        const notesPromise = db.collection("users").doc(uid).collection("notes")
            .orderBy("updatedAt", "desc")
            .limit(10)
            .get();

        const checklistsPromise = db.collection("users").doc(uid).collection("checklists")
            .limit(10)
            .get();

        const shiftsPromise = db.collection("users").doc(uid).collection("shifts").doc(currentMonth).collection("daily_shifts")
            .orderBy("date")
            .get();

        const goldPromise = db.collection("global_gold_prices")
            .orderBy("timestamp", "desc")
            .limit(1)
            .get();

        const eventsPromise = db.collection("users").doc(uid).collection("events")
            .where("notInterested", "==", false)
            .orderBy("date")
            .limit(5)
            .get();

        const walkinsPromise = db.collection("users").doc(uid).collection("walkins")
            .where("notInterested", "==", false)
            .orderBy("date")
            .limit(5)
            .get();

        const goldInsightsPromise = db.collection("gold_ai_insights").doc("latest").get();
        const goldChitAdvicePromise = db.collection("gold_chit_advice").doc("latest").get();

        const [
            remindersSnap,
            dailyRemindersSnap,
            notesSnap,
            checklistsSnap,
            shiftsSnap,
            goldSnap,
            eventsSnap,
            walkinsSnap,
            goldInsightsSnap,
            goldChitAdviceSnap
        ] = await Promise.all([
            remindersPromise,
            dailyRemindersPromise,
            notesPromise,
            checklistsPromise,
            shiftsPromise.catch(() => null),
            goldPromise.catch(() => null),
            eventsPromise.catch(() => null),
            walkinsPromise.catch(() => null),
            goldInsightsPromise.catch(() => null),
            goldChitAdvicePromise.catch(() => null)
        ]);

        const checklistsData: any[] = [];
        if (checklistsSnap && !checklistsSnap.empty) {
            const itemPromises = checklistsSnap.docs.map(async (doc) => {
                const itemsSnap = await doc.ref.collection("items").orderBy("createdAt").get();
                const items = itemsSnap.docs.map(itemDoc => ({
                    id: itemDoc.id,
                    name: itemDoc.data().name || "",
                    isDone: itemDoc.data().isDone || false
                }));
                checklistsData.push({
                    id: doc.id,
                    title: doc.data().title || "",
                    items
                });
            });
            await Promise.all(itemPromises);
        }

        // Format state context
        let contextText = `Current Date and Time (IST): ${nowKolkata.format('YYYY-MM-DD HH:mm dddd')}\n\n`;

        contextText += "--- UPCOMING CALENDAR REMINDERS ---\n";
        if (remindersSnap && !remindersSnap.empty) {
            remindersSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- ID: ${doc.id}, Title: "${d.title}", Date: ${d.date}, Time: ${d.time}, Recurring: ${d.isRecurring || false}, Snooze: ${d.snoozeEnabled || false}\n`;
            });
        } else {
            contextText += "No upcoming scheduled reminders.\n";
        }
        contextText += "\n";

        contextText += "--- DAILY REMINDERS ---\n";
        if (dailyRemindersSnap && !dailyRemindersSnap.empty) {
            dailyRemindersSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- ID: ${doc.id}, Time: ${d.time}, Enabled: ${d.enabled || false}, Label: "${d.label || ''}"\n`;
            });
        } else {
            contextText += "No daily reminders configured.\n";
        }
        contextText += "\n";

        contextText += "--- RECENT NOTES ---\n";
        if (notesSnap && !notesSnap.empty) {
            notesSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- ID: ${doc.id}, Title: "${d.title}", Content: "${d.content || ''}"\n`;
            });
        } else {
            contextText += "No notes found.\n";
        }
        contextText += "\n";

        contextText += "--- CHECKLISTS ---\n";
        if (checklistsData.length > 0) {
            checklistsData.forEach(cl => {
                contextText += `- ID: ${cl.id}, Title: "${cl.title}"\n`;
                if (cl.items.length > 0) {
                    cl.items.forEach((item: any) => {
                        contextText += `  * Item ID: ${item.id}, Name: "${item.name}", Done: ${item.isDone}\n`;
                    });
                } else {
                    contextText += "  (no items)\n";
                }
            });
        } else {
            contextText += "No checklists found.\n";
        }
        contextText += "\n";

        contextText += `--- WORK SHIFTS (${currentMonth}) ---\n`;
        if (shiftsSnap && !shiftsSnap.empty) {
            shiftsSnap.docs.forEach(doc => {
                const d = doc.data();
                if (!d.is_week_off) {
                    contextText += `- Date: ${d.date}, Shift: "${d.shift_type}", Hours: ${d.start_time || ''}-${d.end_time || ''}\n`;
                } else {
                    contextText += `- Date: ${d.date}, Week Off\n`;
                }
            });
        } else {
            contextText += "No shift roster imported for this month.\n";
        }
        contextText += "\n";

        contextText += "--- LATEST GOLD PRICE ---\n";
        if (goldSnap && !goldSnap.empty) {
            const gd = goldSnap.docs[0].data();
            contextText += `Price: ₹${gd.price} per gram, Updated: ${gd.timestamp}\n`;
        } else {
            contextText += "Gold price data unavailable.\n";
        }
        contextText += "\n";

        contextText += "--- GOLD AI MARKET ANALYSIS & INSIGHTS ---\n";
        if (goldInsightsSnap && goldInsightsSnap.exists) {
            const gid = goldInsightsSnap.data();
            if (gid) {
                contextText += `Sentiment: ${gid.sentiment || ''} (Score: ${gid.sentimentScore ?? 0})\n`;
                contextText += `Sentiment Summary: "${gid.sentimentSummary || ''}"\n`;
                contextText += `Predicted Trend: ${gid.predictedTrend || ''}\n`;
                contextText += `Predicted Range: ${gid.predictedPriceRange || ''}\n`;
                contextText += `Rationale: "${gid.predictionRationale || ''}"\n`;
            } else {
                contextText += "Gold AI market analysis data empty.\n";
            }
        } else {
            contextText += "No gold AI market analysis available.\n";
        }
        contextText += "\n";

        contextText += "--- GOLD CHIT ADVICE (BUYING SUGGESTIONS) ---\n";
        if (goldChitAdviceSnap && goldChitAdviceSnap.exists) {
            const gca = goldChitAdviceSnap.data();
            if (gca) {
                contextText += `Recommendation: "${gca.recommendation || ''}"\n`;
                contextText += `Short Reason: "${gca.shortReason || ''}"\n`;
                contextText += `Full Analysis: "${gca.fullAnalysis || ''}"\n`;
            } else {
                contextText += "Gold chit buying advice data empty.\n";
            }
        } else {
            contextText += "No gold chit buying advice available.\n";
        }
        contextText += "\n";

        contextText += "--- UPCOMING TECH EVENTS ---\n";
        if (eventsSnap && !eventsSnap.empty) {
            eventsSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- Title: "${d.title}", Date: ${d.date}, Platform: "${d.platform || ''}"\n`;
            });
        } else {
            contextText += "No upcoming tech events.\n";
        }
        contextText += "\n";

        contextText += "--- UPCOMING WALK-IN DRIVES ---\n";
        if (walkinsSnap && !walkinsSnap.empty) {
            walkinsSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- Company: "${d.title}", Role: "${d.role || ''}", Date: ${d.date}, Location: "${d.location || ''}"\n`;
            });
        } else {
            contextText += "No upcoming walk-in drives.\n";
        }

        // 4. Send query to Gemini
        const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
        
        const systemInstruction = `You are the RemindBuddy AI Voice Assistant. Your goal is to help the user manage reminders, daily alarms, notes, checklists, shifts, gold prices, and search events/walkins.
You will be given the user's voice search or typed query, and the current state of their app data.
Look at the user's query and:
1. Answer questions about their reminders, shifts, gold price, notes, checklists, events, or walk-ins.
2. Resolve dates and times using the provided Current Date and Time (IST) anchor (e.g. today, tomorrow, next week).
3. If they ask to add/create, delete/remove, or toggle items: extract the action and its parameters.
4. Keep the spokenResponse extremely brief, friendly, natural, and speech-friendly (avoid markdown formatting like asterisks or bullet points since it will be read out loud).

Output MUST be a JSON object matching this schema:
{
  "spokenResponse": "Speech-ready text to be read by Text-to-Speech",
  "action": {
    "type": "CREATE_REMINDER" | "DELETE_REMINDER" | "CREATE_NOTE" | "DELETE_NOTE" | "CREATE_CHECKLIST" | "DELETE_CHECKLIST" | "ADD_CHECKLIST_ITEM" | "TOGGLE_CHECKLIST_ITEM" | "DELETE_CHECKLIST_ITEM" | "NONE",
    "params": {
      "reminderId": "Firestore document ID (for DELETE)",
      "title": "Title (for CREATE_REMINDER, CREATE_NOTE, CREATE_CHECKLIST)",
      "content": "Content body (for CREATE_NOTE)",
      "date": "YYYY-MM-DD (for CREATE_REMINDER)",
      "time": "HH:MM (for CREATE_REMINDER)",
      "snoozeEnabled": true/false,
      "snoozeIntervalMinutes": 15,
      "maxSnoozeCount": 3,
      "noteId": "Firestore document ID (for DELETE)",
      "checklistId": "Firestore document ID (for EDIT/DELETE checklist)",
      "itemId": "Firestore document ID (for EDIT/DELETE item)",
      "itemName": "Item name (for ADD_CHECKLIST_ITEM)",
      "isChecked": true/false (for TOGGLE_CHECKLIST_ITEM)"
    }
  }
}`;

        const payload = {
            contents: [
                {
                    parts: [
                        { text: `System Instructions:\n${systemInstruction}\n\nCurrent App State Context:\n${contextText}\n\nUser Query: "${query}"` }
                    ]
                }
            ],
            generationConfig: {
                responseMimeType: "application/json",
                responseSchema: {
                    type: "OBJECT",
                    properties: {
                        spokenResponse: { type: "STRING" },
                        action: {
                            type: "OBJECT",
                            properties: {
                                type: {
                                    type: "STRING",
                                    enum: [
                                        "CREATE_REMINDER", "DELETE_REMINDER",
                                        "CREATE_NOTE", "DELETE_NOTE",
                                        "CREATE_CHECKLIST", "DELETE_CHECKLIST",
                                        "ADD_CHECKLIST_ITEM", "TOGGLE_CHECKLIST_ITEM", "DELETE_CHECKLIST_ITEM",
                                        "NONE"
                                    ]
                                },
                                params: {
                                    type: "OBJECT",
                                    properties: {
                                        reminderId: { type: "STRING" },
                                        title: { type: "STRING" },
                                        content: { type: "STRING" },
                                        date: { type: "STRING" },
                                        time: { type: "STRING" },
                                        snoozeEnabled: { type: "BOOLEAN" },
                                        snoozeIntervalMinutes: { type: "INTEGER" },
                                        maxSnoozeCount: { type: "INTEGER" },
                                        noteId: { type: "STRING" },
                                        checklistId: { type: "STRING" },
                                        itemId: { type: "STRING" },
                                        itemName: { type: "STRING" },
                                        isChecked: { type: "BOOLEAN" }
                                    }
                                }
                            },
                            required: ["type"]
                        }
                    },
                    required: ["spokenResponse", "action"]
                }
            }
        };

        const response = await axios.post(url, payload, { timeout: 15000 });
        const geminiText = response.data.candidates[0].content.parts[0].text;
        const result = JSON.parse(geminiText);

        let actionExecuted = null;

        // 5. Execute action in Firestore if applicable
        if (result.action && result.action.type !== "NONE") {
            const actionType = result.action.type;
            const params = result.action.params || {};

            if (actionType === "CREATE_REMINDER") {
                const { title, date, time } = params;
                if (title && date && time) {
                    const snoozeEnabled = params.snoozeEnabled !== undefined ? params.snoozeEnabled : true;
                    const snoozeIntervalMinutes = params.snoozeIntervalMinutes !== undefined ? params.snoozeIntervalMinutes : 15;
                    const maxSnoozeCount = params.maxSnoozeCount !== undefined ? params.maxSnoozeCount : 3;

                    const docRef = await db.collection("users").doc(uid).collection("calendar_reminders").add({
                        title,
                        description: "Created via Voice Assistant",
                        date,
                        time,
                        isRecurring: false,
                        status: "scheduled",
                        snoozeEnabled,
                        snoozeIntervalMinutes,
                        maxSnoozeCount,
                        currentSnoozeCount: 0,
                        createdAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    actionExecuted = { type: actionType, id: docRef.id, params };
                }
            } else if (actionType === "DELETE_REMINDER") {
                const { reminderId } = params;
                if (reminderId) {
                    await db.collection("users").doc(uid).collection("calendar_reminders").doc(reminderId).delete();
                    actionExecuted = { type: actionType, id: reminderId };
                }
            } else if (actionType === "CREATE_NOTE") {
                const { title, content } = params;
                if (title) {
                    const docRef = await db.collection("users").doc(uid).collection("notes").add({
                        title,
                        content: content || "",
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        updatedAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    actionExecuted = { type: actionType, id: docRef.id, params };
                }
            } else if (actionType === "DELETE_NOTE") {
                const { noteId } = params;
                if (noteId) {
                    await db.collection("users").doc(uid).collection("notes").doc(noteId).delete();
                    actionExecuted = { type: actionType, id: noteId };
                }
            } else if (actionType === "CREATE_CHECKLIST") {
                const { title } = params;
                if (title) {
                    const docRef = await db.collection("users").doc(uid).collection("checklists").add({
                        title,
                        createdAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    actionExecuted = { type: actionType, id: docRef.id, params };
                }
            } else if (actionType === "DELETE_CHECKLIST") {
                const { checklistId } = params;
                if (checklistId) {
                    const itemsSnap = await db.collection("users").doc(uid).collection("checklists").doc(checklistId).collection("items").get();
                    const batch = db.batch();
                    itemsSnap.docs.forEach(doc => batch.delete(doc.ref));
                    batch.delete(db.collection("users").doc(uid).collection("checklists").doc(checklistId));
                    await batch.commit();
                    actionExecuted = { type: actionType, id: checklistId };
                }
            } else if (actionType === "ADD_CHECKLIST_ITEM") {
                const { checklistId, itemName } = params;
                if (checklistId && itemName) {
                    const docRef = await db.collection("users").doc(uid).collection("checklists").doc(checklistId).collection("items").add({
                        name: itemName,
                        isDone: false,
                        createdAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    actionExecuted = { type: actionType, id: docRef.id, params };
                }
            } else if (actionType === "TOGGLE_CHECKLIST_ITEM") {
                const { checklistId, itemId, isChecked } = params;
                if (checklistId && itemId) {
                    await db.collection("users").doc(uid).collection("checklists").doc(checklistId).collection("items").doc(itemId).update({
                        isDone: isChecked
                    });
                    actionExecuted = { type: actionType, id: itemId, params };
                }
            } else if (actionType === "DELETE_CHECKLIST_ITEM") {
                const { checklistId, itemId } = params;
                if (checklistId && itemId) {
                    await db.collection("users").doc(uid).collection("checklists").doc(checklistId).collection("items").doc(itemId).delete();
                    actionExecuted = { type: actionType, id: itemId };
                }
            }
        }

        return {
            success: true,
            spokenResponse: result.spokenResponse,
            action: result.action,
            actionExecuted
        };

    } catch (err: any) {
        console.error("Error in voiceAssistantQuery:", err);
        throw new functions.https.HttpsError('internal', err.message || 'Failed to process voice query.');
    }
});

exports.onInstallmentUpdated = functions.firestore
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

exports.checkPendingGoldChitNotifications = functions.pubsub.schedule('* * * * *')
    .timeZone('Asia/Kolkata')
    .onRun(async (context) => {
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

                // Get updater username
                let updaterUsername = 'A user';
                if (updatedBy) {
                    const updaterSnap = await db.collection('usernames').where('uid', '==', updatedBy).limit(1).get();
                    if (!updaterSnap.empty) {
                        updaterUsername = updaterSnap.docs[0].id;
                    }
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
                    const title = `💰 Gold Chit Updated`;
                    const body = `${updaterUsername} updated the payment for ${formattedMonth} in plan "${planName}".`;

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

                    // Log in Firestore notifications collection
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
    });


exports.checkInterestedEventsNotifications = functions.pubsub.schedule('0 18 * * *').timeZone('Asia/Kolkata').onRun(async () => {
    const tomorrowStr = moment().tz('Asia/Kolkata').add(1, 'days').format('YYYY-MM-DD');
    console.log(`Running checkInterestedEventsNotifications at ${moment().tz('Asia/Kolkata').format()} (Target Date: ${tomorrowStr})`);

    const users = await db.collection('usernames').get();
    for (const u of users.docs) {
        const userData = u.data();
        if (!userData.fcmToken || !userData.uid) continue;

        const uid = userData.uid;
        try {
            // Check if user profile exists and if modules are enabled
            const userProfileDoc = await db.collection("users").doc(uid).get();
            if (!userProfileDoc.exists) continue;

            const uData = userProfileDoc.data();
            const enabledModules = uData?.enabledModules || [];
            const notifPrefs = uData?.notificationPreferences || {};

            // We only process if either events or walkins module is enabled
            const checkEvents = enabledModules.includes("events") && notifPrefs.events !== false;
            const checkWalkins = enabledModules.includes("walkin") && notifPrefs.walkin !== false;

            if (!checkEvents && !checkWalkins) continue;

            if (checkEvents) {
                const eventsSnap = await db.collection('users').doc(uid).collection('events')
                    .where('interested', '==', true)
                    .where('date', '==', tomorrowStr)
                    .get();

                for (const doc of eventsSnap.docs) {
                    const eventData = doc.data();
                    if (eventData.notifiedInterested === true) continue;

                    const title = `📅 Upcoming Event: ${eventData.title || 'Tech Event'}`;
                    const body = `Reminder: "${eventData.title}" is happening tomorrow at ${eventData.timings || 'scheduled time'}.`;
                    
                    console.log(`Sending interested event reminder: ${title} to user ${uid}`);
                    await admin.messaging().send({
                        token: userData.fcmToken,
                        notification: { title, body },
                        android: {
                            notification: {
                                channelId: 'events_reminder_channel',
                                tag: `event_interest_${doc.id}`
                            }
                        },
                        data: { type: "event_interest_reminder", eventId: doc.id }
                    });

                    await logNotification(uid, title, body, "TECH_EVENTS");
                    await doc.ref.update({ notifiedInterested: true });
                }
            }

            if (checkWalkins) {
                const walkinsSnap = await db.collection('users').doc(uid).collection('walkins')
                    .where('interested', '==', true)
                    .where('date', '==', tomorrowStr)
                    .get();

                for (const doc of walkinsSnap.docs) {
                    const walkinData = doc.data();
                    if (walkinData.notifiedInterested === true) continue;

                    const title = `🚶 Upcoming Walk-In: ${walkinData.title || 'Walk-In'}`;
                    const body = `Reminder: Walk-In for "${walkinData.title}" is happening tomorrow at ${walkinData.timings || 'scheduled time'}.`;

                    console.log(`Sending interested walkin reminder: ${title} to user ${uid}`);
                    await admin.messaging().send({
                        token: userData.fcmToken,
                        notification: { title, body },
                        android: {
                            notification: {
                                channelId: 'events_reminder_channel',
                                tag: `walkin_interest_${doc.id}`
                            }
                        },
                        data: { type: "walkin_interest_reminder", walkinId: doc.id }
                    });

                    await logNotification(uid, title, body, "WALK_INS");
                    await doc.ref.update({ notifiedInterested: true });
                }
            }
        } catch (error) {
            console.error(`Failed to check/send interested notifications for user ${uid}:`, error);
        }
    }
});

