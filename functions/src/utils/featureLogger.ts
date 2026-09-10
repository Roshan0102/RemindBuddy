import { admin, db } from "../config/firebase";

export type FeatureLogType = 'auto_apply' | 'cold_outreach' | 'tech_events' | 'walkin_drives';
export type FeatureLogStatus = 'success' | 'no_results' | 'skipped' | 'error';

export interface FeatureLogParams {
    feature: FeatureLogType;
    featureTitle: string;
    status: FeatureLogStatus;
    count: number;
    message: string;
    scheduledSlot?: string;
    details?: string[];
    isManual?: boolean;
}

/**
 * Logs the execution of an automated or manual run to Firestore:
 * users/{uid}/feature_logs/{logId}
 */
export async function logFeatureExecution(uid: string, params: FeatureLogParams): Promise<void> {
    try {
        const timestamp = admin.firestore.FieldValue.serverTimestamp();
        await db.collection("users").doc(uid).collection("feature_logs").add({
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
    } catch (error) {
        console.error(`[featureLogger] Failed to write feature log for user ${uid}:`, error);
    }
}
