"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.processCareerPortalDiscoveryTask = exports.triggerCareerPortalDiscovery = void 0;
exports.verifyJobUrl = verifyJobUrl;
exports.executeCareerPortalDiscovery = executeCareerPortalDiscovery;
exports.internalCareerPortalDiscoveryDispatcher = internalCareerPortalDiscoveryDispatcher;
const functions = require("firebase-functions");
const axios_1 = require("axios");
const firebase_1 = require("../../config/firebase");
const featureLogger_1 = require("../../utils/featureLogger");
const geminiHelper_1 = require("../../utils/geminiHelper");
const tavilyHelper_1 = require("../../utils/tavilyHelper");
const pdfResumeGenerator_1 = require("../../utils/pdfResumeGenerator");
const cloudTasksHelper_1 = require("../../utils/cloudTasksHelper");
const experienceMatcher_1 = require("../../utils/experienceMatcher");
// Curated top tech companies utilizing public Greenhouse job boards
const GREENHOUSE_COMPANIES = [
    "gitlab", "airbnb", "stripe", "cloudflare", "datadog", "hashicorp",
    "figma", "postman", "elastic", "canonical", "razorpay", "cred",
    "automattic", "docker", "github", "reddit", "mongodb", "twilio",
    "segment", "pagerduty", "instacart", "robinhood", "gusto", "brex",
    "carta", "cockroachlabs", "coinbase", "snyk", "auth0"
];
// Curated top tech companies utilizing public Lever job boards
const LEVER_COMPANIES = [
    "palantir", "spotify", "yelp", "affirm", "netflix", "eventbrite",
    "lyft", "medium", "udacity", "wealthfront", "atlassian", "leverdemo"
];
// Curated companies utilizing Ashby job boards
const ASHBY_COMPANIES = [
    "linear", "ramp", "openai", "replit", "perplexity", "sourcegraph"
];
/**
 * Validates a job URL to ensure it exists and does not return 404, 410,
 * or redirect to a Greenhouse/Lever error page.
 */
async function verifyJobUrl(url) {
    var _a, _b;
    if (!url || typeof url !== "string" || !url.startsWith("http"))
        return false;
    try {
        const res = await axios_1.default.get(url, {
            timeout: 7000,
            headers: {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            },
            maxRedirects: 5,
            validateStatus: (status) => status < 400
        });
        const finalUrl = (((_b = (_a = res.request) === null || _a === void 0 ? void 0 : _a.res) === null || _b === void 0 ? void 0 : _b.responseUrl) || url).toLowerCase();
        // Greenhouse redirects invalid/closed jobs to ?error=true
        if (finalUrl.includes("error=true") || finalUrl.includes("/404")) {
            return false;
        }
        // Check for common error titles in returned HTML
        if (typeof res.data === "string") {
            const lowerData = res.data.toLowerCase();
            if (lowerData.includes("<title>404") ||
                lowerData.includes("<title>page not found") ||
                lowerData.includes("<title>job not found") ||
                lowerData.includes("this job is no longer available") ||
                lowerData.includes("this position has been filled")) {
                return false;
            }
        }
        return true;
    }
    catch (_c) {
        return false;
    }
}
/**
 * Queries public Greenhouse boards for fresh openings posted within the last 48 hours.
 */
async function fetchGreenhouseJobs(targetRoleKeywords, targetLocations, cutoffTimeMs) {
    const results = [];
    // Sample across curated companies (limit to batch of 12 per run to stay fast)
    const shuffled = [...GREENHOUSE_COMPANIES].sort(() => 0.5 - Math.random()).slice(0, 12);
    await Promise.all(shuffled.map(async (companySlug) => {
        var _a, _b, _c;
        try {
            const apiUrl = `https://boards-api.greenhouse.io/v1/boards/${companySlug}/jobs?content=true`;
            const resp = await axios_1.default.get(apiUrl, { timeout: 6000 });
            const jobs = ((_a = resp.data) === null || _a === void 0 ? void 0 : _a.jobs) || [];
            for (const j of jobs) {
                const title = (j.title || "").toLowerCase();
                const loc = (((_b = j.location) === null || _b === void 0 ? void 0 : _b.name) || "").toLowerCase();
                const updatedAt = j.updated_at || j.first_published;
                if (!updatedAt)
                    continue;
                const jobTime = new Date(updatedAt).getTime();
                // Strict 48h recency check
                if (jobTime < cutoffTimeMs)
                    continue;
                // Check role match
                const matchesRole = targetRoleKeywords.some(kw => title.includes(kw));
                if (!matchesRole)
                    continue;
                // Check location match (or if remote)
                const isRemote = loc.includes("remote") || loc.includes("anywhere") || loc.includes("worldwide");
                const matchesLoc = isRemote || targetLocations.some(l => loc.includes(l.toLowerCase()));
                if (!matchesLoc)
                    continue;
                const rawContent = (j.content || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
                results.push({
                    title: j.title || "Software Engineer",
                    company: j.company_name || companySlug.charAt(0).toUpperCase() + companySlug.slice(1),
                    url: j.absolute_url,
                    location: ((_c = j.location) === null || _c === void 0 ? void 0 : _c.name) || "Remote",
                    postedAt: new Date(updatedAt).toISOString(),
                    jd: rawContent.slice(0, 2500),
                    portalType: "greenhouse"
                });
            }
        }
        catch (_d) {
            // Ignore individual company 404s/rate-limits
        }
    }));
    return results;
}
/**
 * Queries public Lever boards for fresh postings created within the last 48 hours.
 */
async function fetchLeverJobs(targetRoleKeywords, targetLocations, cutoffTimeMs) {
    const results = [];
    const shuffled = [...LEVER_COMPANIES].sort(() => 0.5 - Math.random()).slice(0, 8);
    await Promise.all(shuffled.map(async (companySlug) => {
        var _a, _b;
        try {
            const apiUrl = `https://api.lever.co/v0/postings/${companySlug}?mode=json`;
            const resp = await axios_1.default.get(apiUrl, { timeout: 6000 });
            const postings = Array.isArray(resp.data) ? resp.data : [];
            for (const p of postings) {
                const title = (p.text || "").toLowerCase();
                const loc = (((_a = p.categories) === null || _a === void 0 ? void 0 : _a.location) || "").toLowerCase();
                const createdAt = typeof p.createdAt === "number" ? p.createdAt : 0;
                // Strict 48h recency check
                if (createdAt < cutoffTimeMs)
                    continue;
                // Check role match
                const matchesRole = targetRoleKeywords.some(kw => title.includes(kw));
                if (!matchesRole)
                    continue;
                // Check location match
                const isRemote = (p.workplaceType || "").toLowerCase() === "remote" ||
                    loc.includes("remote") || loc.includes("anywhere");
                const matchesLoc = isRemote || targetLocations.some(l => loc.includes(l.toLowerCase()));
                if (!matchesLoc)
                    continue;
                const rawContent = (p.descriptionPlain || p.description || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
                results.push({
                    title: p.text || "Software Engineer",
                    company: companySlug.charAt(0).toUpperCase() + companySlug.slice(1),
                    url: p.hostedUrl || p.applyUrl,
                    location: ((_b = p.categories) === null || _b === void 0 ? void 0 : _b.location) || "Remote",
                    postedAt: new Date(createdAt).toISOString(),
                    jd: rawContent.slice(0, 2500),
                    portalType: "lever"
                });
            }
        }
        catch (_c) {
            // Ignore individual company errors
        }
    }));
    return results;
}
/**
 * Queries Ashby boards for fresh postings.
 */
async function fetchAshbyJobs(targetRoleKeywords, targetLocations, _cutoffTimeMs) {
    const results = [];
    await Promise.all(ASHBY_COMPANIES.map(async (companySlug) => {
        var _a;
        try {
            const apiUrl = `https://api.ashbyhq.com/posting-api/job-board/${companySlug}`;
            const resp = await axios_1.default.get(apiUrl, { timeout: 6000 });
            const jobs = ((_a = resp.data) === null || _a === void 0 ? void 0 : _a.jobs) || [];
            for (const j of jobs) {
                const title = (j.title || "").toLowerCase();
                const loc = (j.location || "").toLowerCase();
                const matchesRole = targetRoleKeywords.some(kw => title.includes(kw));
                if (!matchesRole)
                    continue;
                const isRemote = (j.workplaceType || "").toLowerCase() === "remote" ||
                    loc.includes("remote") || loc.includes("anywhere");
                const matchesLoc = isRemote || targetLocations.some(l => loc.includes(l.toLowerCase()));
                if (!matchesLoc)
                    continue;
                const rawContent = (j.descriptionPlain || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
                results.push({
                    title: j.title,
                    company: companySlug.charAt(0).toUpperCase() + companySlug.slice(1),
                    url: j.jobUrl,
                    location: j.location || "Remote",
                    postedAt: new Date().toISOString(),
                    jd: rawContent.slice(0, 2500),
                    portalType: "ashby"
                });
            }
        }
        catch (_b) {
            // Ignore
        }
    }));
    return results;
}
/**
 * Searches Tavily targeting major ATS portals with days: 3 (last 72 hours).
 */
async function fetchTavilyCareerPortals(apiKey, roles, locations, maxExpYears = 3) {
    const allResults = [];
    const primaryRole = roles[0] || "Software Engineer";
    const secondaryRole = roles[1] || (roles[0] ? `${roles[0]} Developer` : "Developer");
    const locQuery = locations.map(l => `"${l}"`).join(" OR ") || '"India" OR "Remote"';
    // When candidate is early-career (<= 3 yrs), strongly exclude senior/staff/lead/executive/manager/ML titles
    const negativeFilters = maxExpYears <= 3
        ? '-senior -sr -staff -principal -lead -manager -director -vp -"product manager" -"machine learning"'
        : '-director -vp';
    const queries = [
        `("${primaryRole}") (${locQuery}) ${negativeFilters}`.trim(),
        `("${secondaryRole}") (${locQuery}) ${negativeFilters}`.trim()
    ];
    for (const q of queries) {
        try {
            const resp = await (0, tavilyHelper_1.searchTavily)({
                apiKey,
                query: q,
                searchDepth: "advanced",
                maxResults: 10,
                days: 3, // Last 72 hours
                includeDomains: [
                    "boards.greenhouse.io",
                    "jobs.lever.co",
                    "jobs.ashbyhq.com",
                    "myworkdayjobs.com"
                ]
            });
            for (const r of resp.results) {
                if (r.url && !allResults.some(existing => existing.url === r.url)) {
                    allResults.push(r);
                }
            }
        }
        catch (err) {
            console.warn(`[CareerPortalATS] Tavily search error: ${err.message}`);
        }
    }
    return allResults;
}
/**
 * Core engine for discovering, validating, and tailoring ATS Career Portal jobs.
 */
async function executeCareerPortalDiscovery(uid, options) {
    var _a, _b, _c, _d;
    console.log(`[CareerPortalATS] Starting discovery for user ${uid}...`);
    const userDoc = await firebase_1.db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
        return { success: false, discoveredCount: 0, jobs: [], message: "User not found." };
    }
    const userData = userDoc.data() || {};
    const enabledModules = userData.enabledModules || [];
    const jobSubPerms = userData.jobAssistantSubPermissions || {};
    const isParentEnabled = enabledModules.includes("job_assistant") ||
        enabledModules.includes("career_portals") ||
        enabledModules.includes("auto_apply");
    if (!isParentEnabled || jobSubPerms.career_portals === false) {
        console.log(`[CareerPortalATS] Skipping user ${uid}: career_portals module is disabled in settings.`);
        return { success: false, discoveredCount: 0, jobs: [], message: "Career portals module is disabled in settings." };
    }
    // User preference toggle (skip if disabled by user and not manual forceRefresh)
    if (((_a = userData.careerPortalsSettings) === null || _a === void 0 ? void 0 : _a.enabled) === false && !(options === null || options === void 0 ? void 0 : options.forceRefresh)) {
        console.log(`[CareerPortalATS] Skipping user ${uid}: career_portals is disabled in user settings.`);
        return { success: false, discoveredCount: 0, jobs: [], message: "Career portals discovery is disabled in your settings." };
    }
    // 1. Extract Target Preferences
    const autoApplySettings = userData.autoApplySettings || {};
    const minExpYears = typeof autoApplySettings.minExpYears === "number" ? autoApplySettings.minExpYears : 0;
    const maxExpYears = typeof autoApplySettings.maxExpYears === "number" ? autoApplySettings.maxExpYears : 3;
    const isFresher = autoApplySettings.isFresher === true || maxExpYears === 0;
    let targetRoles = autoApplySettings.targetRoles || [];
    if (typeof targetRoles === 'string') {
        targetRoles = targetRoles.split(',').map(s => s.trim()).filter(Boolean);
    }
    if (targetRoles.length === 0 && userData.targetRoles) {
        targetRoles = Array.isArray(userData.targetRoles) ? userData.targetRoles : [userData.targetRoles];
    }
    if (targetRoles.length === 0 && userData.targetRole) {
        targetRoles = [userData.targetRole];
    }
    if (targetRoles.length === 0) {
        targetRoles = ["Software Engineer", "Developer"];
    }
    if (options === null || options === void 0 ? void 0 : options.customRole) {
        targetRoles = [options.customRole, ...targetRoles];
    }
    const targetLocations = autoApplySettings.locations || autoApplySettings.targetLocations || ["India", "Remote", "Bengaluru", "Hyderabad", "Pune"];
    const targetRoleKeywords = Array.from(new Set(targetRoles.flatMap(r => r.toLowerCase().split(/[\s/,-]+/).filter(w => w.length > 2))));
    if (targetRoleKeywords.length === 0) {
        targetRoleKeywords.push("developer", "engineer", "software");
    }
    // 2. Extract Keys & Base Resume
    const userApiKeys = userData.userApiKeys || {};
    const tavilyKey = (userApiKeys.tavilyApiKey || userData.tavilyApiKey || "").trim();
    const geminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();
    if (!geminiKey) {
        const msg = "Gemini API key is required. Please configure in Settings -> AI & Search Keys.";
        await (0, featureLogger_1.logFeatureExecution)(uid, {
            feature: "career_portals",
            featureTitle: "Career Portals (ATS Matcher)",
            status: "error",
            count: 0,
            message: msg
        });
        return { success: false, discoveredCount: 0, jobs: [], message: msg };
    }
    // Base Resume loading
    let resumePdfBase64 = (((_b = userData.masterResume) === null || _b === void 0 ? void 0 : _b.base64) || ((_c = userData.masterResume) === null || _c === void 0 ? void 0 : _c.base64Data) || "").toString().trim();
    if (!resumePdfBase64) {
        const profilesSnap = await firebase_1.db.collection("users").doc(uid).collection("resume_profiles").limit(1).get();
        if (!profilesSnap.empty) {
            const pData = profilesSnap.docs[0].data();
            resumePdfBase64 = (pData.base64 || "").toString().trim();
        }
    }
    if (!resumePdfBase64) {
        const msg = "Please upload your base resume PDF in Job Assistant Settings before discovering career portal jobs.";
        await (0, featureLogger_1.logFeatureExecution)(uid, {
            feature: "career_portals",
            featureTitle: "Career Portals (ATS Matcher)",
            status: "error",
            count: 0,
            message: msg
        });
        return { success: false, discoveredCount: 0, jobs: [], message: msg };
    }
    const cleanResumeB64 = resumePdfBase64.replace(/^data:application\/pdf;base64,/, "");
    // 3. Strict 72-Hour Threshold (3 days ago)
    const nowMs = Date.now();
    const cutoff72h = nowMs - (72 * 60 * 60 * 1000);
    // 4. Fetch from All 3 Strategies
    const rawDiscovered = [];
    // A. Greenhouse Public API
    try {
        const ghJobs = await fetchGreenhouseJobs(targetRoleKeywords, targetLocations, cutoff72h);
        rawDiscovered.push(...ghJobs);
        console.log(`[CareerPortalATS] Greenhouse API returned ${ghJobs.length} fresh matching jobs.`);
    }
    catch (e) {
        console.warn(`[CareerPortalATS] Greenhouse API fetch failed: ${e.message}`);
    }
    // B. Lever Public API
    try {
        const leverJobs = await fetchLeverJobs(targetRoleKeywords, targetLocations, cutoff72h);
        rawDiscovered.push(...leverJobs);
        console.log(`[CareerPortalATS] Lever API returned ${leverJobs.length} fresh matching jobs.`);
    }
    catch (e) {
        console.warn(`[CareerPortalATS] Lever API fetch failed: ${e.message}`);
    }
    // C. Ashby Public API
    try {
        const ashbyJobs = await fetchAshbyJobs(targetRoleKeywords, targetLocations, cutoff72h);
        rawDiscovered.push(...ashbyJobs);
    }
    catch (e) {
        console.warn(`[CareerPortalATS] Ashby API fetch failed: ${e.message}`);
    }
    // D. Tavily Search (days: 3)
    if (tavilyKey) {
        try {
            const tavilyResults = await fetchTavilyCareerPortals(tavilyKey, targetRoles, targetLocations, maxExpYears);
            console.log(`[CareerPortalATS] Tavily returned ${tavilyResults.length} ATS links.`);
            for (const r of tavilyResults) {
                let portalType = "other";
                if (r.url.includes("greenhouse.io"))
                    portalType = "greenhouse";
                else if (r.url.includes("lever.co"))
                    portalType = "lever";
                else if (r.url.includes("ashbyhq.com"))
                    portalType = "ashby";
                else if (r.url.includes("myworkdayjobs.com"))
                    portalType = "workday";
                // Extract company name from domain or title
                let compName = "Tech Company";
                const match = r.url.match(/(?:boards\.greenhouse\.io|jobs\.lever\.co|jobs\.ashbyhq\.com)\/([^/?#]+)/i);
                if (match && match[1]) {
                    compName = match[1].charAt(0).toUpperCase() + match[1].slice(1);
                }
                else if (r.title.includes(" - ")) {
                    compName = ((_d = r.title.split(" - ").pop()) === null || _d === void 0 ? void 0 : _d.trim()) || compName;
                }
                rawDiscovered.push({
                    title: r.title.replace(/\|.*$/, "").replace(/-.*$/, "").trim() || "Software Engineer",
                    company: compName,
                    url: r.url,
                    location: "Remote / India",
                    postedAt: new Date().toISOString(),
                    jd: (r.content || "").slice(0, 2500),
                    portalType
                });
            }
        }
        catch (e) {
            console.warn(`[CareerPortalATS] Tavily search error: ${e.message}`);
        }
    }
    // 5. Smart Pre-filtering: Filter out senior/staff roles (if early career) & completely unrelated roles
    const seniorKeywords = ["senior", "sr.", "sr ", "staff", "principal", "lead", "director", "vp", "head of", "manager", "architect"];
    const unrelatedRoleKeywords = ["product manager", "project manager", "scrum master", "data scientist", "machine learning", "sales", "accountant", "marketing", "recruiter", "hr "];
    const eligibleCandidates = rawDiscovered.filter(job => {
        const titleLower = (job.title || "").toLowerCase();
        // If candidate is early-career (maxExpYears <= 3), exclude senior/staff titles
        if (maxExpYears <= 3) {
            if (seniorKeywords.some(kw => titleLower.includes(kw))) {
                console.log(`[CareerPortalATS] Pre-filtered out senior title for candidate (${maxExpYears}y max): "${job.title}" @ ${job.company}`);
                return false;
            }
        }
        // Exclude unrelated disciplines
        if (unrelatedRoleKeywords.some(u => titleLower.includes(u))) {
            console.log(`[CareerPortalATS] Pre-filtered out unrelated discipline: "${job.title}" @ ${job.company}`);
            return false;
        }
        // Ensure title has relevance to candidate target roles or engineering
        const hasRelevance = targetRoleKeywords.some(kw => titleLower.includes(kw)) ||
            titleLower.includes("engineer") ||
            titleLower.includes("developer");
        if (!hasRelevance) {
            console.log(`[CareerPortalATS] Pre-filtered out irrelevant title: "${job.title}" @ ${job.company}`);
            return false;
        }
        return true;
    });
    // 6. Deduplicate by URL
    const seenUrls = new Set();
    const uniqueCandidates = eligibleCandidates.filter(job => {
        if (!job.url || seenUrls.has(job.url))
            return false;
        seenUrls.add(job.url);
        return true;
    });
    console.log(`[CareerPortalATS] Total unique candidates discovered: ${uniqueCandidates.length}. Verifying URLs (no 404s)...`);
    // 7. Strict URL Validation: Filter out broken links, 404s, or error redirects
    const validatedJobs = [];
    for (const cand of uniqueCandidates) {
        const isValid = await verifyJobUrl(cand.url);
        if (isValid) {
            validatedJobs.push(cand);
        }
        else {
            console.log(`[CareerPortalATS] Discarded broken / 404 job link: ${cand.url}`);
        }
        if (validatedJobs.length >= 6)
            break; // Select top 6 high-quality fresh jobs
    }
    if (validatedJobs.length === 0) {
        const msg = `No fresh jobs (<72h) found on career portals matching roles and ${minExpYears}-${maxExpYears} yrs experience right now.`;
        await (0, featureLogger_1.logFeatureExecution)(uid, {
            feature: "career_portals",
            featureTitle: "Career Portals (ATS Matcher)",
            status: "no_results",
            count: 0,
            message: msg
        });
        return { success: true, discoveredCount: 0, jobs: [], message: msg };
    }
    console.log(`[CareerPortalATS] ${validatedJobs.length} verified jobs passed 72h check & 404 verification. Tailoring with Gemini...`);
    // 7. Gemini ATS Matcher & Resume Tailoring (Process up to 4 top matched jobs per run)
    const finalizedRecords = [];
    const jobsToTailor = validatedJobs.slice(0, 4);
    for (const job of jobsToTailor) {
        // Pre-filter: strict experience gate
        const expCheck = (0, experienceMatcher_1.isExperienceExceeded)(`${job.title} ${job.jd}`, maxExpYears, minExpYears);
        if (expCheck.exceeded) {
            console.log(`[CareerPortalATS] Pre-filter skipped job '${job.title}' at '${job.company}': ${expCheck.reason}`);
            continue;
        }
        try {
            const prompt = `You are a Principal Technical Recruiter and ATS Optimization Expert.
Analyze the candidate's attached resume PDF and the following fresh job opening from an official company career portal.

CANDIDATE TARGET PROFILE:
- Target Roles: ${targetRoles.join(', ')}
- Target Experience Level: ${minExpYears} - ${maxExpYears} years ${isFresher ? '(Fresher / Recent Graduate)' : ''}

JOB OPENING:
- Company: ${job.company}
- Title: ${job.title}
- Location: ${job.location}
- Portal URL: ${job.url}
- Job Description:
${job.jd}

CRITICAL SCREENING & ATS EVALUATION RULES:
1. Strict Experience & Seniority Gate:
   - Check the Job Description for required years of experience or seniority tier.
   - If the JD requires more than ${Math.max(maxExpYears + 1, 3)} years of experience (e.g. 4+ years, 5+ years, 7+ years, 10+ years), or requires senior/staff/principal/managerial leadership, set "isQualified": false and "atsScore": 40.
   - If the job discipline does not fit the candidate's target roles (e.g. Product Management, AI/ML Research, Non-technical), set "isQualified": false and "atsScore": 40.
2. Rigorous ATS Match Scoring:
   - Compare the candidate's real skills & experience from the resume against this JD.
   - Assign an ATS Match Score (0 - 100).
   - ONLY assign an atsScore >= 80 if the candidate is a strong, genuine match for this role at their experience level.
   - If "isQualified" is false, atsScore MUST be strictly below 80.
3. Resume Tailoring (ONLY performed if candidate is qualified and atsScore >= 80):
   - Extract the candidate's real personal details (fullName, contactLine with location, phone, email, LinkedIn, GitHub).
   - Write a compelling, tailored 2-3 sentence Professional Summary matching ${job.company}'s requirements, strictly based on candidate's real domain and experience.
   - Categorize Technical Skills into high-impact ATS groupings relevant to the candidate's actual domain and resume (e.g. Languages & Frameworks, Databases & Tools, Architecture & Practices).
   - Tailor the Professional Experience entries: KEEP all original companies, job titles, and employment periods from the candidate's resume, and refine the achievement bullet points to highlight skills matching the JD that the candidate ACTUALLY possesses.
   - CRITICAL ANTI-HALLUCINATION RULE: DO NOT inject, assume, or invent skills, tools, or platforms that the candidate does not have in their attached resume. If the candidate is a .NET Developer, do not inject Cloud/DevOps tools like Terraform, AWS, Docker, or Kubernetes unless they are explicitly present in their resume.
   - Tailor Key Projects highlighting real-world deliverables from their background.
   - Preserve Education & Certifications from the original resume.
   - Note: Do not invent fake employers or fake degrees.

OUTPUT STRICT JSON FORMAT:
{
  "isQualified": true,
  "disqualificationReason": "",
  "atsScore": 88,
  "experienceRequired": "${minExpYears}-${maxExpYears} years",
  "matchReasoning": "Strong match on required candidate technical stack at target experience level...",
  "matchedSkills": ["Skill 1", "Skill 2"],
  "injectedKeywords": ["Relevant Tool from Resume"],
  "tailoredSummary": "Results-driven Developer with...",
  "tailoredResume": {
    "fullName": "Candidate Name",
    "contactLine": "City, Country | +91 ... | email@... | linkedin.com/in/... | github.com/...",
    "professionalSummary": "...",
    "skills": [
      { "category": "Languages & Frameworks", "items": "Relevant candidate languages & frameworks" },
      { "category": "Databases & Tools", "items": "Relevant candidate tools & databases" }
    ],
    "experience": [
      {
        "company": "Company Name",
        "role": "Job Title",
        "period": "2023 - Present",
        "location": "City, Country",
        "bulletPoints": [
          "Developed core features...",
          "Optimized system performance..."
        ]
      }
    ],
    "projects": [
      {
        "title": "Project Title",
        "techStack": "Candidate actual tech stack",
        "bulletPoints": [
          "Implemented..."
        ]
      }
    ],
    "education": [
      {
        "degree": "Degree Name",
        "institution": "University / College",
        "period": "2019 - 2023",
        "location": "India"
      }
    ],
    "certifications": [
      "Candidate Certifications (if present in resume)"
    ]
  }
}`;
            const geminiPayload = {
                contents: [
                    {
                        role: "user",
                        parts: [
                            { text: prompt },
                            {
                                inlineData: {
                                    mimeType: "application/pdf",
                                    data: cleanResumeB64
                                }
                            }
                        ]
                    }
                ],
                generationConfig: {
                    temperature: 0.2,
                    responseMimeType: "application/json"
                }
            };
            const geminiResp = await (0, geminiHelper_1.callGeminiAPI)(geminiPayload, { apiKey: geminiKey, timeout: 90000 });
            const parsed = JSON.parse(geminiResp.text || "{}");
            const atsScore = typeof parsed.atsScore === "number" ? parsed.atsScore : 0;
            const isQualified = parsed.isQualified !== false;
            // USER REQUIREMENT: Only create resume and save if ATS Score >= 80% and matches experience
            if (atsScore < 80 || !isQualified) {
                console.log(`[CareerPortalATS] Discarding ${job.title} @ ${job.company}: ATS Score ${atsScore}% (< 80%) or not qualified (${parsed.disqualificationReason || 'Score below 80%'}). No resume created.`);
                continue;
            }
            const matchedSkills = Array.isArray(parsed.matchedSkills) ? parsed.matchedSkills : [];
            const injectedKeywords = Array.isArray(parsed.injectedKeywords) ? parsed.injectedKeywords : [];
            const matchReasoning = parsed.matchReasoning || "Tailored for ATS optimization.";
            const tailoredSummary = parsed.tailoredSummary || "";
            const tailoredResumeData = parsed.tailoredResume || {
                fullName: "Candidate",
                contactLine: "India | Phone | Email",
                professionalSummary: tailoredSummary
            };
            // 8. Generate Clean ATS Resume PDF using PDFKit
            let pdfBase64 = "";
            let storageUrl = "";
            try {
                const pdfBuffer = await (0, pdfResumeGenerator_1.generateAtsResumePdf)(tailoredResumeData);
                pdfBase64 = pdfBuffer.toString("base64");
                // Optional: Save to Firebase Storage if bucket is configured
                try {
                    const bucket = firebase_1.admin.storage().bucket();
                    const jobIdClean = Buffer.from(job.url).toString("base64url").slice(0, 32);
                    const file = bucket.file(`users/${uid}/tailored_resumes/${jobIdClean}.pdf`);
                    await file.save(pdfBuffer, {
                        metadata: { contentType: "application/pdf" }
                    });
                    const [signedUrl] = await file.getSignedUrl({
                        action: "read",
                        expires: Date.now() + (365 * 24 * 60 * 60 * 1000)
                    });
                    storageUrl = signedUrl;
                }
                catch (stErr) {
                    console.log(`[CareerPortalATS] Storage upload note: ${stErr.message}. Base64 is stored directly in document.`);
                }
            }
            catch (pdfErr) {
                console.warn(`[CareerPortalATS] PDF generation failed for ${job.title}: ${pdfErr.message}`);
            }
            const recordId = Buffer.from(job.url).toString("base64url").slice(0, 32);
            const record = {
                id: recordId,
                jobTitle: job.title,
                companyName: job.company,
                portalType: job.portalType,
                portalUrl: job.url,
                location: job.location,
                workplaceType: job.location.toLowerCase().includes("remote") ? "remote" : "hybrid",
                experienceRequired: parsed.experienceRequired || `${minExpYears}-${maxExpYears} years`,
                postedAt: job.postedAt,
                discoveredAt: firebase_1.admin.firestore.Timestamp.now(),
                atsScore,
                matchedSkills,
                injectedKeywords,
                matchReasoning,
                jobDescriptionSnippet: job.jd.slice(0, 400),
                tailoredResumePdfBase64: pdfBase64 ? `data:application/pdf;base64,${pdfBase64}` : null,
                tailoredResumePdfUrl: storageUrl || null,
                tailoredSummary,
                status: "discovered"
            };
            // Save to Firestore
            await firebase_1.db.collection("users").doc(uid).collection("career_portal_jobs").doc(recordId).set(record, { merge: true });
            finalizedRecords.push(record);
            console.log(`[CareerPortalATS] Successfully tailored & saved: ${record.jobTitle} @ ${record.companyName} (ATS Score: ${record.atsScore}%)`);
        }
        catch (itemErr) {
            console.warn(`[CareerPortalATS] Error tailoring job for ${job.company}: ${itemErr.message}`);
        }
    }
    // Log feature execution summary
    await (0, featureLogger_1.logFeatureExecution)(uid, {
        feature: "career_portals",
        featureTitle: "Career Portals (ATS Matcher)",
        status: finalizedRecords.length > 0 ? "success" : "no_results",
        count: finalizedRecords.length,
        message: finalizedRecords.length > 0
            ? `Discovered and tailored ${finalizedRecords.length} fresh ATS career portal openings (>=80% match, <72h).`
            : `No portal openings met the strict >=80% ATS match and experience criteria (<72h).`
    });
    return {
        success: true,
        discoveredCount: finalizedRecords.length,
        jobs: finalizedRecords,
        message: finalizedRecords.length > 0
            ? `Discovered and tailored ${finalizedRecords.length} high-match (>=80%) career portal jobs (<72h).`
            : `No portal openings met the strict >=80% ATS match and experience criteria for ${minExpYears}-${maxExpYears} yrs.`
    };
}
/**
 * Callable Cloud Function: triggerCareerPortalDiscovery
 */
exports.triggerCareerPortalDiscovery = functions
    .runWith({ timeoutSeconds: 300, memory: "1GB" })
    .https.onCall(async (data, context) => {
    var _a, _b;
    const uid = (_a = context.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid) {
        throw new functions.https.HttpsError("unauthenticated", "Authentication required.");
    }
    const forceRefresh = (_b = data === null || data === void 0 ? void 0 : data.forceRefresh) !== null && _b !== void 0 ? _b : false;
    const customRole = data === null || data === void 0 ? void 0 : data.customRole;
    // Attempt asynchronous dispatch via Cloud Tasks if available
    const taskName = await (0, cloudTasksHelper_1.enqueueUserCloudTask)("career-portals-queue", "processCareerPortalDiscoveryTask", {
        uid,
        forceRefresh,
        customRole
    });
    if (taskName) {
        return {
            status: "queued",
            message: "Career portal discovery started in the background. Fresh tailored resumes will appear shortly."
        };
    }
    // Direct synchronous execution fallback
    const result = await executeCareerPortalDiscovery(uid, { forceRefresh, customRole });
    return result;
});
/**
 * Cloud Task HTTP Handler: processCareerPortalDiscoveryTask
 */
exports.processCareerPortalDiscoveryTask = functions
    .runWith({ timeoutSeconds: 300, memory: "1GB" })
    .https.onRequest(async (req, res) => {
    var _a;
    try {
        const bodyData = ((_a = req.body) === null || _a === void 0 ? void 0 : _a.data) || req.body || {};
        const uid = bodyData.uid;
        if (!uid) {
            res.status(400).send("Missing uid in task payload.");
            return;
        }
        console.log(`[CareerPortalATS] Executing Cloud Task for user ${uid}...`);
        const result = await executeCareerPortalDiscovery(uid, {
            forceRefresh: bodyData.forceRefresh,
            customRole: bodyData.customRole
        });
        res.status(200).json(result);
    }
    catch (err) {
        console.error(`[CareerPortalATS] Cloud Task execution error:`, err);
        res.status(500).send(err.message);
    }
});
/**
 * Scheduled dispatcher for Career Portals discovery.
 * Called twice daily (09:30 AM & 06:30 PM IST).
 */
async function internalCareerPortalDiscoveryDispatcher() {
    var _a;
    console.log("[CareerPortalATS] Starting scheduled Career Portal discovery dispatcher (09:30 AM & 06:30 PM IST)...");
    try {
        const usersSnap = await firebase_1.db.collection("users").get();
        let dispatchedCount = 0;
        for (const userDoc of usersSnap.docs) {
            const uid = userDoc.id;
            const userData = userDoc.data() || {};
            const enabledModules = userData.enabledModules || [];
            const jobSubPerms = userData.jobAssistantSubPermissions || {};
            const isParentEnabled = enabledModules.includes("job_assistant") ||
                enabledModules.includes("career_portals") ||
                enabledModules.includes("auto_apply");
            if (!isParentEnabled || jobSubPerms.career_portals === false) {
                continue;
            }
            // User preference toggle: Skip if disabled by the user
            if (((_a = userData.careerPortalsSettings) === null || _a === void 0 ? void 0 : _a.enabled) === false) {
                console.log(`[CareerPortalATS] User ${uid} disabled career portals in settings. Skipping scheduled run.`);
                continue;
            }
            // Must have Gemini API key configured
            const userApiKeys = userData.userApiKeys || {};
            const geminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();
            if (!geminiKey) {
                continue;
            }
            dispatchedCount++;
            console.log(`[CareerPortalATS] Dispatching scheduled Career Portal discovery for user ${uid}...`);
            const taskName = await (0, cloudTasksHelper_1.enqueueUserCloudTask)("career-portals-queue", "processCareerPortalDiscoveryTask", {
                uid,
                forceRefresh: false
            });
            if (!taskName) {
                executeCareerPortalDiscovery(uid, { forceRefresh: false }).catch(err => {
                    console.error(`[CareerPortalATS] Background execution error for user ${uid}:`, err);
                });
            }
        }
        console.log(`[CareerPortalATS] Dispatcher finished. Queued for ${dispatchedCount} user(s).`);
    }
    catch (e) {
        console.error("[CareerPortalATS] Error in scheduled career portal dispatcher:", e);
    }
}
//# sourceMappingURL=careerPortalATS.js.map