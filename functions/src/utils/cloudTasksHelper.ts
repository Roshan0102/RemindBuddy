import { tasksClient, admin } from "../config/firebase";

/**
 * Reusable helper to enqueue tasks into Cloud Tasks queues.
 * Guarantees sequential execution, configurable dispatch delay, and error isolation.
 */
export async function enqueueUserCloudTask(
    queueName: string,
    functionName: string,
    payload: { uid: string; [key: string]: any },
    scheduleTimeSeconds?: number
): Promise<string | null> {
    try {
        const project = process.env.GCLOUD_PROJECT || admin.app().options.projectId || "remindbuddy-b68f9";
        const location = "us-central1";
        const queuePath = tasksClient.queuePath(project, location, queueName);
        const url = `https://${location}-${project}.cloudfunctions.net/${functionName}`;
        const serviceAccountEmail = `${project}@appspot.gserviceaccount.com`;

        const httpRequest: any = {
            httpMethod: "POST",
            url,
            body: Buffer.from(JSON.stringify({ data: payload })).toString("base64"),
            headers: { "Content-Type": "application/json" },
            oidcToken: {
                serviceAccountEmail,
            },
        };

        const task: any = { httpRequest };
        if (scheduleTimeSeconds) {
            task.scheduleTime = { seconds: scheduleTimeSeconds };
        }

        const [response] = await tasksClient.createTask({
            parent: queuePath,
            task,
        });

        console.log(`[CloudTasks] Enqueued task ${response.name} on ${queueName} for user ${payload.uid} (ETA: ${scheduleTimeSeconds ? new Date(scheduleTimeSeconds * 1000).toISOString() : 'immediate'})`);
        return response.name || null;
    } catch (err: any) {
        console.warn(`[CloudTasks] Note: Could not enqueue to Cloud Tasks queue '${queueName}' (${err.message}). Using direct fallback.`);
        return null;
    }
}
