const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkGoldPrices() {
    try {
        const snap = await db.collection('global_gold_prices').orderBy('timestamp', 'desc').limit(5).get();
        console.log('Recent Gold Prices:');
        snap.forEach(doc => {
            console.log(doc.id, '=>', doc.data());
        });
    } catch (e) {
        console.error('Error:', e);
    } finally {
        process.exit(0);
    }
}

checkGoldPrices();
