import axios from "axios";

export interface LinkedInPostItem {
    id: string;
    url: string;
    authorName: string;
    authorTitle: string;
    authorUrl?: string;
    postedAgo: string;
    timestamp?: number;
    content: string;
    emails: string[];
    hasEmail: boolean;
}

export interface ApifyLinkedInSearchOptions {
    apiToken?: string;
    apiTokens?: string[];
    roles?: string[];
    locations?: string[];
    experienceFilter?: string; // e.g. "1-3 years" or "junior"
    datePosted?: "past-24h" | "past-week" | "past-month";
    maxPosts?: number;
}

/**
 * Searches real-time LinkedIn recruiter hiring posts via Apify harvestapi~linkedin-post-search.
 * Zero cookies / accounts required. Executes in ~5-10 seconds inside Cloud Functions.
 * Cycles across up to 3 configured user Apify tokens if quota is exhausted. Zero retries per token to conserve credits.
 */
export async function searchLinkedInPostsViaApify(
    options: ApifyLinkedInSearchOptions
): Promise<{ success: boolean; totalFetched: number; postsWithEmails: number; posts: LinkedInPostItem[]; usedTokenIndex?: number }> {
    const {
        apiToken,
        apiTokens,
        roles = ["DevOps Engineer", "Cloud Engineer", "Site Reliability Engineer"],
        locations = [],
        datePosted = "past-24h",
        maxPosts = 25
    } = options;

    const tokensToTry: string[] = [];
    if (apiTokens && Array.isArray(apiTokens)) {
        for (const t of apiTokens) {
            const trimmed = (t || "").trim();
            if (trimmed && !tokensToTry.includes(trimmed)) tokensToTry.push(trimmed);
        }
    }
    if (apiToken && !tokensToTry.includes(apiToken.trim())) {
        tokensToTry.unshift(apiToken.trim());
    }

    if (tokensToTry.length === 0) {
        throw new Error("At least one Apify API Token is required.");
    }

    // Limit to max 4 target roles
    const safeRoles = roles.slice(0, 4);

    // Expand location synonyms (e.g. Bengaluru <-> Bangalore) and build location clause
    const expandedLocs: string[] = [];
    for (const loc of (locations || []).slice(0, 5)) {
        const trimmed = (loc || "").trim();
        if (!trimmed) continue;
        if (!expandedLocs.some(x => x.toLowerCase() === trimmed.toLowerCase())) {
            expandedLocs.push(trimmed);
        }
        if (trimmed.toLowerCase() === 'bengaluru' && !expandedLocs.some(x => x.toLowerCase() === 'bangalore')) {
            expandedLocs.push('Bangalore');
        } else if (trimmed.toLowerCase() === 'bangalore' && !expandedLocs.some(x => x.toLowerCase() === 'bengaluru')) {
            expandedLocs.push('Bengaluru');
        }
    }

    const locClause = expandedLocs.length > 0
        ? `(${expandedLocs.map(l => l.includes(' ') ? `"${l}"` : l).join(' OR ')})`
        : "";

    // 1. Primary Combined Query: combines ALL candidate target roles in an OR clause + location clause.
    // This ensures Apify fetches posts across all roles rather than stopping at the first role.
    const searchQueries: string[] = [];
    if (safeRoles.length > 1) {
        const rolesOrClause = safeRoles.map(r => `"${r}"`).join(' OR ');
        searchQueries.push(
            `hiring (${rolesOrClause}) (email OR "send resume" OR "share CV" OR "mail your resume" OR CV)${locClause ? ` ${locClause}` : ''}`
        );
    }

    // 2. Individual role queries as fallback in the same run
    for (const role of safeRoles) {
        searchQueries.push(
            `hiring "${role}" (email OR "send resume" OR "share CV" OR "mail your resume" OR CV)${locClause ? ` ${locClause}` : ''}`
        );
    }

    console.log(`[ApifyLinkedIn] Executing multi-role search across ${safeRoles.length} role(s) with location clause: "${locClause || 'Any'}"...`);

    let response: any = null;
    let usedTokenIndex = 0;
    let lastError: any = null;

    // Cycle through available tokens (e.g. token 1, 2, 3) without retrying any single token
    for (let i = 0; i < tokensToTry.length; i++) {
        const currentToken = tokensToTry[i];
        const maskedToken = currentToken.length > 8 ? `${currentToken.substring(0, 4)}...${currentToken.substring(currentToken.length - 4)}` : '***';
        const endpoint = `https://api.apify.com/v2/acts/harvestapi~linkedin-post-search/run-sync-get-dataset-items?token=${encodeURIComponent(currentToken)}`;

        try {
            console.log(`[ApifyLinkedIn] Trying token #${i + 1} (${maskedToken})...`);
            response = await axios.post(endpoint, {
                searchQueries,
                sortBy: "date",
                datePosted,
                maxPosts,
                scrapeReactions: false,
                scrapeComments: false
            }, {
                headers: { "Content-Type": "application/json" },
                timeout: 60000
            });

            usedTokenIndex = i;
            break; // Success! Do not try subsequent tokens
        } catch (err: any) {
            const status = err.response?.status;
            const errMsg = err.response?.data?.error?.message || err.message;
            console.warn(`[ApifyLinkedIn] Token #${i + 1} failed (HTTP ${status}): ${errMsg}. Moving to next token if available.`);
            lastError = err;
        }
    }

    if (!response) {
        throw new Error(`Apify post search failed across all ${tokensToTry.length} token(s): ${lastError?.message || "Unknown error"}`);
    }

    let rawPosts = Array.isArray(response.data) ? response.data : [];

    // If 0 posts in past-24h, automatically widen window to past-week
    if (rawPosts.length === 0 && datePosted === "past-24h") {
        console.log(`[ApifyLinkedIn] 0 posts found in past-24h. Widening search window to past-week...`);
        try {
            const currentToken = tokensToTry[usedTokenIndex] || tokensToTry[0];
            const endpoint = `https://api.apify.com/v2/acts/harvestapi~linkedin-post-search/run-sync-get-dataset-items?token=${encodeURIComponent(currentToken)}`;
            const fallbackResp = await axios.post(endpoint, {
                searchQueries,
                sortBy: "date",
                datePosted: "past-week",
                maxPosts,
                scrapeReactions: false,
                scrapeComments: false
            }, {
                headers: { "Content-Type": "application/json" },
                timeout: 60000
            });
            if (Array.isArray(fallbackResp.data) && fallbackResp.data.length > 0) {
                rawPosts = fallbackResp.data;
                console.log(`[ApifyLinkedIn] Fallback past-week found ${rawPosts.length} posts.`);
            }
        } catch (fErr: any) {
            console.warn(`[ApifyLinkedIn] Fallback past-week attempt note: ${fErr.message}`);
        }
    }

    const emailRegex = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;

    const posts: LinkedInPostItem[] = [];

    for (const item of rawPosts) {
        const content = item.content || "";
        const rawEmails = content.match(emailRegex) || [];
        const emails: string[] = Array.from(new Set<string>(rawEmails.map((e: string) => e.trim().toLowerCase())))
            .filter((e: string) => !e.endsWith(".png") && !e.endsWith(".jpg") && !e.endsWith(".jpeg") && !e.includes("example.com"));

        const author = item.author || {};
        const postedAt = item.postedAt || {};
        const shareUrl = item.shareLinkedinUrl || (item.socialContent && item.socialContent.shareUrl) || item.linkedinUrl || "";

        posts.push({
            id: item.id || item.entityId || String(Math.random()),
            url: shareUrl,
            authorName: author.name || "LinkedIn Member",
            authorTitle: author.info || "Recruiter",
            authorUrl: author.linkedinUrl || undefined,
            postedAgo: postedAt.postedAgoText || postedAt.postedAgoShort || "Recently",
            timestamp: postedAt.timestamp || undefined,
            content,
            emails,
            hasEmail: emails.length > 0
        });
    }

    const postsWithEmails = posts.filter(p => p.hasEmail);

    return {
        success: true,
        totalFetched: posts.length,
        postsWithEmails: postsWithEmails.length,
        usedTokenIndex,
        posts
    };
}
