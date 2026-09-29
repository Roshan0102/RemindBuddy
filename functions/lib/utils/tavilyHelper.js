"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.searchTavily = searchTavily;
const axios_1 = require("axios");
/**
 * Executes a search query against Tavily Search API.
 * Supports automatic cascading: if the primary key fails or exceeds limits,
 * it seamlessly retries using the secondary API key.
 * Returns clean, parsed webpage text without HTML, ads, or cookie banners.
 */
async function searchTavily(options) {
    var _a, _b, _c, _d, _e, _f;
    const primaryKey = (options.apiKey || "").trim();
    const secondaryKey = (options.secondaryApiKey || "").trim();
    if (!primaryKey && !secondaryKey) {
        throw new Error("Tavily API key is missing or empty.");
    }
    const candidateKeys = [primaryKey, secondaryKey].filter(k => k.length > 0);
    // Deduplicate in case user entered identical keys in primary & secondary
    const keysToTry = Array.from(new Set(candidateKeys));
    let lastError = null;
    for (let i = 0; i < keysToTry.length; i++) {
        const currentKey = keysToTry[i];
        const isFallback = i > 0;
        const maskedKey = currentKey.length > 8 ? `${currentKey.slice(0, 6)}...${currentKey.slice(-4)}` : "key";
        if (isFallback) {
            console.log(`[Tavily] 🔄 Cascading to secondary Tavily API key (${maskedKey}) due to primary key failure...`);
        }
        const payload = {
            api_key: currentKey,
            query: options.query,
            search_depth: options.searchDepth || "advanced",
            max_results: options.maxResults || 5,
            include_answer: (_a = options.includeAnswer) !== null && _a !== void 0 ? _a : false
        };
        if (Array.isArray(options.includeDomains) && options.includeDomains.length > 0) {
            payload.include_domains = options.includeDomains;
        }
        if (Array.isArray(options.excludeDomains) && options.excludeDomains.length > 0) {
            payload.exclude_domains = options.excludeDomains;
        }
        if (typeof options.days === "number" && options.days > 0) {
            payload.days = options.days;
        }
        try {
            const response = await axios_1.default.post("https://api.tavily.com/search", payload, {
                headers: { "Content-Type": "application/json" },
                timeout: options.timeout || 20000
            });
            const data = response.data || {};
            const results = (data.results || []).map((r) => ({
                title: r.title || "",
                url: r.url || "",
                content: r.content || "",
                score: typeof r.score === "number" ? r.score : undefined,
                rawContent: r.raw_content
            }));
            if (isFallback) {
                console.log(`[Tavily] ✅ Secondary Tavily API key succeeded (${results.length} results returned).`);
            }
            return {
                results,
                answer: data.answer,
                query: data.query || options.query
            };
        }
        catch (err) {
            lastError = err;
            const status = (_b = err === null || err === void 0 ? void 0 : err.response) === null || _b === void 0 ? void 0 : _b.status;
            const errMsg = ((_d = (_c = err === null || err === void 0 ? void 0 : err.response) === null || _c === void 0 ? void 0 : _c.data) === null || _d === void 0 ? void 0 : _d.message) || ((_f = (_e = err === null || err === void 0 ? void 0 : err.response) === null || _e === void 0 ? void 0 : _e.data) === null || _f === void 0 ? void 0 : _f.error) || err.message;
            console.warn(`[Tavily] Tavily key ${i + 1}/${keysToTry.length} (${maskedKey}) failed: ${errMsg} (Status: ${status || 'N/A'})`);
            if (i < keysToTry.length - 1) {
                console.log(`[Tavily] ⚠️ Primary key error/limit reached. Automatically cascading to secondary key...`);
                continue;
            }
        }
    }
    throw lastError || new Error("All configured Tavily API keys failed or exceeded quotas.");
}
//# sourceMappingURL=tavilyHelper.js.map