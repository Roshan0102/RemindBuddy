import * as functions from "firebase-functions";
import { callGeminiAPI } from "../../utils/geminiHelper";

export const analyzeRosterImage = functions.runWith({ timeoutSeconds: 180, memory: "1GB" }).https.onCall(async (data, context) => {
    // Ensure user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }

    const { image, employeeName } = data;
    if (!image || !employeeName) {
        throw new functions.https.HttpsError('invalid-argument', 'Image and employeeName are required.');
    }

    // Determine correct image MIME type
    let mimeType = "image/jpeg";
    if (image.startsWith("iVBOR")) {
        mimeType = "image/png";
    } else if (image.startsWith("/9j/")) {
        mimeType = "image/jpeg";
    } else if (image.startsWith("UklGR")) {
        mimeType = "image/webp";
    }

    // 1. Prepare detailed prompt for Gemini API
    const prompt = `You are a precision OCR assistant specialized in reading monthly work rosters and shift schedule tables.

TARGET EMPLOYEE TO EXTRACT: "${employeeName}"

INSTRUCTIONS:
1. IDENTIFY ROSTER STRUCTURE & MONTH:
   - Check the top header, banner, or corner of the roster table (for example, "09-26" indicates Month 09, Year 2026 -> "September 2026").
   - Count the total number of calendar days in that month (e.g. September has 30 days, August has 31 days).
   - Set "month" field cleanly as "Month YYYY" (e.g., "September 2026").

2. LOCATE EMPLOYEE ROW:
   - Search the first column (Employee Names) for a row that matches, starts with, or contains "${employeeName}" (case-insensitive fuzzy match: e.g. "roshan" matches "Roshan J", "Roshan", "ROSHAN", etc.).

3. EXTRACT EVERY SINGLE DAY (DAY 1 TO LAST DAY):
   - You MUST extract an entry for EVERY DAY from Day 1 to the last day of the month (e.g., Day 1 to Day 30).
   - DO NOT stop after 1 day! The "shifts" array MUST contain an entry for each calendar day of the month (e.g. 2026-09-01, 2026-09-02, ..., 2026-09-30) in chronological order.

4. SHIFT CODE & TIMING MAPPING:
   For each day column in this employee's row, inspect the cell text:
   - 'M' or 'Morning' -> shift_type: "morning", start_time: "06:00", end_time: "14:00", is_week_off: false
   - 'A' or 'Afternoon' -> shift_type: "afternoon", start_time: "14:00", end_time: "22:00", is_week_off: false
   - 'N' or 'Night' -> shift_type: "night", start_time: "22:00", end_time: "06:00", is_week_off: false
   - 'D' or 'G' or 'General' -> shift_type: "general", start_time: "09:00", end_time: "17:00", is_week_off: false
   - 'L' (Leave), 'H' (Holiday), 'OFF', blank cell, or empty box -> shift_type: "week_off", start_time: null, end_time: null, is_week_off: true

OUTPUT SCHEMA:
Return ONLY the JSON object matching the requested schema with all days in "shifts".`;

    const payload = {
        contents: [
            {
                parts: [
                    { text: prompt },
                    {
                        inlineData: {
                            mimeType,
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
        const geminiResult = await callGeminiAPI(payload, {
            timeout: 35000,
            models: ["gemini-3.6-flash", "gemini-3.7-flash", "gemini-3.5-flash", "gemini-flash-latest"]
        });
        const textResponse = geminiResult.text;
        if (!textResponse) {
            throw new functions.https.HttpsError('internal', 'Empty content returned from Gemini API.');
        }

        // Return parsed JSON object
        return JSON.parse(textResponse);
    } catch (error: any) {
        console.error("Gemini API Error in analyzeRosterImage:", error.message);
        throw new functions.https.HttpsError('internal', `Error calling Gemini API: ${error.message}`);
    }
});

