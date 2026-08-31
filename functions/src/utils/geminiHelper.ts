import axios from "axios";
import { db } from "../config/firebase";

export interface GeminiCallOptions {
    models?: string[];
    maxRetries?: number;
    timeout?: number;
}

const DEFAULT_MODELS = [
    "gemini-3.7-flash",
    "gemini-3.6-flash",
    "gemini-3.5-flash",
    "gemini-3-flash",
    "gemini-3.0-flash",
    "gemini-2.5-flash",
    "gemini-2.0-flash",
    "gemini-1.5-flash",
    "gemini-1.5-pro"
];

/**
 * Robust Gemini API caller that handles:
 * - Multi-model fallback cascade (gemini-3.7-flash -> gemini-3.6-flash -> gemini-3.5-flash -> gemini-3-flash -> gemini-2.5-flash -> ...)
 * - Multi-API-key fallback across Primary & Secondary keys configured in Firestore admin_creds/gemini_config
 * - Automatic retry & failover on rate limits (429), model unavailability (400/404), or server errors
 */
export async function callGeminiAPI(
    payload: any,
    options: GeminiCallOptions = {}
): Promise<{ text: string; raw: any; modelUsed: string }> {
    // 1. Fetch API Key(s) from admin_creds/gemini_config
    const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
    let primaryKey = "";
    const backupKeys: string[] = [];

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
                if (typeof k === "string" && k.trim().length > 0) backupKeys.push(k.trim());
            }
        } else if (Array.isArray(data.apiKeys)) {
            for (const k of data.apiKeys) {
                if (typeof k === "string" && k.trim().length > 0) backupKeys.push(k.trim());
            }
        }
    }

    // Deduplicate keys while keeping primary first
    const seenKeys = new Set<string>();
    const allKeys: string[] = [];
    for (const k of [primaryKey, ...backupKeys]) {
        if (k && !seenKeys.has(k)) {
            seenKeys.add(k);
            allKeys.push(k);
        }
    }

    if (allKeys.length === 0) {
        throw new Error("Gemini API key is not configured in admin console.");
    }

    const modelsToTry = options.models && options.models.length > 0 ? options.models : DEFAULT_MODELS;
    const timeout = options.timeout || 240000;
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

    for (const model of modelsToTry) {
        for (let keyIndex = 0; keyIndex < allKeys.length; keyIndex++) {
            const apiKey = allKeys[keyIndex];
            const keyLabel = keyIndex === 0 ? "Primary Key" : `Backup Key #${keyIndex}`;
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

                    if (status === 429) {
                        // Rate limit exceeded on this key
                        attempt++;
                        if (attempt <= maxRetries && keyIndex === allKeys.length - 1) {
                            const delayMs = attempt * 1500;
                            console.log(`[GeminiHelper] 429 on all keys for '${model}'. Backing off ${delayMs}ms before next model...`);
                            await new Promise((res) => setTimeout(res, delayMs));
                            continue;
                        }
                        // Move to next key for the same model
                        break;
                    }

                    // For other errors (e.g. 400 model no longer available, 404 not found), fail over to next key or model immediately
                    break;
                }
            }
        }
    }

    const isQuota = lastError?.response?.status === 429;
    const finalMessage = isQuota
        ? "Gemini API Quota Exceeded (HTTP 429). The daily or per-minute rate limit for Gemini API has been reached on this key. Please check your Google AI Studio / GCP quota or configure a backup API key."
        : (lastError?.response?.data?.error?.message || lastError?.message || "All Gemini API attempts failed across all models.");
    throw new Error(`Gemini Service Error: ${finalMessage}`);
}
