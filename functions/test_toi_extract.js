const axios = require('axios');
const cheerio = require('cheerio');
const fs = require('fs');

async function testExtraction() {
    const data = fs.readFileSync('toi.html', 'utf8');
    const $ = cheerio.load(data);
    let finalPrice = null;

    $("h2").each((i, el) => {
        if ($(el).text().toLowerCase().includes("22k gold price trend")) {
            console.log("Found target header:", $(el).text());
            let wrapper = $(el).parent();
            // Go up until we find the root container, then go to next sibling
            while (wrapper.length && !wrapper.next().hasClass('custom-table')) {
                wrapper = wrapper.parent();
                if (wrapper.next().find('.custom-table').length > 0) {
                    wrapper = wrapper.next();
                    break;
                }
            }

            // From wrapper, dive into .Ge2sP > .fCMra
            const rows = wrapper.find('.custom-table .Ge2sP .fCMra');
            if (rows.length > 0) {
                const firstRow = rows.first();
                const cells = firstRow.find('.Gy41U');
                if (cells.length > 1) {
                    const weight = $(cells[0]).text().trim();
                    const priceText = $(cells[1]).text().trim();
                    console.log(`Weight: ${weight}, PriceText: ${priceText}`);
                    if (weight === '1' || weight.includes('1')) {
                        const num = parseInt(priceText.replace(/[^0-9]/g, ''), 10);
                        if (num > 1000) {
                            finalPrice = num;
                            console.log("SUCCESS! Extracted Value:", finalPrice);
                        }
                    }
                }
            }
        }
    });
}
testExtraction();
