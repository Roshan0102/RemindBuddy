import axios from "axios";

export interface TavilySearchResult {
    title: string;
    url: string;
    content: string;
    score?: number;
    rawContent?: string;
}

export interface TavilySearchOptions {
    apiKey: string;
    query: string;
    searchDepth?: "basic" | "advanced";
    maxResults?: number;
    includeDomains?: string[];
    excludeDomains?: string[];
    includeAnswer?: boolean;
    days?: number;
    timeout?: number;
}

/**
 * Executes a search query against Tavily Search API.
 * Returns clean, parsed webpage text without HTML, ads, or cookie banners.
 */
export async function searchTavily(options: TavilySearchOptions): Promise<{
    results: TavilySearchResult[];
    answer?: string;
    query: string;
}> {
    const apiKey = (options.apiKey || "").trim();
    if (!apiKey) {
        throw new Error("Tavily API key is missing or empty.");
    }

    const payload: any = {
        api_key: apiKey,
        query: options.query,
        search_depth: options.searchDepth || "advanced",
        max_results: options.maxResults || 5,
        include_answer: options.includeAnswer ?? false
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

    const response = await axios.post("https://api.tavily.com/search", payload, {
        headers: { "Content-Type": "application/json" },
        timeout: options.timeout || 20000
    });

    const data = response.data || {};
    const results: TavilySearchResult[] = (data.results || []).map((r: any) => ({
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
