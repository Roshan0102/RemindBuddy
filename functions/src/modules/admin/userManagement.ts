import * as functions from "firebase-functions";
import { admin, db } from "../../config/firebase";

export const adminCreateUser = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const username = (data.username || "").trim().toLowerCase();
    const password = (data.password || "").trim();

    if (!username || !password) {
        throw new functions.https.HttpsError('invalid-argument', 'Username and password are required.');
    }
    if (password.length < 6) {
        throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters.');
    }

    try {
        const usernameDoc = await db.collection('usernames').doc(username).get();
        if (usernameDoc.exists) {
            throw new functions.https.HttpsError('already-exists', 'Username is already taken.');
        }

        const email = `${username}@remindbuddy.com`;
        
        const userRecord = await admin.auth().createUser({
            email: email,
            password: password,
            displayName: username,
            emailVerified: true
        });

        const uid = userRecord.uid;

        const allowedCollaborators = Array.isArray(data.allowedCollaborators) ? data.allowedCollaborators : [];

        await db.collection('usernames').doc(username).set({
            email: email,
            uid: uid,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        });

        await db.collection('users').doc(uid).set({
            enabledModules: ['gold', 'reminders', 'notes', 'shifts', 'checklist'],
            allowedCollaborators: allowedCollaborators,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        });

        return { success: true, uid: uid, username: username };
    } catch (error: any) {
        console.error("Error creating user:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to create user.');
    }
});

export const adminChangePassword = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const username = (data.username || "").trim().toLowerCase();
    const newPassword = (data.password || "").trim();

    if (!username || !newPassword) {
        throw new functions.https.HttpsError('invalid-argument', 'Username and new password are required.');
    }
    if (newPassword.length < 6) {
        throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters.');
    }

    try {
        const usernameDoc = await db.collection('usernames').doc(username).get();
        if (!usernameDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Username not found.');
        }

        const uid = usernameDoc.data()?.uid;
        if (!uid) {
            throw new functions.https.HttpsError('not-found', 'UID not found for username.');
        }

        await admin.auth().updateUser(uid, {
            password: newPassword
        });

        return { success: true, username: username };
    } catch (error: any) {
        console.error("Error updating password:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to change password.');
    }
});

export const adminDeleteUser = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const username = (data.username || "").trim().toLowerCase();

    if (!username) {
        throw new functions.https.HttpsError('invalid-argument', 'Username is required.');
    }

    try {
        const usernameDoc = await db.collection('usernames').doc(username).get();
        if (!usernameDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Username not found.');
        }

        const uid = usernameDoc.data()?.uid;
        if (!uid) {
            throw new functions.https.HttpsError('not-found', 'UID not found for username.');
        }

        try {
            await admin.auth().deleteUser(uid);
        } catch (authErr: any) {
            console.warn("Auth user deletion warning:", authErr.message);
        }

        await db.collection('usernames').doc(username).delete();
        await db.collection('users').doc(uid).delete();

        return { success: true, username: username };
    } catch (error: any) {
        console.error("Error deleting user:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to delete user.');
    }
});

export const adminUpdateUserModules = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const targetUid = data.userId;
    const enabledModules = data.enabledModules;
    
    if (!targetUid || !Array.isArray(enabledModules)) {
        throw new functions.https.HttpsError('invalid-argument', 'userId and enabledModules array are required.');
    }
    
    try {
        await db.collection('users').doc(targetUid).set({
            enabledModules: enabledModules
        }, { merge: true });
        
        return { success: true };
    } catch (error: any) {
        console.error("Error updating user modules:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to update modules.');
    }
});

export const adminUpdateAllowedCollaborators = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const targetUid = data.userId;
    const allowedCollaborators = data.allowedCollaborators;
    
    if (!targetUid || !Array.isArray(allowedCollaborators)) {
        throw new functions.https.HttpsError('invalid-argument', 'userId and allowedCollaborators array are required.');
    }
    
    try {
        await db.collection('users').doc(targetUid).set({
            allowedCollaborators: allowedCollaborators
        }, { merge: true });
        
        return { success: true };
    } catch (error: any) {
        console.error("Error updating allowed collaborators:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to update allowed collaborators.');
    }
});
