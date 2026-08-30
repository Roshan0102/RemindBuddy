"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.callGeminiAPI = callGeminiAPI;
const axios_1 = require("axios");
const firebase_1 = require("../config/firebase");
const DEFAULT_MODELS = [
    "gemini-1.5-flash",
    "gemini-2.0-flash",
    "gemini-1.5-pro"
];
/**
 * Robust Gemini API caller that handles:
 * - Invalid model names
 * - HTTP 429 Rate Limiting with exponential backoff
 * - Multi-model fallback cascade (gemini-1.5-flash -> gemini-2.0-flash -> gemini-1.5-pro)
 * - Multi-API-key fallback if configured in Firestore admin_creds/gemini_config
 */
async function callGeminiAPI(payload, options = {}) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l;
    // 1. Fetch API Key(s)
    const configDoc = await firebase_1.db.collection("admin_creds").doc("gemini_config").get();
    let primaryKey = "";
    let backupKeys = [];
    if (configDoc.exists) {
        const data = configDoc.data() || {};
        primaryKey = (data.apiKey || "").trim();
        if (Array.isArray(data.backupApiKeys)) {
            backupKeys = data.backupApiKeys.map((k) => String(k).trim()).filter((k) => k.length > 0);
        }
        else if (Array.isArray(data.apiKeys)) {
            backupKeys = data.apiKeys.map((k) => String(k).trim()).filter((k) => k.length > 0);
        }
    }
    const allKeys = [primaryKey, ...backupKeys].filter(k => k.length > 0);
    if (allKeys.length === 0) {
        throw new Error("Gemini API key is not configured in admin console.");
    }
    const modelsToTry = options.models && options.models.length > 0 ? options.models : DEFAULT_MODELS;
    const timeout = options.timeout || 240000;
    const maxRetries = (_a = options.maxRetries) !== null && _a !== void 0 ? _a : 2;
    let lastError = null;
    // Normalize tools payload for Google Search if present
    const normalizedPayload = JSON.parse(JSON.stringify(payload));
    if (Array.isArray(normalizedPayload.tools)) {
        normalizedPayload.tools = normalizedPayload.tools.map((tool) => {
            if (tool.google_search !== undefined || tool.googleSearch !== undefined) {
                return { googleSearch: {} };
            }
            return tool;
        });
    }
    for (const apiKey of allKeys) {
        for (const model of modelsToTry) {
            let attempt = 0;
            while (attempt <= maxRetries) {
                try {
                    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
                    console.log(`[GeminiHelper] Calling model '${model}' (Key: ...${apiKey.slice(-4)}, Attempt: ${attempt + 1}/${maxRetries + 1})...`);
                    const response = await axios_1.default.post(url, normalizedPayload, {
                        headers: { "Content-Type": "application/json" },
                        timeout
                    });
                    const candidates = (_b = response.data) === null || _b === void 0 ? void 0 : _b.candidates;
                    if (!candidates || candidates.length === 0) {
                        throw new Error(`No candidates returned from Gemini model ${model}`);
                    }
                    const text = ((_e = (_d = (_c = candidates[0].content) === null || _c === void 0 ? void 0 : _c.parts) === null || _d === void 0 ? void 0 : _d[0]) === null || _e === void 0 ? void 0 : _e.text) || "";
                    return {
                        text,
                        raw: response.data,
                        modelUsed: model
                    };
                }
                catch (err) {
                    lastError = err;
                    const status = (_f = err.response) === null || _f === void 0 ? void 0 : _f.status;
                    const errData = (_h = (_g = err.response) === null || _g === void 0 ? void 0 : _g.data) === null || _h === void 0 ? void 0 : _h.error;
                    const errMsg = (errData === null || errData === void 0 ? void 0 : errData.message) || err.message;
                    console.warn(`[GeminiHelper] Error calling '${model}' (Status ${status}): ${errMsg}`);
                    if (status === 429) {
                        // Rate limit exceeded - wait with exponential backoff then retry or switch model
                        attempt++;
                        if (attempt <= maxRetries) {
                            const delayMs = attempt * 2000;
                            console.log(`[GeminiHelper] 429 received. Backing off for ${delayMs}ms before retry...`);
                            await new Promise((res) => setTimeout(res, delayMs));
                            continue;
                        }
                    }
                    // For 404 (model not found) or after retry exhaustion, break to try next fallback model
                    break;
                }
            }
        }
    }
    const finalMessage = ((_l = (_k = (_j = lastError === null || lastError === void 0 ? void 0 : lastError.response) === null || _j === void 0 ? void 0 : _j.data) === null || _k === void 0 ? void 0 : _k.error) === null || _l === void 0 ? void 0 : _l.message) || (lastError === null || lastError === void 0 ? void 0 : lastError.message) || "All Gemini API attempts failed.";
    throw new Error(`Gemini Service Error: ${finalMessage}`);
}
//# sourceMappingURL=geminiHelper.js.map