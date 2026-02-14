const puppeteer = require('puppeteer');

(async () => {
    console.log('🚀 Launching Gold Price Checker...');
    console.log('Target URL: https://www.goodreturns.in/gold-rates/chennai.html');

    const browser = await puppeteer.launch({
        headless: "new",
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });

    try {
        const page = await browser.newPage();

        // Set user agent to match the app (Mobile Android)
        await page.setUserAgent('Mozilla/5.0 (Linux; Android 10; SM-G973F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36');

        console.log('🌍 Navigating to page...');
        await page.goto('https://www.goodreturns.in/gold-rates/chennai.html', {
            waitUntil: 'domcontentloaded',
            timeout: 60000
        });

        console.log('✅ Page loaded! Injecting extraction script...');
        console.log('--------------------------------------------------');

        // Inject the script to run ALL methods and collect results
        const results = await page.evaluate(() => {
            const report = {};

            // ==========================================
            // METHOD 1: XPath (Primary)
            // ==========================================
            try {
                const xpath = '//*[@id="lp-root"]/div/div[2]/div/div[2]/div/div[3]/div[2]/div[2]/div/div[1]/span[1]/span[1]';
                const result = document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);
                const node = result.singleNodeValue;
                if (node && node.innerText) {
                    report.method1_xpath = {
                        status: '✅ SUCCESS',
                        extracted_text: node.innerText.trim(),
                        parsed_price: null
                    };
                    // Try parsing
                    const match = node.innerText.match(/\d{1,3}(,\d{3})+|\d{4,}/);
                    if (match) report.method1_xpath.parsed_price = match[0];
                } else {
                    report.method1_xpath = {
                        status: '❌ FAILED',
                        reason: 'Element not found by XPath'
                    };
                }
            } catch (e) {
                report.method1_xpath = { status: '⚠️ ERROR', message: e.toString() };
            }

            // ==========================================
            // METHOD 2: Inspection (Fallback 1)
            //Selector: [class*="price"], [class*="rate"]...
            // ==========================================
            try {
                const containers = document.querySelectorAll('[class*="price"], [class*="rate"], [class*="Price"], [class*="Rate"]');
                const matches = [];
                for (const c of containers) {
                    const text = c.innerText || c.textContent;
                    // Validates price format with 4+ digits
                    if (text && (text.includes('₹') || text.includes('Rs')) && text.match(/\d{1,3}(,\d{3})+|\d{4,}/)) {
                        matches.push(text.trim());
                    }
                }
                report.method2_inspection = matches.length > 0
                    ? { status: '✅ SUCCESS', count: matches.length, best_match: matches[0], all_matches: matches.slice(0, 3) }
                    : { status: '❌ FAILED', reason: 'No matching containers found' };
            } catch (e) {
                report.method2_inspection = { status: '⚠️ ERROR', message: e.toString() };
            }

            // ==========================================
            // METHOD 3: Heading Search (Fallback 2)
            // Looks for h2 "Today's Gold Rate" -> parent -> .white-space-nowrap
            // ==========================================
            try {
                const h2s = document.getElementsByTagName('h2');
                const matches = [];
                for (let i = 0; i < h2s.length; i++) {
                    if (h2s[i].innerText.includes("Today's Gold Rate") || h2s[i].innerText.includes("Gold Rate")) {
                        const parent = h2s[i].parentElement;
                        if (parent) {
                            const span = parent.querySelector('.white-space-nowrap');
                            if (span && span.innerText.match(/\d{1,3}(,\d{3})+|\d{4,}/)) {
                                matches.push(span.innerText.trim());
                            }
                        }
                    }
                }
                report.method3_heading = matches.length > 0
                    ? { status: '✅ SUCCESS', match: matches[0] }
                    : { status: '❌ FAILED', reason: 'No matching headings found' };
            } catch (e) {
                report.method3_heading = { status: '⚠️ ERROR', message: e.toString() };
            }

            // ==========================================
            // METHOD 4: Generic Search (Fallback 3)
            // Scans ALL spans/divs with .white-space-nowrap for ₹ pattern
            // ==========================================
            try {
                const spans = document.querySelectorAll('.white-space-nowrap, span, div');
                const matches = [];
                let count = 0;
                for (const span of spans) {
                    if (count++ > 5000) break; // Safety limit
                    const text = span.innerText || span.textContent;
                    if (text && (text.includes('₹') || text.includes('Rs')) && text.match(/\d{1,3}(,\d{3})+|\d{4,}/)) {
                        const cleanText = text.trim();
                        // Basic de-duplication
                        if (!matches.includes(cleanText) && cleanText.length < 50) {
                            matches.push(cleanText);
                        }
                    }
                }
                report.method4_generic = matches.length > 0
                    ? { status: '✅ SUCCESS', count: matches.length, samples: matches.slice(0, 5) }
                    : { status: '❌ FAILED', reason: 'No matching elements found' };
            } catch (e) {
                report.method4_generic = { status: '⚠️ ERROR', message: e.toString() };
            }

            return report;
        });

        console.log(JSON.stringify(results, null, 2));
        console.log('--------------------------------------------------');
        console.log('✅ Extraction complete!');

    } catch (error) {
        console.error('❌ Fatal Error:', error);
    } finally {
        await browser.close();
    }
})();
