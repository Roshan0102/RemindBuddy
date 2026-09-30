"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_MODELS = void 0;
exports.fetchAvailableModelsFromAPI = fetchAvailableModelsFromAPI;
exports.callGeminiAPI = callGeminiAPI;
const axios_1 = require("axios");
const firebase_1 = require("../config/firebase");
const groqHelper_1 = require("./groqHelper");
// Active Gemini models ordered by speed, intelligence and fallback hierarchy
exports.DEFAULT_MODELS = [
    "gemini-3.8-flash",
    "gemini-3.7-flash",
    "gemini-3.6-flash",
    "gemini-flash-latest",
    "gemini-3.5-flash",
    "gemini-3.5-flash-lite",
    "gemini-flash-lite-latest",
    "gemini-3.1-flash-lite"
];
/**
 * Dynamically queries Google AI Studio REST API (/v1beta/models)
 * to retrieve the exact list of active Gemini models supported for a given API key.
 */
async function fetchAvailableModelsFromAPI(apiKey) {
    var _a;
    try {
        const url = `https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}`;
        const response = await axios_1.default.get(url, { timeout: 10000 });
        const modelsList = ((_a = response.data) === null || _a === void 0 ? void 0 : _a.models) || [];
        const validModels = modelsList
            .filter((m) => Array.isArray(m.supportedGenerationMethods) &&
            m.supportedGenerationMethods.includes("generateContent") &&
            typeof m.name === "string" &&
            m.name.startsWith("models/gemini-"))
            .map((m) => m.name.replace(/^models\//, ""));
        if (validModels.length > 0) {
            console.log(`[GeminiHelper] Dynamically discovered ${validModels.length} models for API key:`, validModels);
            return validModels;
        }
    }
    catch (e) {
        console.warn(`[GeminiHelper] Could not fetch dynamic models list from Google API: ${e.message}`);
    }
    return exports.DEFAULT_MODELS;
}
// In-memory runtime cache to eliminate latency on repeated calls
const unsupportedModels = new Set();
/**
 * High-performance Gemini API caller:
 * - Operates purely on custom user BYOK apiKey (or falls back to central admin key if none configured)
 * - Intelligent 8-tier cascade starting with gemini-3.8-flash -> 3.7 -> 3.6 -> flash-latest -> 3.5 -> 3.5-lite -> flash-lite-latest -> 3.1-lite
 * - Built-in exponential backoff for HTTP 503 (high-demand transient spikes) and HTTP 429
 */
async function callGeminiAPI(payload, options = {}) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t;
    let targetApiKey = (options.apiKey || "").trim();
    // If no custom user key provided, fetch admin key from Firestore
    if (!targetApiKey) {
        const configDoc = await firebase_1.db.collection("admin_creds").doc("gemini_config").get();
        if (configDoc.exists) {
            const data = configDoc.data() || {};
            targetApiKey = (data.apiKey || "").trim();
        }
    }
    if (!targetApiKey) {
        throw new Error("Gemini API key is not configured (neither user key nor admin key available).");
    }
    let candidateModels = options.models && options.models.length > 0 ? [...options.models] : [...exports.DEFAULT_MODELS];
    // Filter out models that were already identified as 404/unsupported in this container instance
    candidateModels = candidateModels.filter(m => !unsupportedModels.has(m));
    if (candidateModels.length === 0) {
        candidateModels = [...exports.DEFAULT_MODELS];
    }
    const timeout = options.timeout || 120000;
    const maxRetries = (_a = options.maxRetries) !== null && _a !== void 0 ? _a : 0;
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
    const apiKey = targetApiKey;
    const keyLabel = options.apiKey ? "User BYOK Key" : "Admin Key";
    for (const model of candidateModels) {
        let attempt = 0;
        while (attempt <= maxRetries) {
            try {
                const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
                console.log(`[GeminiHelper] Trying model '${model}' with ${keyLabel} (...${apiKey.slice(-4)}, Attempt: ${attempt + 1}/${maxRetries + 1})...`);
                const response = await axios_1.default.post(url, normalizedPayload, {
                    headers: { "Content-Type": "application/json" },
                    timeout
                });
                const candidates = (_b = response.data) === null || _b === void 0 ? void 0 : _b.candidates;
                if (!candidates || candidates.length === 0) {
                    throw new Error(`No candidates returned from Gemini model ${model}`);
                }
                const text = ((_e = (_d = (_c = candidates[0].content) === null || _c === void 0 ? void 0 : _c.parts) === null || _d === void 0 ? void 0 : _d[0]) === null || _e === void 0 ? void 0 : _e.text) || "";
                console.log(`[GeminiHelper] Successfully executed '${model}' with ${keyLabel}!`);
                return {
                    text,
                    raw: response.data,
                    modelUsed: `${model} (${keyLabel})`
                };
            }
            catch (err) {
                lastError = err;
                const status = (_f = err.response) === null || _f === void 0 ? void 0 : _f.status;
                const errData = (_h = (_g = err.response) === null || _g === void 0 ? void 0 : _g.data) === null || _h === void 0 ? void 0 : _h.error;
                const errMsg = (errData === null || errData === void 0 ? void 0 : errData.message) || err.message;
                console.warn(`[GeminiHelper] Error on '${model}' with ${keyLabel} (Status ${status}): ${errMsg}`);
                // If model doesn't exist on Google API, prune it immediately
                if (status === 404 || (status === 400 && (errMsg.includes("no longer available") || errMsg.includes("not supported") || errMsg.includes("not found")))) {
                    console.log(`[GeminiHelper] Model '${model}' is unavailable on Google API. Pruning from active list.`);
                    unsupportedModels.add(model);
                    break;
                }
                // 429 Rate limit
                if (status === 429) {
                    attempt++;
                    if (attempt <= maxRetries) {
                        const delayMs = attempt * 1500;
                        console.log(`[GeminiHelper] 429 for '${model}'. Backing off ${delayMs}ms before retry...`);
                        await new Promise((res) => setTimeout(res, delayMs));
                        continue;
                    }
                    console.log(`[GeminiHelper] 429 for '${model}'. Cascading immediately to next model in tier...`);
                    break; // Move to next model in cascade
                }
                // 503 / 502 / 504 Transient high demand or server overload spike
                if (status === 503 || status === 502 || status === 504 || (errMsg && (errMsg.includes("high demand") || errMsg.includes("spikes in demand") || errMsg.includes("temporarily unavailable") || errMsg.includes("overloaded")))) {
                    attempt++;
                    if (attempt <= maxRetries) {
                        const delayMs = attempt * 2000;
                        console.log(`[GeminiHelper] Server transient high-demand/busy spike (Status ${status}) on '${model}'. Backing off ${delayMs}ms before retry...`);
                        await new Promise((res) => setTimeout(res, delayMs));
                        continue;
                    }
                    console.log(`[GeminiHelper] High demand (Status ${status}) on '${model}'. Cascading immediately to next model in tier...`);
                    break; // Move to next model in cascade
                }
                // For any other unexpected error, immediately cascade to next model
                console.warn(`[GeminiHelper] Error on '${model}' (${status}): ${errMsg}. Cascading to next model...`);
                break; // Move to next model
            }
        }
    }
    // Tier-2 Universal Fallback: If all Gemini models failed, attempt Groq (Llama 3.3 70B)
    const groqKey = (options.groqApiKey || "").trim();
    if (groqKey) {
        console.log(`[GeminiHelper] 🔄 All Gemini models failed or rate-limited. Cascading to Tier-2 Groq fallback (llama-3.3-70b-versatile)...`);
        try {
            let extractedText = "";
            if (payload && Array.isArray(payload.contents)) {
                for (const item of payload.contents) {
                    if (Array.isArray(item.parts)) {
                        for (const part of item.parts) {
                            if (typeof part.text === "string") {
                                extractedText += part.text + "\n";
                            }
                        }
                    }
                }
            }
            else if (typeof payload === "string") {
                extractedText = payload;
            }
            if (extractedText.trim()) {
                const groqRes = await (0, groqHelper_1.callGroqAPI)({
                    apiKey: groqKey,
                    prompt: extractedText
                });
                console.log(`[GeminiHelper] ✅ Tier-2 Groq fallback succeeded (${groqRes.modelUsed})!`);
                return {
                    text: groqRes.text,
                    raw: groqRes.raw,
                    modelUsed: `Groq (${groqRes.modelUsed}) [Gemini Fallback]`
                };
            }
        }
        catch (groqErr) {
            console.error(`[GeminiHelper] Tier-2 Groq fallback also failed: ${groqErr.message}`);
        }
    }
    const isQuota = ((_j = lastError === null || lastError === void 0 ? void 0 : lastError.response) === null || _j === void 0 ? void 0 : _j.status) === 429;
    const isBusy = ((_k = lastError === null || lastError === void 0 ? void 0 : lastError.response) === null || _k === void 0 ? void 0 : _k.status) === 503 ||
        ((_l = lastError === null || lastError === void 0 ? void 0 : lastError.response) === null || _l === void 0 ? void 0 : _l.status) === 502 ||
        ((_m = lastError === null || lastError === void 0 ? void 0 : lastError.response) === null || _m === void 0 ? void 0 : _m.status) === 504 ||
        (((_q = (_p = (_o = lastError === null || lastError === void 0 ? void 0 : lastError.response) === null || _o === void 0 ? void 0 : _o.data) === null || _p === void 0 ? void 0 : _p.error) === null || _q === void 0 ? void 0 : _q.message) && (lastError.response.data.error.message.includes("high demand") ||
            lastError.response.data.error.message.includes("spikes in demand") ||
            lastError.response.data.error.message.includes("overloaded")));
    const finalMessage = isQuota
        ? "Gemini API Quota Exceeded (HTTP 429). The daily or per-minute rate limit for Gemini API has been reached on this key. Please check your Google AI Studio / GCP quota or configure a backup API key."
        : isBusy
            ? "Google AI Studio is currently experiencing high demand (HTTP 503). Spikes in traffic are temporary. Please try again after a few moments."
            : (((_t = (_s = (_r = lastError === null || lastError === void 0 ? void 0 : lastError.response) === null || _r === void 0 ? void 0 : _r.data) === null || _s === void 0 ? void 0 : _s.error) === null || _t === void 0 ? void 0 : _t.message) || (lastError === null || lastError === void 0 ? void 0 : lastError.message) || "All Gemini API attempts failed across all models.");
    throw new Error(`Gemini Service Error: ${finalMessage}`);
}
//# sourceMappingURL=geminiHelper.js.map