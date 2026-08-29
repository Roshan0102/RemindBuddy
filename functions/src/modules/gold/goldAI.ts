import * as functions from "firebase-functions";
import axios from "axios";
import * as moment from "moment-timezone";
import { admin, db } from "../../config/firebase";
import { fetchLatestGoldNews } from "./goldScrapers";

export async function runGoldAIPredictionInternal(): Promise<any> {
    const nowIST = moment().tz('Asia/Kolkata');
    const todayStr = nowIST.format('YYYY-MM-DD');

    // Deduplication check: if AI forecast was already generated today, reuse it unless forced
    const latestDoc = await db.collection("gold_ai_insights").doc("latest").get();
    if (latestDoc.exists) {
        const latestData = latestDoc.data();
        if (latestData && latestData.timestamp) {
            const latestTime = moment(latestData.timestamp).tz('Asia/Kolkata');
            if (latestTime.format('YYYY-MM-DD') === todayStr) {
                console.log(`[GoldAIPrediction] 11:00 AM AI Market Forecast already generated for today (${todayStr}). Skipping duplicate run.`);
                return latestData;
            }
        }
    }

    // 1. Fetch Gemini API key from Firestore
    const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
    let apiKey = "";
    if (configDoc.exists) {
        apiKey = configDoc.data()?.apiKey || "";
    }
    if (!apiKey) {
        throw new Error('Gemini API key is not configured in admin console.');
    }

    // 2. Fetch recent gold prices (last 15 records)
    const priceSnap = await db.collection("global_gold_prices").orderBy("timestamp", "desc").limit(15).get();
    const priceHistory: any[] = [];
    priceSnap.forEach(d => {
        const val = d.data();
        priceHistory.push({
            date: val.date,
            price: val.price,
            priceChange: val.priceChange,
            source: val.source
        });
    });

    // 3. Fetch latest news from Google News RSS using fetchLatestGoldNews helper
    const newsItems = await fetchLatestGoldNews();

    // 4. Prepare prompt for Gemini
    const currentPriceInfo = priceHistory.length > 0 ? priceHistory[0] : null;
    const prompt = `You are a financial analyst specializing in precious metals, especially Gold rates in India.
Analyze the following recent historical 22K gold prices (per 2 grams or current units) and the latest gold market news headlines.

CRITICAL INSTRUCTIONS:
- You must carefully analyze only active real-time events and occurrences reported in the provided latest gold news headlines and price history.
- Specifically mention US economic data (like CPI/inflation), Federal Reserve decisions, statements from major banks (like JPMorgan, Goldman Sachs), or geopolitical tensions/wars ONLY if they are actually present and reported in the provided news headlines. Do not write generic template sentences about them, and do not mention them if they are not actively happening (do not say "no CPI data was released" or "no war tensions exist").
- Ensure your predictionRationale is a concise, summarized explanation containing all key aspects, but it MUST be strictly under 1000 characters in total (including spaces). 

Your output must be written in very simple, plain, and easy-to-understand English. 
CRITICAL: Do NOT use difficult financial jargon (like 'bearish', 'bullish', 'consolidation', 'correction') without immediately explaining them in extremely simple terms. For example, instead of 'market is bearish', write 'prices are likely to fall (bearish)'. Keep explanations very simple.

Provide:
1. Market Sentiment: "bullish" (upward trend/prices rising), "bearish" (downward trend/prices dropping), or "neutral".
2. Sentiment Score: An integer from -100 (extremely bearish/falling) to 100 (extremely bullish/rising).
3. Sentiment Summary: A concise, 1-2 sentence summary of what is driving this sentiment using simple English.
4. Predicted Trend: "upward", "downward", or "stable" for the next 1-3 days.
5. Predicted Price Range: A realistic price range (e.g. "13,100 - 13,300") in the same format/currency unit as the input price (the current latest price is ${currentPriceInfo ? currentPriceInfo.price : 'unknown'}).
6. Prediction Rationale: A summarized explanation of why you predict this trend. Keep it concise, containing every important driver (referencing specific news events, inflation, or geopolitical factors only if they are actively reported in the news), but strictly under 1000 characters (including spaces).

Input Data:
Recent Price History (latest first):
${JSON.stringify(priceHistory, null, 2)}

Latest Gold News Headlines:
${JSON.stringify(newsItems, null, 2)}

Respond ONLY with a JSON object matching this schema:
{
  "sentiment": "bullish" | "bearish" | "neutral",
  "sentimentScore": number,
  "sentimentSummary": "string",
  "predictedTrend": "upward" | "downward" | "stable",
  "predictedPriceRange": "string",
  "predictionRationale": "string"
}`;

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
    const payload = {
        contents: [
            {
                parts: [
                    { text: prompt }
                ]
            }
        ],
        generationConfig: {
            responseMimeType: "application/json",
            responseSchema: {
                type: "OBJECT",
                properties: {
                    sentiment: { type: "STRING", description: "bullish, bearish, or neutral" },
                    sentimentScore: { type: "INTEGER", description: "-100 to 100 score" },
                    sentimentSummary: { type: "STRING" },
                    predictedTrend: { type: "STRING", description: "upward, downward, or stable" },
                    predictedPriceRange: { type: "STRING" },
                    predictionRationale: { type: "STRING", description: "Summarized rationale, strictly under 1000 characters" }
                },
                required: ["sentiment", "sentimentScore", "sentimentSummary", "predictedTrend", "predictedPriceRange", "predictionRationale"]
            }
        }
    };

    let attempts = 0;
    const maxAttempts = 3;
    let lastError: any = null;

    while (attempts < maxAttempts) {
        try {
            attempts++;
            console.log(`Calling Gemini API for market forecast prediction (attempt ${attempts}/${maxAttempts})...`);
            const response = await axios.post(url, payload, {
                headers: { 'Content-Type': 'application/json' },
                timeout: 60000
            });

            const candidates = response.data?.candidates;
            if (!candidates || candidates.length === 0) {
                throw new Error('No response candidates returned from Gemini API.');
            }

            const textResponse = candidates[0].content?.parts[0]?.text;
            if (!textResponse) {
                throw new Error('Empty content returned from Gemini API.');
            }

            const parsedResult = JSON.parse(textResponse);
            
            // 6. Store the result in Firestore
            const nowIST = moment().tz('Asia/Kolkata');
            const timestampStr = nowIST.toISOString();
            const docId = timestampStr.replace(/[:.]/g, '-');
            
            const insightData = {
                ...parsedResult,
                news: newsItems,
                priceHistoryAnalyzed: priceHistory,
                timestamp: timestampStr,
                createdAt: admin.firestore.FieldValue.serverTimestamp()
            };

            await db.collection("gold_ai_insights").doc(docId).set(insightData);
            await db.collection("gold_ai_insights").doc("latest").set(insightData);

            return insightData;
        } catch (error: any) {
            lastError = error;
            console.error(`Attempt ${attempts} failed for market forecast:`, error.message);
            if (attempts < maxAttempts) {
                const backoffMs = attempts * 10000;
                console.log(`Waiting ${backoffMs / 1000}s before retrying...`);
                await new Promise(resolve => setTimeout(resolve, backoffMs));
            }
        }
    }

    throw lastError || new Error("Failed to generate gold AI insights after maximum attempts.");
}

export const generateGoldAIInsights = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    try {
        return await runGoldAIPredictionInternal();
    } catch (error: any) {
        console.error("generateGoldAIInsights Error:", error.message);
        throw new functions.https.HttpsError('internal', error.message || "Failed to generate gold AI insights.");
    }
});

export async function generateGoldChitRecommendation(apiKey: string, priceHistory: any[], newsItems: any[]): Promise<{ recommendation: string, shortReason: string, fullAnalysis: string }> {
    const nowIST = moment().tz('Asia/Kolkata');
    const dayOfMonth = nowIST.date();
    const currentMonthName = nowIST.format('MMMM YYYY');
    const currentPriceStr = priceHistory.length > 0 ? `₹${priceHistory[0].price}` : 'unknown';

    // Override advice if it is between 26th and the end of the month
    if (dayOfMonth >= 26) {
        return {
            recommendation: "WAIT",
            shortReason: "Chit payment window closed. Next month-uku 1st lendhu pay pannunga.",
            fullAnalysis: "Monthly gold chit payment cycle (1st - 25th) ippo closed. Next month window 1st date thaan open aagum. Adhuvarai wait pannunga."
        };
    }

    const prompt = `You are a financial advisor helping an investor who deposits ₹10,000 monthly in a gold chit.
The chit payment must be made between the 1st and the 25th of every month. The chit company purchases gold on the exact day the payment is received.
Your goal is to recommend whether the investor should pay today to lock in today's gold rate, or wait for a potentially lower rate later in the month (up to the 25th).

Current Date: ${nowIST.format('YYYY-MM-DD')} (Day ${dayOfMonth} of ${currentMonthName})
Current Gold Price: ${currentPriceStr}

Recent Price History (latest first):
${JSON.stringify(priceHistory, null, 2)}

Latest Gold News Headlines:
${JSON.stringify(newsItems, null, 2)}

Task:
Determine if today is a good day to buy (i.e. we are at or near a short-term low, or prices are expected to rise significantly before the 25th) or if they should wait.
Write the 'shortReason' and 'fullAnalysis' in clear, friendly Tanglish (Tamil language written using the English/Latin alphabet, mixing Tamil and English naturally. E.g., 'Iniku gold price romba low-ah iruku, pay pannalam!' or 'Price inum kuraiyuradhuku chance iruku, so waiting list la irunga.').
Do NOT use Tamil script (characters like தமிழ்), only use English letters.

Respond ONLY with a JSON object matching this schema:
{
  "recommendation": "BUY" | "WAIT",
  "shortReason": "string (A concise notification/alert message in Tanglish, max 80 characters, summarizing the recommendation. E.g., 'Iniku rate low-ah iruku, pay pannunga!' or 'Price high-ah iruku, konjam wait pannalam.')",
  "fullAnalysis": "string (A detailed 2-3 sentence analysis in Tanglish explaining why, referencing the trend or news.)"
}`;

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`;
    const payload = {
        contents: [
            {
                parts: [
                    { text: prompt }
                ]
            }
        ],
        generationConfig: {
            responseMimeType: "application/json",
            responseSchema: {
                type: "OBJECT",
                properties: {
                    recommendation: { type: "STRING" },
                    shortReason: { type: "STRING" },
                    fullAnalysis: { type: "STRING" }
                },
                required: ["recommendation", "shortReason", "fullAnalysis"]
            }
        }
    };

    const response = await axios.post(url, payload, {
        headers: { 'Content-Type': 'application/json' },
        timeout: 60000
    });

    const candidates = response.data?.candidates;
    if (!candidates || candidates.length === 0) {
        throw new Error('No response candidates returned from Gemini API.');
    }

    const textResponse = candidates[0].content?.parts[0]?.text;
    if (!textResponse) {
        throw new Error('Empty content returned from Gemini API.');
    }

    return JSON.parse(textResponse);
}

export const generateGoldChitAdvice = functions.runWith({ timeoutSeconds: 120, memory: "1GB" }).https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    try {
        const configDoc = await db.collection("admin_creds").doc("gemini_config").get();
        let apiKey = "";
        if (configDoc.exists) {
            apiKey = configDoc.data()?.apiKey || "";
        }
        if (!apiKey) {
            throw new Error('Gemini API key is not configured in admin console.');
        }

        // 1. Fetch prices
        const priceSnap = await db.collection("global_gold_prices").orderBy("timestamp", "desc").limit(15).get();
        const priceHistory: any[] = [];
        priceSnap.forEach(d => {
            const val = d.data();
            priceHistory.push({
                date: val.date,
                price: val.price,
                priceChange: val.priceChange,
                source: val.source
            });
        });

        // 2. Fetch news
        const newsItems = await fetchLatestGoldNews();

        const advice = await generateGoldChitRecommendation(apiKey, priceHistory, newsItems);
        
        const nowIST = moment().tz('Asia/Kolkata');
        const timestampStr = nowIST.toISOString();
        const docData = {
            ...advice,
            timestamp: timestampStr,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        };

        await db.collection("gold_chit_advice").doc("latest").set(docData);
        await db.collection("gold_chit_advice").doc(timestampStr.replace(/[:.]/g, '-')).set(docData);

        return docData;
    } catch (error: any) {
        console.error("generateGoldChitAdvice Error:", error.message);
        throw new functions.https.HttpsError('internal', error.message || "Failed to generate gold chit advice.");
    }
});
