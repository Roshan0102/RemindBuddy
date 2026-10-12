import { PubSub } from "@google-cloud/pubsub";

let pubsubClient: PubSub | null = null;

function getPubSubClient(): PubSub {
    if (!pubsubClient) {
        pubsubClient = new PubSub();
    }
    return pubsubClient;
}

/**
 * Publishes an asynchronous task message to a Pub/Sub topic for an individual user.
 * Each message triggers an isolated serverless function instance, guaranteeing
 * independent execution time, separate error handling, and zero scheduler timeout risk.
 * 
 * Topics are automatically provisioned by Google Cloud & Firebase upon function deployment.
 */
export async function publishUserPubSubMessage(
    topicName: string,
    payload: { uid: string; [key: string]: any }
): Promise<string | null> {
    try {
        const pubsub = getPubSubClient();
        const topic = pubsub.topic(topicName);
        const messageId = await topic.publishMessage({ json: payload });
        console.log(`[PubSub] Published message ${messageId} to topic '${topicName}' for user ${payload.uid}`);
        return messageId;
    } catch (err: any) {
        console.error(`[PubSub] Failed to publish message to topic '${topicName}' for user ${payload.uid}:`, err.message || err);
        return null;
    }
}
