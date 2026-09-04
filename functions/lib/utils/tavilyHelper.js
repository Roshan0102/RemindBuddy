"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.searchTavily = searchTavily;
const axios_1 = require("axios");
/**
 * Executes a search query against Tavily Search API.
 * Returns clean, parsed webpage text without HTML, ads, or cookie banners.
 */
async function searchTavily(options) {
    var _a;
    const apiKey = (options.apiKey || "").trim();
    if (!apiKey) {
        throw new Error("Tavily API key is missing or empty.");
    }
    const payload = {
        api_key: apiKey,
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
    return {
        results,
        answer: data.answer,
        query: data.query || options.query
    };
}
//# sourceMappingURL=tavilyHelper.js.map