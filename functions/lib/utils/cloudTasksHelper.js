"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.enqueueUserCloudTask = enqueueUserCloudTask;
const firebase_1 = require("../config/firebase");
// In-memory sliding window cache to prevent duplicate / storm enqueues
const recentTaskDispatches = new Map();
/**
 * Reusable helper to enqueue tasks into Cloud Tasks queues.
 * Guarantees sequential execution, configurable dispatch delay, error isolation,
 * and built-in rate-limiting/storm prevention.
 */
async function enqueueUserCloudTask(queueName, functionName, payload, scheduleTimeSeconds, options) {
    var _a, _b;
    try {
        const uid = payload.uid || "global";
        const minIntervalSeconds = (_a = options === null || options === void 0 ? void 0 : options.minIntervalSeconds) !== null && _a !== void 0 ? _a : 60; // 1-minute minimum cooldown by default
        const now = Date.now();
        const dispatchKey = `${queueName}:${uid}:${functionName}`;
        // Periodic cache eviction (keep map clean)
        if (recentTaskDispatches.size > 200) {
            const cutoff = now - 600000; // 10 minutes
            for (const [key, ts] of recentTaskDispatches.entries()) {
                if (ts < cutoff)
                    recentTaskDispatches.delete(key);
            }
        }
        // 1. In-memory Rate-Limiter Guard
        if (minIntervalSeconds > 0) {
            const lastDispatched = recentTaskDispatches.get(dispatchKey);
            if (lastDispatched && (now - lastDispatched) < (minIntervalSeconds * 1000)) {
                const elapsedSec = Math.round((now - lastDispatched) / 1000);
                console.warn(`[CloudTasks] STORM GUARD BLOCKED: Task for '${queueName}' (${functionName}) for user '${uid}' was already enqueued ${elapsedSec}s ago (min interval: ${minIntervalSeconds}s). Dropping duplicate dispatch.`);
                return null;
            }
        }
        const project = process.env.GCLOUD_PROJECT || firebase_1.admin.app().options.projectId || "remindbuddy-b68f9";
        const location = "us-central1";
        const queuePath = firebase_1.tasksClient.queuePath(project, location, queueName);
        const url = `https://${location}-${project}.cloudfunctions.net/${functionName}`;
        const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;
        const httpRequest = {
            httpMethod: "POST",
            url,
            body: Buffer.from(JSON.stringify({ data: payload })).toString("base64"),
            headers: { "Content-Type": "application/json" },
            oidcToken: {
                serviceAccountEmail,
            },
        };
        const task = { httpRequest };
        if (scheduleTimeSeconds) {
            task.scheduleTime = { seconds: scheduleTimeSeconds };
        }
        // 2. Deterministic Task Naming (Native GCP Cloud Tasks Deduplication Guard)
        // If a task with the same name was already created, GCP Cloud Tasks natively rejects duplicates with ALREADY_EXISTS (HTTP 409)
        const windowMinute = Math.floor(now / 60000); // 1-minute time bucket
        const safeTaskId = (options === null || options === void 0 ? void 0 : options.customTaskId)
            ? options.customTaskId.replace(/[^a-zA-Z0-9_-]/g, "_")
            : `${queueName.slice(0, 15)}_${uid.slice(0, 12)}_${windowMinute}`;
        task.name = firebase_1.tasksClient.taskPath(project, location, queueName, safeTaskId);
        const [response] = await firebase_1.tasksClient.createTask({
            parent: queuePath,
            task,
        });
        // Record successful dispatch timestamp for rate limiter
        recentTaskDispatches.set(dispatchKey, now);
        console.log(`[CloudTasks] Enqueued task ${response.name} on ${queueName} for user ${uid} (ETA: ${scheduleTimeSeconds ? new Date(scheduleTimeSeconds * 1000).toISOString() : 'immediate'})`);
        return response.name || null;
    }
    catch (err) {
        // Native GCP ALREADY_EXISTS (code 6) means Cloud Tasks deduplication caught a duplicate within the deduplication window!
        if (err.code === 6 || ((_b = err.message) === null || _b === void 0 ? void 0 : _b.includes("ALREADY_EXISTS"))) {
            console.log(`[CloudTasks] NATIVE DEDUPLICATION: Duplicate task for '${queueName}' (${functionName}) already exists in queue. Safely ignored.`);
            return null;
        }
        console.warn(`[CloudTasks] Note: Could not enqueue to Cloud Tasks queue '${queueName}' (${err.message}). Using direct fallback.`);
        return null;
    }
}
//# sourceMappingURL=cloudTasksHelper.js.map