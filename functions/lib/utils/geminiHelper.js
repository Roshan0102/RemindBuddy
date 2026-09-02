"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.fetchAvailableModelsFromAPI = fetchAvailableModelsFromAPI;
exports.callGeminiAPI = callGeminiAPI;
const axios_1 = require("axios");
const firebase_1 = require("../config/firebase");
// Official active Gemini models ordered by speed, intelligence and fallback hierarchy
const DEFAULT_MODELS = [
    "gemini-3.7-flash",
    "gemini-3.6-flash",
    "gemini-3.5-flash",
    "gemini-flash-latest",
    "gemini-3.5-flash-lite",
    "gemini-2.5-flash",
    "gemini-3.1-pro-preview"
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
    return DEFAULT_MODELS;
}
// In-memory runtime cache to eliminate 40-second latency on repeated calls
const unsupportedModels = new Set();
let cachedWorkingModel = null;
/**
 * High-performance Gemini API caller:
 * - Instant sub-second response via cached working model
 * - Multi-API-key fallback across Primary & Secondary keys configured in Firestore admin_creds/gemini_config
 * - Immediate 404/unsupported model pruning (no redundant second-key requests on non-existent models)
 * - Automatic failover on rate limits (429) or server errors
 */
async function callGeminiAPI(payload, options = {}) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m;
    // 1. Fetch API Key(s) from admin_creds/gemini_config
    const configDoc = await firebase_1.db.collection("admin_creds").doc("gemini_config").get();
    let primaryKey = "";
    const backupKeys = [];
    if (configDoc.exists) {
        const data = configDoc.data() || {};
        primaryKey = (data.apiKey || "").trim();
        // Support string secondaryApiKey from admin panel
        if (typeof data.secondaryApiKey === "string" && data.secondaryApiKey.trim().length > 0) {
            backupKeys.push(data.secondaryApiKey.trim());
        }
        if (typeof data.backupApiKey === "string" && data.backupApiKey.trim().length > 0) {
            backupKeys.push(data.backupApiKey.trim());
        }
        if (Array.isArray(data.backupApiKeys)) {
            for (const k of data.backupApiKeys) {
                if (typeof k === "string" && k.trim().length > 0)
                    backupKeys.push(k.trim());
            }
        }
        else if (Array.isArray(data.apiKeys)) {
            for (const k of data.apiKeys) {
                if (typeof k === "string" && k.trim().length > 0)
                    backupKeys.push(k.trim());
            }
        }
    }
    // Deduplicate keys while keeping primary first
    const seenKeys = new Set();
    const allKeys = [];
    for (const k of [primaryKey, ...backupKeys]) {
        if (k && !seenKeys.has(k)) {
            seenKeys.add(k);
            allKeys.push(k);
        }
    }
    if (allKeys.length === 0) {
        throw new Error("Gemini API key is not configured in admin console.");
    }
    let candidateModels = options.models && options.models.length > 0 ? [...options.models] : [...DEFAULT_MODELS];
    // Filter out models that were already identified as 404/unsupported in this container instance
    candidateModels = candidateModels.filter(m => !unsupportedModels.has(m));
    // Prioritize the known working model to get instant responses
    if (cachedWorkingModel && candidateModels.includes(cachedWorkingModel)) {
        candidateModels = [cachedWorkingModel, ...candidateModels.filter(m => m !== cachedWorkingModel)];
    }
    if (candidateModels.length === 0) {
        // Fallback in case all were filtered
        candidateModels = [...DEFAULT_MODELS];
    }
    const timeout = options.timeout || 120000;
    const maxRetries = (_a = options.maxRetries) !== null && _a !== void 0 ? _a : 1;
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
    for (const model of candidateModels) {
        for (let keyIndex = 0; keyIndex < allKeys.length; keyIndex++) {
            const apiKey = allKeys[keyIndex];
            const keyLabel = keyIndex === 0 ? "Primary Key" : `Backup Key #${keyIndex}`;
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
                    // Remember working model for instant future executions
                    cachedWorkingModel = model;
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
                    // If model doesn't exist on Google API, prune it immediately so it doesn't waste time on backup keys or future calls
                    if (status === 404 || (status === 400 && (errMsg.includes("no longer available") || errMsg.includes("not supported") || errMsg.includes("not found")))) {
                        console.log(`[GeminiHelper] Model '${model}' is unavailable on Google API. Pruning from active list.`);
                        unsupportedModels.add(model);
                        if (cachedWorkingModel === model) {
                            cachedWorkingModel = null;
                        }
                        // Skip remaining keys for this non-existent model
                        break;
                    }
                    if (status === 429) {
                        // Rate limit on this key -> switch to next backup key immediately
                        attempt++;
                        if (attempt <= maxRetries && keyIndex === allKeys.length - 1) {
                            const delayMs = attempt * 1000;
                            console.log(`[GeminiHelper] 429 on all keys for '${model}'. Backing off ${delayMs}ms before next model...`);
                            await new Promise((res) => setTimeout(res, delayMs));
                            continue;
                        }
                        break;
                    }
                    // For other errors, try next key or next model
                    break;
                }
            }
        }
    }
    const isQuota = ((_j = lastError === null || lastError === void 0 ? void 0 : lastError.response) === null || _j === void 0 ? void 0 : _j.status) === 429;
    const finalMessage = isQuota
        ? "Gemini API Quota Exceeded (HTTP 429). The daily or per-minute rate limit for Gemini API has been reached on this key. Please check your Google AI Studio / GCP quota or configure a backup API key."
        : (((_m = (_l = (_k = lastError === null || lastError === void 0 ? void 0 : lastError.response) === null || _k === void 0 ? void 0 : _k.data) === null || _l === void 0 ? void 0 : _l.error) === null || _m === void 0 ? void 0 : _m.message) || (lastError === null || lastError === void 0 ? void 0 : lastError.message) || "All Gemini API attempts failed across all models.");
    throw new Error(`Gemini Service Error: ${finalMessage}`);
}
//# sourceMappingURL=geminiHelper.js.map