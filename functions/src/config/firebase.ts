import * as admin from "firebase-admin";
import { CloudTasksClient } from "@google-cloud/tasks";

if (!admin.apps.length) {
    admin.initializeApp();
}

export const db = admin.firestore();
export const tasksClient = new CloudTasksClient();
export { admin };
