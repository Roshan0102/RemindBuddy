const test = require('firebase-functions-test')({
    projectId: 'remindbuddy-b68f9'
}, '../serviceAccountKey.json');

const myFunctions = require('./lib/index.js');

async function run() {
    console.log("-----------------------------------------");
    console.log("⏰ Manually Triggering Daily Shift Reminder Test...");
    const wrapped = test.wrap(myFunctions.dailyShiftReminder);
    await wrapped({});
    console.log("✅ Shift Reminder Test Completed.");
    test.cleanup();
}

run().then(() => {
    process.exit(0);
}).catch((e) => {
    console.error("❌ Shift Reminder Test Failed:", e);
    process.exit(1);
});
