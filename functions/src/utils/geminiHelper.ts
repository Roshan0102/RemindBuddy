import axios from "axios";
import { db } from "../config/firebase";

export interface GeminiCallOptions {
    apiKey?: string;
    models?: string[];
    maxRetries?: number;
    timeout?: number;
}

// Active Gemini models ordered by speed, intelligence and fallback hierarchy
export const DEFAULT_MODELS = [
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
export async function fetchAvailableModelsFromAPI(apiKey: string): Promise<string[]> {
    try {
        const url = `https://generativelanguage.googleapis.com/v1beta/models?key=${apiKey}`;
        const response = await axios.get(url, { timeout: 10000 });
        const modelsList: any[] = response.data?.models || [];
        const validModels = modelsList
            .filter((m: any) =>
                Array.isArray(m.supportedGenerationMethods) &&
                m.supportedGenerationMethods.includes("generateContent") &&
                typeof m.name === "string" &&
                m.name.startsWith("models/gemini-")
            )
            .map((m: any) => m.name.replace(/^models\//, ""));

        if (validModels.length > 0) {
            console.log(`[GeminiHelper] Dynamically discovered ${validModels.length} models for API key:`, validModels);
            return validModels;
        }
    } catch (e: any) {
        console.warn(`[GeminiHelper] Could not fetch dynamic models list from Google API: ${e.message}`);
    }
    return DEFAULT_MODELS;
}

// In-memory runtime cache to eliminate latency on repeated calls
const unsupportedModels = new Set<string>();

/**
 * High-performance Gemini API caller:
 * - Operates purely on custom user BYOK apiKey (or falls back to central admin key if none configured)
 * - Intelligent 8-tier cascade starting with gemini-3.8-flash -> 3.7 -> 3.6 -> flash-latest -> 3.5 -> 3.5-lite -> flash-lite-latest -> 3.1-lite
 * - Built-in exponential backoff for HTTP 503 (high-demand transient spikes) and HTTP 429
 */
export async function callGeminiAPI(
    payload: any,
    options: GeminiCallOptions = {}
): Promise<{ text: string; raw: any; modelUsed: string }> {
    let targetApiKey = (options.apiKey || "").trim();

    // If no custom user key provided, fetch admin key from Firestore
    if (!targetApiKey) {
        const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
        if (configDoc.exists) {
            const data = configDoc.data() || {};
            targetApiKey = (data.apiKey || "").trim();
        }
    }

    if (!targetApiKey) {
        throw new Error("Gemini API key is not configured (neither user key nor admin key available).");
    }

    let candidateModels = options.models && options.models.length > 0 ? [...options.models] : [...DEFAULT_MODELS];

    // Filter out models that were already identified as 404/unsupported in this container instance
    candidateModels = candidateModels.filter(m => !unsupportedModels.has(m));

    if (candidateModels.length === 0) {
        candidateModels = [...DEFAULT_MODELS];
    }

    const timeout = options.timeout || 120000;
    const maxRetries = options.maxRetries ?? 1;

    let lastError: any = null;

    // Normalize tools payload for Google Search if present
    const normalizedPayload = JSON.parse(JSON.stringify(payload));
    if (Array.isArray(normalizedPayload.tools)) {
        normalizedPayload.tools = normalizedPayload.tools.map((tool: any) => {
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

                const response = await axios.post(url, normalizedPayload, {
                    headers: { "Content-Type": "application/json" },
                    timeout
                });

                const candidates = response.data?.candidates;
                if (!candidates || candidates.length === 0) {
                    throw new Error(`No candidates returned from Gemini model ${model}`);
                }

                const text = candidates[0].content?.parts?.[0]?.text || "";
                console.log(`[GeminiHelper] Successfully executed '${model}' with ${keyLabel}!`);

                return {
                    text,
                    raw: response.data,
                    modelUsed: `${model} (${keyLabel})`
                };
            } catch (err: any) {
                lastError = err;
                const status = err.response?.status;
                const errData = err.response?.data?.error;
                const errMsg = errData?.message || err.message;
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
                    console.log(`[GeminiHelper] 429 limit reached for '${model}'. Cascading to next model in tier...`);
                    await new Promise((res) => setTimeout(res, 500));
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
                    console.log(`[GeminiHelper] Server still busy for '${model}'. Cascading to next model in tier...`);
                    await new Promise((res) => setTimeout(res, 500));
                    break; // Move to next model in cascade
                }

                // For any other unexpected error, pause briefly and cascade to next model
                console.warn(`[GeminiHelper] Unhandled error on '${model}' (${status}): ${errMsg}. Cascading to next model...`);
                await new Promise((res) => setTimeout(res, 400));
                break; // Move to next model
            }
        }
    }

    const isQuota = lastError?.response?.status === 429;
    const finalMessage = isQuota
        ? "Gemini API Quota Exceeded (HTTP 429). The daily or per-minute rate limit for Gemini API has been reached on this key. Please check your Google AI Studio / GCP quota or configure a backup API key."
        : (lastError?.response?.data?.error?.message || lastError?.message || "All Gemini API attempts failed across all models.");
    throw new Error(`Gemini Service Error: ${finalMessage}`);
}

