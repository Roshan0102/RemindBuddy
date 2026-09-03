"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onCalendarReminderCreated = exports.onCalendarReminderUpdated = exports.onCalendarReminderDeleted = exports.autoSnoozeReminderCheckTask = exports.processCalendarReminderTask = void 0;
const functions = require("firebase-functions");
const moment = require("moment-timezone");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
/**
 * Task Handler: Called by Cloud Task queue.
 */
exports.processCalendarReminderTask = functions.tasks
    .taskQueue({
    retryConfig: { maxAttempts: 3 },
    rateLimits: { maxConcurrentDispatches: 10 },
})
    .onDispatch(async (rawPayload, context) => {
    var _a;
    const payload = (rawPayload && typeof rawPayload === 'object' && rawPayload.data) ? rawPayload.data : rawPayload;
    const uid = payload === null || payload === void 0 ? void 0 : payload.uid;
    const reminderId = payload === null || payload === void 0 ? void 0 : payload.reminderId;
    const title = payload === null || payload === void 0 ? void 0 : payload.title;
    const body = payload === null || payload === void 0 ? void 0 : payload.body;
    console.log(`[processCalendarReminderTask] Executing task for reminder ${reminderId} (user: ${uid})`);
    try {
        if (!uid || !reminderId) {
            console.error("[processCalendarReminderTask] Missing uid or reminderId in payload:", rawPayload);
            return;
        }
        const reminderRef = firebase_1.db.collection("users").doc(uid).collection("calendar_reminders").doc(reminderId);
        const reminderDoc = await reminderRef.get();
        if (!reminderDoc.exists) {
            console.warn(`[processCalendarReminderTask] Reminder ${reminderId} does not exist for user ${uid}.`);
            return;
        }
        const userProfileDoc = await firebase_1.db.collection("users").doc(uid).get();
        let isEnabled = true;
        if (userProfileDoc.exists) {
            const uData = userProfileDoc.data();
            const enabledModules = (uData === null || uData === void 0 ? void 0 : uData.enabledModules) || [];
            const notifPrefs = (uData === null || uData === void 0 ? void 0 : uData.notificationPreferences) || {};
            if (!enabledModules.includes("reminders") || notifPrefs.calendar_reminders === false) {
                isEnabled = false;
            }
        }
        const rData = reminderDoc.data();
        const snoozeEnabled = rData ? rData.snoozeEnabled === true : false;
        if (isEnabled) {
            let token = "";
            const userDoc = await firebase_1.db.collection("usernames").where("uid", "==", uid).limit(1).get();
            if (!userDoc.empty) {
                token = userDoc.docs[0].data().fcmToken;
            }
            if (!token && userProfileDoc.exists) {
                token = (_a = userProfileDoc.data()) === null || _a === void 0 ? void 0 : _a.fcmToken;
            }
            if (token) {
                const message = {
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
                        snoozeIntervalMinutes: String((rData === null || rData === void 0 ? void 0 : rData.snoozeIntervalMinutes) || 15),
                        maxSnoozeCount: String((rData === null || rData === void 0 ? void 0 : rData.maxSnoozeCount) || 3),
                        currentSnoozeCount: String((rData === null || rData === void 0 ? void 0 : rData.currentSnoozeCount) || 0),
                        uid: uid
                    }
                };
                await firebase_1.admin.messaging().send(message);
                await (0, logger_1.logNotification)(uid, title, body, "CALENDAR_REMINDER");
                console.log(`[processCalendarReminderTask] Successfully sent notification to user ${uid} for reminder ${reminderId}`);
            }
            else {
                console.warn(`[processCalendarReminderTask] No FCM token found for user ${uid}, cannot send push notification.`);
            }
        }
        else {
            console.log(`Skipping notification for calendar reminder ${reminderId} (user ${uid}): disabled.`);
        }
        const currentSnoozeCount = Number((rData === null || rData === void 0 ? void 0 : rData.currentSnoozeCount) || 0);
        const maxSnoozeCount = Number((rData === null || rData === void 0 ? void 0 : rData.maxSnoozeCount) || 3);
        const isLastNotification = snoozeEnabled && (currentSnoozeCount + 1 >= maxSnoozeCount);
        const updateData = {
            notifiedAt: firebase_1.admin.firestore.FieldValue.serverTimestamp()
        };
        if (!snoozeEnabled || isLastNotification) {
            const expireAt = new Date();
            expireAt.setDate(expireAt.getDate() + 30);
            updateData.status = "completed";
            updateData.expireAt = firebase_1.admin.firestore.Timestamp.fromDate(expireAt);
        }
        else {
            updateData.status = "notified";
        }
        await reminderRef.update(updateData);
        if ((rData === null || rData === void 0 ? void 0 : rData.pairedUid) && (rData === null || rData === void 0 ? void 0 : rData.pairedDocId) && (!snoozeEnabled || isLastNotification)) {
            try {
                await firebase_1.db.collection("users").doc(rData.pairedUid).collection("calendar_reminders").doc(rData.pairedDocId).update(updateData);
                console.log(`Updated paired reminder ${rData.pairedDocId} for user ${rData.pairedUid} on completion.`);
            }
            catch (pErr) {
                console.error("Error updating paired reminder on completion:", pErr);
            }
        }
        if (snoozeEnabled && !isLastNotification) {
            try {
                const project = process.env.GCLOUD_PROJECT || firebase_1.admin.app().options.projectId;
                const location = 'us-central1';
                const queue = 'autoSnoozeReminderCheckTask';
                const queuePath = firebase_1.tasksClient.queuePath(project, location, queue);
                const url = `https://${location}-${project}.cloudfunctions.net/autoSnoozeReminderCheckTask`;
                const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;
                const runTime = moment().tz('Asia/Kolkata').add(30, 'seconds');
                const checkRequest = {
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
                await firebase_1.tasksClient.createTask(checkRequest);
                console.log(`Enqueued autoSnooze check task for reminder ${reminderId} at ${runTime.format()}`);
            }
            catch (err) {
                console.error("Failed to enqueue autoSnooze check task:", err);
            }
        }
        // Reschedule recurring reminder
        if (rData && rData.isRecurring === true) {
            const remaining = rData.remainingOccurrences; // undefined, null, or a number
            // If remaining is explicitly defined, and is <= 1, we stop repeating!
            if (remaining !== undefined && remaining !== null && remaining <= 1) {
                console.log(`Recurring reminder sequence ended for user ${uid} (reminder ${reminderId}).`);
            }
            else {
                const recurrenceValue = rData.recurrenceValue || 1;
                const recurrenceUnit = rData.recurrenceUnit || "days";
                const currentScheduledMoment = moment.tz(`${rData.date} ${rData.time}`, "YYYY-MM-DD HH:mm", "Asia/Kolkata");
                if (currentScheduledMoment.isValid()) {
                    const nextMoment = currentScheduledMoment.clone();
                    if (recurrenceUnit === "days") {
                        nextMoment.add(recurrenceValue, "days");
                    }
                    else if (recurrenceUnit === "weeks") {
                        nextMoment.add(recurrenceValue, "weeks");
                    }
                    else if (recurrenceUnit === "months") {
                        nextMoment.add(recurrenceValue, "months");
                    }
                    else if (recurrenceUnit === "minutes") {
                        nextMoment.add(recurrenceValue, "minutes");
                    }
                    else if (recurrenceUnit === "hours") {
                        nextMoment.add(recurrenceValue, "hours");
                    }
                    else {
                        nextMoment.add(recurrenceValue, "days");
                    }
                    const nextDateStr = nextMoment.format("YYYY-MM-DD");
                    const nextTimeStr = nextMoment.format("HH:mm");
                    const nextRemaining = (remaining !== undefined && remaining !== null) ? (remaining - 1) : null;
                    const nextReminderData = {
                        title: rData.title,
                        description: rData.description,
                        date: nextDateStr,
                        time: nextTimeStr,
                        status: "pending",
                        createdAt: firebase_1.admin.firestore.FieldValue.serverTimestamp(),
                        isRecurring: true,
                        recurrenceValue: recurrenceValue,
                        recurrenceUnit: recurrenceUnit
                    };
                    if (nextRemaining !== null) {
                        nextReminderData.remainingOccurrences = nextRemaining;
                    }
                    await firebase_1.db.collection("users").doc(uid).collection("calendar_reminders").add(nextReminderData);
                    console.log(`Created next recurring reminder for user ${uid} on date ${nextDateStr} (every ${recurrenceValue} ${recurrenceUnit}, remaining: ${nextRemaining})`);
                }
            }
        }
    }
    catch (error) {
        console.error("Task execution failed:", error);
        throw error;
    }
});
exports.autoSnoozeReminderCheckTask = functions.tasks
    .taskQueue({
    retryConfig: { maxAttempts: 3 },
    rateLimits: { maxConcurrentDispatches: 10 },
})
    .onDispatch(async (rawPayload, context) => {
    const payload = (rawPayload && typeof rawPayload === 'object' && rawPayload.data) ? rawPayload.data : rawPayload;
    const uid = payload === null || payload === void 0 ? void 0 : payload.uid;
    const reminderId = payload === null || payload === void 0 ? void 0 : payload.reminderId;
    console.log(`[autoSnoozeReminderCheckTask] Running auto-snooze check for reminder ${reminderId} (user: ${uid})`);
    try {
        if (!uid || !reminderId) {
            console.error("[autoSnoozeReminderCheckTask] Missing uid or reminderId in payload:", rawPayload);
            return;
        }
        const reminderRef = firebase_1.db.collection("users").doc(uid).collection("calendar_reminders").doc(reminderId);
        const reminderDoc = await reminderRef.get();
        if (!reminderDoc.exists)
            return;
        const rData = reminderDoc.data();
        if (!rData || rData.status !== "notified") {
            console.log(`Auto-snooze check: Reminder ${reminderId} is not in notified status (current status: ${rData === null || rData === void 0 ? void 0 : rData.status}). Skipping.`);
            return;
        }
        console.log(`Auto-snooze check: User did not interact with reminder ${reminderId}. Auto-snoozing.`);
        const currentSnooze = Number(rData.currentSnoozeCount || 0);
        const maxSnooze = Number(rData.maxSnoozeCount || 3);
        const interval = Number(rData.snoozeIntervalMinutes || 15);
        if (currentSnooze + 1 < maxSnooze) {
            const nowKolkata = moment().tz('Asia/Kolkata');
            const baseDate = rData.originalDate || rData.date;
            const baseTime = rData.originalTime || rData.time;
            const baseMoment = moment.tz(`${baseDate} ${baseTime}`, "YYYY-MM-DD HH:mm", "Asia/Kolkata");
            let dateStr;
            let timeStr;
            if (baseMoment.isValid()) {
                const totalSnoozeMinutes = (currentSnooze + 1) * interval;
                let nextTime = baseMoment.clone().add(totalSnoozeMinutes, 'minutes');
                if (nextTime.isBefore(nowKolkata)) {
                    nextTime = nowKolkata.clone().add(interval, 'minutes');
                }
                dateStr = nextTime.format('YYYY-MM-DD');
                timeStr = nextTime.format('HH:mm');
            }
            else {
                const nextTime = nowKolkata.clone().add(interval, 'minutes');
                dateStr = nextTime.format('YYYY-MM-DD');
                timeStr = nextTime.format('HH:mm');
            }
            const updatePayload = {
                date: dateStr,
                time: timeStr,
                status: "pending",
                currentSnoozeCount: currentSnooze + 1
            };
            if (!rData.originalDate)
                updatePayload.originalDate = baseDate;
            if (!rData.originalTime)
                updatePayload.originalTime = baseTime;
            await reminderRef.update(updatePayload);
            console.log(`Auto-snoozed reminder ${reminderId} to ${dateStr} ${timeStr}. (Snooze count: ${currentSnooze + 1}/${maxSnooze})`);
        }
        else {
            const expireAt = new Date();
            expireAt.setDate(expireAt.getDate() + 30);
            const updates = {
                status: "completed",
                expireAt: firebase_1.admin.firestore.Timestamp.fromDate(expireAt)
            };
            await reminderRef.update(updates);
            if (rData.pairedUid && rData.pairedDocId) {
                try {
                    await firebase_1.db.collection("users").doc(rData.pairedUid).collection("calendar_reminders").doc(rData.pairedDocId).update(updates);
                    console.log(`Auto-snooze check: Updated paired reminder ${rData.pairedDocId} to completed.`);
                }
                catch (pErr) {
                    console.error("Error updating paired reminder on auto-snooze:", pErr);
                }
            }
            console.log(`Auto-snooze check: Max snooze reached for reminder ${reminderId}. Marked completed.`);
        }
    }
    catch (error) {
        console.error(`Auto-snooze check failed for ${reminderId}:`, error);
    }
});
exports.onCalendarReminderDeleted = functions.firestore
    .document('users/{uid}/calendar_reminders/{reminderId}')
    .onDelete(async (snapshot, context) => {
    const data = snapshot.data();
    if (!data)
        return;
    if (data.taskId && data.status === "scheduled") {
        try {
            await firebase_1.tasksClient.deleteTask({ name: data.taskId });
        }
        catch (error) {
            console.error("Failed to delete scheduled task:", error);
        }
    }
    // Delete paired reminder document for recipient/creator if present
    if (data.pairedUid && data.pairedDocId) {
        try {
            const pairedRef = firebase_1.db.collection('users').doc(data.pairedUid).collection('calendar_reminders').doc(data.pairedDocId);
            const pairedDoc = await pairedRef.get();
            if (pairedDoc.exists) {
                await pairedRef.delete();
                console.log(`Deleted paired reminder ${data.pairedDocId} for user ${data.pairedUid}`);
            }
        }
        catch (error) {
            console.error("Failed to delete paired reminder doc:", error);
        }
    }
});
exports.onCalendarReminderUpdated = functions.firestore
    .document('users/{uid}/calendar_reminders/{reminderId}')
    .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after)
        return;
    const { uid, reminderId } = context.params;
    // Sync status & completion changes to paired document if present
    if (after.pairedUid && after.pairedDocId) {
        if (before.status !== after.status || before.date !== after.date || before.time !== after.time || before.currentSnoozeCount !== after.currentSnoozeCount) {
            try {
                const pairedRef = firebase_1.db.collection('users').doc(after.pairedUid).collection('calendar_reminders').doc(after.pairedDocId);
                const pairedSnap = await pairedRef.get();
                if (pairedSnap.exists) {
                    const pData = pairedSnap.data();
                    if (pData && (pData.status !== after.status || pData.date !== after.date || pData.time !== after.time || pData.currentSnoozeCount !== after.currentSnoozeCount)) {
                        const syncPayload = {
                            status: after.status
                        };
                        if (after.expireAt)
                            syncPayload.expireAt = after.expireAt;
                        if (after.notifiedAt)
                            syncPayload.notifiedAt = after.notifiedAt;
                        if (after.date)
                            syncPayload.date = after.date;
                        if (after.time)
                            syncPayload.time = after.time;
                        if (after.currentSnoozeCount !== undefined)
                            syncPayload.currentSnoozeCount = after.currentSnoozeCount;
                        await pairedRef.update(syncPayload);
                        console.log(`Synced status '${after.status}' to paired document ${after.pairedDocId} for user ${after.pairedUid}`);
                    }
                }
            }
            catch (syncErr) {
                console.error("Failed syncing update to paired doc:", syncErr);
            }
        }
    }
    if (after.scheduledForUid && after.scheduledForUid !== uid) {
        console.log(`Reminder update for creator copy. Status is ${after.status}.`);
        if (after.status === "pending") {
            return change.after.ref.update({ status: "scheduled" });
        }
        return;
    }
    const changed = before.title !== after.title ||
        before.description !== after.description ||
        before.date !== after.date ||
        before.time !== after.time ||
        before.isRecurring !== after.isRecurring ||
        before.recurrenceValue !== after.recurrenceValue ||
        before.recurrenceUnit !== after.recurrenceUnit ||
        (before.status !== after.status && (after.status === "pending" || after.status === "scheduled"));
    if (!changed)
        return;
    if (before.taskId) {
        try {
            await firebase_1.tasksClient.deleteTask({ name: before.taskId });
            console.log(`Deleted task ${before.taskId} for rescheduling`);
        }
        catch (error) {
            console.error("Failed to delete old scheduled task:", error);
        }
    }
    const nowKolkata = moment().tz('Asia/Kolkata');
    const scheduledTime = moment.tz(`${after.date} ${after.time}`, "YYYY-MM-DD HH:mm", "Asia/Kolkata");
    if (!scheduledTime.isValid()) {
        console.log(`Rescheduled reminder ${reminderId} is invalid. Marking as expired.`);
        return change.after.ref.update({
            status: "expired",
            taskId: firebase_1.admin.firestore.FieldValue.delete(),
            scheduledAtTimestamp: firebase_1.admin.firestore.FieldValue.delete()
        });
    }
    let taskScheduleUnix = scheduledTime.unix();
    if (taskScheduleUnix <= nowKolkata.unix() + 5) {
        taskScheduleUnix = nowKolkata.unix() + 10;
    }
    try {
        const project = process.env.GCLOUD_PROJECT || firebase_1.admin.app().options.projectId;
        const location = 'us-central1';
        const queue = 'processCalendarReminderTask';
        const queuePath = firebase_1.tasksClient.queuePath(project, location, queue);
        const url = `https://${location}-${project}.cloudfunctions.net/processCalendarReminderTask`;
        const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;
        let notifTitle = after.title;
        if (after.scheduledByUsername) {
            notifTitle = `${after.title} (by @${after.scheduledByUsername})`;
        }
        const taskRequest = {
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
                    seconds: taskScheduleUnix,
                },
            },
        };
        const [response] = await firebase_1.tasksClient.createTask(taskRequest);
        const taskId = response.name;
        console.log(`Successfully rescheduled task ${taskId} for reminder ${reminderId} at unix ${taskScheduleUnix}`);
        return change.after.ref.update({
            status: "scheduled",
            taskId: taskId,
            scheduledAtTimestamp: new firebase_1.admin.firestore.Timestamp(taskScheduleUnix, 0)
        });
    }
    catch (error) {
        console.error("Rescheduling failed:", error);
        return change.after.ref.update({ status: "error", error: String(error) });
    }
});
exports.onCalendarReminderCreated = functions.firestore
    .document('users/{uid}/calendar_reminders/{reminderId}')
    .onCreate(async (snapshot, context) => {
    const data = snapshot.data();
    if (!data)
        return;
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
        const project = process.env.GCLOUD_PROJECT || firebase_1.admin.app().options.projectId;
        const location = 'us-central1';
        const queue = 'processCalendarReminderTask';
        const queuePath = firebase_1.tasksClient.queuePath(project, location, queue);
        const url = `https://${location}-${project}.cloudfunctions.net/processCalendarReminderTask`;
        const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;
        let notifTitle = data.title;
        if (data.scheduledByUsername) {
            notifTitle = `${data.title} (by @${data.scheduledByUsername})`;
        }
        const taskRequest = {
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
        const [response] = await firebase_1.tasksClient.createTask(taskRequest);
        const taskId = response.name;
        console.log(`Successfully enqueued task ${taskId} for reminder ${reminderId}`);
        return snapshot.ref.update({
            status: "scheduled",
            taskId: taskId,
            scheduledAtTimestamp: firebase_1.admin.firestore.Timestamp.fromMillis(scheduledTime.valueOf())
        });
    }
    catch (error) {
        console.error("Scheduling failed:", error);
        return snapshot.ref.update({ status: "error", error: String(error) });
    }
});
//# sourceMappingURL=calendarReminders.js.map