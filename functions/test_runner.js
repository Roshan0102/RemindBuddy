const test = require('firebase-functions-test')();
process.env.GOOGLE_APPLICATION_CREDENTIALS = '../serviceAccountKey.json';

const myFunctions = require('./lib/index.js');

async function play() {
    const wrapped = test.wrap(myFunctions.scheduledGoldFetch);
    console.log("🚀 Firing Cloud Function emulator hook...");
    await wrapped({});
    test.cleanup();
}

play().then(() => {
    console.log("✅ Emulator Test Closed.");
    process.exit(0);
}).catch((e) => {
    console.error("❌ Emulator Test Failed:", e);
    process.exit(1);
});
