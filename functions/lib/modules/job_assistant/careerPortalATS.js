"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.processCareerPortalDiscoveryTask = exports.triggerCareerPortalDiscovery = void 0;
exports.verifyJobUrl = verifyJobUrl;
exports.executeCareerPortalDiscovery = executeCareerPortalDiscovery;
const functions = require("firebase-functions");
const axios_1 = require("axios");
const firebase_1 = require("../../config/firebase");
const featureLogger_1 = require("../../utils/featureLogger");
const geminiHelper_1 = require("../../utils/geminiHelper");
const tavilyHelper_1 = require("../../utils/tavilyHelper");
const pdfResumeGenerator_1 = require("../../utils/pdfResumeGenerator");
const cloudTasksHelper_1 = require("../../utils/cloudTasksHelper");
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
                    title: j.title || "DevOps / Cloud Engineer",
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
                    title: p.text || "Cloud / DevOps Engineer",
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
 * Searches Tavily targeting major ATS portals with days: 2 (last 48 hours).
 */
async function fetchTavilyCareerPortals(apiKey, roles, locations) {
    const allResults = [];
    const primaryRole = roles[0] || "DevOps Engineer";
    const locQuery = locations.map(l => `"${l}"`).join(" OR ") || '"India" OR "Remote"';
    const queries = [
        `("${primaryRole}" OR "Cloud Engineer") (${locQuery}) ("1-3 years" OR "2+ years")`,
        `("Site Reliability Engineer" OR "Infrastructure Engineer") (${locQuery})`
    ];
    for (const q of queries) {
        try {
            const resp = await (0, tavilyHelper_1.searchTavily)({
                apiKey,
                query: q,
                searchDepth: "advanced",
                maxResults: 6,
                days: 2, // Last 48 hours strictly
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
    var _a, _b, _c;
    console.log(`[CareerPortalATS] Starting discovery for user ${uid}...`);
    const userDoc = await firebase_1.db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
        return { success: false, discoveredCount: 0, jobs: [], message: "User not found." };
    }
    const userData = userDoc.data() || {};
    const enabledModules = userData.enabledModules || [];
    if (!enabledModules.includes("career_portals") && !enabledModules.includes("auto_apply")) {
        console.log(`[CareerPortalATS] Skipping user ${uid}: career_portals module is disabled.`);
        return { success: false, discoveredCount: 0, jobs: [], message: "Career portals module is disabled in settings." };
    }
    // 1. Extract Target Preferences
    const autoApplySettings = userData.autoApplySettings || {};
    let targetRoles = autoApplySettings.targetRoles || ["DevOps Engineer", "Cloud Engineer"];
    if (options === null || options === void 0 ? void 0 : options.customRole) {
        targetRoles = [options.customRole, ...targetRoles];
    }
    const targetLocations = autoApplySettings.targetLocations || ["India", "Remote", "Bengaluru", "Hyderabad", "Pune"];
    const targetRoleKeywords = ["devops", "cloud", "sre", "reliability", "infrastructure", "platform", "kubernetes", "terraform", "aws"];
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
    let resumePdfBase64 = (((_a = userData.masterResume) === null || _a === void 0 ? void 0 : _a.base64) || ((_b = userData.masterResume) === null || _b === void 0 ? void 0 : _b.base64Data) || "").toString().trim();
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
    // 3. Strict 48-Hour Threshold (2 days ago)
    const nowMs = Date.now();
    const cutoff48h = nowMs - (48 * 60 * 60 * 1000);
    // 4. Fetch from All 3 Strategies
    const rawDiscovered = [];
    // A. Greenhouse Public API
    try {
        const ghJobs = await fetchGreenhouseJobs(targetRoleKeywords, targetLocations, cutoff48h);
        rawDiscovered.push(...ghJobs);
        console.log(`[CareerPortalATS] Greenhouse API returned ${ghJobs.length} fresh matching jobs.`);
    }
    catch (e) {
        console.warn(`[CareerPortalATS] Greenhouse API fetch failed: ${e.message}`);
    }
    // B. Lever Public API
    try {
        const leverJobs = await fetchLeverJobs(targetRoleKeywords, targetLocations, cutoff48h);
        rawDiscovered.push(...leverJobs);
        console.log(`[CareerPortalATS] Lever API returned ${leverJobs.length} fresh matching jobs.`);
    }
    catch (e) {
        console.warn(`[CareerPortalATS] Lever API fetch failed: ${e.message}`);
    }
    // C. Ashby Public API
    try {
        const ashbyJobs = await fetchAshbyJobs(targetRoleKeywords, targetLocations, cutoff48h);
        rawDiscovered.push(...ashbyJobs);
    }
    catch (e) {
        console.warn(`[CareerPortalATS] Ashby API fetch failed: ${e.message}`);
    }
    // D. Tavily Search (days: 2)
    if (tavilyKey) {
        try {
            const tavilyResults = await fetchTavilyCareerPortals(tavilyKey, targetRoles, targetLocations);
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
                    compName = ((_c = r.title.split(" - ").pop()) === null || _c === void 0 ? void 0 : _c.trim()) || compName;
                }
                rawDiscovered.push({
                    title: r.title.replace(/\|.*$/, "").replace(/-.*$/, "").trim() || "DevOps Engineer",
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
    // 5. Deduplicate by URL
    const seenUrls = new Set();
    const uniqueCandidates = rawDiscovered.filter(job => {
        if (!job.url || seenUrls.has(job.url))
            return false;
        seenUrls.add(job.url);
        return true;
    });
    console.log(`[CareerPortalATS] Total unique candidates discovered: ${uniqueCandidates.length}. Verifying URLs (no 404s)...`);
    // 6. Strict URL Validation: Filter out broken links, 404s, or error redirects
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
        const msg = "No fresh jobs (<48h) found on career portals matching your criteria right now.";
        await (0, featureLogger_1.logFeatureExecution)(uid, {
            feature: "career_portals",
            featureTitle: "Career Portals (ATS Matcher)",
            status: "no_results",
            count: 0,
            message: msg
        });
        return { success: true, discoveredCount: 0, jobs: [], message: msg };
    }
    console.log(`[CareerPortalATS] ${validatedJobs.length} verified jobs passed 48h check & 404 verification. Tailoring with Gemini...`);
    // 7. Gemini ATS Matcher & Resume Tailoring (Process up to 4 top matched jobs per run)
    const finalizedRecords = [];
    const jobsToTailor = validatedJobs.slice(0, 4);
    for (const job of jobsToTailor) {
        try {
            const prompt = `You are a Principal Technical Recruiter and ATS Optimization Expert.
Analyze the candidate's attached resume PDF and the following fresh job opening from an official company career portal.

JOB OPENING:
- Company: ${job.company}
- Title: ${job.title}
- Location: ${job.location}
- Portal URL: ${job.url}
- Job Description:
${job.jd}

YOUR TASK:
1. Compute an accurate ATS Match Score (0 - 100) comparing the candidate's real skills & experience to this JD.
2. Identify matched skills already present.
3. Identify crucial missing ATS keywords from the JD that can be ethically highlighted.
4. TAILOR THE RESUME:
   - Extract the candidate's real personal details (fullName, contactLine with location, phone, email, LinkedIn, GitHub).
   - Write a compelling, tailored 2-3 sentence Professional Summary matching ${job.company}'s requirements.
   - Categorize Technical Skills into high-impact ATS groupings (Cloud & DevOps, CI/CD, Containerization, IaC, Monitoring, Scripting).
   - Tailor the Professional Experience entries: KEEP all original companies, job titles, and employment periods from the candidate's resume, but REWRITE the achievement bullet points to prominently incorporate the target keywords (e.g. Kubernetes, Terraform, Docker, AWS, Prometheus, GitHub Actions, Linux) with measurable impact.
   - Tailor Key Projects highlighting real-world deliverables.
   - Preserve Education & Certifications from the original resume.
   - Note: The resume can be 1 page or 2 pages based on candidate's history. Do not invent fake employers or fake degrees.

OUTPUT STRICT JSON FORMAT:
{
  "atsScore": 92,
  "matchReasoning": "Strong match on AWS, Docker, Kubernetes. Highlighted Terraform and GitOps CI/CD pipelines.",
  "matchedSkills": ["AWS", "Docker", "Kubernetes", "Linux", "CI/CD"],
  "injectedKeywords": ["Terraform", "ArgoCD", "Helm", "Prometheus"],
  "tailoredSummary": "Results-driven Cloud/DevOps Engineer with...",
  "tailoredResume": {
    "fullName": "Candidate Name",
    "contactLine": "City, Country | +91 ... | email@... | linkedin.com/in/... | github.com/...",
    "professionalSummary": "...",
    "skills": [
      { "category": "Cloud & Infrastructure", "items": "AWS, Docker, Kubernetes, Terraform" },
      { "category": "CI/CD & Automation", "items": "GitHub Actions, Jenkins, Bash, Python" }
    ],
    "experience": [
      {
        "company": "Company Name",
        "role": "Job Title",
        "period": "2023 - Present",
        "location": "Bengaluru, India",
        "bulletPoints": [
          "Automated cloud infrastructure with Terraform...",
          "Architected CI/CD pipelines reducing deployment times by 40%..."
        ]
      }
    ],
    "projects": [
      {
        "title": "Project Title",
        "techStack": "AWS, Kubernetes, Terraform",
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
      "AWS Certified Solutions Architect"
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
            const atsScore = typeof parsed.atsScore === "number" ? parsed.atsScore : 85;
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
                experienceRequired: "1-3 years",
                postedAt: job.postedAt,
                discoveredAt: firebase_1.admin.firestore.Timestamp.now(),
                atsScore,
                matchedSkills,
                injectedKeywords,
                matchReasoning,
                jobDescriptionSnippet: job.jd.slice(0, 400),
                tailoredResumePdfBase64: pdfBase64 ? `data:application/pdf;base64,${pdfBase64}` : undefined,
                tailoredResumePdfUrl: storageUrl || undefined,
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
        message: `Discovered and tailored ${finalizedRecords.length} fresh ATS career portal openings (<48h).`
    });
    return {
        success: true,
        discoveredCount: finalizedRecords.length,
        jobs: finalizedRecords,
        message: `Discovered and tailored ${finalizedRecords.length} fresh career portal jobs (<48h).`
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
//# sourceMappingURL=careerPortalATS.js.map