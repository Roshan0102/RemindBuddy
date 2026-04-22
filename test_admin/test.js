const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function exploreSubcollections() {
    try {
        const uid = 'ZVF3IBIV31ZPjUUCNIhXJTeQOqy1';
        console.log(`\n--- SUBCOLLECTIONS FOR users/${uid} ---`);
        const docRef = db.collection('users').doc(uid);
        const subcollections = await docRef.listCollections();

        for (let sub of subcollections) {
            console.log(`📂 Subcollection: ${sub.id}`);
            const snap = await sub.limit(1).get();
            if (!snap.empty) {
                console.log(`   Sample Data from ${sub.id}:`, snap.docs[0].data());
            }
        }
    } catch (error) {
        console.error('Error:', error.message);
    } finally {
        process.exit(0);
    }
}

exploreSubcollections();
