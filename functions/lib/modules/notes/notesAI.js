"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.processNoteWithAI = void 0;
const functions = require("firebase-functions");
const firebase_1 = require("../../config/firebase");
const geminiHelper_1 = require("../../utils/geminiHelper");
/**
 * AI Power Tools for Notes:
 * - Fix Grammar & Spelling
 * - Polish & Professionalize Tone
 * - Summarize Key Takeaways
 * - Convert Notes / Text to Checklist
 * - Solve All Math Expressions Across the Note
 */
exports.processNoteWithAI = functions.runWith({
    timeoutSeconds: 60,
    memory: "512MB"
}).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
    }
    const uid = context.auth.uid;
    const { action, text, title } = data;
    if (!text || typeof text !== "string" || text.trim().length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "Note text is required.");
    }
    try {
        const userDoc = await firebase_1.db.collection("users").doc(uid).get();
        const userData = userDoc.exists ? (userDoc.data() || {}) : {};
        const userApiKeys = userData.userApiKeys || {};
        const geminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();
        const groqKey = (userApiKeys.groqApiKey || userData.groqApiKey || "").trim();
        let systemInstruction = "";
        switch (action) {
            case "fix_grammar":
                systemInstruction = `You are a professional copyeditor.
Carefully review the user's note text and fix all spelling errors, grammatical mistakes, missing punctuation, and typos.
CRITICAL RULES:
- Preserve the user's authentic tone, structure, and original vocabulary as much as possible.
- Do NOT add any preamble, explanation, or greeting. Output ONLY the corrected text.`;
                break;
            case "polish":
                systemInstruction = `You are an elite executive communications expert.
Refine and polish the user's note to make it clear, concise, professional, and well-structured.
CRITICAL RULES:
- Elevate phrasing and remove redundant fluff while retaining 100% of the facts and original meaning.
- Do NOT add any conversational remarks. Output ONLY the polished text.`;
                break;
            case "summarize":
                systemInstruction = `You are an executive summary specialist.
Analyze the note content and generate 3 to 5 concise, actionable bullet points (each starting with "• ") capturing the most vital takeaways.
CRITICAL RULES:
- Output ONLY the bullet points, with no conversational fluff or intro.`;
                break;
            case "to_checklist":
                systemInstruction = `You are a productivity organizer.
Transform the tasks, steps, ingredients, or items in the user's note into a clean checklist.
CRITICAL RULES:
- Each item must start with "[ ] " (empty checkbox).
- Output ONLY the list of checklist items, one per line.`;
                break;
            case "solve_all_math":
                systemInstruction = `You are a precision mathematical evaluator.
Scan the entire note text for every mathematical equation or arithmetic calculation ending with "=" (for example "100 + 30 =", "15 * 24 =", "1500 / 3 =", "10% of 250 =").
Calculate the exact result for each expression and append the answer directly after the "=" sign (for example "100 + 30 = 130").
CRITICAL RULES:
- Keep all surrounding non-math sentences, headings, and formatting exactly as they are.
- Only calculate and fill in the missing numbers after "=".
- Output ONLY the updated full text with calculations filled in.`;
                break;
            default:
                throw new functions.https.HttpsError("invalid-argument", `Unknown action: ${action}`);
        }
        const prompt = `${systemInstruction}

NOTE TITLE: ${title || "Untitled"}
--- NOTE CONTENT ---
${text}
--------------------`;
        const payload = {
            contents: [
                {
                    parts: [{ text: prompt }]
                }
            ],
            generationConfig: {
                temperature: action === "fix_grammar" || action === "solve_all_math" ? 0.0 : 0.3
            }
        };
        const geminiResponse = await (0, geminiHelper_1.callGeminiAPI)(payload, {
            apiKey: geminiKey,
            groqApiKey: groqKey
        });
        const rawResult = geminiResponse.text || "";
        const cleanResult = rawResult.trim();
        return {
            success: true,
            action,
            result: cleanResult
        };
    }
    catch (err) {
        console.error(`[NotesAI] Error executing ${action} for user ${uid}:`, err);
        throw new functions.https.HttpsError("internal", err.message || "Failed to process note with AI");
    }
});
//# sourceMappingURL=notesAI.js.map