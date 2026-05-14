const admin = require('firebase-admin');
admin.initializeApp({
  projectId: 'remindbuddy-b68f9'
});
const db = admin.firestore();

async function checkDoc() {
  const users = await db.collection('users').get();
  for (const user of users.docs) {
    const reminders = await user.ref.collection('calendar_reminders').where('status', '==', 'scheduled').get();
    for (const rem of reminders.docs) {
      console.log(`User: ${user.id}, Doc: ${rem.id}`);
      console.log(JSON.stringify(rem.data(), null, 2));
    }
  }
}

checkDoc();
