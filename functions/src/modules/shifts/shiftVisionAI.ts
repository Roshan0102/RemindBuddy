import * as functions from "firebase-functions";
import { callGeminiAPI } from "../../utils/geminiHelper";

export const analyzeRosterImage = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
    // Ensure user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }

    const { image, employeeName } = data;
    if (!image || !employeeName) {
        throw new functions.https.HttpsError('invalid-argument', 'Image and employeeName are required.');
    }

    // 1. Prepare payload for Gemini API
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
        const geminiResult = await callGeminiAPI(payload, { timeout: 60000 });
        const textResponse = geminiResult.text;
        if (!textResponse) {
            throw new functions.https.HttpsError('internal', 'Empty content returned from Gemini API.');
        }

        // Return parsed JSON object
        return JSON.parse(textResponse);
    } catch (error: any) {
        console.error("Gemini API Error:", error.message);
        throw new functions.https.HttpsError('internal', `Error calling Gemini API: ${error.message}`);
    }
});
