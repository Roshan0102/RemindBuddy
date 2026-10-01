"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.analyzeRosterImage = void 0;
const functions = require("firebase-functions");
const firebase_1 = require("../../config/firebase");
const geminiHelper_1 = require("../../utils/geminiHelper");
exports.analyzeRosterImage = functions.runWith({ timeoutSeconds: 540, memory: "1GB" }).https.onCall(async (data, context) => {
    var _a;
    // Ensure user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const uid = context.auth.uid;
    let userGeminiKey = "";
    try {
        const userDoc = await firebase_1.db.collection("users").doc(uid).get();
        if (userDoc.exists) {
            const uData = userDoc.data() || {};
            const enabledModules = uData.enabledModules || [];
            if (!enabledModules.includes("shifts")) {
                throw new functions.https.HttpsError('permission-denied', 'The Shifts module is disabled for your account.');
            }
            userGeminiKey = (((_a = uData.userApiKeys) === null || _a === void 0 ? void 0 : _a.geminiApiKey) || uData.geminiApiKey || "").trim();
        }
    }
    catch (e) {
        console.warn("[ShiftVisionAI] Could not fetch user API key:", e.message);
    }
    const { image, employeeName } = data;
    if (!image || !employeeName) {
        throw new functions.https.HttpsError('invalid-argument', 'Image and employeeName are required.');
    }
    // Determine correct image MIME type
    let mimeType = "image/jpeg";
    if (image.startsWith("iVBOR")) {
        mimeType = "image/png";
    }
    else if (image.startsWith("/9j/")) {
        mimeType = "image/jpeg";
    }
    else if (image.startsWith("UklGR")) {
        mimeType = "image/webp";
    }
    // 1. Prepare detailed prompt for Gemini API
    const prompt = `You are a world-class precision OCR and schedule parsing engine specialized in reading monthly work rosters and shift schedule tables.

TARGET EMPLOYEE TO EXTRACT: "${employeeName}"

CRITICAL RULES & STEP-BY-STEP INSTRUCTIONS:

1. IDENTIFY ROSTER MONTH & CALENDAR DAYS:
   - Read the table header / title / month code (for example: "10-26" indicates Month 10 = October, Year 2026 -> "October 2026"; "09-26" indicates September 2026).
   - Find the total calendar days for this month (e.g. October has 31 days: 1 to 31; September has 30 days: 1 to 30).
   - Set "month" cleanly as "Month YYYY" (e.g. "October 2026").
   - Construct full ISO dates: "YYYY-MM-DD" for every day from Day 1 to the last day of the month (e.g., 2026-10-01 to 2026-10-31).

2. LOCATE TARGET EMPLOYEE ROW:
   - In the leftmost column (Employee Names / Staff list), find the row whose name matches "${employeeName}" (case-insensitive fuzzy match: e.g. "roshan" or "Roshan" matches "Roshan J", "Roshan", "ROSHAN", etc.).
   - Pin down the exact single horizontal row belonging to this employee.

3. STRICT HORIZONTAL ROW ISOLATION (ZERO BLEED):
   - You MUST constrain your visual scanning strictly and exclusively to the single horizontal row belonging to "${employeeName}".
   - DO NOT look at the row above or the row below!
   - DO NOT look at shifts of other employees in adjacent rows (such as Vittal, Vishal Raj, Kushal V, Pruthviraj, Dayanand, etc.). Even if other employees have night shifts ('N'), you MUST NEVER assign letters from adjacent rows to the target employee!
   - DO NOT look at the summary/totals rows at the bottom (e.g. "N - Night", "M - Morning").

4. ROW SEQUENCE EXTRACTION (CHAIN OF THOUGHT):
   - For every column from Day 1 to the last Day of the month:
     Look straight down from the column header (Day 1..N) into ONLY the target employee's row cell.
     Read the exact character visible in that specific cell.
   - Under "extracted_raw_sequence", record an array of strings representing the literal character seen in each cell from Day 1 to Day N.
     If a cell is empty/blank or is simply a colored box (yellow, orange, grey, or white) with NO letter, record it as "" (empty string).

5. SHIFT CODE & TIMING MAPPING:
   For each day cell in this employee's row:
   - 'D' or 'Day' or 'G' or 'General' -> shift_type: "day", start_time: "09:00", end_time: "17:00", is_week_off: false
   - 'M' or 'Morning' -> shift_type: "morning", start_time: "06:00", end_time: "14:00", is_week_off: false
   - 'A' or 'Afternoon' -> shift_type: "afternoon", start_time: "14:00", end_time: "22:00", is_week_off: false
   - 'N' or 'Night' -> shift_type: "night", start_time: "22:00", end_time: "06:00", is_week_off: false
     *** STRICT 'N' / NIGHT SHIFT VERIFICATION RULE ***:
     You are STRICTLY FORBIDDEN from assigning a "night" shift unless the literal capital letter 'N' is physically printed inside that exact cell in the target employee's row.
     If the cell contains 'D' (Day shift), 'M', 'A', 'H', 'L', or is a blank/colored box, it is NEVER a night shift.
     If this employee's row has no 'N' letters, the "shifts" output MUST HAVE ZERO night shifts.
   - 'H' (Public Holiday), 'L' (Paid Leave), 'OFF', 'WO' (Week Off), or any blank/empty/colored box (yellow, orange, grey, white) with no shift letter -> shift_type: "week_off", start_time: null, end_time: null, is_week_off: true

6. FULL CHRONOLOGICAL OUTPUT:
   - You MUST include every single calendar day from Day 1 to the end of the month in the "shifts" array in strict chronological order.

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
                    extracted_raw_sequence: {
                        type: "ARRAY",
                        items: { type: "STRING" },
                        description: "Literal character read from each day cell 1..N (e.g. ['A', 'H', 'L', 'L', 'L', '', 'A', ...])"
                    },
                    shifts: {
                        type: "ARRAY",
                        items: {
                            type: "OBJECT",
                            properties: {
                                date: { type: "STRING", description: "Date formatted as YYYY-MM-DD" },
                                shift_type: { type: "STRING", description: "morning, afternoon, night, day, or week_off" },
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
        const geminiResult = await (0, geminiHelper_1.callGeminiAPI)(payload, {
            apiKey: userGeminiKey || undefined,
            timeout: 60000,
            maxRetries: 0
        });
        const textResponse = geminiResult.text;
        if (!textResponse) {
            throw new functions.https.HttpsError('internal', 'Empty content returned from Gemini API.');
        }
        // Return parsed JSON object including modelUsed
        const parsed = JSON.parse(textResponse);
        // Verification & Guardrail: Ensure night shifts are only present if rawCode actually was 'N'
        if (Array.isArray(parsed.extracted_raw_sequence) && Array.isArray(parsed.shifts)) {
            for (let i = 0; i < parsed.shifts.length; i++) {
                const rawCode = (parsed.extracted_raw_sequence[i] || "").trim().toUpperCase();
                const shift = parsed.shifts[i];
                if (shift.shift_type === 'night' && rawCode !== 'N' && !rawCode.includes('N')) {
                    console.warn(`[ShiftVisionAI] Correcting hallucinated night shift on day ${i + 1}: rawCode is '${rawCode}'`);
                    if (rawCode === 'D' || rawCode === 'G') {
                        shift.shift_type = 'day';
                        shift.start_time = '09:00';
                        shift.end_time = '17:00';
                        shift.is_week_off = false;
                    }
                    else if (rawCode === 'M') {
                        shift.shift_type = 'morning';
                        shift.start_time = '06:00';
                        shift.end_time = '14:00';
                        shift.is_week_off = false;
                    }
                    else if (rawCode === 'A') {
                        shift.shift_type = 'afternoon';
                        shift.start_time = '14:00';
                        shift.end_time = '22:00';
                        shift.is_week_off = false;
                    }
                    else {
                        shift.shift_type = 'week_off';
                        shift.start_time = null;
                        shift.end_time = null;
                        shift.is_week_off = true;
                    }
                }
            }
        }
        return Object.assign(Object.assign({}, parsed), { modelUsed: geminiResult.modelUsed });
    }
    catch (error) {
        console.error("Gemini API Error in analyzeRosterImage:", error.message);
        let userMessage = error.message || "Failed to analyze roster image.";
        if (userMessage.includes("503") || userMessage.toLowerCase().includes("high demand") || userMessage.toLowerCase().includes("overloaded")) {
            userMessage = "Google AI Studio is currently experiencing heavy server traffic (high demand spike). Please wait a moment and try scanning again.";
        }
        else if (userMessage.includes("429") || userMessage.toLowerCase().includes("quota")) {
            userMessage = "AI API quota limit reached (HTTP 429). Please check your Gemini API key quota or try again in a few minutes.";
        }
        throw new functions.https.HttpsError('internal', userMessage);
    }
});
//# sourceMappingURL=shiftVisionAI.js.map