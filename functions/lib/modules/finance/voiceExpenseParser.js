"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseVoiceExpensesWithAI = void 0;
const functions = require("firebase-functions");
const firebase_1 = require("../../config/firebase");
const geminiHelper_1 = require("../../utils/geminiHelper");
/**
 * High-speed AI Voice Expense Parser for Smart Bank Tracker
 * Parses multiple spoken transactions from a single speech input using the user's BYOK Gemini API Key.
 * Fallback cascade: gemini-3.7-flash -> gemini-3.6-flash -> gemini-3.5-flash -> gemini-2.5-flash
 */
exports.parseVoiceExpensesWithAI = functions.runWith({ timeoutSeconds: 60, memory: "1GB" }).https.onCall(async (data, context) => {
    var _a;
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    const uid = context.auth.uid;
    const { transcript, accounts, customCategories } = data;
    if (!transcript || typeof transcript !== 'string' || transcript.trim().length === 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Voice transcript text is required.');
    }
    // 1. Fetch user's individual Gemini API Key (Per-user BYOK requirement)
    let userGeminiKey = "";
    try {
        const userDoc = await firebase_1.db.collection("users").doc(uid).get();
        if (userDoc.exists) {
            const uData = userDoc.data() || {};
            userGeminiKey = (((_a = uData.userApiKeys) === null || _a === void 0 ? void 0 : _a.geminiApiKey) || uData.geminiApiKey || "").trim();
        }
    }
    catch (e) {
        console.warn("[VoiceExpenseParser] Could not fetch user Gemini API Key:", e.message);
    }
    if (!userGeminiKey) {
        throw new functions.https.HttpsError('failed-precondition', 'Please configure your Gemini API Key in AI Keys Settings to use Voice Expense Logging.');
    }
    // 2. Prepare Category & Account context
    const defaultCategories = [
        "Food & Dining",
        "Fuel & Travel",
        "Groceries",
        "Bills & Utilities",
        "Shopping",
        "Personal Transfer",
        "Self Transfer",
        "Entertainment",
        "Health & Medical",
        "Personal Care",
        "Investment",
        "Salary / Income",
        "Borrowed",
        "Lended",
        "Other"
    ];
    const combinedCategories = Array.from(new Set([
        ...defaultCategories,
        ...(Array.isArray(customCategories) ? customCategories.map((c) => String(c).trim()).filter(Boolean) : [])
    ]));
    const accountsListStr = Array.isArray(accounts) && accounts.length > 0
        ? accounts.map((a) => `- ${a.name || a.id}`).join('\n')
        : "- Cash\n- UPI / GPay / PhonePe\n- Primary Bank Account";
    const prompt = `You are a high-speed, intelligent financial transaction parser for RemindBuddy Smart Bank Tracker.
The user dictated multiple daily expenses, payments, or received money in a single voice sentence.

Extract EVERY separate transaction mentioned in the spoken text and output a JSON object with a "transactions" array.

Available Categories:
${combinedCategories.map(c => `- ${c}`).join('\n')}

Known Accounts / Payment Modes:
${accountsListStr}

For each transaction found, extract:
- "title": Concise 2-4 word description (e.g., "Breakfast", "Petrol Refill", "Auto Fare", "Received from Rahul", "Electricity Bill")
- "amount": Positive numeric amount (float or int). If user says "50 rupees", amount is 50. If "2.5k", amount is 2500.
- "type": "debit" (for spent, paid, bought, transferred out) OR "credit" (for received, cashback, salary, refund, transferred in)
- "category": Best matching category from the list above.
- "account": Name of the payment mode or bank if mentioned (e.g. "HDFC", "SBI", "GPay", "Cash", "Credit Card"), or null if none mentioned.
- "notes": Any specific merchant or person name mentioned.

CRITICAL RULES:
1. If multiple transactions are spoken in one sentence (e.g. "I paid 50 for food, 200 for fuel, and received 500 from Rahul"), you MUST output 3 distinct transaction items in the array.
2. Return ONLY valid JSON matching this schema:
{
  "transactions": [
    {
      "title": string,
      "amount": number,
      "type": "debit" | "credit",
      "category": string,
      "account": string | null,
      "notes": string
    }
  ]
}

Spoken Text:
"${transcript.trim()}"`;
    const geminiPayload = {
        contents: [
            {
                parts: [{ text: prompt }]
            }
        ],
        generationConfig: {
            responseMimeType: "application/json",
            temperature: 0.1,
        }
    };
    // 3. Call Gemini with explicit user API key and model fallback cascade
    const candidateModels = [
        "gemini-3.7-flash",
        "gemini-3.6-flash",
        "gemini-3.5-flash",
        "gemini-2.5-flash"
    ];
    try {
        const aiResponse = await (0, geminiHelper_1.callGeminiAPI)(geminiPayload, {
            apiKey: userGeminiKey,
            models: candidateModels,
            timeout: 25000,
            maxRetries: 1
        });
        const rawText = aiResponse.text.trim();
        let parsedResult = null;
        try {
            parsedResult = JSON.parse(rawText);
        }
        catch (jsonErr) {
            // Attempt markdown block extraction
            const jsonMatch = rawText.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
            if (jsonMatch && jsonMatch[1]) {
                parsedResult = JSON.parse(jsonMatch[1]);
            }
            else {
                throw new Error("Could not parse AI response as JSON: " + rawText);
            }
        }
        const rawList = Array.isArray(parsedResult === null || parsedResult === void 0 ? void 0 : parsedResult.transactions)
            ? parsedResult.transactions
            : (Array.isArray(parsedResult) ? parsedResult : []);
        const validTransactions = rawList.map((tx) => ({
            title: String(tx.title || 'Expense').trim(),
            amount: Math.abs(parseFloat(tx.amount) || 0.0),
            type: String(tx.type || 'debit').toLowerCase().includes('credit') ? 'credit' : 'debit',
            category: combinedCategories.includes(tx.category) ? tx.category : 'Other',
            account: tx.account ? String(tx.account).trim() : null,
            notes: tx.notes ? String(tx.notes).trim() : ''
        })).filter((tx) => tx.amount > 0);
        return {
            success: true,
            modelUsed: aiResponse.modelUsed,
            transcript: transcript.trim(),
            transactions: validTransactions,
            count: validTransactions.length
        };
    }
    catch (err) {
        console.error("[VoiceExpenseParser] Extraction failed:", err.message || err);
        throw new functions.https.HttpsError('internal', err.message || 'Failed to extract voice expenses with Gemini.');
    }
});
//# sourceMappingURL=voiceExpenseParser.js.map