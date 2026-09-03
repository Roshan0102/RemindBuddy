import * as functions from "firebase-functions";
import * as moment from "moment-timezone";
import { admin, db } from "../../config/firebase";
import { logNotification } from "../../utils/logger";

import { callGeminiAPI } from "../../utils/geminiHelper";
import { enqueueUserCloudTask } from "../../utils/cloudTasksHelper";

export async function fetchAndStoreEventsForUserInternal(uid: string, triggerNotification: boolean): Promise<any> {
    const userDoc = await db.collection("users").doc(uid).get();
    let interests = ["Cloud", "Devops", "AI", "Agentic AI"];
    let location = "Bengaluru, India";
    let eventMode = "In-Person";

    if (userDoc.exists) {
        const data = userDoc.data();
        if (data) {
            if (data.eventInterests && Array.isArray(data.eventInterests) && data.eventInterests.length > 0) {
                interests = data.eventInterests;
            }
            if (data.eventLocation && typeof data.eventLocation === "string" && data.eventLocation.trim().length > 0) {
                location = data.eventLocation.trim();
            }
            if (data.eventMode && typeof data.eventMode === "string" && data.eventMode.trim().length > 0) {
                eventMode = data.eventMode.trim();
            }
        }
    }

    const today = moment().tz('Asia/Kolkata');
    const startDateStr = today.clone().add(1, 'day').format('YYYY-MM-DD');
    const endDateStr = today.clone().add(60, 'days').format('YYYY-MM-DD');

    let modeConstraint = "";
    if (eventMode === "In-Person") {
        modeConstraint = `Include ONLY physical, in-person offline events hosted in or near ${location}. Do NOT include online webinars or virtual streams.`;
    } else if (eventMode === "Online") {
        modeConstraint = `Include ONLY online webinars, virtual workshops, or live streams accessible from ${location}. Do NOT include physical in-person events.`;
    } else {
        modeConstraint = `Include both physical in-person events in ${location} and online webinars/virtual workshops.`;
    }

    const prompt = `Find upcoming real Tech events, developer meetups, workshops, hackathons happening in ${location} strictly focused on these user interests: ${interests.join(', ')}.
The events must happen between ${startDateStr} and ${endDateStr}.
CRITICAL CONSTRAINTS:
1. ${modeConstraint}
2. ONLY include technical topics relevant to: ${interests.join(', ')}.
3. Strictly EXCLUDE non-technical events, school/college general quizzes, IQ competitions, marketing sales pitches, and unrelated general hackathons.
4. Use Google Search grounding to find real, currently active upcoming events from luma.com, eventbrite.com, meetup.com, hackerearth.com, 10times.com, and linkedin.com.
5. Provide a clean JSON list of events. The "registrationLink" property must point directly to the actual event source registration/info page.

If no events match the criteria, respond ONLY with an empty JSON array: []. Do not include any conversational explanation or markdown preamble.
Respond ONLY with a JSON array matching this schema:
[
  {
    "title": "string",
    "date": "YYYY-MM-DD",
    "timings": "string",
    "location": "string",
    "registrationLink": "string (direct link to the event source page)",
    "sourcePlatform": "string (Luma, Eventbrite, Meetup, HackerEarth, 10times, LinkedIn, or Google Search)"
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

    const geminiResult = await callGeminiAPI(payload, { timeout: 240000 });
    const textResponse = geminiResult.text;
    if (!textResponse) {
        throw new Error('Empty content returned from Gemini API.');
    }

    let cleanedText = textResponse.trim();
    if (cleanedText.startsWith("```")) {
        cleanedText = cleanedText.replace(/^```json\s*/i, "").replace(/```\s*$/, "").trim();
    }
    
    let parsedEvents: any[] = [];
    try {
        parsedEvents = JSON.parse(cleanedText) as any[];
    } catch (e) {
        console.warn("Failed to parse JSON response directly for events. Attempting regex extraction.", e);
        const match = cleanedText.match(/\[[\s\S]*\]/);
        if (match) {
            try {
                parsedEvents = JSON.parse(match[0]) as any[];
            } catch (e2) {
                console.error("Regex extraction failed for events JSON.", e2);
                parsedEvents = [];
            }
        } else {
            console.error("No JSON array found in response text for events:", cleanedText);
            parsedEvents = [];
        }
    }

    // Deduplicate events by normalized title, excluding conferences
    const seen = new Set<string>();
    const uniqueEvents: any[] = [];
    for (const event of parsedEvents) {
        if (!event.title || !event.date) continue;
        const normTitle = event.title.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        if (normTitle.includes("conference") || /\bconf\b/.test(normTitle)) continue;
        if (!seen.has(normTitle)) {
            seen.add(normTitle);
            uniqueEvents.push(event);
        }
    }

    const eventsCol = db.collection("users").doc(uid).collection("events");
    const existingSnap = await eventsCol.get();

    // Map existing events by normTitle -> docRef & date for smart deduplication across all users
    const existingMap = new Map<string, { id: string; ref: FirebaseFirestore.DocumentReference; date: string }>();
    existingSnap.forEach(doc => {
        const d = doc.data();
        const t = d.title || "";
        const normTitle = t.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        if (normTitle) {
            existingMap.set(normTitle, { id: doc.id, ref: doc.ref, date: d.date || "" });
        }
    });

    // Mark all existing events as not new (isNew: false)
    const batch = db.batch();
    existingSnap.forEach(doc => {
        batch.update(doc.ref, { isNew: false });
    });
    await batch.commit();

    let newCount = 0;
    const writeBatch = db.batch();
    for (const event of uniqueEvents) {
        const normTitle = event.title.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        if (!normTitle) continue;

        if (existingMap.has(normTitle)) {
            // Already exists in Firestore! Merge date info instead of creating duplicate document!
            const existing = existingMap.get(normTitle)!;
            if (existing.date && !existing.date.includes(event.date)) {
                writeBatch.update(existing.ref, {
                    date: `${existing.date}, ${event.date}`
                });
            }
        } else {
            // Brand new event title!
            const cleanTitle = event.title.replace(/[^a-zA-Z0-9]/g, '_').toLowerCase();
            const docId = `${event.date}_${cleanTitle.substring(0, 30)}`;
            const docRef = eventsCol.doc(docId);
            writeBatch.set(docRef, {
                ...event,
                isNew: true,
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            });
            existingMap.set(normTitle, { id: docId, ref: docRef, date: event.date });
            newCount++;
        }
    }
    await writeBatch.commit();

    // Update last updated timestamp on user doc
    const updateData: any = {
        eventsLastRan: admin.firestore.FieldValue.serverTimestamp()
    };
    if (newCount > 0) {
        updateData.eventsLastUpdated = admin.firestore.FieldValue.serverTimestamp();
    }
    await db.collection("users").doc(uid).update(updateData);

    // Send push notification if automatic scheduling triggered it and new items were added
    if (triggerNotification && newCount > 0 && userDoc.exists) {
        const uData = userDoc.data();
        const enabledModules = uData?.enabledModules || [];
        const notifPrefs = uData?.notificationPreferences || {};

        if (enabledModules.includes("events") && notifPrefs.events !== false) {
            const usernameDoc = await db.collection("usernames").where("uid", "==", uid).limit(1).get();
            if (!usernameDoc.empty) {
                const token = usernameDoc.docs[0].data().fcmToken;
                if (token) {
                    const title = "New Tech Events Found";
                    const body = `Found ${newCount} new tech event(s) and meetup(s) in Bengaluru.`;
                    await admin.messaging().send({
                        token,
                        notification: { title, body },
                        android: { 
                            notification: { 
                                channelId: "events_reminder_channel",
                                tag: "tech_events"
                            } 
                        },
                        data: { type: "events_reminder" }
                    });
                    await logNotification(uid, title, body, "TECH_EVENTS");
                }
            }
        }
    }

    return { success: true, count: newCount };
}

export const fetchUserTechEvents = functions.runWith({ timeoutSeconds: 120, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const uid = context.auth.uid;
    try {
        return await fetchAndStoreEventsForUserInternal(uid, false);
    } catch (error: any) {
        console.error("Error in fetchUserTechEvents:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to fetch tech events.');
    }
});

/**
 * Cloud Tasks queue handler for isolated sequential Tech Events processing per user.
 * maxConcurrentDispatches: 1 guarantees strictly 1 user at a time.
 */
export const processTechEventsUserTask = functions.runWith({ timeoutSeconds: 300, memory: "512MB" }).tasks
    .taskQueue({
        retryConfig: { maxAttempts: 2 },
        rateLimits: { maxConcurrentDispatches: 1 },
    })
    .onDispatch(async (rawPayload: any, context?: any) => {
        const payload = (rawPayload && typeof rawPayload === 'object' && rawPayload.data) ? rawPayload.data : rawPayload;
        const uid = payload?.uid;
        if (!uid) {
            console.error("[processTechEventsUserTask] Missing uid in payload:", rawPayload);
            return;
        }

        console.log(`[processTechEventsUserTask] Processing Tech Events for user ${uid}`);
        try {
            const res = await fetchAndStoreEventsForUserInternal(uid, true);
            console.log(`[processTechEventsUserTask] Completed Tech Events fetch for user ${uid}:`, res);
        } catch (err: any) {
            console.error(`[processTechEventsUserTask] Error fetching tech events for user ${uid}:`, err.message || err);
            throw err;
        }
    });

export async function internalDailyTechEventsFetcher(): Promise<void> {
    console.log("[internalDailyTechEventsFetcher] Starting daily Tech Events dispatcher at 7 PM IST");
    try {
        const usersSnap = await db.collection("users").get();
        const eligibleUids: string[] = [];

        for (const userDoc of usersSnap.docs) {
            const uid = userDoc.id;
            const uData = userDoc.data() || {};
            const enabledModules = uData.enabledModules || [];

            // 1. Must have module enabled
            if (!enabledModules.includes("events")) {
                console.log(`[internalDailyTechEventsFetcher] Skipping user ${uid}: 'events' module not enabled.`);
                continue;
            }

            // 2. Must have valid preferences (interests and location) entered
            const interests = uData.eventInterests;
            const location = uData.eventLocation;
            if (!Array.isArray(interests) || interests.length === 0 || !location || typeof location !== 'string' || location.trim().length === 0) {
                console.log(`[internalDailyTechEventsFetcher] Skipping user ${uid}: missing eventInterests or eventLocation.`);
                continue;
            }

            eligibleUids.push(uid);
        }

        console.log(`[internalDailyTechEventsFetcher] Found ${eligibleUids.length} eligible user(s) with configured preferences:`, eligibleUids);

        if (eligibleUids.length === 0) {
            return;
        }

        const nowUnix = moment().tz('Asia/Kolkata').unix();
        for (let i = 0; i < eligibleUids.length; i++) {
            const uid = eligibleUids[i];
            const etaUnix = nowUnix + (i * 25); // Stagger by 25s for safe RPM rate limits
            const taskId = await enqueueUserCloudTask(
                "processTechEventsUserTask",
                "processTechEventsUserTask",
                { uid },
                etaUnix
            );

            // Fallback: If Cloud Tasks queue enqueue fails, process directly with safe delay
            if (!taskId) {
                console.warn(`[internalDailyTechEventsFetcher] Cloud Tasks queue unavailable for ${uid}. Running directly as fallback...`);
                try {
                    await fetchAndStoreEventsForUserInternal(uid, true);
                } catch (e: any) {
                    console.error(`[internalDailyTechEventsFetcher] Error in fallback execution for ${uid}:`, e.message || e);
                }
                await new Promise((r) => setTimeout(r, 5000));
            }
        }
    } catch (e: any) {
        console.error("Error in internalDailyTechEventsFetcher:", e.message || e);
    }
}

export const fetchUserTechEventsTrigger = functions.runWith({ timeoutSeconds: 300, memory: "256MB" }).pubsub.topic('fetch-user-tech-events').onPublish(async (message) => {
    const data = message.json;
    const uid = data.uid;
    if (!uid) {
        console.error("No uid in PubSub message");
        return;
    }
    console.log(`Processing tech events for user via PubSub: ${uid}`);
    try {
        await fetchAndStoreEventsForUserInternal(uid, true);
    } catch (err: any) {
        console.error(`Error processing tech events for user ${uid}:`, err.message);
    }
});

export async function internalCheckInterestedTechEventsNotifications() {
    const tomorrowStr = moment().tz('Asia/Kolkata').add(1, 'days').format('YYYY-MM-DD');
    console.log(`Running checkInterestedTechEventsNotifications at ${moment().tz('Asia/Kolkata').format()} (Target Date: ${tomorrowStr})`);

    const users = await db.collection('usernames').get();
    for (const u of users.docs) {
        const userData = u.data();
        if (!userData.fcmToken || !userData.uid) continue;

        const uid = userData.uid;
        try {
            const userProfileDoc = await db.collection("users").doc(uid).get();
            if (!userProfileDoc.exists) continue;

            const uData = userProfileDoc.data();
            const enabledModules = uData?.enabledModules || [];
            const notifPrefs = uData?.notificationPreferences || {};

            if (!enabledModules.includes("events") || notifPrefs.events === false) continue;

            const eventsSnap = await db.collection('users').doc(uid).collection('events')
                .where('interested', '==', true)
                .where('date', '==', tomorrowStr)
                .get();

            for (const doc of eventsSnap.docs) {
                const eventData = doc.data();
                if (eventData.notifiedInterested === true) continue;

                const title = `📅 Upcoming Event: ${eventData.title || 'Tech Event'}`;
                const body = `Reminder: "${eventData.title}" is happening tomorrow at ${eventData.timings || 'scheduled time'}.`;
                
                console.log(`Sending interested event reminder: ${title} to user ${uid}`);
                await admin.messaging().send({
                    token: userData.fcmToken,
                    notification: { title, body },
                    android: {
                        notification: {
                            channelId: 'events_reminder_channel',
                            tag: `event_interest_${doc.id}`
                        }
                    },
                    data: { type: "event_interest_reminder", eventId: doc.id }
                });

                await logNotification(uid, title, body, "TECH_EVENTS");
                await doc.ref.update({ notifiedInterested: true });
            }
        } catch (error) {
            console.error(`Failed to check/send interested event notifications for user ${uid}:`, error);
        }
    }
}

export const internalCheckInterestedEventsNotifications = internalCheckInterestedTechEventsNotifications;
