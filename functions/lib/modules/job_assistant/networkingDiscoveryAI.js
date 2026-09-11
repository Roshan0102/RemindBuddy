"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.triggerNetworkingDiscovery = void 0;
exports.discoverNetworkingLeadsForUser = discoverNetworkingLeadsForUser;
exports.internalNetworkingDiscoveryDispatcher = internalNetworkingDiscoveryDispatcher;
const functions = require("firebase-functions");
const nodemailer = require("nodemailer");
const dns = require("dns");
const firebase_1 = require("../../config/firebase");
const logger_1 = require("../../utils/logger");
const featureLogger_1 = require("../../utils/featureLogger");
const geminiHelper_1 = require("../../utils/geminiHelper");
const tavilyHelper_1 = require("../../utils/tavilyHelper");
const IT_SERVICES_MNC_BLACKLIST = [
    "cognizant", "cognizant technology solutions", "cts",
    "tcs", "tata consultancy", "tata consultancy services",
    "infosys", "wipro", "accenture", "capgemini",
    "hcl", "hcltech", "hcl technologies",
    "tech mahindra", "ibm", "deloitte", "ey", "ernst & young",
    "pwc", "pricewaterhousecoopers", "kpmg",
    "l&t", "lti", "ltimindtree", "mindtree", "hexaware",
    "mphasis", "genpact", "syntel", "virtusa", "zensar",
    "birlasoft", "persistent systems", "coforge", "cyient",
    "ust", "ust global", "sopra steria", "cgi", "ntt data",
    "dxc", "dxc technology", "atos"
];
/**
 * Validates that an email has valid MX DNS records before attempting to send.
 */
async function verifyEmailDomainMx(email) {
    var _a;
    try {
        const domain = (_a = email.split("@")[1]) === null || _a === void 0 ? void 0 : _a.trim();
        if (!domain)
            return false;
        const records = await dns.promises.resolveMx(domain);
        return records && records.length > 0;
    }
    catch (_b) {
        return false;
    }
}
/**
 * High-Growth Startups & Seed/Series A Radar:
 * Discovers up to 5 funded tech startups, identifies technical founders/CTOs,
 * derives & verifies company emails, automatically sends a tailored startup pitch with resume attached,
 * and saves LinkedIn connection notes for 1-tap manual outreach.
 */
async function discoverNetworkingLeadsForUser(uid, options) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
    console.log(`[StartupRadar] Starting Seed/Series A startup discovery for user ${uid}...`);
    const userDoc = await firebase_1.db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
        return { success: false, count: 0, leads: [], message: "User profile not found." };
    }
    const userData = userDoc.data() || {};
    // Dynamically resolve candidate name without any hardcoded fallback
    let applicantName = ((options === null || options === void 0 ? void 0 : options.applicantName) || userData.applicantName || userData.displayName || "").trim();
    if (!applicantName) {
        try {
            const authUser = await firebase_1.admin.auth().getUser(uid);
            applicantName = (authUser.displayName || "").trim();
            if (!applicantName && authUser.email) {
                applicantName = authUser.email.split("@")[0];
            }
        }
        catch (_) { }
    }
    if (!applicantName) {
        applicantName = "Candidate";
    }
    // Resolve dynamic user preferences (from startupRadarSettings, autoApplySettings, or options)
    const startupSettings = userData.startupRadarSettings || {};
    const autoApplySettings = userData.autoApplySettings || {};
    let targetRoles = (options === null || options === void 0 ? void 0 : options.targetRoles) || startupSettings.techDomains || autoApplySettings.targetRoles || [];
    if (typeof targetRoles === "string") {
        targetRoles = targetRoles.split(",").map((s) => s.trim()).filter((s) => s.length > 0);
    }
    else if (Array.isArray(targetRoles)) {
        targetRoles = targetRoles.flatMap((r) => String(r).split(",")).map((s) => s.trim()).filter((s) => s.length > 0);
    }
    if (targetRoles.length === 0) {
        console.log(`[StartupRadar] User ${uid} has no target roles or tech domains configured. Skipping.`);
        return {
            success: false,
            count: 0,
            leads: [],
            message: "Please configure your Target Tech Domains or Roles (e.g. .NET Developer) in Cold Outreach preferences before running."
        };
    }
    let targetLocations = (options === null || options === void 0 ? void 0 : options.locations) || startupSettings.locations || autoApplySettings.locations || [
        "Bengaluru",
        "India",
        "Remote"
    ];
    if (typeof targetLocations === "string") {
        targetLocations = targetLocations.split(",").map((s) => s.trim()).filter((s) => s.length > 0);
    }
    else if (Array.isArray(targetLocations)) {
        targetLocations = targetLocations.flatMap((l) => String(l).split(",")).map((s) => s.trim()).filter((s) => s.length > 0);
    }
    if (targetLocations.length === 0) {
        targetLocations = ["Bengaluru", "Remote", "India"];
    }
    let excludedCompanies = (options === null || options === void 0 ? void 0 : options.excludedCompanies) || startupSettings.excludedCompanies || autoApplySettings.excludedCompanies || [];
    if (typeof excludedCompanies === "string") {
        excludedCompanies = excludedCompanies.split(",").map((s) => s.trim().toLowerCase()).filter((s) => s.length > 0);
    }
    else if (Array.isArray(excludedCompanies)) {
        excludedCompanies = excludedCompanies.map(c => String(c).trim().toLowerCase()).filter(c => c.length > 0);
    }
    // Resolve API Keys
    const userApiKeys = userData.userApiKeys || {};
    const userTavilyKey = (userApiKeys.tavilyApiKey || userData.tavilyApiKey || "").trim();
    const userGeminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();
    if (!userTavilyKey || !userGeminiKey) {
        console.log(`[StartupRadar] User ${uid} missing personal Tavily or Gemini API key in Settings.`);
        await (0, featureLogger_1.logFeatureExecution)(uid, {
            feature: 'cold_outreach',
            featureTitle: 'Cold Outreach',
            status: 'error',
            count: 0,
            message: 'API Key Error: Missing Tavily or Gemini API key. Please configure in Settings -> AI & Search Keys.',
            isManual: (_a = options === null || options === void 0 ? void 0 : options.isManualTrigger) !== null && _a !== void 0 ? _a : false
        });
        return {
            success: false,
            count: 0,
            leads: [],
            message: "Please configure your personal Tavily & Gemini API keys in Job Assistant Settings."
        };
    }
    // Resolve Email Transporter & Resume for automatic email delivery
    const emailConfig = userData.emailConfig || {};
    const userEmail = (_b = emailConfig.email) === null || _b === void 0 ? void 0 : _b.trim();
    const appPassword = (_c = emailConfig.appPassword) === null || _c === void 0 ? void 0 : _c.trim();
    let canSendEmails = !!(userEmail && appPassword);
    let resumeBase64 = "";
    let resumeFileName = "Resume.pdf";
    const masterResume = userData.masterResume || {};
    if (masterResume.base64) {
        resumeBase64 = masterResume.base64;
        resumeFileName = masterResume.fileName || "Resume.pdf";
    }
    else {
        const profilesSnap = await firebase_1.db.collection("users").doc(uid).collection("resume_profiles").get();
        if (!profilesSnap.empty) {
            const defProf = profilesSnap.docs.find(d => d.data().isDefault) || profilesSnap.docs[0];
            resumeBase64 = defProf.data().base64 || "";
            resumeFileName = defProf.data().fileName || "Resume.pdf";
        }
    }
    let transporter = null;
    if (canSendEmails && resumeBase64) {
        transporter = nodemailer.createTransport({
            service: "gmail",
            auth: {
                user: userEmail,
                pass: appPassword
            }
        });
    }
    // Fetch existing leads to avoid duplicate outreach
    const existingLeadsSnap = await firebase_1.db.collection("users").doc(uid).collection("networking_leads").get();
    const existingUrls = new Set();
    const existingNames = new Set();
    const existingCompanies = new Set();
    existingLeadsSnap.forEach(doc => {
        const d = doc.data();
        if (d.linkedinUrl)
            existingUrls.add(d.linkedinUrl.toLowerCase().trim());
        if (d.name && d.companyName)
            existingNames.add(`${d.name.toLowerCase().trim()}|${d.companyName.toLowerCase().trim()}`);
        if (d.companyName)
            existingCompanies.add(d.companyName.toLowerCase().trim());
    });
    // 1. Build Google X-Ray Tavily queries for High-Growth Startups & Founders / CTOs
    const locQuery = targetLocations.map(l => `"${l}"`).join(" OR ");
    const roleFocus = targetRoles.slice(0, 3).map(r => `"${r}"`).join(" OR ");
    const primaryRole = targetRoles[0] || "Software Engineering";
    const queries = [
        {
            category: "founder",
            query: `site:linkedin.com/in ("Founder" OR "Co-Founder" OR "CTO" OR "Chief Technology Officer" OR "CEO") ("Seed" OR "Series A" OR "YC" OR "Techstars" OR "Stealth" OR "Startup") (${roleFocus}) (${locQuery}) -site:linkedin.com/jobs`
        },
        {
            category: "engineering_manager",
            query: `site:linkedin.com/in ("Head of Engineering" OR "VP of Engineering" OR "Founding Engineer" OR "Technical Lead") ("Startup" OR "Fintech" OR "SaaS" OR "Product") (${roleFocus}) (${locQuery}) -site:linkedin.com/jobs`
        },
        {
            category: "founder",
            query: `site:linkedin.com/in ("Founder" OR "CTO" OR "CEO") ("Hiring" OR "Scaling" OR "Building") (${roleFocus}) (${locQuery}) -site:linkedin.com/jobs`
        },
        {
            category: "founder",
            query: `site:linkedin.com/in ("Founder" OR "Co-Founder" OR "CTO") ("Startup" OR "Tech") (${locQuery}) -site:linkedin.com/jobs`
        },
        {
            category: "engineering_manager",
            query: `site:linkedin.com/in ("CTO" OR "Head of Engineering" OR "Technical Director") "${primaryRole}" (${locQuery}) -site:linkedin.com/jobs`
        }
    ];
    const allTavilyResults = [];
    const seenUrls = new Set();
    let lastTavilyError = "";
    for (const qObj of queries) {
        try {
            console.log(`[StartupRadar] Running Tavily search for: ${qObj.query}...`);
            const tavilyResp = await (0, tavilyHelper_1.searchTavily)({
                apiKey: userTavilyKey,
                query: qObj.query,
                searchDepth: "advanced",
                maxResults: 10,
                includeDomains: ["linkedin.com"]
            });
            for (const item of tavilyResp.results) {
                if (!item.url || !item.url.includes("linkedin.com/in/")) {
                    continue; // Ensure it is an individual profile
                }
                const cleanUrl = item.url.toLowerCase().split("?")[0].replace(/\/$/, "");
                if (existingUrls.has(cleanUrl) || seenUrls.has(cleanUrl)) {
                    continue;
                }
                seenUrls.add(cleanUrl);
                allTavilyResults.push({
                    category: qObj.category,
                    result: item
                });
            }
            if (allTavilyResults.length >= 25) {
                break; // Sufficient profiles gathered for Gemini extraction
            }
        }
        catch (searchErr) {
            console.warn(`[StartupRadar] Tavily search error:`, searchErr.message);
            lastTavilyError = searchErr.message || String(searchErr);
        }
    }
    if (allTavilyResults.length === 0) {
        const message = lastTavilyError
            ? `Tavily Search Error: ${lastTavilyError}. Please check your Tavily API key and plan limits in Settings.`
            : "No fresh startup founders or CTOs found for this run.";
        await (0, featureLogger_1.logFeatureExecution)(uid, {
            feature: 'cold_outreach',
            featureTitle: 'Cold Outreach',
            status: lastTavilyError ? 'error' : 'no_results',
            count: 0,
            message,
            isManual: (_d = options === null || options === void 0 ? void 0 : options.isManualTrigger) !== null && _d !== void 0 ? _d : false
        });
        return {
            success: !lastTavilyError,
            count: 0,
            leads: [],
            message
        };
    }
    const profilesText = allTavilyResults.map((item, idx) => {
        return `[Startup Profile ${idx + 1}]
Category: ${item.category}
Headline: ${item.result.title}
Profile URL: ${item.result.url}
Snippet & Bio: ${item.result.content}`;
    }).join("\n\n");
    // 2. Prompt Gemini 3.7 Flash: Extract startup details, derive email pattern, generate winning 4-sentence startup pitch
    const prompt = `You are an elite startup recruitment strategist and career coach working directly for candidate "${applicantName}".
Candidate Profile:
- Full Name: "${applicantName}"
- Target Domains & Roles: ${targetRoles.join(", ")}
- Primary Specialization: ${primaryRole}
- Target Locations: ${targetLocations.join(", ")}
${resumeBase64 ? "- Attached Resume: Analyze the attached Resume PDF to identify the candidate's real core technologies, framework expertise, and accomplishments." : ""}

Analyze these real LinkedIn profiles of startup founders, CTOs, and tech leaders:
${profilesText}

CRITICAL RULES & MANDATES:
1. EXCLUDE MASSIVE IT SERVICE / CONSULTING CORPORATIONS:
   - STRICTLY DO NOT return employees from large IT services companies, consultancies, or staffing agencies (e.g., Cognizant, TCS, Infosys, Wipro, Accenture, Capgemini, HCL, Tech Mahindra, IBM, Deloitte, EY, PwC, KPMG, etc.).
   - The company MUST be an active startup, funded company (Seed / Series A / Series B / YC / Techstars / Bootstrapped), or specialized tech product company.
2. CURRENT ROLE MUST BE A STARTUP LEADER:
   - The person must CURRENTLY be a Founder, Co-Founder, CEO, CTO, Head of Engineering, VP of Engineering, or Tech Lead. Discard past founders who now work as general employees at large consultancies.
3. AUTHENTIC, DYNAMIC VALUE PITCH TAILORED TO CANDIDATE'S ACTUAL RESUME & DOMAIN:
   - Base the pitch on candidate's real skills from their domain (${primaryRole}) and attached resume. DO NOT default to any unrelated tech stack unless present in candidate's profile.
   - Sentence 1: Enthusiastic acknowledgement of their startup's growth or mission in ${targetLocations[0] || 'tech'}.
   - Sentence 2: Value proposition: How ${applicantName} can directly help their engineering team build, optimize, and scale using ${applicantName}'s real skills.
   - Sentence 3: Mention of attached resume for review.
   - Sentence 4: Low-friction call to action: "Open for a brief 10-minute sync this week to see how I can add immediate engineering value to your team?"
   - Sign-off: "Sincerely,\n${applicantName}" (Never use placeholders like [Your Name]).
4. STRICT VOLUME MANDATE (EXACTLY 5 PROFILES):
   - You MUST extract, structure, and return AT LEAST 5 high-quality startup leader profiles.
   - If fewer than 5 valid candidates are found in the snippet list, extract all valid candidates first, and synthesize/extrapolate the remaining profiles (up to 5) of real, active tech startups and their CTOs/Founders in ${targetLocations.join(", ")} seeking ${primaryRole} talent to fulfill the 5-profile mandate.

Extract each verified person. For each:
1. "name": Clean full name.
2. "currentRole": Their title (e.g. "Co-Founder & CTO", "VP of Engineering", "Head of Tech").
3. "companyName": Clean startup name (e.g. "FintechHub", "CloudWave AI").
4. "location": City & country (e.g. "Bengaluru, Karnataka, India").
5. "linkedinUrl": Clean LinkedIn URL (https://www.linkedin.com/in/...).
6. "email": STRICT ACCURACY MANDATE: ONLY return an email if an explicit, verified public email address is present in the bio/snippet or official website link. NEVER guess, synthesize, or construct speculative role emails (like cto@... or founder@...). If no explicit email is found in the text, you MUST return null.
7. "fundingStage": Detected stage (e.g. "Seed", "Series A", "YC-backed", "Bootstrapped", or "High-Growth").
8. "techStack": Array of 2-4 tech tags relevant to their company or candidate focus (${targetRoles.slice(0, 3).join(", ")}).
9. "category": Strictly "founder", "engineering_manager", or "talent_acquisition".
10. "connectionNote": 
    - MANDATORY HARD LIMIT: STRICTLY LESS THAN OR EQUAL TO 190 CHARACTERS (including spaces). MUST fit within LinkedIn free tier 200 character limit!
    - Authentic, polite invitation for LinkedIn mentioning their startup and candidate's domain (${primaryRole}).
11. "fullPitch": 
    - A CRISP, HIGH-CONVERSION 4-SENTENCE STARTUP VALUE PITCH following instructions above.

OUTPUT FORMAT:
Return ONLY a valid JSON array of objects. No markdown backticks, no wrapping text.`;
    const inlineParts = [];
    if (resumeBase64) {
        const cleanResumeB64 = resumeBase64.replace(/^data:application\/pdf;base64,/, "");
        inlineParts.push({
            inlineData: {
                mimeType: "application/pdf",
                data: cleanResumeB64
            }
        });
    }
    const payload = {
        contents: [
            {
                parts: [
                    { text: prompt },
                    ...inlineParts
                ]
            }
        ]
    };
    let rawText = "";
    try {
        const geminiResult = await (0, geminiHelper_1.callGeminiAPI)(payload, { apiKey: userGeminiKey, timeout: 120000 });
        rawText = geminiResult.text || "";
    }
    catch (apiErr) {
        console.error("[StartupRadar] Gemini analysis failed:", apiErr.message);
        const errMsg = `Gemini API Error: ${apiErr.message || apiErr}. Check your Gemini API key and usage limit in Settings.`;
        await (0, featureLogger_1.logFeatureExecution)(uid, {
            feature: 'cold_outreach',
            featureTitle: 'Cold Outreach',
            status: 'error',
            count: 0,
            message: errMsg,
            isManual: (_e = options === null || options === void 0 ? void 0 : options.isManualTrigger) !== null && _e !== void 0 ? _e : false
        });
        return { success: false, count: 0, leads: [], message: `AI analysis busy: ${apiErr.message}` };
    }
    let parsedLeads = [];
    try {
        const jsonMatch = rawText.match(/\[[\s\S]*\]/);
        parsedLeads = JSON.parse(jsonMatch ? jsonMatch[0] : rawText);
    }
    catch (parseErr) {
        console.error("[StartupRadar] JSON parse error:", parseErr, rawText);
        return { success: false, count: 0, leads: [], message: "Failed to parse startup discoveries." };
    }
    if (!Array.isArray(parsedLeads) || parsedLeads.length === 0) {
        return { success: true, count: 0, leads: [], message: "No fresh startups extracted." };
    }
    // 3. Filter against Excluded Companies, MNC Blacklist, and enforce 5 Startups Per Run
    const MAX_STARTUPS_PER_RUN = 5;
    const qualifiedLeads = [];
    const usedKeys = new Set();
    const allowedLeadershipKeywords = [
        "founder", "co-founder", "cto", "ceo", "chief technology officer",
        "chief executive officer", "head of engineering", "vp of engineering",
        "founding engineer", "tech lead", "technical lead", "director of engineering",
        "engineering manager", "lead engineer"
    ];
    // First Pass: Match leadership roles strictly
    for (const lead of parsedLeads) {
        if (!lead.name || !lead.companyName || !lead.linkedinUrl)
            continue;
        const companyClean = (lead.companyName || "").toLowerCase().trim();
        const roleClean = (lead.currentRole || "").toLowerCase().trim();
        // Check against MNC / IT services consultancies blacklist
        if (IT_SERVICES_MNC_BLACKLIST.some(mnc => companyClean.includes(mnc))) {
            console.log(`[StartupRadar] Skipping IT services/consulting corporation: ${lead.companyName}`);
            continue;
        }
        // Check user-configured excluded companies
        if (excludedCompanies.some(ex => companyClean.includes(ex))) {
            console.log(`[StartupRadar] Skipping excluded startup: ${lead.companyName}`);
            continue;
        }
        // Verify leadership / founder role
        const isLeadership = allowedLeadershipKeywords.some(kw => roleClean.includes(kw));
        if (!isLeadership) {
            continue;
        }
        const personKey = `${lead.name.toLowerCase().trim()}|${companyClean}`;
        if (existingNames.has(personKey) || existingCompanies.has(companyClean) || usedKeys.has(personKey)) {
            continue;
        }
        usedKeys.add(personKey);
        // Clamp connection note to <= 200 characters (LinkedIn free tier limit)
        let note = (lead.connectionNote || "").trim();
        if (note.length > 200) {
            note = note.substring(0, 197) + "...";
        }
        qualifiedLeads.push({
            name: lead.name.trim(),
            currentRole: lead.currentRole || "Co-Founder & CTO",
            companyName: lead.companyName.trim(),
            location: lead.location || targetLocations[0] || "Bengaluru, India",
            linkedinUrl: lead.linkedinUrl.trim(),
            email: lead.email ? lead.email.trim().toLowerCase() : null,
            category: ["founder", "engineering_manager", "talent_acquisition"].includes(lead.category) ? lead.category : "founder",
            connectionNote: note,
            fullPitch: ((_f = lead.fullPitch) === null || _f === void 0 ? void 0 : _f.trim()) || note,
            fundingStage: lead.fundingStage || "Seed / Series A",
            techStack: Array.isArray(lead.techStack) ? lead.techStack : targetRoles.slice(0, 3)
        });
        if (qualifiedLeads.length >= MAX_STARTUPS_PER_RUN) {
            break;
        }
    }
    // Second Pass (Fallback if fewer than 5): Include any non-MNC tech company lead to reach 5
    if (qualifiedLeads.length < MAX_STARTUPS_PER_RUN) {
        for (const lead of parsedLeads) {
            if (!lead.name || !lead.companyName || !lead.linkedinUrl)
                continue;
            const companyClean = (lead.companyName || "").toLowerCase().trim();
            if (IT_SERVICES_MNC_BLACKLIST.some(mnc => companyClean.includes(mnc)))
                continue;
            if (excludedCompanies.some(ex => companyClean.includes(ex)))
                continue;
            const personKey = `${lead.name.toLowerCase().trim()}|${companyClean}`;
            if (usedKeys.has(personKey) || existingNames.has(personKey) || existingCompanies.has(companyClean))
                continue;
            usedKeys.add(personKey);
            // Clamp connection note to <= 200 characters (LinkedIn free tier limit)
            let note = (lead.connectionNote || "").trim();
            if (note.length > 200) {
                note = note.substring(0, 197) + "...";
            }
            qualifiedLeads.push({
                name: lead.name.trim(),
                currentRole: lead.currentRole || "Tech Lead",
                companyName: lead.companyName.trim(),
                location: lead.location || targetLocations[0] || "Bengaluru, India",
                linkedinUrl: lead.linkedinUrl.trim(),
                email: lead.email ? lead.email.trim().toLowerCase() : null,
                category: ["founder", "engineering_manager", "talent_acquisition"].includes(lead.category) ? lead.category : "engineering_manager",
                connectionNote: note,
                fullPitch: ((_g = lead.fullPitch) === null || _g === void 0 ? void 0 : _g.trim()) || note,
                fundingStage: lead.fundingStage || "High-Growth Startup",
                techStack: Array.isArray(lead.techStack) ? lead.techStack : targetRoles.slice(0, 3)
            });
            if (qualifiedLeads.length >= MAX_STARTUPS_PER_RUN) {
                break;
            }
        }
    }
    if (qualifiedLeads.length === 0) {
        await (0, featureLogger_1.logFeatureExecution)(uid, {
            feature: 'cold_outreach',
            featureTitle: 'Cold Outreach',
            status: 'no_results',
            count: 0,
            message: 'All discovered startups were previously pitched or excluded.',
            isManual: (_h = options === null || options === void 0 ? void 0 : options.isManualTrigger) !== null && _h !== void 0 ? _h : false
        });
        return { success: true, count: 0, leads: [], message: "All discovered startups were previously pitched or excluded." };
    }
    // 4. Automatically Send Emails to Founders/CTOs ONLY if Email is Explicitly Verified
    let emailsSentCount = 0;
    const cleanResumeB64 = resumeBase64.replace(/^data:application\/pdf;base64,/, "");
    // Load global bounce blacklist
    const globalBouncedSet = new Set();
    try {
        const bouncedSnap = await firebase_1.db.collection("system_bounced_emails").get();
        bouncedSnap.forEach(d => {
            const data = d.data() || {};
            if (data.email)
                globalBouncedSet.add(data.email.toLowerCase().trim());
            globalBouncedSet.add(d.id.toLowerCase().trim());
            try {
                globalBouncedSet.add(decodeURIComponent(d.id).toLowerCase().trim());
            }
            catch (_) { }
        });
    }
    catch (bErr) {
        console.warn("[StartupRadar] Warning loading system_bounced_emails:", bErr.message);
    }
    for (const lead of qualifiedLeads) {
        lead.emailSent = false;
        if (!lead.email || lead.email.trim().length === 0) {
            console.log(`[StartupRadar] No verified email for ${lead.name} (${lead.companyName}). Skipping email send; ready for LinkedIn outreach.`);
            continue;
        }
        const cleanEmail = lead.email.trim();
        const lowerEmail = cleanEmail.toLowerCase();
        // Check global bounce blacklist
        if (globalBouncedSet.has(lowerEmail) || globalBouncedSet.has(encodeURIComponent(lowerEmail))) {
            console.log(`[StartupRadar] Discarding blacklisted email '${cleanEmail}' for ${lead.name} at ${lead.companyName}. Retaining for LinkedIn outreach.`);
            lead.email = null;
            continue;
        }
        // Strict guard: discard speculative or generic role emails that cause "Address Not Found" bounces
        const speculativeRolePrefixes = ["cto@", "founder@", "founders@", "ceo@", "info@", "contact@", "admin@", "support@", "jobs@", "careers@"];
        if (speculativeRolePrefixes.some(prefix => lowerEmail.startsWith(prefix)) || !lowerEmail.includes("@") || !lowerEmail.includes(".")) {
            console.log(`[StartupRadar] Discarding speculative role email '${cleanEmail}' for ${lead.name} at ${lead.companyName}. Retaining for LinkedIn outreach.`);
            lead.email = null;
            continue;
        }
        if (transporter && cleanResumeB64) {
            // Verify MX DNS records before attempting to send
            const isDomainValid = await verifyEmailDomainMx(cleanEmail);
            if (isDomainValid) {
                const emailSubject = `${primaryRole} for ${lead.companyName} (${applicantName})`;
                try {
                    console.log(`[StartupRadar] Dispatching cold pitch email to ${cleanEmail} (${lead.companyName})...`);
                    const info = await transporter.sendMail({
                        from: `"${applicantName}" <${userEmail}>`,
                        to: cleanEmail,
                        subject: emailSubject,
                        text: lead.fullPitch,
                        attachments: [
                            {
                                filename: resumeFileName,
                                content: cleanResumeB64,
                                encoding: "base64"
                            }
                        ]
                    });
                    lead.emailSent = true;
                    lead.emailSentAt = new Date();
                    lead.emailSubject = emailSubject;
                    lead.messageId = info.messageId || "";
                    emailsSentCount++;
                    console.log(`[StartupRadar] Email delivered to ${cleanEmail} (Message-ID: ${lead.messageId})`);
                }
                catch (mailErr) {
                    console.warn(`[StartupRadar] Failed to email ${cleanEmail}:`, mailErr.message);
                }
            }
            else {
                console.log(`[StartupRadar] Domain MX records invalid for ${cleanEmail}. Skipping email send.`);
            }
        }
    }
    // 5. Persist to Firestore in `users/{uid}/networking_leads`
    const batch = firebase_1.db.batch();
    for (const lead of qualifiedLeads) {
        const leadRef = firebase_1.db.collection("users").doc(uid).collection("networking_leads").doc();
        batch.set(leadRef, {
            name: lead.name,
            currentRole: lead.currentRole,
            companyName: lead.companyName,
            location: lead.location,
            linkedinUrl: lead.linkedinUrl,
            email: lead.email || null,
            category: lead.category,
            connectionNote: lead.connectionNote,
            fullPitch: lead.fullPitch,
            fundingStage: lead.fundingStage,
            techStack: lead.techStack,
            emailSent: (_j = lead.emailSent) !== null && _j !== void 0 ? _j : false,
            emailSentAt: lead.emailSentAt ? firebase_1.admin.firestore.Timestamp.fromDate(lead.emailSentAt) : null,
            emailSubject: lead.emailSubject || null,
            messageId: lead.messageId || null,
            status: lead.emailSent ? "email_sent" : "discovered",
            isReplyDismissed: false,
            isBounced: false,
            discoveredAt: firebase_1.admin.firestore.FieldValue.serverTimestamp()
        });
    }
    await batch.commit();
    console.log(`[StartupRadar] Saved ${qualifiedLeads.length} startup leads. Auto-dispatched ${emailsSentCount} emails.`);
    // 6. Push Notification & Email Digest for User (Web & Mobile)
    try {
        const notifTitle = "🚀 Startup Radar: New Pitches Dispatched!";
        const notifBody = emailsSentCount > 0
            ? `Dispatched ${emailsSentCount} direct pitches to startup CTOs in ${targetLocations[0]}! LinkedIn notes ready.`
            : `Found ${qualifiedLeads.length} Seed/Series A startups in ${targetLocations[0]}! LinkedIn notes ready.`;
        await (0, logger_1.logNotification)(uid, notifTitle, notifBody, "JOB_ASSISTANT");
        // Send confirmation summary email to user's inbox for web & mobile users
        const notifPrefs = userData.notificationPreferences || {};
        const isEmailEnabled = notifPrefs.cold_outreach_email !== false && notifPrefs.job_assistant_email !== false;
        if (isEmailEnabled && transporter && userEmail) {
            const leadsHtml = qualifiedLeads.map(l => `<li style="margin-bottom: 12px; border-bottom: 1px solid #f3f4f6; padding-bottom: 8px;">
                    <strong>${l.name}</strong> – ${l.currentRole} at <strong>${l.companyName}</strong> (${l.location})<br>
                    <span style="color: #0284C7; font-size: 13px;">🔗 <a href="${l.linkedinUrl}">LinkedIn Profile</a></span> | 
                    <span style="color: ${l.emailSent ? '#16A34A' : '#6B7280'}; font-size: 13px;">${l.emailSent ? '✅ Direct Email Pitch Sent' : (l.email ? `✉️ ${l.email}` : 'LinkedIn Note Ready')}</span><br>
                    <div style="background: #F9FAFB; padding: 6px 10px; border-radius: 6px; font-size: 12px; margin-top: 4px; color: #374151;">
                        <em>"${l.connectionNote}"</em>
                    </div>
                </li>`).join('');
            await transporter.sendMail({
                from: `"RemindBuddy Startup Radar" <${userEmail}>`,
                to: userEmail,
                subject: `🚀 [RemindBuddy] Discovered 5 Startup Leaders in ${targetLocations[0] || 'Target Locations'}`,
                html: `
                    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px;">
                        <h2 style="color: #0284C7; margin-top: 0;">🚀 Startup Radar Discovery (${primaryRole})</h2>
                        <p>Hello <strong>${applicantName}</strong>,</p>
                        <p>Your Startup Radar ran a new outreach discovery pass for <strong>${targetLocations.join(', ')}</strong> and generated tailored pitches for <strong>${qualifiedLeads.length} startup leaders</strong>:</p>
                        <ul style="padding-left: 20px; list-style-type: none;">${leadsHtml}</ul>
                        <p style="color: #6B7280; font-size: 13px; margin-top: 24px; border-top: 1px solid #eee; padding-top: 12px;">
                            Pitches and 200-char LinkedIn connection notes are also ready in your RemindBuddy Cold Outreach dashboard.
                        </p>
                    </div>
                `
            });
            console.log(`[StartupRadar] Sent email digest to ${userEmail}`);
        }
    }
    catch (e) {
        console.warn("[StartupRadar] Notification / email digest error:", e);
    }
    const leadDetails = qualifiedLeads.map(l => `${l.name} (${l.currentRole} at ${l.companyName})`);
    await (0, featureLogger_1.logFeatureExecution)(uid, {
        feature: 'cold_outreach',
        featureTitle: 'Cold Outreach',
        status: qualifiedLeads.length > 0 ? 'success' : 'no_results',
        count: qualifiedLeads.length,
        message: emailsSentCount > 0
            ? `Auto-dispatched ${emailsSentCount} startup pitch(es) via email. ${qualifiedLeads.length} LinkedIn notes ready.`
            : `Discovered ${qualifiedLeads.length} startup leader(s) in ${targetLocations[0] || 'target area'} (LinkedIn notes ready).`,
        details: leadDetails,
        isManual: (_k = options === null || options === void 0 ? void 0 : options.isManualTrigger) !== null && _k !== void 0 ? _k : false
    });
    return {
        success: true,
        count: qualifiedLeads.length,
        leads: qualifiedLeads,
        message: emailsSentCount > 0
            ? `Auto-dispatched ${emailsSentCount} startup pitches via email! LinkedIn connection notes are ready in your dashboard.`
            : `Discovered ${qualifiedLeads.length} startup leaders. LinkedIn notes ready!`
    };
}
/**
 * Scheduled dispatcher called daily from masterHalfHourlyRunner at 11:30 AM IST
 */
async function internalNetworkingDiscoveryDispatcher() {
    var _a;
    console.log("[internalNetworkingDiscoveryDispatcher] Starting daily Startup Radar scan...");
    try {
        const usersSnap = await firebase_1.db.collection("users").get();
        const eligibleUids = [];
        for (const doc of usersSnap.docs) {
            const data = doc.data() || {};
            const uid = doc.id;
            const userApiKeys = data.userApiKeys || {};
            const hasKeys = !!((userApiKeys.tavilyApiKey || data.tavilyApiKey) && (userApiKeys.geminiApiKey || data.geminiApiKey));
            if (!hasKeys)
                continue;
            if (((_a = data.autoApplySettings) === null || _a === void 0 ? void 0 : _a.enabled) === false)
                continue;
            eligibleUids.push(uid);
        }
        console.log(`[internalNetworkingDiscoveryDispatcher] Eligible users for Startup Radar: ${eligibleUids.length}`);
        for (const uid of eligibleUids) {
            try {
                await discoverNetworkingLeadsForUser(uid, { isManualTrigger: false });
            }
            catch (err) {
                console.error(`[internalNetworkingDiscoveryDispatcher] Error for user ${uid}:`, err.message || err);
            }
            await new Promise(res => setTimeout(res, 3000));
        }
    }
    catch (e) {
        console.error("[internalNetworkingDiscoveryDispatcher] Daily dispatcher error:", e.message || e);
    }
}
/**
 * On-Demand HTTPS Callable for Flutter App
 */
exports.triggerNetworkingDiscovery = functions.runWith({ timeoutSeconds: 300, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
    }
    const uid = context.auth.uid;
    try {
        const result = await discoverNetworkingLeadsForUser(uid, {
            applicantName: data.applicantName,
            targetRoles: data.targetRoles,
            locations: data.targetLocations,
            excludedCompanies: data.excludedCompanies,
            isManualTrigger: true
        });
        return result;
    }
    catch (err) {
        console.error("[triggerNetworkingDiscovery] Callable error:", err);
        throw new functions.https.HttpsError("internal", err.message || "Failed to discover startups.");
    }
});
//# sourceMappingURL=networkingDiscoveryAI.js.map