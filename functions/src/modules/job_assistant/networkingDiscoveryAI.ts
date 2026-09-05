import * as functions from "firebase-functions";
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
    category: "engineering_manager" | "founder" | "talent_acquisition";
    connectionNote: string; // Strictly <= 300 characters
    fullPitch: string;
}

export interface NetworkingDiscoveryOptions {
    targetRoles?: string[];
    locations?: string[];
    excludedCompanies?: string[];
    isManualTrigger?: boolean;
}

/**
 * Searches LinkedIn profiles via Google X-Ray & Tavily, then analyzes them with Gemini 3.7 Flash
 * to discover Engineering Managers, Founders, and Talent Acquisition Leads in target locations.
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
    console.log(`[NetworkingDiscovery] Starting leadership outreach discovery for user ${uid}...`);

    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
        return { success: false, count: 0, leads: [], message: "User profile not found." };
    }

    const userData = userDoc.data() || {};
    const applicantName = userData.displayName || "Roshan J";

    // Resolve target roles, locations & excluded companies
    const autoApplySettings = userData.autoApplySettings || {};
    let targetRoles: string[] = options?.targetRoles || autoApplySettings.targetRoles || [
        "Flutter Developer",
        "Mobile Application Developer",
        "DevOps Engineer",
        "Cloud Engineer"
    ];
    if (typeof targetRoles === 'string') {
        targetRoles = (targetRoles as string).split(',').map((s: string) => s.trim()).filter((s: string) => s.length > 0);
    }
    if (targetRoles.length === 0) {
        targetRoles = ["Flutter Developer", "Mobile Engineer", "DevOps Engineer", "Cloud Engineer"];
    }

    let targetLocations: string[] = options?.locations || autoApplySettings.locations || [
        "Bengaluru",
        "India",
        "Remote"
    ];
    if (typeof targetLocations === 'string') {
        targetLocations = (targetLocations as string).split(',').map((s: string) => s.trim()).filter((s: string) => s.length > 0);
    }
    if (targetLocations.length === 0) {
        targetLocations = ["Bengaluru", "India", "Remote"];
    }

    let excludedCompanies: string[] = options?.excludedCompanies || autoApplySettings.excludedCompanies || [];
    if (typeof excludedCompanies === 'string') {
        excludedCompanies = (excludedCompanies as string).split(',').map((s: string) => s.trim().toLowerCase()).filter((s: string) => s.length > 0);
    } else if (Array.isArray(excludedCompanies)) {
        excludedCompanies = excludedCompanies.map(c => String(c).trim().toLowerCase()).filter(c => c.length > 0);
    }

    // Resolve API Keys
    const userApiKeys = userData.userApiKeys || {};
    const userTavilyKey = (userApiKeys.tavilyApiKey || userData.tavilyApiKey || "").trim();
    const userGeminiKey = (userApiKeys.geminiApiKey || userData.geminiApiKey || "").trim();

    if (!userTavilyKey || !userGeminiKey) {
        console.log(`[NetworkingDiscovery] User ${uid} missing personal Tavily or Gemini API key in Settings.`);
        return {
            success: false,
            count: 0,
            leads: [],
            message: "Please configure your personal Tavily & Gemini API keys in Job Assistant Settings."
        };
    }

    // Fetch existing discovered leads to avoid duplicates
    const existingLeadsSnap = await db.collection("users").doc(uid).collection("networking_leads").get();
    const existingUrls = new Set<string>();
    const existingNames = new Set<string>();

    existingLeadsSnap.forEach(doc => {
        const d = doc.data();
        if (d.linkedinUrl) {
            existingUrls.add(d.linkedinUrl.toLowerCase().trim());
        }
        if (d.name && d.companyName) {
            existingNames.add(`${d.name.toLowerCase().trim()}|${d.companyName.toLowerCase().trim()}`);
        }
    });

    // 1. Build Google X-Ray Tavily queries for the 3 key leadership categories
    const locQuery = targetLocations.map(l => `"${l}"`).join(" OR ");
    const roleFocus = targetRoles.slice(0, 3).map(r => `"${r}"`).join(" OR ");

    const queries: { category: "engineering_manager" | "founder" | "talent_acquisition"; query: string }[] = [
        {
            category: "engineering_manager",
            query: `site:linkedin.com/in ("Engineering Manager" OR "Head of Engineering" OR "Director of Engineering" OR "Technical Lead") (${roleFocus}) (${locQuery})`
        },
        {
            category: "founder",
            query: `site:linkedin.com/in ("Founder" OR "Co-Founder" OR "CTO") ("Tech" OR "Software" OR "AI" OR "App") (${locQuery})`
        },
        {
            category: "talent_acquisition",
            query: `site:linkedin.com/in ("Talent Acquisition" OR "Technical Recruiter" OR "Lead Recruiter") (${roleFocus}) (${locQuery})`
        }
    ];

    const allTavilyResults: { category: "engineering_manager" | "founder" | "talent_acquisition"; result: TavilySearchResult }[] = [];
    const seenUrls = new Set<string>();

    for (const qObj of queries) {
        try {
            console.log(`[NetworkingDiscovery] Running X-Ray Tavily search for category "${qObj.category}"...`);
            const tavilyResp = await searchTavily({
                apiKey: userTavilyKey,
                query: qObj.query,
                searchDepth: "advanced",
                maxResults: 6,
                includeDomains: ["linkedin.com"]
            });

            for (const item of tavilyResp.results) {
                if (!item.url || !item.url.includes("linkedin.com/in/")) {
                    continue; // Strictly ensure it's a personal LinkedIn profile URL
                }
                const cleanUrl = item.url.toLowerCase().split("?")[0].replace(/\/$/, "");
                if (existingUrls.has(cleanUrl) || seenUrls.has(cleanUrl)) {
                    continue; // Skip duplicates
                }
                seenUrls.add(cleanUrl);
                allTavilyResults.push({
                    category: qObj.category,
                    result: item
                });
            }
        } catch (searchErr: any) {
            console.warn(`[NetworkingDiscovery] Error querying Tavily for ${qObj.category}:`, searchErr.message);
        }
    }

    if (allTavilyResults.length === 0) {
        console.log(`[NetworkingDiscovery] 0 fresh LinkedIn leadership profiles found for user ${uid}.`);
        return {
            success: true,
            count: 0,
            leads: [],
            message: "No fresh new leadership profiles discovered today. Check back tomorrow!"
        };
    }

    const profilesText = allTavilyResults.map((item, idx) => {
        return `[Candidate Profile ${idx + 1}]
Category: ${item.category}
Title / Headline: ${item.result.title}
Profile URL: ${item.result.url}
Snippet / Experience: ${item.result.content}`;
    }).join("\n\n");

    // 2. Prompt Gemini 3.7 Flash to extract profile details and craft hyper-personalized outreach messages
    const prompt = `You are an elite career strategist and executive outreach AI assistant working for ${applicantName}.
Candidate Profile:
- Name: ${applicantName}
- Background: Senior/Lead Software Engineer specializing in Flutter, Mobile Architecture, DevOps (Docker, CI/CD pipelines, Kubernetes, Linux), and Cloud (GCP/Firebase, AWS).
- Seeking high-impact roles, engineering collaborations, and leadership networking in ${targetLocations.join(', ')}.

Below are real LinkedIn profiles found via search engine indexing:
${profilesText}

Analyze each profile carefully. For each valid person:
1. Extract their clean full name (e.g. "Jane Doe").
2. Identify their current job title / role (e.g. "Engineering Manager", "Founder & CTO", "Senior Technical Recruiter").
3. Identify their company name (e.g. "Razorpay", "Swiggy", "CRED").
4. Extract location (e.g. "Bengaluru, Karnataka, India").
5. Use their clean LinkedIn profile URL (https://www.linkedin.com/in/...).
6. Extract public business/personal email if explicitly found in the snippet; otherwise null.
7. Assign category: strictly one of "engineering_manager", "founder", or "talent_acquisition".
8. CONNECTION NOTE (CRITICAL MANDATE):
   - LinkedIn connection notes have a STRICT LIMIT OF 300 CHARACTERS.
   - YOUR GENERATED "connectionNote" MUST BE AT OR UNDER 280 CHARACTERS TO BE 100% SAFE (INCLUDING SPACES).
   - Tone: Courteous, genuine, conversational, confident, and professional.
   - Mention their team/company and express sincere interest in connecting regarding Flutter / Cloud engineering.
   - Example style: "Hi [Name], loved following [Company]'s work in tech. As an engineer building scalable Flutter & Cloud systems, I'd love to connect and follow your leadership journey!"
9. FULL PITCH:
   - A complete 2-3 paragraph introductory cold message / email / InMail pitch.
   - Paragraph 1: Friendly greeting, authentic commendation of their company/initiatives.
   - Paragraph 2: Brief highlights of ${applicantName}'s relevant engineering impact (cross-platform Flutter apps, automated DevOps pipelines, high reliability).
   - Paragraph 3: Polite invite to connect or sync for a short 10-minute coffee chat or discussion if their team is growing.

EXCLUSIONS:
Do NOT output fictional people. Only output people from the provided snippets.

OUTPUT FORMAT:
Return ONLY a valid JSON array of objects with the exact schema:
[
  {
    "name": string,
    "currentRole": string,
    "companyName": string,
    "location": string,
    "linkedinUrl": string,
    "email": string or null,
    "category": "engineering_manager" | "founder" | "talent_acquisition",
    "connectionNote": string (STRICTLY <= 290 CHARACTERS),
    "fullPitch": string
  }
]
No markdown wrapping, no extra words, output raw JSON.`;

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
        console.error("[NetworkingDiscovery] Gemini analysis failed:", apiErr.message);
        return { success: false, count: 0, leads: [], message: `AI temporarily busy: ${apiErr.message}` };
    }

    if (!rawText) {
        return { success: true, count: 0, leads: [], message: "Empty response from leadership AI." };
    }

    let parsedLeads: DiscoveredLeadAI[] = [];
    try {
        const jsonMatch = rawText.match(/\[[\s\S]*\]/);
        if (jsonMatch) {
            parsedLeads = JSON.parse(jsonMatch[0]);
        } else {
            parsedLeads = JSON.parse(rawText);
        }
    } catch (parseErr) {
        console.error("[NetworkingDiscovery] Failed to parse JSON from AI response:", parseErr, rawText);
        return { success: false, count: 0, leads: [], message: "Failed to parse AI networking discoveries." };
    }

    if (!Array.isArray(parsedLeads) || parsedLeads.length === 0) {
        return { success: true, count: 0, leads: [], message: "No relevant leaders extracted." };
    }

    // 3. Filter against Excluded Companies Blacklist and sanitize character limits
    const validLeadsToSave: DiscoveredLeadAI[] = [];

    for (const lead of parsedLeads) {
        if (!lead.name || !lead.linkedinUrl) continue;

        const companyClean = (lead.companyName || "").toLowerCase().trim();
        if (excludedCompanies.some(excluded => companyClean.includes(excluded))) {
            console.log(`[NetworkingDiscovery] Skipping lead ${lead.name} at excluded company "${lead.companyName}"`);
            continue;
        }

        const personKey = `${lead.name.toLowerCase().trim()}|${companyClean}`;
        if (existingNames.has(personKey)) {
            continue;
        }

        // Enforce strict 300 character maximum limit for LinkedIn note
        let note = (lead.connectionNote || "").trim();
        if (note.length > 300) {
            note = note.substring(0, 297) + "...";
        }

        validLeadsToSave.push({
            name: lead.name.trim(),
            currentRole: lead.currentRole || "Technology Leader",
            companyName: lead.companyName || "Tech Company",
            location: lead.location || "Bengaluru, India",
            linkedinUrl: lead.linkedinUrl.trim(),
            email: lead.email ? lead.email.trim() : null,
            category: ["engineering_manager", "founder", "talent_acquisition"].includes(lead.category)
                ? lead.category
                : "engineering_manager",
            connectionNote: note,
            fullPitch: lead.fullPitch || note
        });
    }

    if (validLeadsToSave.length === 0) {
        return { success: true, count: 0, leads: [], message: "All discovered leaders were previously saved or excluded." };
    }

    // 4. Save to Firestore in subcollection `users/{uid}/networking_leads`
    const batch = db.batch();
    for (const lead of validLeadsToSave) {
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
            status: "discovered",
            discoveredAt: admin.firestore.FieldValue.serverTimestamp()
        });
    }
    await batch.commit();

    console.log(`[NetworkingDiscovery] Successfully saved ${validLeadsToSave.length} networking leads for user ${uid}.`);

    // 5. Send User Push Notification
    try {
        const notifTitle = "🤝 New Tech Leaders Discovered!";
        const notifBody = `Found ${validLeadsToSave.length} Engineering Managers & Hiring Leads in ${targetLocations[0] || 'Bengaluru'} ready for outreach.`;
        await logNotification(uid, notifTitle, notifBody, "JOB_ASSISTANT");
    } catch (e) {
        console.warn("[NetworkingDiscovery] Failed to log push notification:", e);
    }

    return {
        success: true,
        count: validLeadsToSave.length,
        leads: validLeadsToSave,
        message: `Discovered ${validLeadsToSave.length} new tech leaders ready for 1-tap LinkedIn/Email outreach!`
    };
}

/**
 * Scheduled dispatcher called daily from masterHalfHourlyRunner (e.g. at 11:30 AM IST)
 */
export async function internalNetworkingDiscoveryDispatcher(): Promise<void> {
    console.log("[internalNetworkingDiscoveryDispatcher] Starting daily leadership networking scan...");
    try {
        const usersSnap = await db.collection("users").get();
        const eligibleUids: string[] = [];

        for (const doc of usersSnap.docs) {
            const data = doc.data() || {};
            const uid = doc.id;

            // Must have Tavily and Gemini keys configured
            const userApiKeys = data.userApiKeys || {};
            const hasKeys = !!((userApiKeys.tavilyApiKey || data.tavilyApiKey) && (userApiKeys.geminiApiKey || data.geminiApiKey));
            if (!hasKeys) continue;

            // Check if job discovery is enabled
            if (data.autoApplySettings?.enabled === false) continue;

            eligibleUids.push(uid);
        }

        console.log(`[internalNetworkingDiscoveryDispatcher] Eligible users for networking discovery: ${eligibleUids.length}`);

        for (const uid of eligibleUids) {
            try {
                await discoverNetworkingLeadsForUser(uid, { isManualTrigger: false });
            } catch (err: any) {
                console.error(`[internalNetworkingDiscoveryDispatcher] Error for user ${uid}:`, err.message || err);
            }
            // Small delay between users
            await new Promise(res => setTimeout(res, 3000));
        }
    } catch (e: any) {
        console.error("[internalNetworkingDiscoveryDispatcher] Error running daily networking dispatcher:", e.message || e);
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
            throw new functions.https.HttpsError("internal", err.message || "Failed to discover networking leads.");
        }
    }
);
