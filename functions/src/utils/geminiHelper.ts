import axios from "axios";
import { db } from "../config/firebase";

export interface GeminiCallOptions {
    apiKey?: string;
    models?: string[];
    maxRetries?: number;
    timeout?: number;
}

// Active Gemini models ordered by speed, intelligence and fallback hierarchy
const DEFAULT_MODELS = [
    "gemini-3.7-flash",
    "gemini-3.6-flash",
    "gemini-3.5-flash"
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
let cachedWorkingModel: string | null = null;

/**
 * High-performance Gemini API caller:
 * - Supports custom user BYOK apiKey via options.apiKey
 * - Falls back to central admin Gemini API key from admin_creds/gemini_config
 * - Cascade failover across models: Gemini 3.7 Flash -> Gemini 3.6 Flash -> Gemini 3.5 Flash
 * - Instant response via cached working model
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

    // Prioritize the known working model to get instant responses
    if (cachedWorkingModel && candidateModels.includes(cachedWorkingModel)) {
        candidateModels = [cachedWorkingModel, ...candidateModels.filter(m => m !== cachedWorkingModel)];
    }

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

                // Remember working model for instant future executions
                cachedWorkingModel = model;

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
                    if (cachedWorkingModel === model) {
                        cachedWorkingModel = null;
                    }
                    break;
                }

                if (status === 429) {
                    attempt++;
                    if (attempt <= maxRetries) {
                        const delayMs = attempt * 1000;
                        console.log(`[GeminiHelper] 429 for '${model}'. Backing off ${delayMs}ms before retry...`);
                        await new Promise((res) => setTimeout(res, delayMs));
                        continue;
                    }
                    break; // Move to next model in cascade
                }

                break; // For other errors, move to next model
            }
        }
    }

    const isQuota = lastError?.response?.status === 429;
    const finalMessage = isQuota
        ? "Gemini API Quota Exceeded (HTTP 429). The daily or per-minute rate limit for Gemini API has been reached on this key. Please check your Google AI Studio / GCP quota or configure a backup API key."
        : (lastError?.response?.data?.error?.message || lastError?.message || "All Gemini API attempts failed across all models.");
    throw new Error(`Gemini Service Error: ${finalMessage}`);
}

