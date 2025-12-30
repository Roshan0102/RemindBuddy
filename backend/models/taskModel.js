// This is a temporary in-memory storage.
// In the future, replace this with SQLite or MongoDB connection.

let tasks = [];
let currentId = 1;

const TaskModel = {
    getAll: () => tasks,

    getById: (id) => tasks.find(t => t.id === parseInt(id)),

    create: (taskData) => {
        const newTask = {
            id: currentId++,
            title: taskData.title,
            description: taskData.description,
            date: taskData.date, // Format: YYYY-MM-DD
            time: taskData.time, // Format: HH:MM
            repeat: taskData.repeat || 'none', // none, daily, weekly, monthly
            createdAt: new Date().toISOString()
        };
        tasks.push(newTask);
        return newTask;
    },

    update: (id, taskData) => {
        const index = tasks.findIndex(t => t.id === parseInt(id));
        if (index !== -1) {
            tasks[index] = { ...tasks[index], ...taskData };
            return tasks[index];
        }
        return null;
    },

    delete: (id) => {
        const index = tasks.findIndex(t => t.id === parseInt(id));
        if (index !== -1) {
            const deletedTask = tasks[index];
            tasks.splice(index, 1);
            return deletedTask;
        }
        return null;
    },

    // Helper to get tasks for a specific date
    getByDate: (date) => {
        return tasks.filter(t => t.date === date);
    }
};

module.exports = TaskModel;
