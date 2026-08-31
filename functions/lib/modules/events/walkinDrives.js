"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.fetchUserWalkInsTrigger = exports.fetchUserWalkInDrives = exports.fetchUserWalkIns = void 0;
exports.fetchAndStoreWalkInsForUserInternal = fetchAndStoreWalkInsForUserInternal;
exports.internalDailyWalkInsFetcher = internalDailyWalkInsFetcher;
exports.internalCheckInterestedWalkinsNotifications = internalCheckInterestedWalkinsNotifications;
const functions = require("firebase-functions");
const moment = require("moment-timezone");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
const geminiHelper_1 = require("../../utils/geminiHelper");
async function fetchAndStoreWalkInsForUserInternal(uid, triggerNotification) {
    const userDoc = await firebase_1.db.collection("users").doc(uid).get();
    let roles = ["DevOps Engineer", "Cloud Engineer", "Site Reliability Engineer"];
    let location = "Bengaluru";
    if (userDoc.exists) {
        const data = userDoc.data();
        if (data && data.walkinRoles && Array.isArray(data.walkinRoles) && data.walkinRoles.length > 0) {
            roles = data.walkinRoles;
        }
        if (data && data.walkinLocation && typeof data.walkinLocation === "string" && data.walkinLocation.trim().length > 0) {
            location = data.walkinLocation.trim();
        }
    }
    const today = moment().tz('Asia/Kolkata');
    const startDateStr = today.clone().add(1, 'day').format('YYYY-MM-DD');
    const endDateStr = today.clone().add(60, 'days').format('YYYY-MM-DD');
    const prompt = `Find Walk-in drives/interviews happening in ${location}, India for the following job roles: ${roles.join(', ')}.
The drives/interviews must happen between ${startDateStr} and ${endDateStr}.
Use Google Search grounding to find real, current upcoming walk-in interviews.
Provide a clean JSON list of walk-in drives. The "registrationLink" property in the JSON should point directly to the specific page/post/posting URL from where you found the drive (e.g. LinkedIn post, company career post, event page, etc.).
Extract the company name into the "company" field and the required experience level (e.g. "0-2 yrs", "Freshers", "3-5 yrs", or "N/A") into the "experience" field.

If no walk-in drives or interviews match the criteria, respond ONLY with an empty JSON array: []. Do not include any conversational explanation, preamble, or notes.
Respond ONLY with a JSON array matching this schema:
[
  {
    "title": "string (e.g. DevOps Engineer Walk-in Drive)",
    "company": "string (e.g. Google)",
    "date": "YYYY-MM-DD",
    "timings": "string (e.g. 9:00 AM - 1:00 PM)",
    "location": "string (specific address or location in ${location})",
    "experience": "string (e.g. 0-2 yrs, Freshers, 3-5 yrs, or N/A)",
    "registrationLink": "string (direct link to where this walk-in info was found)"
  }
]`;
    const payload = {
        contents: [
            {
                parts: [
                    { text: prompt }
                ]
            }
        ],
        tools: [
            {
                googleSearch: {}
            }
        ]
    };
    const geminiResult = await (0, geminiHelper_1.callGeminiAPI)(payload, { timeout: 240000 });
    const textResponse = geminiResult.text;
    if (!textResponse) {
        throw new Error('Empty content returned from Gemini API.');
    }
    let cleanedText = textResponse.trim();
    if (cleanedText.startsWith("```")) {
        cleanedText = cleanedText.replace(/^```json\s*/i, "").replace(/```\s*$/, "").trim();
    }
    let parsedWalkIns = [];
    try {
        parsedWalkIns = JSON.parse(cleanedText);
    }
    catch (e) {
        console.warn("Failed to parse JSON response directly for walk-ins. Attempting regex extraction.", e);
        const match = cleanedText.match(/\[[\s\S]*\]/);
        if (match) {
            try {
                parsedWalkIns = JSON.parse(match[0]);
            }
            catch (e2) {
                console.error("Regex extraction failed for walk-ins JSON.", e2);
                parsedWalkIns = [];
            }
        }
        else {
            console.error("No JSON array found in response text for walk-ins:", cleanedText);
            parsedWalkIns = [];
        }
    }
    // Deduplicate walk-ins by date and normalized title
    const seen = new Set();
    const uniqueWalkIns = [];
    for (const walkin of parsedWalkIns) {
        if (!walkin.title || !walkin.date)
            continue;
        const normTitle = walkin.title.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        const key = `${walkin.date}_${normTitle}`;
        if (!seen.has(key)) {
            seen.add(key);
            uniqueWalkIns.push(walkin);
        }
    }
    const walkinsCol = firebase_1.db.collection("users").doc(uid).collection("walkins");
    const existingSnap = await walkinsCol.get();
    // Store existing walkin keys to prevent adding duplicate walkin drives
    const existingKeys = new Set();
    existingSnap.forEach(doc => {
        const d = doc.data();
        const t = d.title || "";
        const normTitle = t.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        existingKeys.add(`${d.date}_${normTitle}`);
    });
    // Mark all existing walk-ins as NOT new (isNew: false)
    const batch = firebase_1.db.batch();
    existingSnap.forEach(doc => {
        batch.update(doc.ref, { isNew: false });
    });
    await batch.commit();
    let newCount = 0;
    const writeBatch = firebase_1.db.batch();
    for (const walkin of uniqueWalkIns) {
        const normTitle = walkin.title.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        const key = `${walkin.date}_${normTitle}`;
        if (!existingKeys.has(key)) {
            const cleanTitle = walkin.title.replace(/[^a-zA-Z0-9]/g, '_').toLowerCase();
            const docId = `${walkin.date}_${cleanTitle.substring(0, 30)}`;
            const docRef = walkinsCol.doc(docId);
            writeBatch.set(docRef, Object.assign(Object.assign({}, walkin), { isNew: true, createdAt: firebase_1.admin.firestore.FieldValue.serverTimestamp() }));
            newCount++;
        }
    }
    await writeBatch.commit();
    // Update last updated timestamp on user doc
    const updateData = {
        walkinsLastRan: firebase_1.admin.firestore.FieldValue.serverTimestamp()
    };
    if (newCount > 0) {
        updateData.walkinsLastUpdated = firebase_1.admin.firestore.FieldValue.serverTimestamp();
    }
    await firebase_1.db.collection("users").doc(uid).update(updateData);
    // Send push notification if automatic scheduling triggered it and new items were added
    if (triggerNotification && newCount > 0 && userDoc.exists) {
        const uData = userDoc.data();
        const enabledModules = (uData === null || uData === void 0 ? void 0 : uData.enabledModules) || [];
        const notifPrefs = (uData === null || uData === void 0 ? void 0 : uData.notificationPreferences) || {};
        if (enabledModules.includes("walkin") && notifPrefs.walkin !== false) {
            const usernameDoc = await firebase_1.db.collection("usernames").where("uid", "==", uid).limit(1).get();
            if (!usernameDoc.empty) {
                const token = usernameDoc.docs[0].data().fcmToken;
                if (token) {
                    const title = "New Walk-In Drives Found";
                    const body = `Found ${newCount} new walk-in drive(s) for DevOps/Cloud/SRE roles in Bengaluru.`;
                    await firebase_1.admin.messaging().send({
                        token,
                        notification: { title, body },
                        android: {
                            notification: {
                                channelId: "walkin_reminder_channel",
                                tag: "walkin_drives"
                            }
                        },
                        data: { type: "walkin_reminder" }
                    });
                    await (0, logger_1.logNotification)(uid, title, body, "WALKIN_DRIVES");
                }
            }
        }
    }
    return { success: true, count: newCount };
}
exports.fetchUserWalkIns = functions.runWith({ timeoutSeconds: 120, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const uid = context.auth.uid;
    try {
        return await fetchAndStoreWalkInsForUserInternal(uid, false);
    }
    catch (error) {
        console.error("Error in fetchUserWalkIns:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to fetch walk-ins.');
    }
});
exports.fetchUserWalkInDrives = exports.fetchUserWalkIns;
async function internalDailyWalkInsFetcher() {
    console.log("Starting dailyWalkInsFetcher at 8 PM IST");
    try {
        const usersSnap = await firebase_1.db.collection("users").get();
        console.log(`[internalDailyWalkInsFetcher] Found ${usersSnap.size} user documents.`);
        for (const userDoc of usersSnap.docs) {
            const uid = userDoc.id;
            console.log(`Processing walk-in drives fetch for user: ${uid}`);
            try {
                const res = await fetchAndStoreWalkInsForUserInternal(uid, true);
                console.log(`Walk-in drives fetch completed for user ${uid}:`, res);
            }
            catch (err) {
                console.error(`Error fetching walk-in drives for user ${uid}:`, err.message || err);
            }
        }
    }
    catch (e) {
        console.error("Error in internalDailyWalkInsFetcher:", e.message || e);
    }
}
exports.fetchUserWalkInsTrigger = functions.runWith({ timeoutSeconds: 300, memory: "256MB" }).pubsub.topic('fetch-user-walkins').onPublish(async (message) => {
    const data = message.json;
    const uid = data.uid;
    if (!uid) {
        console.error("No uid in PubSub message");
        return;
    }
    console.log(`Processing walk-ins for user via PubSub: ${uid}`);
    try {
        await fetchAndStoreWalkInsForUserInternal(uid, true);
    }
    catch (err) {
        console.error(`Error processing walk-ins for user ${uid}:`, err.message);
    }
});
async function internalCheckInterestedWalkinsNotifications() {
    const tomorrowStr = moment().tz('Asia/Kolkata').add(1, 'days').format('YYYY-MM-DD');
    console.log(`Running checkInterestedWalkinsNotifications at ${moment().tz('Asia/Kolkata').format()} (Target Date: ${tomorrowStr})`);
    const users = await firebase_1.db.collection('usernames').get();
    for (const u of users.docs) {
        const userData = u.data();
        if (!userData.fcmToken || !userData.uid)
            continue;
        const uid = userData.uid;
        try {
            const userProfileDoc = await firebase_1.db.collection("users").doc(uid).get();
            if (!userProfileDoc.exists)
                continue;
            const uData = userProfileDoc.data();
            const enabledModules = (uData === null || uData === void 0 ? void 0 : uData.enabledModules) || [];
            const notifPrefs = (uData === null || uData === void 0 ? void 0 : uData.notificationPreferences) || {};
            if (!enabledModules.includes("walkin") || notifPrefs.walkin === false)
                continue;
            const walkinsSnap = await firebase_1.db.collection('users').doc(uid).collection('walkins')
                .where('interested', '==', true)
                .where('date', '==', tomorrowStr)
                .get();
            for (const doc of walkinsSnap.docs) {
                const walkinData = doc.data();
                if (walkinData.notifiedInterested === true)
                    continue;
                const title = `🚶 Upcoming Walk-In: ${walkinData.title || 'Walk-In'}`;
                const body = `Reminder: Walk-In for "${walkinData.title}" is happening tomorrow at ${walkinData.timings || 'scheduled time'}.`;
                console.log(`Sending interested walkin reminder: ${title} to user ${uid}`);
                await firebase_1.admin.messaging().send({
                    token: userData.fcmToken,
                    notification: { title, body },
                    android: {
                        notification: {
                            channelId: 'events_reminder_channel',
                            tag: `walkin_interest_${doc.id}`
                        }
                    },
                    data: { type: "walkin_interest_reminder", walkinId: doc.id }
                });
                await (0, logger_1.logNotification)(uid, title, body, "WALK_INS");
                await doc.ref.update({ notifiedInterested: true });
            }
        }
        catch (error) {
            console.error(`Failed to check/send interested walkin notifications for user ${uid}:`, error);
        }
    }
}
//# sourceMappingURL=walkinDrives.js.map