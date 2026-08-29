"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.analyzeRosterImage = void 0;
const functions = require("firebase-functions");
const axios_1 = require("axios");
const firebase_1 = require("../../config/firebase");
exports.analyzeRosterImage = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    // Ensure user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const { image, employeeName } = data;
    if (!image || !employeeName) {
        throw new functions.https.HttpsError('invalid-argument', 'Image and employeeName are required.');
    }
    // 1. Fetch the Gemini API key from Firestore admin_creds/gemini_config
    const configDoc = await firebase_1.db.collection("admin_creds").doc("gemini_config").get();
    let apiKey = "";
    if (configDoc.exists) {
        apiKey = ((_a = configDoc.data()) === null || _a === void 0 ? void 0 : _a.apiKey) || "";
    }
    if (!apiKey) {
        throw new functions.https.HttpsError('failed-precondition', 'Gemini API key is not configured in admin console.');
    }
    // 2. Prepare payload for Gemini API
    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
    const prompt = `Analyze the work roster image. Extract the shift schedule for employee "${employeeName}".
The output MUST be a JSON object matching this schema. If a shift date is unclear or missing, mark it as "week_off".

Shift Types in roster:
- M or morning: Morning shift (06:00 - 14:00)
- A or afternoon: Afternoon shift (14:00 - 22:00)
- N or night: Night shift (22:00 - 06:00)
- L or holiday: Holiday / Week Off (is_week_off: true, shift_type: 'week_off')
- Empty box: Week Off (is_week_off: true, shift_type: 'week_off')

Required JSON format:
{
  "employee_name": "${employeeName}",
  "month": "Month Year (e.g. March 2026)",
  "shifts": [
    {
      "date": "YYYY-MM-DD",
      "shift_type": "morning|afternoon|night|week_off",
      "start_time": "HH:MM or null",
      "end_time": "HH:MM or null",
      "is_week_off": true|false
    }
  ]
}`;
    const payload = {
        contents: [
            {
                parts: [
                    { text: prompt },
                    {
                        inlineData: {
                            mimeType: "image/jpeg",
                            data: image // Base64 string without data:image/jpeg;base64 prefix
                        }
                    }
                ]
            }
        ],
        generationConfig: {
            responseMimeType: "application/json",
            responseSchema: {
                type: "OBJECT",
                properties: {
                    employee_name: { type: "STRING" },
                    month: { type: "STRING" },
                    shifts: {
                        type: "ARRAY",
                        items: {
                            type: "OBJECT",
                            properties: {
                                date: { type: "STRING", description: "Date formatted as YYYY-MM-DD" },
                                shift_type: { type: "STRING", description: "morning, afternoon, night, or week_off" },
                                start_time: { type: "STRING", nullable: true, description: "HH:MM format" },
                                end_time: { type: "STRING", nullable: true, description: "HH:MM format" },
                                is_week_off: { type: "BOOLEAN" }
                            },
                            required: ["date", "shift_type", "is_week_off"]
                        }
                    }
                },
                required: ["employee_name", "month", "shifts"]
            }
        }
    };
    try {
        const response = await axios_1.default.post(url, payload, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 60000
        });
        const candidates = (_b = response.data) === null || _b === void 0 ? void 0 : _b.candidates;
        if (!candidates || candidates.length === 0) {
            throw new functions.https.HttpsError('internal', 'No response candidates returned from Gemini API.');
        }
        const textResponse = (_d = (_c = candidates[0].content) === null || _c === void 0 ? void 0 : _c.parts[0]) === null || _d === void 0 ? void 0 : _d.text;
        if (!textResponse) {
            throw new functions.https.HttpsError('internal', 'Empty content returned from Gemini API.');
        }
        // Return parsed JSON object
        return JSON.parse(textResponse);
    }
    catch (error) {
        console.error("Gemini API Error:", ((_e = error === null || error === void 0 ? void 0 : error.response) === null || _e === void 0 ? void 0 : _e.data) || error.message);
        throw new functions.https.HttpsError('internal', `Error calling Gemini API: ${((_h = (_g = (_f = error === null || error === void 0 ? void 0 : error.response) === null || _f === void 0 ? void 0 : _f.data) === null || _g === void 0 ? void 0 : _g.error) === null || _h === void 0 ? void 0 : _h.message) || error.message}`);
    }
});
//# sourceMappingURL=shiftVisionAI.js.map