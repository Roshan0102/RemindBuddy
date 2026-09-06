import * as functions from "firebase-functions";
import * as nodemailer from "nodemailer";
import * as dns from "dns";
import { admin, db } from "../../config/firebase";
import { logNotification } from "../../utils/logger";
import { callGeminiAPI } from "../../utils/geminiHelper";
import { searchTavily, TavilySearchResult } from "../../utils/tavilyHelper";

export interface DiscoveredLeadAI {
    name: string;
    currentRole: string;
    companyName: string;
    location: string;
    linkedinUrl: string;
    email?: string | null;
    category: "founder" | "engineering_manager" | "talent_acquisition";
    connectionNote: string; // Strictly <= 300 characters
    fullPitch: string;
    fundingStage?: string;
    techStack?: string[];
    emailSent?: boolean;
    emailSentAt?: Date;
    emailSubject?: string;
    messageId?: string;
}

export interface NetworkingDiscoveryOptions {
    targetRoles?: string[];
    locations?: string[];
    excludedCompanies?: string[];
    isManualTrigger?: boolean;
}

/**
 * Validates that an email has valid MX DNS records before attempting to send.
 */
async function verifyEmailDomainMx(email: string): Promise<boolean> {
    try {
        const domain = email.split("@")[1]?.trim();
        if (!domain) return false;
        const records = await dns.promises.resolveMx(domain);
        return records && records.length > 0;
    } catch {
        return false;
    }
}

/**
 * High-Growth Startups & Seed/Series A Radar:
 * Discovers up to 5 funded tech startups, identifies technical founders/CTOs,
 * derives & verifies company emails, automatically sends a tailored startup pitch with resume attached,
 * and saves LinkedIn connection notes for 1-tap manual outreach.
 */
export async function discoverNetworkingLeadsForUser(
    uid: string,
    options?: NetworkingDiscoveryOptions
): Promise<{
    success: boolean;
    count: number;
    leads: DiscoveredLeadAI[];
    message: string;
}> {
    console.log(`[StartupRadar] Starting Seed/Series A startup discovery for user ${uid}...`);

    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
        return { success: false, count: 0, leads: [], message: "User profile not found." };
    }

    const userData = userDoc.data() || {};
    const applicantName = userData.displayName || "Roshan J";

    // Resolve dynamic user preferences (from startupRadarSettings, autoApplySettings, or options)
    const startupSettings = userData.startupRadarSettings || {};
    const autoApplySettings = userData.autoApplySettings || {};

    let targetRoles: string[] = options?.targetRoles || startupSettings.techDomains || autoApplySettings.targetRoles || [
        "DevOps Engineer",
        "Cloud Engineer",
        "AWS Cloud Architect",
        "Site Reliability Engineer (SRE)",
        "Flutter Developer"
    ];
    if (typeof targetRoles === "string") {
        targetRoles = (targetRoles as string).split(",").map((s: string) => s.trim()).filter((s: string) => s.length > 0);
    }
    if (targetRoles.length === 0) {
        targetRoles = ["DevOps Engineer", "Cloud Engineer", "AWS Engineer", "SRE"];
    }

    let targetLocations: string[] = options?.locations || startupSettings.locations || autoApplySettings.locations || [
        "Bengaluru",
        "India",
        "Remote"
    ];
    if (typeof targetLocations === "string") {
        targetLocations = (targetLocations as string).split(",").map((s: string) => s.trim()).filter((s: string) => s.length > 0);
    }
    if (targetLocations.length === 0) {
        targetLocations = ["Bengaluru", "Remote", "India"];
    }

    let excludedCompanies: string[] = options?.excludedCompanies || startupSettings.excludedCompanies || autoApplySettings.excludedCompanies || [];
    if (typeof excludedCompanies === "string") {
        excludedCompanies = (excludedCompanies as string).split(",").map((s: string) => s.trim().toLowerCase()).filter((s: string) => s.length > 0);
    } else if (Array.isArray(excludedCompanies)) {
        excludedCompanies = excludedCompanies.map(c => String(c).trim().toLowerCase()).filter(c => c.length > 0);
    }

    // Resolve API Keys
    const userApiKeys = userData.userApiKeys || {};
    const userTavilyKey = (userApiKeys.tavilyApiKey || userData.tavilyApiKey || "").trim();
    const userGeminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();

    if (!userTavilyKey || !userGeminiKey) {
        console.log(`[StartupRadar] User ${uid} missing personal Tavily or Gemini API key in Settings.`);
        return {
            success: false,
            count: 0,
            leads: [],
            message: "Please configure your personal Tavily & Gemini API keys in Job Assistant Settings."
        };
    }

    // Resolve Email Transporter & Resume for automatic email delivery
    const emailConfig = userData.emailConfig || {};
    const userEmail = emailConfig.email?.trim();
    const appPassword = emailConfig.appPassword?.trim();
    let canSendEmails = !!(userEmail && appPassword);

    let resumeBase64 = "";
    let resumeFileName = "Resume.pdf";
    const masterResume = userData.masterResume || {};
    if (masterResume.base64) {
        resumeBase64 = masterResume.base64;
        resumeFileName = masterResume.fileName || "Resume.pdf";
    } else {
        const profilesSnap = await db.collection("users").doc(uid).collection("resume_profiles").get();
        if (!profilesSnap.empty) {
            const defProf = profilesSnap.docs.find(d => d.data().isDefault) || profilesSnap.docs[0];
            resumeBase64 = defProf.data().base64 || "";
            resumeFileName = defProf.data().fileName || "Resume.pdf";
        }
    }

    let transporter: nodemailer.Transporter | null = null;
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
    const existingLeadsSnap = await db.collection("users").doc(uid).collection("networking_leads").get();
    const existingUrls = new Set<string>();
    const existingNames = new Set<string>();
    const existingCompanies = new Set<string>();

    existingLeadsSnap.forEach(doc => {
        const d = doc.data();
        if (d.linkedinUrl) existingUrls.add(d.linkedinUrl.toLowerCase().trim());
        if (d.name && d.companyName) existingNames.add(`${d.name.toLowerCase().trim()}|${d.companyName.toLowerCase().trim()}`);
        if (d.companyName) existingCompanies.add(d.companyName.toLowerCase().trim());
    });

    // 1. Build Google X-Ray Tavily queries for High-Growth Startups & Founders / CTOs
    const locQuery = targetLocations.map(l => `"${l}"`).join(" OR ");
    const roleFocus = targetRoles.slice(0, 3).map(r => `"${r}"`).join(" OR ");

    const queries: { category: "founder" | "engineering_manager" | "talent_acquisition"; query: string }[] = [
        {
            category: "founder",
            query: `site:linkedin.com/in ("Founder" OR "Co-Founder" OR "CTO" OR "Chief Technology Officer") ("Seed" OR "Series A" OR "YC" OR "Techstars" OR "Stealth") (${roleFocus}) (${locQuery})`
        },
        {
            category: "engineering_manager",
            query: `site:linkedin.com/in ("Head of Engineering" OR "VP of Engineering" OR "Founding Engineer" OR "DevOps Lead") ("Startup" OR "Fintech" OR "SaaS" OR "AI") (${roleFocus}) (${locQuery})`
        },
        {
            category: "founder",
            query: `site:linkedin.com/in ("Founder" OR "CTO") ("Hiring" OR "Scaling") ("Cloud" OR "DevOps" OR "AWS") (${locQuery})`
        }
    ];

    const allTavilyResults: { category: "founder" | "engineering_manager" | "talent_acquisition"; result: TavilySearchResult }[] = [];
    const seenUrls = new Set<string>();

    for (const qObj of queries) {
        try {
            console.log(`[StartupRadar] Running Tavily search for: ${qObj.query}...`);
            const tavilyResp = await searchTavily({
                apiKey: userTavilyKey,
                query: qObj.query,
                searchDepth: "advanced",
                maxResults: 6,
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
        } catch (searchErr: any) {
            console.warn(`[StartupRadar] Tavily search error:`, searchErr.message);
        }
    }

    if (allTavilyResults.length === 0) {
        console.log(`[StartupRadar] 0 fresh startup profiles found for user ${uid}.`);
        return {
            success: true,
            count: 0,
            leads: [],
            message: "No fresh startup founders or CTOs found today. Check back tomorrow!"
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
    const prompt = `You are an elite startup recruitment strategist working for ${applicantName}.
Candidate Profile:
- Name: ${applicantName}
- Target Domains: ${targetRoles.join(", ")}
- Specialization: AWS Cloud Infrastructure, Docker containerization, Terraform Infrastructure-as-Code, Linux, CI/CD automation pipelines, and SRE/monitoring.
- Target Locations: ${targetLocations.join(", ")}

Analyze these real LinkedIn profiles of startup founders, CTOs, and tech leaders:
${profilesText}

Extract each verified person. For each:
1. "name": Clean full name.
2. "currentRole": Their title (e.g. "Co-Founder & CTO", "VP of Engineering", "Head of Tech").
3. "companyName": Clean startup name (e.g. "FintechHub", "CloudWave AI").
4. "location": City & country (e.g. "Bengaluru, Karnataka, India").
5. "linkedinUrl": Clean LinkedIn URL (https://www.linkedin.com/in/...).
6. "email": If a public/company email is mentioned in the bio/snippet, extract it. Otherwise, derive the most likely startup work email format using company domain (e.g., "cto@company.com", "first@company.com", or "careers@company.com"). If completely unknown, use null.
7. "fundingStage": Detected stage (e.g. "Seed", "Series A", "YC-backed", "Bootstrapped", or "High-Growth").
8. "techStack": Array of 2-4 tech tags relevant to their company or candidate focus (e.g. ["AWS", "Docker", "Terraform", "Kubernetes"]).
9. "category": Strictly "founder", "engineering_manager", or "talent_acquisition".
10. "connectionNote": 
    - MANDATORY HARD LIMIT: STRICTLY LESS THAN OR EQUAL TO 280 CHARACTERS (including spaces).
    - Authentic, polite, non-generic invitation for LinkedIn. Mention their startup and your focus in DevOps/Cloud.
11. "fullPitch": 
    - A CRISP, HIGH-CONVERSION 4-SENTENCE STARTUP VALUE PITCH (Perfect for cold email).
    - Sentence 1: Enthusiastic acknowledgement of their startup's growth in ${targetLocations[0] || 'tech'}.
    - Sentence 2: Value proposition: How ${applicantName} helps early/scaling startups automate AWS/Docker CI/CD deployments and maintain 99.9% uptime.
    - Sentence 3: Mention of attached 1-page resume + GitHub infrastructure portfolio.
    - Sentence 4: Low-friction call to action: "Open for a brief 10-minute sync this week to see if I can take cloud/infrastructure load off your dev team?"

OUTPUT FORMAT:
Return ONLY a valid JSON array of objects. No markdown backticks, no wrapping text.`;

    const payload = {
        contents: [
            {
                parts: [{ text: prompt }]
            }
        ]
    };

    let rawText = "";
    try {
        const geminiResult = await callGeminiAPI(payload, { apiKey: userGeminiKey, timeout: 120000 });
        rawText = geminiResult.text || "";
    } catch (apiErr: any) {
        console.error("[StartupRadar] Gemini analysis failed:", apiErr.message);
        return { success: false, count: 0, leads: [], message: `AI analysis busy: ${apiErr.message}` };
    }

    let parsedLeads: any[] = [];
    try {
        const jsonMatch = rawText.match(/\[[\s\S]*\]/);
        parsedLeads = JSON.parse(jsonMatch ? jsonMatch[0] : rawText);
    } catch (parseErr) {
        console.error("[StartupRadar] JSON parse error:", parseErr, rawText);
        return { success: false, count: 0, leads: [], message: "Failed to parse startup discoveries." };
    }

    if (!Array.isArray(parsedLeads) || parsedLeads.length === 0) {
        return { success: true, count: 0, leads: [], message: "No fresh startups extracted." };
    }

    // 3. Filter against Excluded Companies and enforce Maximum 5 Startups Per Run
    const MAX_STARTUPS_PER_RUN = 5;
    const qualifiedLeads: DiscoveredLeadAI[] = [];

    for (const lead of parsedLeads) {
        if (!lead.name || !lead.companyName || !lead.linkedinUrl) continue;

        const companyClean = (lead.companyName || "").toLowerCase().trim();
        if (excludedCompanies.some(ex => companyClean.includes(ex))) {
            console.log(`[StartupRadar] Skipping excluded startup: ${lead.companyName}`);
            continue;
        }

        const personKey = `${lead.name.toLowerCase().trim()}|${companyClean}`;
        if (existingNames.has(personKey) || existingCompanies.has(companyClean)) {
            continue;
        }

        // Clamp connection note to <= 300 characters
        let note = (lead.connectionNote || "").trim();
        if (note.length > 300) {
            note = note.substring(0, 297) + "...";
        }

        qualifiedLeads.push({
            name: lead.name.trim(),
            currentRole: lead.currentRole || "Co-Founder & CTO",
            companyName: lead.companyName.trim(),
            location: lead.location || "Bengaluru, India",
            linkedinUrl: lead.linkedinUrl.trim(),
            email: lead.email ? lead.email.trim().toLowerCase() : null,
            category: ["founder", "engineering_manager", "talent_acquisition"].includes(lead.category) ? lead.category : "founder",
            connectionNote: note,
            fullPitch: lead.fullPitch?.trim() || note,
            fundingStage: lead.fundingStage || "Seed / Series A",
            techStack: Array.isArray(lead.techStack) ? lead.techStack : ["AWS", "Docker", "CI/CD", "DevOps"]
        });

        if (qualifiedLeads.length >= MAX_STARTUPS_PER_RUN) {
            break; // Respect maximum 5 companies limit per run
        }
    }

    if (qualifiedLeads.length === 0) {
        return { success: true, count: 0, leads: [], message: "All discovered startups were previously pitched or excluded." };
    }

    // 4. Automatically Send Emails to Founders/CTOs if Email is Available & Verified
    let emailsSentCount = 0;
    const cleanResumeB64 = resumeBase64.replace(/^data:application\/pdf;base64,/, "");

    for (const lead of qualifiedLeads) {
        lead.emailSent = false;

        if (lead.email && transporter && cleanResumeB64) {
            // Verify MX DNS records before attempting to send
            const isDomainValid = await verifyEmailDomainMx(lead.email);
            if (isDomainValid) {
                const emailSubject = `DevOps & Cloud Infrastructure for ${lead.companyName} (${applicantName})`;
                try {
                    console.log(`[StartupRadar] Dispatching cold pitch email to ${lead.email} (${lead.companyName})...`);
                    const info = await transporter.sendMail({
                        from: `"${applicantName}" <${userEmail}>`,
                        to: lead.email,
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
                    console.log(`[StartupRadar] Email delivered to ${lead.email} (Message-ID: ${lead.messageId})`);
                } catch (mailErr: any) {
                    console.warn(`[StartupRadar] Failed to email ${lead.email}:`, mailErr.message);
                }
            }
        }
    }

    // 5. Persist to Firestore in `users/{uid}/networking_leads`
    const batch = db.batch();
    for (const lead of qualifiedLeads) {
        const leadRef = db.collection("users").doc(uid).collection("networking_leads").doc();
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
            emailSent: lead.emailSent ?? false,
            emailSentAt: lead.emailSentAt ? admin.firestore.Timestamp.fromDate(lead.emailSentAt) : null,
            emailSubject: lead.emailSubject || null,
            messageId: lead.messageId || null,
            status: lead.emailSent ? "email_sent" : "discovered",
            discoveredAt: admin.firestore.FieldValue.serverTimestamp()
        });
    }
    await batch.commit();

    console.log(`[StartupRadar] Saved ${qualifiedLeads.length} startup leads. Auto-dispatched ${emailsSentCount} emails.`);

    // 6. Push Notification
    try {
        const notifTitle = "🚀 Startup Radar: New Pitches Dispatched!";
        const notifBody = emailsSentCount > 0
            ? `Dispatched ${emailsSentCount} direct pitches to startup CTOs in ${targetLocations[0]}! LinkedIn notes ready.`
            : `Found ${qualifiedLeads.length} Seed/Series A startups in ${targetLocations[0]}! LinkedIn notes ready.`;
        await logNotification(uid, notifTitle, notifBody, "JOB_ASSISTANT");
    } catch (e) {
        console.warn("[StartupRadar] Notification error:", e);
    }

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
export async function internalNetworkingDiscoveryDispatcher(): Promise<void> {
    console.log("[internalNetworkingDiscoveryDispatcher] Starting daily Startup Radar scan...");
    try {
        const usersSnap = await db.collection("users").get();
        const eligibleUids: string[] = [];

        for (const doc of usersSnap.docs) {
            const data = doc.data() || {};
            const uid = doc.id;

            const userApiKeys = data.userApiKeys || {};
            const hasKeys = !!((userApiKeys.tavilyApiKey || data.tavilyApiKey) && (userApiKeys.geminiApiKey || data.geminiApiKey));
            if (!hasKeys) continue;

            if (data.autoApplySettings?.enabled === false) continue;

            eligibleUids.push(uid);
        }

        console.log(`[internalNetworkingDiscoveryDispatcher] Eligible users for Startup Radar: ${eligibleUids.length}`);

        for (const uid of eligibleUids) {
            try {
                await discoverNetworkingLeadsForUser(uid, { isManualTrigger: false });
            } catch (err: any) {
                console.error(`[internalNetworkingDiscoveryDispatcher] Error for user ${uid}:`, err.message || err);
            }
            await new Promise(res => setTimeout(res, 3000));
        }
    } catch (e: any) {
        console.error("[internalNetworkingDiscoveryDispatcher] Daily dispatcher error:", e.message || e);
    }
}

/**
 * On-Demand HTTPS Callable for Flutter App
 */
export const triggerNetworkingDiscovery = functions.runWith({ timeoutSeconds: 300, memory: "1GB" }).https.onCall(
    async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "User must be authenticated.");
        }
        const uid = context.auth.uid;
        try {
            const result = await discoverNetworkingLeadsForUser(uid, {
                targetRoles: data.targetRoles,
                locations: data.targetLocations,
                excludedCompanies: data.excludedCompanies,
                isManualTrigger: true
            });
            return result;
        } catch (err: any) {
            console.error("[triggerNetworkingDiscovery] Callable error:", err);
            throw new functions.https.HttpsError("internal", err.message || "Failed to discover startups.");
        }
    }
);
