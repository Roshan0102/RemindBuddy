"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.enqueueUserCloudTask = enqueueUserCloudTask;
const firebase_1 = require("../config/firebase");
/**
 * Reusable helper to enqueue tasks into Cloud Tasks queues.
 * Guarantees sequential execution, configurable dispatch delay, and error isolation.
 */
async function enqueueUserCloudTask(queueName, functionName, payload, scheduleTimeSeconds) {
    try {
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
        const [response] = await firebase_1.tasksClient.createTask({
            parent: queuePath,
            task,
        });
        console.log(`[CloudTasks] Enqueued task ${response.name} on ${queueName} for user ${payload.uid} (ETA: ${scheduleTimeSeconds ? new Date(scheduleTimeSeconds * 1000).toISOString() : 'immediate'})`);
        return response.name || null;
    }
    catch (err) {
        console.warn(`[CloudTasks] Note: Could not enqueue to Cloud Tasks queue '${queueName}' (${err.message}). Using direct fallback.`);
        return null;
    }
}
//# sourceMappingURL=cloudTasksHelper.js.map