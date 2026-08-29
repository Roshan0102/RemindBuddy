"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.logNotification = logNotification;
const firebase_1 = require("../config/firebase");
async function logNotification(uid, title, body, type) {
    try {
        const timestamp = firebase_1.admin.firestore.FieldValue.serverTimestamp();
        await firebase_1.db.collection("users").doc(uid).collection("notifications").add({
            title,
            body,
            timestamp,
            type
        });
        // Cleanup notifications older than 24 hours
        const cutoff = new Date();
        cutoff.setHours(cutoff.getHours() - 24);
        const oldNotifications = await firebase_1.db.collection("users")
            .doc(uid)
            .collection("notifications")
            .where("timestamp", "<", cutoff)
            .get();
        if (!oldNotifications.empty) {
            const batch = firebase_1.db.batch();
            oldNotifications.docs.forEach(doc => {
                batch.delete(doc.ref);
            });
            await batch.commit();
            console.log(`Cleaned up ${oldNotifications.size} expired notifications for user ${uid}`);
        }
    }
    catch (error) {
        console.error("Failed to log/cleanup notification:", error);
    }
}
//# sourceMappingURL=logger.js.map