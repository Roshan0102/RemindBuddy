"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.publishUserPubSubMessage = publishUserPubSubMessage;
const pubsub_1 = require("@google-cloud/pubsub");
let pubsubClient = null;
function getPubSubClient() {
    if (!pubsubClient) {
        pubsubClient = new pubsub_1.PubSub();
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
async function publishUserPubSubMessage(topicName, payload) {
    try {
        const pubsub = getPubSubClient();
        const topic = pubsub.topic(topicName);
        const messageId = await topic.publishMessage({ json: payload });
        console.log(`[PubSub] Published message ${messageId} to topic '${topicName}' for user ${payload.uid}`);
        return messageId;
    }
    catch (err) {
        console.error(`[PubSub] Failed to publish message to topic '${topicName}' for user ${payload.uid}:`, err.message || err);
        return null;
    }
}
//# sourceMappingURL=pubsubHelper.js.map