import * as functions from "firebase-functions";
import * as moment from "moment-timezone";
import { admin, db } from "../../config/firebase";
import { callGeminiAPI } from "../../utils/geminiHelper";
import { getTodayLunarPhase } from "../astro/astroNotifications";

export const voiceAssistantQuery = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const uid = context.auth.uid;
    const { query } = data;
    if (!query) {
        throw new functions.https.HttpsError('invalid-argument', 'Query text is required.');
    }

    try {
        // 1. Fetch user permissions and modules
        const userDoc = await db.collection("users").doc(uid).get();
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User not found.');
        }
        const userData = userDoc.data();
        const enabledModules = userData?.enabledModules || [];
        if (!enabledModules.includes("voice_assistant")) {
            throw new functions.https.HttpsError('permission-denied', 'Voice Assistant feature is disabled.');
        }

        // 2. Gather state context in parallel
        const nowKolkata = moment().tz('Asia/Kolkata');
        const currentMonth = nowKolkata.format('YYYY-MM');

        const remindersPromise = db.collection("users").doc(uid).collection("calendar_reminders")
            .where("status", "==", "scheduled")
            .limit(15)
            .get();

        const dailyRemindersPromise = db.collection("users").doc(uid).collection("daily_reminders")
            .limit(15)
            .get();

        const notesPromise = db.collection("users").doc(uid).collection("notes")
            .orderBy("updatedAt", "desc")
            .limit(10)
            .get();

        const shiftsPromise = db.collection("users").doc(uid).collection("shifts").doc(currentMonth).collection("daily_shifts")
            .orderBy("date")
            .get();

        const goldPromise = db.collection("global_gold_prices")
            .orderBy("timestamp", "desc")
            .limit(1)
            .get();

        const eventsPromise = db.collection("users").doc(uid).collection("events")
            .where("notInterested", "==", false)
            .orderBy("date")
            .limit(10)
            .get();

        const walkinsPromise = db.collection("users").doc(uid).collection("walkins")
            .where("notInterested", "==", false)
            .orderBy("date")
            .limit(10)
            .get();

        const goldInsightsPromise = db.collection("gold_ai_insights").doc("latest").get();
        const goldChitAdvicePromise = db.collection("gold_chit_advice").doc("latest").get();
        const jobAppsPromise = db.collection("users").doc(uid).collection("job_applications").orderBy("appliedAt", "desc").limit(15).get();

        const [
            remindersSnap,
            dailyRemindersSnap,
            notesSnap,
            shiftsSnap,
            goldSnap,
            eventsSnap,
            walkinsSnap,
            goldInsightsSnap,
            goldChitAdviceSnap,
            jobAppsSnap
        ] = await Promise.all([
            remindersPromise,
            dailyRemindersPromise,
            notesPromise,
            shiftsPromise.catch(() => null),
            goldPromise.catch(() => null),
            eventsPromise.catch(() => null),
            walkinsPromise.catch(() => null),
            goldInsightsPromise.catch(() => null),
            goldChitAdvicePromise.catch(() => null),
            jobAppsPromise.catch(() => null)
        ]);

        // Format state context
        let contextText = `Current Date and Time (IST): ${nowKolkata.format('YYYY-MM-DD HH:mm dddd')}\n\n`;

        contextText += "--- UPCOMING CALENDAR REMINDERS ---\n";
        if (remindersSnap && !remindersSnap.empty) {
            remindersSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- ID: ${doc.id}, Title: "${d.title}", Date: ${d.date}, Time: ${d.time}, Recurring: ${d.isRecurring || false}, Snooze: ${d.snoozeEnabled || false}\n`;
            });
        } else {
            contextText += "No upcoming scheduled reminders.\n";
        }
        contextText += "\n";

        contextText += "--- DAILY REMINDERS ---\n";
        if (dailyRemindersSnap && !dailyRemindersSnap.empty) {
            dailyRemindersSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- ID: ${doc.id}, Time: ${d.time}, Enabled: ${d.enabled || false}, Label: "${d.label || ''}"\n`;
            });
        } else {
            contextText += "No daily reminders configured.\n";
        }
        contextText += "\n";

        contextText += "--- RECENT NOTES ---\n";
        if (notesSnap && !notesSnap.empty) {
            notesSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- ID: ${doc.id}, Title: "${d.title}", Content: "${d.content || ''}"\n`;
            });
        } else {
            contextText += "No notes found.\n";
        }
        contextText += "\n";

        contextText += `--- WORK SHIFTS (${currentMonth}) ---\n`;
        if (shiftsSnap && !shiftsSnap.empty) {
            shiftsSnap.docs.forEach(doc => {
                const d = doc.data();
                if (!d.is_week_off) {
                    contextText += `- Date: ${d.date}, Shift: "${d.shift_type}", Hours: ${d.start_time || ''}-${d.end_time || ''}\n`;
                } else {
                    contextText += `- Date: ${d.date}, Week Off\n`;
                }
            });
        } else {
            contextText += "No shift roster imported for this month.\n";
        }
        contextText += "\n";

        contextText += "--- LATEST GOLD PRICE ---\n";
        if (goldSnap && !goldSnap.empty) {
            const gd = goldSnap.docs[0].data();
            contextText += `Price: ₹${gd.price} per gram, Updated: ${gd.timestamp}\n`;
        } else {
            contextText += "Gold price data unavailable.\n";
        }
        contextText += "\n";

        contextText += "--- GOLD AI MARKET ANALYSIS & INSIGHTS ---\n";
        if (goldInsightsSnap && goldInsightsSnap.exists) {
            const gid = goldInsightsSnap.data();
            if (gid) {
                contextText += `Sentiment: ${gid.sentiment || ''} (Score: ${gid.sentimentScore ?? 0})\n`;
                contextText += `Sentiment Summary: "${gid.sentimentSummary || ''}"\n`;
                contextText += `Predicted Trend: ${gid.predictedTrend || ''}\n`;
                contextText += `Predicted Range: ${gid.predictedPriceRange || ''}\n`;
                contextText += `Rationale: "${gid.predictionRationale || ''}"\n`;
            } else {
                contextText += "Gold AI market analysis data empty.\n";
            }
        } else {
            contextText += "No gold AI market analysis available.\n";
        }
        contextText += "\n";

        contextText += "--- GOLD CHIT ADVICE (BUYING SUGGESTIONS) ---\n";
        if (goldChitAdviceSnap && goldChitAdviceSnap.exists) {
            const gca = goldChitAdviceSnap.data();
            if (gca) {
                contextText += `Recommendation: "${gca.recommendation || ''}"\n`;
                contextText += `Short Reason: "${gca.shortReason || ''}"\n`;
                contextText += `Full Analysis: "${gca.fullAnalysis || ''}"\n`;
            } else {
                contextText += "Gold chit buying advice data empty.\n";
            }
        } else {
            contextText += "No gold chit buying advice available.\n";
        }
        contextText += "\n";

        contextText += "--- AI JOB ASSISTANT RECENT APPLICATIONS ---\n";
        if (jobAppsSnap && !jobAppsSnap.empty) {
            const todayStr = nowKolkata.format('YYYY-MM-DD');
            let todayCount = 0;
            jobAppsSnap.docs.forEach((doc: any) => {
                const d = doc.data();
                const appliedDate = d.appliedAt ? moment(d.appliedAt.toDate ? d.appliedAt.toDate() : d.appliedAt).tz('Asia/Kolkata').format('YYYY-MM-DD') : '';
                const isToday = appliedDate === todayStr;
                if (isToday) todayCount++;
                contextText += `- Role: "${d.jobTitle}", Company: "${d.companyName}", Recipient: "${d.recipientEmail}", Status: ${d.status || 'sent'}, Date: ${appliedDate || 'Recent'}${isToday ? ' (Applied Today)' : ''}\n`;
            });
            contextText += `Total applications listed: ${jobAppsSnap.size}. Total applied today: ${todayCount}.\n`;
        } else {
            contextText += "No job applications sent yet. Zero applications today.\n";
        }
        contextText += "\n";

        contextText += "--- UPCOMING TECH EVENTS ---\n";
        if (eventsSnap && !eventsSnap.empty) {
            eventsSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- Title: "${d.title}", Date: ${d.date}, Platform: "${d.platform || ''}"\n`;
            });
        } else {
            contextText += "No upcoming tech events.\n";
        }
        contextText += "\n";

        contextText += "--- UPCOMING WALK-IN DRIVES ---\n";
        if (walkinsSnap && !walkinsSnap.empty) {
            walkinsSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- Company: "${d.title}", Role: "${d.role || ''}", Date: ${d.date}, Location: "${d.location || ''}"\n`;
            });
        } else {
            contextText += "No upcoming walk-in drives.\n";
        }
        contextText += "\n";

        // Astro Calendar & Lunar Phases
        contextText += "--- ASTRO CALENDAR & LUNAR PHASES ---\n";
        const todayPhase = getTodayLunarPhase(nowKolkata);
        const tomorrowPhase = getTodayLunarPhase(nowKolkata.clone().add(1, 'day'));
        contextText += `Today's Lunar Status: ${todayPhase === 'new_moon' ? '🌑 Amavasya (New Moon) Today' : todayPhase === 'full_moon' ? '🌕 Pournami (Full Moon) Today' : 'Regular lunar day'}\n`;
        if (tomorrowPhase) {
            contextText += `Tomorrow's Lunar Status: ${tomorrowPhase === 'new_moon' ? '🌑 Amavasya (New Moon) Tomorrow' : '🌕 Pournami (Full Moon) Tomorrow'}\n`;
        }
        const dayOfWeek = nowKolkata.day(); // 0 = Sun, 1 = Mon, ..., 6 = Sat
        const rahuYamaMap: { [key: number]: { rahu: string, yama: string } } = {
            0: { rahu: "04:30 PM - 06:00 PM", yama: "12:00 PM - 01:30 PM" },
            1: { rahu: "07:30 AM - 09:00 AM", yama: "01:30 PM - 03:00 PM" },
            2: { rahu: "03:00 PM - 04:30 PM", yama: "09:00 AM - 10:30 AM" },
            3: { rahu: "12:00 PM - 01:30 PM", yama: "07:30 AM - 09:00 AM" },
            4: { rahu: "01:30 PM - 03:00 PM", yama: "06:00 AM - 07:30 AM" },
            5: { rahu: "10:30 AM - 12:00 PM", yama: "03:00 PM - 04:30 PM" },
            6: { rahu: "09:00 AM - 10:30 AM", yama: "01:30 PM - 03:00 PM" }
        };
        const ry = rahuYamaMap[dayOfWeek];
        if (ry) {
            contextText += `Today's Rahu Kaalam: ${ry.rahu}, Yamagandam: ${ry.yama}\n`;
        }
        contextText += "\n";

        // 4. Send query to Gemini
        const systemInstruction = `You are the RemindBuddy AI Voice Assistant. Your goal is to help the user manage reminders, daily alarms, notes, work shifts, gold prices & insights, tech events, walk-in drives, astro calendar & lunar phases, and job applications.

CRITICAL PRIVACY & SECURITY GUARDRAILS (STRICT COMPLIANCE REQUIRED):
1. USER DATA ISOLATION: You are strictly querying and accessing ONLY the authenticated user's private data. You NEVER share, summarize, or reveal data across different users. (Gold price is the only shared global market information).
2. FINANCE PRIVACY: The Finance feature (bank accounts, balances, transactions, debit/credit SMS, spends, and budgets) is strictly private and confidential. You do NOT have access to it and must NEVER query, speak about, or reveal bank accounts, balances, or transactions. If the user asks about bank balances, spending, or finances, politely respond: "I do not have access to your private financial details or bank balances for privacy and security."
3. SECURE VAULT PRIVACY: The Secure Vault feature is encrypted and strictly confidential. You do NOT have access to it and must NEVER query, speak about, or reveal vault documents, passwords, credentials, or secret files. If asked, politely respond: "I do not have access to your Secure Vault documents or passwords."
4. ADMIN CONSOLE & USER CREDENTIALS: The Admin Console, user management, and user passwords/credentials are strictly restricted. You do not have access. If asked, politely decline.
5. GCP CLOUD COST TRACKER: Google Cloud Platform cost tracker and infrastructure billing are strictly restricted system administrator data. You do not have access.

Look at the user's voice search or typed query, and the current state of their app data:
1. Answer queries about Job applications (e.g. what jobs applied today, companies, status), Walk-in drives, Tech events, Notes, Work shifts, Calendar reminders, Daily alarms, Gold rate & buying advice, and Astro calendar (lunar phases like Amavasya/Pournami, Rahu Kaalam, Yamagandam).
2. Resolve dates and times using the provided Current Date and Time (IST) anchor (e.g. today, tomorrow, this week).
3. If they ask to add/create or delete/remove items (reminders, notes): extract the action and its parameters.
4. Keep the spokenResponse extremely brief, friendly, natural, and speech-ready (avoid markdown formatting like asterisks or bullet points since it will be read out loud).

Output MUST be a JSON object matching this schema:
{
  "spokenResponse": "Speech-ready text to be read by Text-to-Speech",
  "action": {
    "type": "CREATE_REMINDER" | "DELETE_REMINDER" | "CREATE_NOTE" | "DELETE_NOTE" | "NONE",
    "params": {
      "reminderId": "Firestore document ID (for DELETE)",
      "title": "Title (for CREATE_REMINDER, CREATE_NOTE)",
      "content": "Content body (for CREATE_NOTE)",
      "date": "YYYY-MM-DD (for CREATE_REMINDER)",
      "time": "HH:MM (for CREATE_REMINDER)",
      "snoozeEnabled": true/false,
      "snoozeIntervalMinutes": 15,
      "maxSnoozeCount": 3,
      "noteId": "Firestore document ID (for DELETE)"
    }
  }
}`;

        const payload = {
            contents: [
                {
                    parts: [
                        { text: `System Instructions:\n${systemInstruction}\n\nCurrent App State Context:\n${contextText}\n\nUser Query: "${query}"` }
                    ]
                }
            ],
            generationConfig: {
                responseMimeType: "application/json",
                responseSchema: {
                    type: "OBJECT",
                    properties: {
                        spokenResponse: { type: "STRING" },
                        action: {
                            type: "OBJECT",
                            properties: {
                                type: {
                                    type: "STRING",
                                    enum: [
                                        "CREATE_REMINDER", "DELETE_REMINDER",
                                        "CREATE_NOTE", "DELETE_NOTE",
                                        "NONE"
                                    ]
                                },
                                params: {
                                    type: "OBJECT",
                                    properties: {
                                        reminderId: { type: "STRING" },
                                        title: { type: "STRING" },
                                        content: { type: "STRING" },
                                        date: { type: "STRING" },
                                        time: { type: "STRING" },
                                        snoozeEnabled: { type: "BOOLEAN" },
                                        snoozeIntervalMinutes: { type: "INTEGER" },
                                        maxSnoozeCount: { type: "INTEGER" },
                                        noteId: { type: "STRING" }
                                    }
                                }
                            },
                            required: ["type"]
                        }
                    },
                    required: ["spokenResponse", "action"]
                }
            }
        };

        const geminiResult = await callGeminiAPI(payload, { timeout: 30000 });
        const geminiText = geminiResult.text;
        const result = JSON.parse(geminiText);

        let actionExecuted = null;

        // 5. Execute action in Firestore if applicable
        if (result.action && result.action.type !== "NONE") {
            const actionType = result.action.type;
            const params = result.action.params || {};

            if (actionType === "CREATE_REMINDER") {
                const { title, date, time } = params;
                if (title && date && time) {
                    const snoozeEnabled = params.snoozeEnabled !== undefined ? params.snoozeEnabled : true;
                    const snoozeIntervalMinutes = params.snoozeIntervalMinutes !== undefined ? params.snoozeIntervalMinutes : 15;
                    const maxSnoozeCount = params.maxSnoozeCount !== undefined ? params.maxSnoozeCount : 3;

                    const docRef = await db.collection("users").doc(uid).collection("calendar_reminders").add({
                        title,
                        description: "Created via Voice Assistant",
                        date,
                        time,
                        isRecurring: false,
                        status: "scheduled",
                        snoozeEnabled,
                        snoozeIntervalMinutes,
                        maxSnoozeCount,
                        currentSnoozeCount: 0,
                        createdAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    actionExecuted = { type: actionType, id: docRef.id, params };
                }
            } else if (actionType === "DELETE_REMINDER") {
                const { reminderId } = params;
                if (reminderId) {
                    await db.collection("users").doc(uid).collection("calendar_reminders").doc(reminderId).delete();
                    actionExecuted = { type: actionType, id: reminderId };
                }
            } else if (actionType === "CREATE_NOTE") {
                const { title, content } = params;
                if (title) {
                    const docRef = await db.collection("users").doc(uid).collection("notes").add({
                        title,
                        content: content || "",
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        updatedAt: admin.firestore.FieldValue.serverTimestamp()
                    });
                    actionExecuted = { type: actionType, id: docRef.id, params };
                }
            } else if (actionType === "DELETE_NOTE") {
                const { noteId } = params;
                if (noteId) {
                    await db.collection("users").doc(uid).collection("notes").doc(noteId).delete();
                    actionExecuted = { type: actionType, id: noteId };
                }
            }
        }

        return {
            success: true,
            spokenResponse: result.spokenResponse,
            action: result.action,
            actionExecuted
        };

    } catch (err: any) {
        console.error("Error in voiceAssistantQuery:", err);
        throw new functions.https.HttpsError('internal', err.message || 'Failed to process voice query.');
    }
});
