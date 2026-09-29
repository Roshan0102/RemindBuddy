"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.GROQ_MODELS = void 0;
exports.callGroqAPI = callGroqAPI;
const axios_1 = require("axios");
exports.GROQ_MODELS = [
    "llama-3.3-70b-versatile",
    "llama-3.1-8b-instant"
];
/**
 * Executes an AI completion against Groq's high-speed LPU inference engine.
 * Fully compatible with OpenAI chat completions schema.
 */
async function callGroqAPI(options) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
    const apiKey = (options.apiKey || "").trim();
    if (!apiKey) {
        throw new Error("Groq API key is missing or empty.");
    }
    const candidateModels = options.model ? [options.model, ...exports.GROQ_MODELS] : exports.GROQ_MODELS;
    const messages = [];
    if (options.systemPrompt && options.systemPrompt.trim()) {
        messages.push({ role: "system", content: options.systemPrompt.trim() });
    }
    messages.push({ role: "user", content: options.prompt.trim() });
    let lastError = null;
    for (const model of candidateModels) {
        try {
            console.log(`[GroqHelper] Calling Groq API with model '${model}'...`);
            const payload = {
                model,
                messages,
                temperature: (_a = options.temperature) !== null && _a !== void 0 ? _a : 0.2,
                max_tokens: (_b = options.maxTokens) !== null && _b !== void 0 ? _b : 4096
            };
            if (options.responseFormat === "json_object") {
                payload.response_format = { type: "json_object" };
            }
            const response = await axios_1.default.post("https://api.groq.com/openai/v1/chat/completions", payload, {
                headers: {
                    "Authorization": `Bearer ${apiKey}`,
                    "Content-Type": "application/json"
                },
                timeout: 60000
            });
            const content = ((_f = (_e = (_d = (_c = response.data) === null || _c === void 0 ? void 0 : _c.choices) === null || _d === void 0 ? void 0 : _d[0]) === null || _e === void 0 ? void 0 : _e.message) === null || _f === void 0 ? void 0 : _f.content) || "";
            console.log(`[GroqHelper] ✅ Successfully executed '${model}' on Groq!`);
            return {
                text: content,
                raw: response.data,
                modelUsed: model
            };
        }
        catch (err) {
            lastError = err;
            const status = (_g = err.response) === null || _g === void 0 ? void 0 : _g.status;
            const errMsg = ((_k = (_j = (_h = err.response) === null || _h === void 0 ? void 0 : _h.data) === null || _j === void 0 ? void 0 : _j.error) === null || _k === void 0 ? void 0 : _k.message) || err.message;
            console.warn(`[GroqHelper] Model '${model}' failed on Groq (HTTP ${status}): ${errMsg}`);
            if (status === 401) {
                // Invalid API key, do not retry other models
                throw new Error(`Groq API Authentication Error (HTTP 401): ${errMsg}`);
            }
        }
    }
    throw lastError || new Error("All Groq models failed.");
}
//# sourceMappingURL=groqHelper.js.map