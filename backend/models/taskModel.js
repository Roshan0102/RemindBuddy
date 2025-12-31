const db = require('../config/db');

const TaskModel = {
    getAll: () => {
        return new Promise((resolve, reject) => {
            db.all("SELECT * FROM tasks ORDER BY date, time", [], (err, rows) => {
                if (err) reject(err);
                else resolve(rows);
            });
        });
    },

    getByDate: (date) => {
        return new Promise((resolve, reject) => {
            db.all("SELECT * FROM tasks WHERE date = ?", [date], (err, rows) => {
                if (err) reject(err);
                else resolve(rows);
            });
        });
    },

    getById: (id) => {
        return new Promise((resolve, reject) => {
            db.get("SELECT * FROM tasks WHERE id = ?", [id], (err, row) => {
                if (err) reject(err);
                else resolve(row);
            });
        });
    },

    create: (taskData) => {
        return new Promise((resolve, reject) => {
            const { title, description, date, time, repeat } = taskData;
            const createdAt = new Date().toISOString();
            const query = `INSERT INTO tasks (title, description, date, time, repeat, createdAt) VALUES (?, ?, ?, ?, ?, ?)`;

            db.run(query, [title, description, date, time, repeat || 'none', createdAt], function (err) {
                if (err) reject(err);
                else {
                    // 'this.lastID' contains the ID of the inserted row
                    resolve({ id: this.lastID, ...taskData, createdAt });
                }
            });
        });
    },

    update: (id, taskData) => {
        return new Promise((resolve, reject) => {
            const { title, description, date, time, repeat } = taskData;
            const query = `UPDATE tasks SET title = ?, description = ?, date = ?, time = ?, repeat = ? WHERE id = ?`;

            db.run(query, [title, description, date, time, repeat, id], function (err) {
                if (err) reject(err);
                else if (this.changes === 0) resolve(null); // No row updated
                else resolve({ id, ...taskData });
            });
        });
    },

    delete: (id) => {
        return new Promise((resolve, reject) => {
            db.run("DELETE FROM tasks WHERE id = ?", [id], function (err) {
                if (err) reject(err);
                else if (this.changes === 0) resolve(null);
                else resolve({ id });
            });
        });
    }
};

module.exports = TaskModel;
