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
    secondaryApiKey?: string;
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
 * Supports automatic cascading: if the primary key fails or exceeds limits,
 * it seamlessly retries using the secondary API key.
 * Returns clean, parsed webpage text without HTML, ads, or cookie banners.
 */
export async function searchTavily(options: TavilySearchOptions): Promise<{
    results: TavilySearchResult[];
    answer?: string;
    query: string;
}> {
    const primaryKey = (options.apiKey || "").trim();
    const secondaryKey = (options.secondaryApiKey || "").trim();

    if (!primaryKey && !secondaryKey) {
        throw new Error("Tavily API key is missing or empty.");
    }

    const candidateKeys = [primaryKey, secondaryKey].filter(k => k.length > 0);
    // Deduplicate in case user entered identical keys in primary & secondary
    const keysToTry = Array.from(new Set(candidateKeys));

    let lastError: any = null;

    for (let i = 0; i < keysToTry.length; i++) {
        const currentKey = keysToTry[i];
        const isFallback = i > 0;
        const maskedKey = currentKey.length > 8 ? `${currentKey.slice(0, 6)}...${currentKey.slice(-4)}` : "key";

        if (isFallback) {
            console.log(`[Tavily] 🔄 Cascading to secondary Tavily API key (${maskedKey}) due to primary key failure...`);
        }

        const payload: any = {
            api_key: currentKey,
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

        try {
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

            if (isFallback) {
                console.log(`[Tavily] ✅ Secondary Tavily API key succeeded (${results.length} results returned).`);
            }

            return {
                results,
                answer: data.answer,
                query: data.query || options.query
            };
        } catch (err: any) {
            lastError = err;
            const status = err?.response?.status;
            const errMsg = err?.response?.data?.message || err?.response?.data?.error || err.message;
            console.warn(`[Tavily] Tavily key ${i + 1}/${keysToTry.length} (${maskedKey}) failed: ${errMsg} (Status: ${status || 'N/A'})`);

            if (i < keysToTry.length - 1) {
                console.log(`[Tavily] ⚠️ Primary key error/limit reached. Automatically cascading to secondary key...`);
                continue;
            }
        }
    }

    throw lastError || new Error("All configured Tavily API keys failed or exceeded quotas.");
}
