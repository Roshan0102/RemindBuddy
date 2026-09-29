import axios from "axios";

export interface GroqCallOptions {
    apiKey: string;
    prompt: string;
    systemPrompt?: string;
    model?: string;
    temperature?: number;
    maxTokens?: number;
    responseFormat?: "json_object" | "text";
}

export const GROQ_MODELS = [
    "llama-3.3-70b-versatile",
    "llama-3.1-8b-instant"
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

    const candidateModels = options.model ? [options.model, ...GROQ_MODELS] : GROQ_MODELS;
    const messages: Array<{ role: "system" | "user"; content: string }> = [];

    if (options.systemPrompt && options.systemPrompt.trim()) {
        messages.push({ role: "system", content: options.systemPrompt.trim() });
    }
    messages.push({ role: "user", content: options.prompt.trim() });

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
