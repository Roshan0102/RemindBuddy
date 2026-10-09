"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.scrapeJobPosting = scrapeJobPosting;
const axios_1 = require("axios");
const cheerio = require("cheerio");
/**
 * High-fidelity job posting web scraper.
 * Supports: Workday (myworkdayjobs.com), Greenhouse, Lever, Ashby, and general corporate career sites.
 *
 * Fetches the authentic web page, parses JSON-LD (JobPosting schema) and targeted DOM elements,
 * and extracts the complete official requirements, responsibilities, and experience criteria.
 */
async function scrapeJobPosting(url, timeoutMs = 12000) {
    if (!url || typeof url !== "string" || !url.startsWith("http")) {
        return null;
    }
    try {
        const res = await axios_1.default.get(url, {
            timeout: timeoutMs,
            headers: {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
                "Accept-Language": "en-US,en;q=0.9",
                "Cache-Control": "no-cache"
            },
            maxRedirects: 5,
            responseType: "text",
            validateStatus: (status) => status < 400
        });
        const html = typeof res.data === "string" ? res.data : "";
        if (!html || html.length < 120) {
            return null;
        }
        const lowerHtml = html.toLowerCase();
        // Check for common closed / 404 / error pages
        if (lowerHtml.includes("<title>404") ||
            lowerHtml.includes("<title>page not found") ||
            lowerHtml.includes("<title>job not found") ||
            lowerHtml.includes("job is no longer available") ||
            lowerHtml.includes("this position has been filled") ||
            lowerHtml.includes("job opening has expired") ||
            lowerHtml.includes("error=true")) {
            return null;
        }
        const $ = cheerio.load(html);
        let structuredTitle = "";
        let structuredCompany = "";
        let structuredLocation = "";
        let structuredDesc = "";
        let structuredFound = false;
        // 1. Extract JSON-LD Schema (Workday, Greenhouse, SmartRecruiters, Lever, etc.)
        $("script[type=\"application/ld+json\"]").each((_, el) => {
            var _a, _b;
            try {
                const raw = $(el).html() || "{}";
                const json = JSON.parse(raw);
                const items = Array.isArray(json) ? json : [json];
                for (const item of items) {
                    if (item["@type"] === "JobPosting" || item.description || item.title) {
                        structuredFound = true;
                        if (item.title && !structuredTitle) {
                            structuredTitle = cheerio.load(item.title).text().trim();
                        }
                        if (((_a = item.hiringOrganization) === null || _a === void 0 ? void 0 : _a.name) && !structuredCompany) {
                            structuredCompany = cheerio.load(item.hiringOrganization.name).text().trim();
                        }
                        if (((_b = item.jobLocation) === null || _b === void 0 ? void 0 : _b.address) && !structuredLocation) {
                            const addr = item.jobLocation.address;
                            if (typeof addr === "string") {
                                structuredLocation = addr;
                            }
                            else if (typeof addr === "object") {
                                const parts = [addr.addressLocality, addr.addressRegion, addr.addressCountry].filter(Boolean);
                                structuredLocation = parts.join(", ");
                            }
                        }
                        if (item.description) {
                            const cleanedDesc = cheerio.load(item.description).text().trim();
                            if (cleanedDesc.length > structuredDesc.length) {
                                structuredDesc = cleanedDesc;
                            }
                        }
                    }
                }
            }
            catch (_c) {
                // Ignore malformed JSON-LD scripts
            }
        });
        // 2. Extract Clean DOM Content
        $("script, style, noscript, nav, header, footer, svg, button, form, iframe").remove();
        // Target high-priority job posting containers first
        let mainContent = "";
        const prioritySelectors = [
            "[data-automation-id=\"jobPostingDescription\"]", // Workday
            "[data-qa=\"job-description\"]",
            ".job-description",
            "#job-description",
            ".posting-page", // Lever
            ".section-page",
            ".job-details",
            "main",
            "article"
        ];
        for (const sel of prioritySelectors) {
            const el = $(sel).first();
            if (el.length > 0) {
                const text = el.text().replace(/\s+/g, " ").trim();
                if (text.length > 400) {
                    mainContent = text;
                    break;
                }
            }
        }
        if (!mainContent) {
            mainContent = $("body").text().replace(/\s+/g, " ").trim();
        }
        // Merge structured description and page body
        let combinedContent = "";
        if (structuredDesc && structuredDesc.length > 300) {
            combinedContent = structuredDesc;
            // Append supplementary body text if it contains unique requirements
            if (mainContent && !mainContent.includes(structuredDesc.slice(0, 100))) {
                combinedContent += "\n\n" + mainContent;
            }
        }
        else {
            combinedContent = mainContent;
        }
        combinedContent = combinedContent.replace(/\s+/g, " ").trim();
        if (combinedContent.length < 150) {
            return null;
        }
        const fallbackTitle = $("title").text().replace(/[-|].*$/, "").trim() || "Software Engineer";
        return {
            title: structuredTitle || fallbackTitle,
            company: structuredCompany || "",
            location: structuredLocation || undefined,
            content: combinedContent.slice(0, 12000), // Rich context limit for LLM prompt
            structuredDataFound: structuredFound
        };
    }
    catch (_a) {
        return null;
    }
}
//# sourceMappingURL=jobScraper.js.map