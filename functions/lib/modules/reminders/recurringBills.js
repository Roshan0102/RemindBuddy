"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.internalCheckRecurringBillNotifications = internalCheckRecurringBillNotifications;
const moment = require("moment-timezone");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
async function internalCheckRecurringBillNotifications() {
    try {
        const nowKolkata = moment().tz('Asia/Kolkata');
        const todayStr = nowKolkata.format('YYYY-MM-DD');
        const currentTimeStr = nowKolkata.format('HH:mm');
        const usersSnap = await firebase_1.db.collection("users").get();
        for (const userDoc of usersSnap.docs) {
            const uid = userDoc.id;
            const uData = userDoc.data() || {};
            const enabledModules = uData.enabledModules || [];
            const notifPrefs = uData.notificationPreferences || {};
            if (!enabledModules.includes("finance") || notifPrefs.finance === false || notifPrefs.finance_bills === false) {
                continue;
            }
            // Support both finance_bills and bills subcollections
            const [financeBillsSnap, legacyBillsSnap] = await Promise.all([
                userDoc.ref.collection("finance_bills").where("isActive", "==", true).get(),
                userDoc.ref.collection("bills").where("isActive", "==", true).get()
            ]);
            const allBillDocs = [...financeBillsSnap.docs, ...legacyBillsSnap.docs];
            if (allBillDocs.length === 0)
                continue;
            for (const billDoc of allBillDocs) {
                const bill = billDoc.data();
                if (!bill.dueDate)
                    continue;
                const dueMoment = moment(bill.dueDate.toDate ? bill.dueDate.toDate() : bill.dueDate).tz('Asia/Kolkata');
                const dueDateStr = dueMoment.format('YYYY-MM-DD');
                const notifications = bill.notifications || ['On the day at 9 AM'];
                for (const notifRule of notifications) {
                    let targetDateMoment = dueMoment.clone();
                    let notifTime = "09:00";
                    const timeMatch = notifRule.match(/at\s+(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?/i);
                    if (timeMatch) {
                        let h = parseInt(timeMatch[1], 10);
                        const m = timeMatch[2] ? parseInt(timeMatch[2], 10) : 0;
                        const ampm = timeMatch[3] ? timeMatch[3].toUpperCase() : null;
                        if (ampm === "PM" && h < 12)
                            h += 12;
                        if (ampm === "AM" && h === 12)
                            h = 0;
                        notifTime = `${h.toString().padStart(2, '0')}:${m.toString().padStart(2, '0')}`;
                    }
                    if (notifRule.includes("On the day")) {
                        targetDateMoment = dueMoment.clone();
                    }
                    else if (notifRule.includes("day before") || notifRule.includes("days before")) {
                        const daysMatch = notifRule.match(/(\d+)\s+days?\s+before/i);
                        const days = daysMatch ? parseInt(daysMatch[1], 10) : 1;
                        targetDateMoment = dueMoment.clone().subtract(days, 'days');
                    }
                    else if (notifRule.includes("week before") || notifRule.includes("weeks before")) {
                        const weeksMatch = notifRule.match(/(\d+)\s+weeks?\s+before/i);
                        const weeks = weeksMatch ? parseInt(weeksMatch[1], 10) : 1;
                        targetDateMoment = dueMoment.clone().subtract(weeks, 'weeks');
                    }
                    const targetDateStr = targetDateMoment.format('YYYY-MM-DD');
                    if (todayStr === targetDateStr && currentTimeStr === notifTime) {
                        const notifKey = `bill_notif_${billDoc.id}_${dueDateStr}_${notifRule.replace(/\s+/g, '_')}`;
                        const notifRef = firebase_1.db.collection("users").doc(uid).collection("notification_logs").doc(notifKey);
                        const notifDoc = await notifRef.get();
                        if (notifDoc.exists)
                            continue;
                        const userAccountDoc = await firebase_1.db.collection("usernames").where("uid", "==", uid).limit(1).get();
                        if (!userAccountDoc.empty) {
                            const token = userAccountDoc.docs[0].data().fcmToken;
                            if (token) {
                                const title = `Bill Due Reminder 🧾: ${bill.title}`;
                                const body = notifRule.includes("On the day")
                                    ? `Your bill for ${bill.title} (₹${bill.amount}) is due today!`
                                    : `Your bill for ${bill.title} (₹${bill.amount}) is due on ${dueMoment.format('MMM D, YYYY')}.`;
                                await firebase_1.admin.messaging().send({
                                    token,
                                    notification: { title, body },
                                    android: { notification: { channelId: "bill_reminder_channel" } },
                                    data: { type: "BILL_REMINDER", billId: billDoc.id }
                                });
                                await (0, logger_1.logNotification)(uid, title, body, "BILL_REMINDER");
                                await notifRef.set({ sentAt: firebase_1.admin.firestore.FieldValue.serverTimestamp() });
                                console.log(`Sent bill reminder notification for bill ${billDoc.id} to user ${uid}`);
                            }
                        }
                    }
                }
            }
        }
    }
    catch (err) {
        console.error("Error in internalCheckRecurringBillNotifications:", err);
    }
}
//# sourceMappingURL=recurringBills.js.map