"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.logFeatureExecution = logFeatureExecution;
const firebase_1 = require("../config/firebase");
/**
 * Logs the execution of an automated or manual run to Firestore:
 * users/{uid}/feature_logs/{logId}
 */
async function logFeatureExecution(uid, params) {
    try {
        const timestamp = firebase_1.admin.firestore.FieldValue.serverTimestamp();
        await firebase_1.db.collection("users").doc(uid).collection("feature_logs").add({
            feature: params.feature,
            featureTitle: params.featureTitle,
            status: params.status,
            count: params.count,
            message: params.message,
            scheduledSlot: params.scheduledSlot || (params.isManual ? "Manual Run" : "Scheduled Run"),
            details: params.details || [],
            isManual: params.isManual || false,
            timestamp,
        });
        console.log(`[featureLogger] Logged ${params.feature} (${params.status}, count: ${params.count}) for user ${uid}`);
    }
    catch (error) {
        console.error(`[featureLogger] Failed to write feature log for user ${uid}:`, error);
    }
}
//# sourceMappingURL=featureLogger.js.map