const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function checkIds() {
    try {
        console.log('=== gold_ai_insights Document IDs ===');
        const aiSnap = await db.collection('gold_ai_insights').get();
        aiSnap.forEach(doc => {
            console.log(`- ${doc.id}`);
        });

        console.log('\n=== gold_chit_advice Document IDs ===');
        const chitSnap = await db.collection('gold_chit_advice').get();
        chitSnap.forEach(doc => {
            console.log(`- ${doc.id}`);
        });
    } catch (e) {
        console.error(e);
    } finally {
        process.exit(0);
    }
}

checkIds();
