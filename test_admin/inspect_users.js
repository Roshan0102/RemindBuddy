const admin = require('firebase-admin');
const serviceAccount = require('../serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function inspectUsers() {
    try {
        console.log('=== Sample from users collection ===');
        const usersSnap = await db.collection('users').limit(5).get();
        usersSnap.forEach(doc => {
            console.log(`Doc ID: ${doc.id}`);
            console.log(JSON.stringify(doc.data(), null, 2));
        });

        console.log('\n=== Sample from usernames collection ===');
        const usernamesSnap = await db.collection('usernames').limit(5).get();
        usernamesSnap.forEach(doc => {
            console.log(`Doc ID (Username): ${doc.id}`);
            console.log(JSON.stringify(doc.data(), null, 2));
        });
    } catch (e) {
        console.error(e);
    } finally {
        process.exit(0);
    }
}

inspectUsers();
