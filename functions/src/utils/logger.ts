import { admin, db } from "../config/firebase";

export async function logNotification(uid: string, title: string, body: string, type: string) {
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
