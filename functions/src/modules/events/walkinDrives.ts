import * as functions from "firebase-functions";
import * as moment from "moment-timezone";
import { admin, db } from "../../config/firebase";
import { logNotification } from "../../utils/logger";

import { callGeminiAPI } from "../../utils/geminiHelper";
import { searchTavily, TavilySearchResult } from "../../utils/tavilyHelper";
import { enqueueUserCloudTask } from "../../utils/cloudTasksHelper";

export async function fetchAndStoreWalkInsForUserInternal(uid: string, triggerNotification: boolean): Promise<any> {
    const userDoc = await db.collection("users").doc(uid).get();
    let roles = ["DevOps Engineer", "Cloud Engineer", "Site Reliability Engineer"];
    let location = "Bengaluru";
    let userTavilyKey = "";
    let userGeminiKey = "";

    if (userDoc.exists) {
        const data = userDoc.data();
        if (data) {
            if (data.walkinRoles && Array.isArray(data.walkinRoles) && data.walkinRoles.length > 0) {
                roles = data.walkinRoles;
            }
            if (data.walkinLocation && typeof data.walkinLocation === "string" && data.walkinLocation.trim().length > 0) {
                location = data.walkinLocation.trim();
            }
            const userApiKeys = data.userApiKeys || {};
            userTavilyKey = (userApiKeys.tavilyApiKey || data.tavilyApiKey || "").trim();
            userGeminiKey = (userApiKeys.geminiApiKey || data.geminiApiKey || "").trim();
        }
    }

    if (!userTavilyKey || !userGeminiKey) {
        console.log(`[WalkinDrives] User ${uid} has not configured their personal Tavily and Gemini API keys in Settings. Skipping.`);
        return { success: false, walkins: [], message: "Tavily and Gemini API keys not configured in Settings." };
    }

    const today = moment().tz('Asia/Kolkata');
    const startDateStr = today.clone().add(1, 'day').format('YYYY-MM-DD');
    const endDateStr = today.clone().add(60, 'days').format('YYYY-MM-DD');
    const currentMonthYear = today.format("MMMM YYYY");

    // Run targeted Tavily search query per role
    const allTavilyResults: TavilySearchResult[] = [];
    const seenUrls = new Set<string>();

    for (const role of roles.slice(0, 4)) {
        try {
            const query = `"${role}" ("walk-in drive" OR "walk-in interview" OR "walk in hiring") "${location}" "${currentMonthYear}" "venue"`;
            console.log(`[WalkinDrives] Querying Tavily for user ${uid} (Role: "${role}")...`);
            const tavilyResp = await searchTavily({
                apiKey: userTavilyKey,
                query,
                searchDepth: "basic",
                maxResults: 4
            });

            for (const item of tavilyResp.results) {
                if (item.url && !seenUrls.has(item.url)) {
                    seenUrls.add(item.url);
                    allTavilyResults.push(item);
                }
            }
        } catch (tavilyErr: any) {
            console.warn(`[WalkinDrives] Tavily search error for role "${role}":`, tavilyErr.message);
        }
    }

    if (allTavilyResults.length === 0) {
        console.log(`[WalkinDrives] No search results returned from Tavily for user ${uid}.`);
        return { success: true, walkins: [], message: "No upcoming walk-in drives found from search." };
    }

    const searchResultsSummary = allTavilyResults.map((r, i) =>
        `[Walk-In Search Result ${i + 1}]\nTitle: ${r.title}\nSource: ${r.url}\nDetails: ${r.content}`
    ).join("\n\n");

    const prompt = `You are an expert career and walk-in drive coordinator. Below are real-time search results for upcoming walk-in interviews and hiring drives:

${searchResultsSummary}

Target Roles: ${roles.join(', ')}
Target Location: ${location}
Target Date Range: between ${startDateStr} and ${endDateStr}.

Provide a clean JSON list of walk-in drives. Extract the company name, exact interview date, reporting timings, venue location/address, required experience, and direct source link.

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
        ]
    };

    const geminiResult = await callGeminiAPI(payload, { apiKey: userGeminiKey, timeout: 60000 });
    const textResponse = geminiResult.text;
    if (!textResponse) {
        throw new Error('Empty content returned from Gemini API.');
    }

    let cleanedText = textResponse.trim();
    if (cleanedText.startsWith("```")) {
        cleanedText = cleanedText.replace(/^```json\s*/i, "").replace(/```\s*$/, "").trim();
    }
    
    let parsedWalkIns: any[] = [];
    try {
        parsedWalkIns = JSON.parse(cleanedText) as any[];
    } catch (e) {
        console.warn("Failed to parse JSON response directly for walk-ins. Attempting regex extraction.", e);
        const match = cleanedText.match(/\[[\s\S]*\]/);
        if (match) {
            try {
                parsedWalkIns = JSON.parse(match[0]) as any[];
            } catch (e2) {
                console.error("Regex extraction failed for walk-ins JSON.", e2);
                parsedWalkIns = [];
            }
        } else {
            console.error("No JSON array found in response text for walk-ins:", cleanedText);
            parsedWalkIns = [];
        }
    }

    // Deduplicate walk-ins by date and normalized title
    const seen = new Set<string>();
    const uniqueWalkIns: any[] = [];
    for (const walkin of parsedWalkIns) {
        if (!walkin.title || !walkin.date) continue;
        const normTitle = walkin.title.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        const key = `${walkin.date}_${normTitle}`;
        if (!seen.has(key)) {
            seen.add(key);
            uniqueWalkIns.push(walkin);
        }
    }

    const walkinsCol = db.collection("users").doc(uid).collection("walkins");
    const existingSnap = await walkinsCol.get();
    
    // Store existing walkin keys to prevent adding duplicate walkin drives
    const existingKeys = new Set<string>();
    existingSnap.forEach(doc => {
        const d = doc.data();
        const t = d.title || "";
        const normTitle = t.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        existingKeys.add(`${d.date}_${normTitle}`);
    });

    // Mark all existing walk-ins as NOT new (isNew: false)
    const batch = db.batch();
    existingSnap.forEach(doc => {
        batch.update(doc.ref, { isNew: false });
    });
    await batch.commit();

    let newCount = 0;
    const writeBatch = db.batch();
    for (const walkin of uniqueWalkIns) {
        const normTitle = walkin.title.toLowerCase().replace(/[^a-z0-9]/g, "").trim();
        const key = `${walkin.date}_${normTitle}`;
        
        if (!existingKeys.has(key)) {
            const cleanTitle = walkin.title.replace(/[^a-zA-Z0-9]/g, '_').toLowerCase();
            const docId = `${walkin.date}_${cleanTitle.substring(0, 30)}`;
            const docRef = walkinsCol.doc(docId);
            writeBatch.set(docRef, {
                ...walkin,
                isNew: true,
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            });
            newCount++;
        }
    }
    await writeBatch.commit();

    // Update last updated timestamp on user doc
    const updateData: any = {
        walkinsLastRan: admin.firestore.FieldValue.serverTimestamp()
    };
    if (newCount > 0) {
        updateData.walkinsLastUpdated = admin.firestore.FieldValue.serverTimestamp();
    }
    await db.collection("users").doc(uid).update(updateData);

    // Send push notification if automatic scheduling triggered it and new items were added
    if (triggerNotification && newCount > 0 && userDoc.exists) {
        const uData = userDoc.data();
        const enabledModules = uData?.enabledModules || [];
        const notifPrefs = uData?.notificationPreferences || {};
        
        if (enabledModules.includes("walkin") && notifPrefs.walkin !== false) {
            const usernameDoc = await db.collection("usernames").where("uid", "==", uid).limit(1).get();
            if (!usernameDoc.empty) {
                const token = usernameDoc.docs[0].data().fcmToken;
                if (token) {
                    const title = "New Walk-In Drives Found";
                    const body = `Found ${newCount} new walk-in drive(s) for DevOps/Cloud/SRE roles in Bengaluru.`;
                    await admin.messaging().send({
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
                    await logNotification(uid, title, body, "WALKIN_DRIVES");
                }
            }
        }
    }

    return { success: true, count: newCount };
}

export const fetchUserWalkIns = functions.runWith({ timeoutSeconds: 120, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const uid = context.auth.uid;
    try {
        return await fetchAndStoreWalkInsForUserInternal(uid, false);
    } catch (error: any) {
        console.error("Error in fetchUserWalkIns:", error);
        throw new functions.https.HttpsError('internal', error.message || 'Failed to fetch walk-ins.');
    }
});

export const fetchUserWalkInDrives = fetchUserWalkIns;

/**
 * Cloud Tasks queue handler for isolated sequential Walk-In Drives processing per user.
 * maxConcurrentDispatches: 1 guarantees strictly 1 user at a time.
 */
export const processWalkInUserTask = functions.runWith({ timeoutSeconds: 300, memory: "512MB" }).tasks
    .taskQueue({
        retryConfig: { maxAttempts: 2 },
        rateLimits: { maxConcurrentDispatches: 1 },
    })
    .onDispatch(async (rawPayload: any, context?: any) => {
        const payload = (rawPayload && typeof rawPayload === 'object' && rawPayload.data) ? rawPayload.data : rawPayload;
        const uid = payload?.uid;
        if (!uid) {
            console.error("[processWalkInUserTask] Missing uid in payload:", rawPayload);
            return;
        }

        console.log(`[processWalkInUserTask] Processing Walk-In Drives for user ${uid}`);
        try {
            const res = await fetchAndStoreWalkInsForUserInternal(uid, true);
            console.log(`[processWalkInUserTask] Completed Walk-In Drives fetch for user ${uid}:`, res);
        } catch (err: any) {
            console.error(`[processWalkInUserTask] Error fetching walk-in drives for user ${uid}:`, err.message || err);
            throw err;
        }
    });

export async function internalDailyWalkInsFetcher(): Promise<void> {
    console.log("[internalDailyWalkInsFetcher] Starting daily Walk-In Drives dispatcher at 8 PM IST");
    try {
        const usersSnap = await db.collection("users").get();
        const eligibleUids: string[] = [];

        for (const userDoc of usersSnap.docs) {
            const uid = userDoc.id;
            const uData = userDoc.data() || {};
            const enabledModules = uData.enabledModules || [];

            // 1. Must have module enabled
            if (!enabledModules.includes("walkin")) {
                console.log(`[internalDailyWalkInsFetcher] Skipping user ${uid}: 'walkin' module not enabled.`);
                continue;
            }

            // 2. Must have valid preferences (roles and location) entered
            const roles = uData.walkinRoles;
            const location = uData.walkinLocation;
            if (!Array.isArray(roles) || roles.length === 0 || !location || typeof location !== 'string' || location.trim().length === 0) {
                console.log(`[internalDailyWalkInsFetcher] Skipping user ${uid}: missing walkinRoles or walkinLocation.`);
                continue;
            }

            eligibleUids.push(uid);
        }

        console.log(`[internalDailyWalkInsFetcher] Found ${eligibleUids.length} eligible user(s) with configured preferences:`, eligibleUids);

        if (eligibleUids.length === 0) {
            return;
        }

        const nowUnix = moment().tz('Asia/Kolkata').unix();
        for (let i = 0; i < eligibleUids.length; i++) {
            const uid = eligibleUids[i];
            const etaUnix = nowUnix + (i * 25); // Stagger by 25s for safe RPM rate limits
            const taskId = await enqueueUserCloudTask(
                "processWalkInUserTask",
                "processWalkInUserTask",
                { uid },
                etaUnix
            );

            // Fallback: If Cloud Tasks queue enqueue fails, process directly with safe delay
            if (!taskId) {
                console.warn(`[internalDailyWalkInsFetcher] Cloud Tasks queue unavailable for ${uid}. Running directly as fallback...`);
                try {
                    await fetchAndStoreWalkInsForUserInternal(uid, true);
                } catch (e: any) {
                    console.error(`[internalDailyWalkInsFetcher] Error in fallback execution for ${uid}:`, e.message || e);
                }
                await new Promise((r) => setTimeout(r, 5000));
            }
        }
    } catch (e: any) {
        console.error("Error in internalDailyWalkInsFetcher:", e.message || e);
    }
}

export const fetchUserWalkInsTrigger = functions.runWith({ timeoutSeconds: 300, memory: "256MB" }).pubsub.topic('fetch-user-walkins').onPublish(async (message) => {
    const data = message.json;
    const uid = data.uid;
    if (!uid) {
        console.error("No uid in PubSub message");
        return;
    }
    console.log(`Processing walk-ins for user via PubSub: ${uid}`);
    try {
        await fetchAndStoreWalkInsForUserInternal(uid, true);
    } catch (err: any) {
        console.error(`Error processing walk-ins for user ${uid}:`, err.message);
    }
});

export async function internalCheckInterestedWalkinsNotifications() {
    const tomorrowStr = moment().tz('Asia/Kolkata').add(1, 'days').format('YYYY-MM-DD');
    console.log(`Running checkInterestedWalkinsNotifications at ${moment().tz('Asia/Kolkata').format()} (Target Date: ${tomorrowStr})`);

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

            if (!enabledModules.includes("walkin") || notifPrefs.walkin === false) continue;

            const walkinsSnap = await db.collection('users').doc(uid).collection('walkins')
                .where('interested', '==', true)
                .where('date', '==', tomorrowStr)
                .get();

            for (const doc of walkinsSnap.docs) {
                const walkinData = doc.data();
                if (walkinData.notifiedInterested === true) continue;

                const title = `🚶 Upcoming Walk-In: ${walkinData.title || 'Walk-In'}`;
                const body = `Reminder: Walk-In for "${walkinData.title}" is happening tomorrow at ${walkinData.timings || 'scheduled time'}.`;

                console.log(`Sending interested walkin reminder: ${title} to user ${uid}`);
                await admin.messaging().send({
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

                await logNotification(uid, title, body, "WALK_INS");
                await doc.ref.update({ notifiedInterested: true });
            }
        } catch (error) {
            console.error(`Failed to check/send interested walkin notifications for user ${uid}:`, error);
        }
    }
}
