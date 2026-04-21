const axios = require('axios');
const fs = require('fs');

async function testTOI() {
    const url = 'https://timesofindia.indiatimes.com/business/gold-rates-today/gold-price-in-chennai';
    try {
        const { data } = await axios.get(url, {
            headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            }
        });

        fs.writeFileSync('toi.html', data);
        console.log("HTML dumped to toi.html");
    } catch (e) {
        console.error("Error fetching TOI:", e.message);
    }
}
testTOI();
