import axios from "axios";

export interface GroqCallOptions {
    apiKey: string;
    prompt?: string;
    messages?: Array<{
        role: "system" | "user" | "assistant";
        content: string | any[];
    }>;
    systemPrompt?: string;
    model?: string;
    models?: string[];
    temperature?: number;
    maxTokens?: number;
    responseFormat?: "json_object" | "text";
}

export const GROQ_MODELS = [
    "llama-3.3-70b-versatile",
    "llama-3.1-8b-instant",
    "qwen/qwen3.8-27b",
    "openai/gpt-oss-120b",
    "openai/gpt-oss-20b"
];

export const GROQ_VISION_MODELS = [
    "llama-3.2-11b-vision-preview",
    "llama-3.2-90b-vision-preview"
];

/**
 * Executes an AI completion against Groq's high-speed LPU inference engine.
 * Fully compatible with OpenAI chat completions schema.
 */
export async function callGroqAPI(
    options: GroqCallOptions
): Promise<{ text: string; raw: any; modelUsed: string }> {
    const apiKey = (options.apiKey || "").trim();
    if (!apiKey) {
        throw new Error("Groq API key is missing or empty.");
    }

    const messages: Array<{ role: "system" | "user" | "assistant"; content: string | any[] }> = [];

    if (options.messages && options.messages.length > 0) {
        messages.push(...options.messages);
    } else {
        if (options.systemPrompt && options.systemPrompt.trim()) {
            messages.push({ role: "system", content: options.systemPrompt.trim() });
        }
        if (options.prompt) {
            messages.push({ role: "user", content: options.prompt.trim() });
        }
    }

    const hasImages = messages.some(m => Array.isArray(m.content) && m.content.some((p: any) => p.type === "image_url"));
    let candidateModels: string[];

    if (options.models && options.models.length > 0) {
        candidateModels = options.models;
    } else if (options.model) {
        candidateModels = [options.model];
    } else if (hasImages) {
        candidateModels = [...GROQ_VISION_MODELS, ...GROQ_MODELS];
    } else {
        candidateModels = GROQ_MODELS;
    }

    let lastError: any = null;

    for (const model of candidateModels) {
        try {
            console.log(`[GroqHelper] Calling Groq API with model '${model}'...`);
            const payload: any = {
                model,
                messages,
                temperature: options.temperature ?? 0.2,
                max_tokens: options.maxTokens ?? 4096
            };

            if (options.responseFormat === "json_object") {
                payload.response_format = { type: "json_object" };
            }

            const response = await axios.post("https://api.groq.com/openai/v1/chat/completions", payload, {
                headers: {
                    "Authorization": `Bearer ${apiKey}`,
                    "Content-Type": "application/json"
                },
                timeout: 60000
            });

            const content = response.data?.choices?.[0]?.message?.content || "";
            console.log(`[GroqHelper] ✅ Successfully executed '${model}' on Groq!`);
            return {
                text: content,
                raw: response.data,
                modelUsed: model
            };
        } catch (err: any) {
            lastError = err;
            const status = err.response?.status;
            const errMsg = err.response?.data?.error?.message || err.message;
            console.warn(`[GroqHelper] Model '${model}' failed on Groq (HTTP ${status}): ${errMsg}`);
            if (status === 401) {
                // Invalid API key, do not retry other models
                throw new Error(`Groq API Authentication Error (HTTP 401): ${errMsg}`);
            }
        }
    }

    throw lastError || new Error("All Groq models failed.");
}
