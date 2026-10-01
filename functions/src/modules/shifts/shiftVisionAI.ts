import * as functions from "firebase-functions";
import { db } from "../../config/firebase";
import { callGeminiAPI } from "../../utils/geminiHelper";

export const analyzeRosterImage = functions.runWith({ timeoutSeconds: 540, memory: "1GB" }).https.onCall(async (data, context) => {
    // Ensure user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }

    const uid = context.auth.uid;
    let userGeminiKey = "";
    try {
        const userDoc = await db.collection("users").doc(uid).get();
        if (userDoc.exists) {
            const uData = userDoc.data() || {};
            const enabledModules = uData.enabledModules || [];
            if (!enabledModules.includes("shifts")) {
                throw new functions.https.HttpsError('permission-denied', 'The Shifts module is disabled for your account.');
            }
            userGeminiKey = (uData.userApiKeys?.geminiApiKey || uData.geminiApiKey || "").trim();
        }
    } catch (e: any) {
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
    } else if (image.startsWith("/9j/")) {
        mimeType = "image/jpeg";
    } else if (image.startsWith("UklGR")) {
        mimeType = "image/webp";
    }

    // 1. Prepare detailed prompt for Gemini API
    const prompt = `You are a world-class precision OCR and schedule parsing engine specialized in reading monthly work rosters and shift schedule tables.

TARGET EMPLOYEE TO EXTRACT: "${employeeName}"

CRITICAL RULES & STEP-BY-STEP INSTRUCTIONS:

1. IDENTIFY ROSTER MONTH & CALENDAR DAYS:
   - Read the table header / title / month code (for example: "10-26" indicates Month 10 = October, Year 2026 -> "October 2026"; "09-26" indicates September 2026; "05-25" indicates May 2025).
   - Find the total calendar days for this month (e.g. October has 31 days: 1 to 31; September has 30 days: 1 to 30; February has 28 or 29 days).
   - Set "month" cleanly as "Month YYYY" (e.g. "October 2026").
   - Construct full ISO dates: "YYYY-MM-DD" for every day from Day 1 to the last day of the month (e.g., 2026-10-01 to 2026-10-31).

2. LOCATE TARGET EMPLOYEE ROW:
   - In the leftmost column (Employee Names / Staff list), find the row whose name matches "${employeeName}" (case-insensitive fuzzy match: e.g. "roshan" or "Roshan" matches "Roshan J", "Roshan", "ROSHAN", etc.).
   - Pin down the exact single horizontal row belonging to this employee.

3. STRICT HORIZONTAL ROW ISOLATION (ZERO BLEED):
   - You MUST constrain your visual scanning strictly and exclusively to the single horizontal row belonging to "${employeeName}".
   - DO NOT look at the row above or the row below!
   - DO NOT look at shifts of other employees in adjacent rows. Even if other employees have night shifts ('N'), you MUST NEVER assign letters from adjacent rows to the target employee!
   - DO NOT look at the summary/totals rows at the bottom (e.g. "N - Night", "M - Morning").

4. ROW SEQUENCE EXTRACTION:
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

6. MANDATORY COMPLETE MONTH EXTRACTION:
   - YOU MUST OUTPUT AN ENTRY FOR EVERY SINGLE DAY FROM DAY 1 TO THE LAST DAY OF THE MONTH (e.g. all 30 or 31 days).
   - NEVER STOP AFTER 1 DAY! NEVER STOP IN THE MIDDLE!
   - Both working shifts and off/leave/holiday days must have an entry in the "shifts" array in strict chronological order from Day 1 to Day N.

OUTPUT FORMAT:
Return a valid JSON object matching this exact structure:
{
  "employee_name": "${employeeName}",
  "month": "October 2026",
  "extracted_raw_sequence": ["A", "H", "L", "L", "L", "", "A", "A", "A", ...],
  "shifts": [
    {
      "date": "YYYY-MM-01",
      "shift_type": "afternoon",
      "start_time": "14:00",
      "end_time": "22:00",
      "is_week_off": false
    },
    ... (EVERY DAY up to the last day of the month)
  ]
}`;

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
            maxOutputTokens: 8192
        }
    };

    try {
        const geminiResult = await callGeminiAPI(payload, {
            apiKey: userGeminiKey || undefined,
            timeout: 60000,
            maxRetries: 0
        });
        const textResponse = geminiResult.text;
        if (!textResponse) {
            throw new functions.https.HttpsError('internal', 'Empty content returned from Gemini API.');
        }

        // Return parsed JSON object including modelUsed
        let parsed: any;
        try {
            // Strip any leading/trailing markdown code blocks if present
            const cleanJsonText = textResponse.replace(/^```json\s*/i, '').replace(/\s*```$/i, '').trim();
            parsed = JSON.parse(cleanJsonText);
        } catch (pe: any) {
            console.error("[ShiftVisionAI] JSON parse failed on Gemini response:", textResponse);
            throw new functions.https.HttpsError('internal', 'Failed to parse AI schedule response.');
        }

        // 1. Determine Year & Month
        let year: number | null = null;
        let monthIndex: number | null = null; // 0-indexed: 0 = Jan, 11 = Dec

        // Try extracting from shifts array first (e.g. "2026-10-01")
        if (Array.isArray(parsed.shifts)) {
            for (const s of parsed.shifts) {
                if (typeof s?.date === 'string') {
                    const match = s.date.trim().match(/^(\d{4})[-/](\d{1,2})/);
                    if (match) {
                        year = parseInt(match[1], 10);
                        monthIndex = parseInt(match[2], 10) - 1;
                        break;
                    }
                }
            }
        }

        // If not found in shifts, try parsing from parsed.month string
        if (year === null || monthIndex === null) {
            const monthStr = (parsed.month || "").trim();
            const monthNames = [
                "january", "february", "march", "april", "may", "june",
                "july", "august", "september", "october", "november", "december"
            ];
            const nameMatch = monthStr.match(/([a-zA-Z]+)[^0-9]*(\d{4})/i);
            const numMatch = monthStr.match(/^(\d{1,2})[-/](\d{2,4})$/);
            if (nameMatch) {
                const idx = monthNames.indexOf(nameMatch[1].toLowerCase());
                if (idx !== -1) {
                    monthIndex = idx;
                    year = parseInt(nameMatch[2], 10);
                }
            } else if (numMatch) {
                monthIndex = parseInt(numMatch[1], 10) - 1;
                let y = parseInt(numMatch[2], 10);
                if (y < 100) y += 2000;
                year = y;
            }
        }

        // Fallback to current year & month if completely missing
        const now = new Date();
        if (year === null || isNaN(year) || year < 2000 || year > 2100) {
            year = now.getFullYear();
        }
        if (monthIndex === null || isNaN(monthIndex) || monthIndex < 0 || monthIndex > 11) {
            monthIndex = now.getMonth();
        }

        const monthNamesList = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ];
        parsed.month = `${monthNamesList[monthIndex]} ${year}`;
        parsed.employee_name = (parsed.employee_name || employeeName || "").trim();

        // Total calendar days in this specific month (e.g. 28, 29, 30, or 31)
        const totalDaysInMonth = new Date(year, monthIndex + 1, 0).getDate();

        // Index existing shifts by normalized day number (1..totalDaysInMonth)
        const existingShiftsByDay = new Map<number, any>();
        if (Array.isArray(parsed.shifts)) {
            for (const s of parsed.shifts) {
                if (s && typeof s.date === 'string') {
                    const match = s.date.trim().match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})/);
                    if (match) {
                        const dNum = parseInt(match[3], 10);
                        if (dNum >= 1 && dNum <= totalDaysInMonth) {
                            existingShiftsByDay.set(dNum, s);
                        }
                    }
                }
            }
        }

        const rawSequence: string[] = Array.isArray(parsed.extracted_raw_sequence)
            ? parsed.extracted_raw_sequence.map((x: any) => String(x || "").trim().toUpperCase())
            : [];

        const finalizedShifts: any[] = [];
        const monthPad = String(monthIndex + 1).padStart(2, "0");

        for (let day = 1; day <= totalDaysInMonth; day++) {
            const dayPad = String(day).padStart(2, "0");
            const fullDate = `${year}-${monthPad}-${dayPad}`;
            const rawCode = rawSequence[day - 1] || "";

            let shift = existingShiftsByDay.get(day);

            if (shift) {
                // Shift already extracted by AI - validate and normalize
                shift.date = fullDate;
                let sType = (shift.shift_type || "").trim().toLowerCase();

                // Verification: prevent hallucinated night shifts if raw code is not 'N'
                if (sType === 'night' && rawCode && rawCode !== 'N' && !rawCode.includes('N')) {
                    if (rawCode === 'D' || rawCode === 'G') sType = 'day';
                    else if (rawCode === 'M') sType = 'morning';
                    else if (rawCode === 'A') sType = 'afternoon';
                    else sType = 'week_off';
                }

                if (shift.is_week_off === true || sType === 'week_off' || sType === 'off' || sType === 'leave') {
                    shift.shift_type = 'week_off';
                    shift.start_time = null;
                    shift.end_time = null;
                    shift.is_week_off = true;
                } else if (sType === 'morning') {
                    shift.shift_type = 'morning';
                    shift.start_time = shift.start_time || '06:00';
                    shift.end_time = shift.end_time || '14:00';
                    shift.is_week_off = false;
                } else if (sType === 'afternoon') {
                    shift.shift_type = 'afternoon';
                    shift.start_time = shift.start_time || '14:00';
                    shift.end_time = shift.end_time || '22:00';
                    shift.is_week_off = false;
                } else if (sType === 'night') {
                    shift.shift_type = 'night';
                    shift.start_time = shift.start_time || '22:00';
                    shift.end_time = shift.end_time || '06:00';
                    shift.is_week_off = false;
                } else if (sType === 'day' || sType === 'general') {
                    shift.shift_type = 'day';
                    shift.start_time = shift.start_time || '09:00';
                    shift.end_time = shift.end_time || '17:00';
                    shift.is_week_off = false;
                } else {
                    shift.shift_type = 'week_off';
                    shift.start_time = null;
                    shift.end_time = null;
                    shift.is_week_off = true;
                }
                finalizedShifts.push(shift);
            } else {
                // Gap filler: AI missed this day! Recover from rawCode if possible, else default to week_off
                console.warn(`[ShiftVisionAI] Day ${day} (${fullDate}) was missing from AI output. Auto-filling.`);
                if (rawCode === 'D' || rawCode === 'G') {
                    finalizedShifts.push({
                        date: fullDate,
                        shift_type: 'day',
                        start_time: '09:00',
                        end_time: '17:00',
                        is_week_off: false
                    });
                } else if (rawCode === 'M') {
                    finalizedShifts.push({
                        date: fullDate,
                        shift_type: 'morning',
                        start_time: '06:00',
                        end_time: '14:00',
                        is_week_off: false
                    });
                } else if (rawCode === 'A') {
                    finalizedShifts.push({
                        date: fullDate,
                        shift_type: 'afternoon',
                        start_time: '14:00',
                        end_time: '22:00',
                        is_week_off: false
                    });
                } else if (rawCode === 'N') {
                    finalizedShifts.push({
                        date: fullDate,
                        shift_type: 'night',
                        start_time: '22:00',
                        end_time: '06:00',
                        is_week_off: false
                    });
                } else {
                    finalizedShifts.push({
                        date: fullDate,
                        shift_type: 'week_off',
                        start_time: null,
                        end_time: null,
                        is_week_off: true
                    });
                }
            }
        }

        parsed.shifts = finalizedShifts;

        return {
            ...parsed,
            modelUsed: geminiResult.modelUsed
        };
    } catch (error: any) {
        console.error("Gemini API Error in analyzeRosterImage:", error.message);
        let userMessage = error.message || "Failed to analyze roster image.";
        if (userMessage.includes("503") || userMessage.toLowerCase().includes("high demand") || userMessage.toLowerCase().includes("overloaded")) {
            userMessage = "Google AI Studio is currently experiencing heavy server traffic (high demand spike). Please wait a moment and try scanning again.";
        } else if (userMessage.includes("429") || userMessage.toLowerCase().includes("quota")) {
            userMessage = "AI API quota limit reached (HTTP 429). Please check your Gemini API key quota or try again in a few minutes.";
        }
        throw new functions.https.HttpsError('internal', userMessage);
    }
});

