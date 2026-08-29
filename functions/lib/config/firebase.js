"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.admin = exports.tasksClient = exports.db = void 0;
const admin = require("firebase-admin");
exports.admin = admin;
const tasks_1 = require("@google-cloud/tasks");
if (!admin.apps.length) {
    admin.initializeApp();
}
exports.db = admin.firestore();
exports.tasksClient = new tasks_1.CloudTasksClient();
//# sourceMappingURL=firebase.js.map