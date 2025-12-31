const sqlite3 = require('sqlite3').verbose();
const path = require('path');

// Connect to SQLite database
// It will create 'tasks.db' file in the backend directory if it doesn't exist
const dbPath = path.resolve(__dirname, '../tasks.db');
const db = new sqlite3.Database(dbPath, (err) => {
    if (err) {
        console.error('Error connecting to database:', err.message);
    } else {
        console.log('Connected to the SQLite database.');
        initDb();
    }
});

function initDb() {
    const createTableQuery = `
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT,
            date TEXT NOT NULL,
            time TEXT NOT NULL,
            repeat TEXT DEFAULT 'none',
            createdAt TEXT
        )
    `;

    db.run(createTableQuery, (err) => {
        if (err) {
            console.error('Error creating table:', err.message);
        } else {
            console.log('Tasks table ready.');
        }
    });
}

module.exports = db;
