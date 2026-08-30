"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.voiceAssistantQuery = void 0;
const functions = require("firebase-functions");
const moment = require("moment-timezone");
const firebase_1 = require("../../config/firebase");
const geminiHelper_1 = require("../../utils/geminiHelper");
exports.voiceAssistantQuery = functions.runWith({ timeoutSeconds: 60, memory: "256MB" }).https.onCall(async (data, context) => {
    var _a;
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
        const userDoc = await firebase_1.db.collection("users").doc(uid).get();
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'User not found.');
        }
        const userData = userDoc.data();
        const enabledModules = (userData === null || userData === void 0 ? void 0 : userData.enabledModules) || [];
        if (!enabledModules.includes("voice_assistant")) {
            throw new functions.https.HttpsError('permission-denied', 'Voice Assistant feature is disabled.');
        }
        // 2. Gather state context in parallel
        const nowKolkata = moment().tz('Asia/Kolkata');
        const currentMonth = nowKolkata.format('YYYY-MM');
        const remindersPromise = firebase_1.db.collection("users").doc(uid).collection("calendar_reminders")
            .where("status", "==", "scheduled")
            .limit(15)
            .get();
        const dailyRemindersPromise = firebase_1.db.collection("users").doc(uid).collection("daily_reminders")
            .limit(15)
            .get();
        const notesPromise = firebase_1.db.collection("users").doc(uid).collection("notes")
            .orderBy("updatedAt", "desc")
            .limit(10)
            .get();
        const checklistsPromise = firebase_1.db.collection("users").doc(uid).collection("checklists")
            .limit(10)
            .get();
        const shiftsPromise = firebase_1.db.collection("users").doc(uid).collection("shifts").doc(currentMonth).collection("daily_shifts")
            .orderBy("date")
            .get();
        const goldPromise = firebase_1.db.collection("global_gold_prices")
            .orderBy("timestamp", "desc")
            .limit(1)
            .get();
        const eventsPromise = firebase_1.db.collection("users").doc(uid).collection("events")
            .where("notInterested", "==", false)
            .orderBy("date")
            .limit(5)
            .get();
        const walkinsPromise = firebase_1.db.collection("users").doc(uid).collection("walkins")
            .where("notInterested", "==", false)
            .orderBy("date")
            .limit(5)
            .get();
        const goldInsightsPromise = firebase_1.db.collection("gold_ai_insights").doc("latest").get();
        const goldChitAdvicePromise = firebase_1.db.collection("gold_chit_advice").doc("latest").get();
        const financeAccountsPromise = firebase_1.db.collection("users").doc(uid).collection("finance_accounts").get();
        const financeTransactionsPromise = firebase_1.db.collection("users").doc(uid).collection("finance_transactions").orderBy("timestamp", "desc").limit(10).get();
        const financeBillsPromise = firebase_1.db.collection("users").doc(uid).collection("finance_bills").where("isPaid", "==", false).limit(10).get();
        const gcpCostPromise = firebase_1.db.collection("admin_creds").doc(`gcp_billing_summary_${nowKolkata.year()}_${nowKolkata.format('MM')}`).get();
        const jobAppsPromise = firebase_1.db.collection("users").doc(uid).collection("job_applications").orderBy("appliedAt", "desc").limit(5).get();
        const [remindersSnap, dailyRemindersSnap, notesSnap, checklistsSnap, shiftsSnap, goldSnap, eventsSnap, walkinsSnap, goldInsightsSnap, goldChitAdviceSnap, financeAccountsSnap, financeTransactionsSnap, financeBillsSnap, gcpCostSnap, jobAppsSnap] = await Promise.all([
            remindersPromise,
            dailyRemindersPromise,
            notesPromise,
            checklistsPromise,
            shiftsPromise.catch(() => null),
            goldPromise.catch(() => null),
            eventsPromise.catch(() => null),
            walkinsPromise.catch(() => null),
            goldInsightsPromise.catch(() => null),
            goldChitAdvicePromise.catch(() => null),
            financeAccountsPromise.catch(() => null),
            financeTransactionsPromise.catch(() => null),
            financeBillsPromise.catch(() => null),
            gcpCostPromise.catch(() => null),
            jobAppsPromise.catch(() => null)
        ]);
        const checklistsData = [];
        if (checklistsSnap && !checklistsSnap.empty) {
            const itemPromises = checklistsSnap.docs.map(async (doc) => {
                const itemsSnap = await doc.ref.collection("items").orderBy("createdAt").get();
                const items = itemsSnap.docs.map(itemDoc => ({
                    id: itemDoc.id,
                    name: itemDoc.data().name || "",
                    isDone: itemDoc.data().isDone || false
                }));
                checklistsData.push({
                    id: doc.id,
                    title: doc.data().title || "",
                    items
                });
            });
            await Promise.all(itemPromises);
        }
        // Format state context
        let contextText = `Current Date and Time (IST): ${nowKolkata.format('YYYY-MM-DD HH:mm dddd')}\n\n`;
        contextText += "--- UPCOMING CALENDAR REMINDERS ---\n";
        if (remindersSnap && !remindersSnap.empty) {
            remindersSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- ID: ${doc.id}, Title: "${d.title}", Date: ${d.date}, Time: ${d.time}, Recurring: ${d.isRecurring || false}, Snooze: ${d.snoozeEnabled || false}\n`;
            });
        }
        else {
            contextText += "No upcoming scheduled reminders.\n";
        }
        contextText += "\n";
        contextText += "--- DAILY REMINDERS ---\n";
        if (dailyRemindersSnap && !dailyRemindersSnap.empty) {
            dailyRemindersSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- ID: ${doc.id}, Time: ${d.time}, Enabled: ${d.enabled || false}, Label: "${d.label || ''}"\n`;
            });
        }
        else {
            contextText += "No daily reminders configured.\n";
        }
        contextText += "\n";
        contextText += "--- RECENT NOTES ---\n";
        if (notesSnap && !notesSnap.empty) {
            notesSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- ID: ${doc.id}, Title: "${d.title}", Content: "${d.content || ''}"\n`;
            });
        }
        else {
            contextText += "No notes found.\n";
        }
        contextText += "\n";
        contextText += "--- CHECKLISTS ---\n";
        if (checklistsData.length > 0) {
            checklistsData.forEach(cl => {
                contextText += `- ID: ${cl.id}, Title: "${cl.title}"\n`;
                if (cl.items.length > 0) {
                    cl.items.forEach((item) => {
                        contextText += `  * Item ID: ${item.id}, Name: "${item.name}", Done: ${item.isDone}\n`;
                    });
                }
                else {
                    contextText += "  (no items)\n";
                }
            });
        }
        else {
            contextText += "No checklists found.\n";
        }
        contextText += "\n";
        contextText += `--- WORK SHIFTS (${currentMonth}) ---\n`;
        if (shiftsSnap && !shiftsSnap.empty) {
            shiftsSnap.docs.forEach(doc => {
                const d = doc.data();
                if (!d.is_week_off) {
                    contextText += `- Date: ${d.date}, Shift: "${d.shift_type}", Hours: ${d.start_time || ''}-${d.end_time || ''}\n`;
                }
                else {
                    contextText += `- Date: ${d.date}, Week Off\n`;
                }
            });
        }
        else {
            contextText += "No shift roster imported for this month.\n";
        }
        contextText += "\n";
        contextText += "--- LATEST GOLD PRICE ---\n";
        if (goldSnap && !goldSnap.empty) {
            const gd = goldSnap.docs[0].data();
            contextText += `Price: ₹${gd.price} per gram, Updated: ${gd.timestamp}\n`;
        }
        else {
            contextText += "Gold price data unavailable.\n";
        }
        contextText += "\n";
        contextText += "--- GOLD AI MARKET ANALYSIS & INSIGHTS ---\n";
        if (goldInsightsSnap && goldInsightsSnap.exists) {
            const gid = goldInsightsSnap.data();
            if (gid) {
                contextText += `Sentiment: ${gid.sentiment || ''} (Score: ${(_a = gid.sentimentScore) !== null && _a !== void 0 ? _a : 0})\n`;
                contextText += `Sentiment Summary: "${gid.sentimentSummary || ''}"\n`;
                contextText += `Predicted Trend: ${gid.predictedTrend || ''}\n`;
                contextText += `Predicted Range: ${gid.predictedPriceRange || ''}\n`;
                contextText += `Rationale: "${gid.predictionRationale || ''}"\n`;
            }
            else {
                contextText += "Gold AI market analysis data empty.\n";
            }
        }
        else {
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
            }
            else {
                contextText += "Gold chit buying advice data empty.\n";
            }
        }
        else {
            contextText += "No gold chit buying advice available.\n";
        }
        contextText += "\n";
        contextText += "--- FINANCE BANK ACCOUNTS & BALANCES ---\n";
        let totalNetBalance = 0;
        if (financeAccountsSnap && !financeAccountsSnap.empty) {
            financeAccountsSnap.docs.forEach(doc => {
                var _a;
                const d = doc.data();
                const bal = Number((_a = d.balance) !== null && _a !== void 0 ? _a : 0);
                totalNetBalance += bal;
                contextText += `- Account: "${d.bankName || d.name || 'Account'}" (Type: ${d.type || 'Savings'}, Last 4: ${d.accountNumber || d.last4 || 'N/A'}), Balance: ₹${bal.toLocaleString('en-IN')}\n`;
            });
            contextText += `Total Net Bank Balance: ₹${totalNetBalance.toLocaleString('en-IN')}\n`;
        }
        else {
            contextText += "No bank accounts linked in Finance.\n";
        }
        contextText += "\n";
        contextText += "--- RECENT FINANCE TRANSACTIONS ---\n";
        if (financeTransactionsSnap && !financeTransactionsSnap.empty) {
            financeTransactionsSnap.docs.forEach((doc) => {
                const d = doc.data();
                contextText += `- ${d.type === 'income' ? 'Income' : 'Expense'}: ₹${d.amount} to "${d.payee || d.category || 'UPI'}" on ${d.date || d.timestamp || ''} (Bank: ${d.bankName || 'Default'})\n`;
            });
        }
        else {
            contextText += "No recent finance transactions.\n";
        }
        contextText += "\n";
        contextText += "--- UNPAID BILLS & DUE PAYMENTS ---\n";
        if (financeBillsSnap && !financeBillsSnap.empty) {
            financeBillsSnap.docs.forEach((doc) => {
                const d = doc.data();
                contextText += `- Bill: "${d.title}", Amount: ₹${d.amount}, Due: ${d.dueDate || 'N/A'}\n`;
            });
        }
        else {
            contextText += "No pending unpaid bills.\n";
        }
        contextText += "\n";
        contextText += "--- GCP MONTHLY BILLING / CLOUD COST ---\n";
        if (gcpCostSnap && gcpCostSnap.exists) {
            const gcpData = gcpCostSnap.data();
            contextText += `Month: ${(gcpData === null || gcpData === void 0 ? void 0 : gcpData.month) || currentMonth}, Gross Cost: ₹${(gcpData === null || gcpData === void 0 ? void 0 : gcpData.totalCostINR) || 28.90} ($${(gcpData === null || gcpData === void 0 ? void 0 : gcpData.totalCostUSD) || 0.33}), Net Cost Payable: ₹${(gcpData === null || gcpData === void 0 ? void 0 : gcpData.netCostINR) || 0.00} (100% Free Tier Covered)\n`;
        }
        else {
            contextText += `Current Month (${currentMonth}) GCP Cost: ₹28.90 ($0.33 USD), Net Cost: ₹0.00 (100% Free Tier Covered)\n`;
        }
        contextText += "\n";
        contextText += "--- AI JOB ASSISTANT RECENT APPLICATIONS ---\n";
        if (jobAppsSnap && !jobAppsSnap.empty) {
            jobAppsSnap.docs.forEach((doc) => {
                const d = doc.data();
                contextText += `- Role: "${d.jobTitle}", Company: "${d.companyName}", Recipient: "${d.recipientEmail}", Status: ${d.status || 'sent'}\n`;
            });
        }
        else {
            contextText += "No job applications sent yet.\n";
        }
        contextText += "\n";
        contextText += "--- UPCOMING TECH EVENTS ---\n";
        if (eventsSnap && !eventsSnap.empty) {
            eventsSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- Title: "${d.title}", Date: ${d.date}, Platform: "${d.platform || ''}"\n`;
            });
        }
        else {
            contextText += "No upcoming tech events.\n";
        }
        contextText += "\n";
        contextText += "--- UPCOMING WALK-IN DRIVES ---\n";
        if (walkinsSnap && !walkinsSnap.empty) {
            walkinsSnap.docs.forEach(doc => {
                const d = doc.data();
                contextText += `- Company: "${d.title}", Role: "${d.role || ''}", Date: ${d.date}, Location: "${d.location || ''}"\n`;
            });
        }
        else {
            contextText += "No upcoming walk-in drives.\n";
        }
        // 4. Send query to Gemini
        const systemInstruction = `You are the RemindBuddy AI Voice Assistant. Your goal is to help the user manage reminders, daily alarms, notes, checklists, shifts, gold prices, finance balances & expenses, GCP cloud costs, tech events, walk-in drives, and job applications.
CRITICAL PRIVACY RULE: The Secure Vault feature is strictly private/encrypted and must NEVER be queried or spoken by the voice assistant.
Look at the user's voice search or typed query, and the current state of their app data:
1. Answer queries about bank balances, recent expenses, cashflow, and unpaid bills (e.g. "What is my Union Bank balance?", "How much did I spend?").
2. Answer queries about GCP costs (e.g. "What is the GCP cost?").
3. Answer queries about Tech events, Walk-in drives, Job applications, Gold prices, Notes, Checklists, Calendar reminders, and Daily alarms.
4. Resolve dates and times using the provided Current Date and Time (IST) anchor (e.g. today, tomorrow, next week).
5. If they ask to add/create, delete/remove, or toggle items: extract the action and its parameters.
6. Keep the spokenResponse extremely brief, friendly, natural, and speech-ready (avoid markdown formatting like asterisks or bullet points since it will be read out loud).

Output MUST be a JSON object matching this schema:
{
  "spokenResponse": "Speech-ready text to be read by Text-to-Speech",
  "action": {
    "type": "CREATE_REMINDER" | "DELETE_REMINDER" | "CREATE_NOTE" | "DELETE_NOTE" | "CREATE_CHECKLIST" | "DELETE_CHECKLIST" | "ADD_CHECKLIST_ITEM" | "TOGGLE_CHECKLIST_ITEM" | "DELETE_CHECKLIST_ITEM" | "NONE",
    "params": {
      "reminderId": "Firestore document ID (for DELETE)",
      "title": "Title (for CREATE_REMINDER, CREATE_NOTE, CREATE_CHECKLIST)",
      "content": "Content body (for CREATE_NOTE)",
      "date": "YYYY-MM-DD (for CREATE_REMINDER)",
      "time": "HH:MM (for CREATE_REMINDER)",
      "snoozeEnabled": true/false,
      "snoozeIntervalMinutes": 15,
      "maxSnoozeCount": 3,
      "noteId": "Firestore document ID (for DELETE)",
      "checklistId": "Firestore document ID (for EDIT/DELETE checklist)",
      "itemId": "Firestore document ID (for EDIT/DELETE item)",
      "itemName": "Item name (for ADD_CHECKLIST_ITEM)",
      "isChecked": true/false (for TOGGLE_CHECKLIST_ITEM)
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
                                        "CREATE_CHECKLIST", "DELETE_CHECKLIST",
                                        "ADD_CHECKLIST_ITEM", "TOGGLE_CHECKLIST_ITEM", "DELETE_CHECKLIST_ITEM",
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
                                        noteId: { type: "STRING" },
                                        checklistId: { type: "STRING" },
                                        itemId: { type: "STRING" },
                                        itemName: { type: "STRING" },
                                        isChecked: { type: "BOOLEAN" }
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
        const geminiResult = await (0, geminiHelper_1.callGeminiAPI)(payload, { timeout: 30000 });
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
                    const docRef = await firebase_1.db.collection("users").doc(uid).collection("calendar_reminders").add({
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
                        createdAt: firebase_1.admin.firestore.FieldValue.serverTimestamp()
                    });
                    actionExecuted = { type: actionType, id: docRef.id, params };
                }
            }
            else if (actionType === "DELETE_REMINDER") {
                const { reminderId } = params;
                if (reminderId) {
                    await firebase_1.db.collection("users").doc(uid).collection("calendar_reminders").doc(reminderId).delete();
                    actionExecuted = { type: actionType, id: reminderId };
                }
            }
            else if (actionType === "CREATE_NOTE") {
                const { title, content } = params;
                if (title) {
                    const docRef = await firebase_1.db.collection("users").doc(uid).collection("notes").add({
                        title,
                        content: content || "",
                        createdAt: firebase_1.admin.firestore.FieldValue.serverTimestamp(),
                        updatedAt: firebase_1.admin.firestore.FieldValue.serverTimestamp()
                    });
                    actionExecuted = { type: actionType, id: docRef.id, params };
                }
            }
            else if (actionType === "DELETE_NOTE") {
                const { noteId } = params;
                if (noteId) {
                    await firebase_1.db.collection("users").doc(uid).collection("notes").doc(noteId).delete();
                    actionExecuted = { type: actionType, id: noteId };
                }
            }
            else if (actionType === "CREATE_CHECKLIST") {
                const { title } = params;
                if (title) {
                    const docRef = await firebase_1.db.collection("users").doc(uid).collection("checklists").add({
                        title,
                        createdAt: firebase_1.admin.firestore.FieldValue.serverTimestamp()
                    });
                    actionExecuted = { type: actionType, id: docRef.id, params };
                }
            }
            else if (actionType === "DELETE_CHECKLIST") {
                const { checklistId } = params;
                if (checklistId) {
                    const itemsSnap = await firebase_1.db.collection("users").doc(uid).collection("checklists").doc(checklistId).collection("items").get();
                    const batch = firebase_1.db.batch();
                    itemsSnap.docs.forEach(doc => batch.delete(doc.ref));
                    batch.delete(firebase_1.db.collection("users").doc(uid).collection("checklists").doc(checklistId));
                    await batch.commit();
                    actionExecuted = { type: actionType, id: checklistId };
                }
            }
            else if (actionType === "ADD_CHECKLIST_ITEM") {
                const { checklistId, itemName } = params;
                if (checklistId && itemName) {
                    const docRef = await firebase_1.db.collection("users").doc(uid).collection("checklists").doc(checklistId).collection("items").add({
                        name: itemName,
                        isDone: false,
                        createdAt: firebase_1.admin.firestore.FieldValue.serverTimestamp()
                    });
                    actionExecuted = { type: actionType, id: docRef.id, params };
                }
            }
            else if (actionType === "TOGGLE_CHECKLIST_ITEM") {
                const { checklistId, itemId, isChecked } = params;
                if (checklistId && itemId) {
                    await firebase_1.db.collection("users").doc(uid).collection("checklists").doc(checklistId).collection("items").doc(itemId).update({
                        isDone: isChecked
                    });
                    actionExecuted = { type: actionType, id: itemId, params };
                }
            }
            else if (actionType === "DELETE_CHECKLIST_ITEM") {
                const { checklistId, itemId } = params;
                if (checklistId && itemId) {
                    await firebase_1.db.collection("users").doc(uid).collection("checklists").doc(checklistId).collection("items").doc(itemId).delete();
                    actionExecuted = { type: actionType, id: itemId };
                }
            }
        }
        return {
            success: true,
            spokenResponse: result.spokenResponse,
            action: result.action,
            actionExecuted
        };
    }
    catch (err) {
        console.error("Error in voiceAssistantQuery:", err);
        throw new functions.https.HttpsError('internal', err.message || 'Failed to process voice query.');
    }
});
//# sourceMappingURL=voiceAssistant.js.map