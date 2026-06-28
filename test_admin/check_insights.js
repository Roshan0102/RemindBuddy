const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkInsightsAndAdvice() {
    try {
        console.log('=== Checking gold_ai_insights collection ===');
        const aiSnap = await db.collection('gold_ai_insights').get();
        aiSnap.forEach(doc => {
            console.log(`Doc ID: ${doc.id}`);
            console.log(JSON.stringify(doc.data(), null, 2));
            console.log('---------------------------------------------');
        });

        console.log('\n=== Checking gold_chit_advice collection ===');
        const chitSnap = await db.collection('gold_chit_advice').get();
        chitSnap.forEach(doc => {
            console.log(`Doc ID: ${doc.id}`);
            console.log(JSON.stringify(doc.data(), null, 2));
            console.log('---------------------------------------------');
        });
    } catch (e) {
        console.error('Error reading collections:', e);
    } finally {
        process.exit(0);
    }
}

checkInsightsAndAdvice();
