const TaskModel = require('../models/taskModel');

exports.getAllTasks = async (req, res) => {
    try {
        const { date } = req.query;
        let tasks;
        if (date) {
            tasks = await TaskModel.getByDate(date);
        } else {
            tasks = await TaskModel.getAll();
        }
        res.json(tasks);
    } catch (err) {
        res.status(500).json({ message: err.message });
    }
};

exports.getTaskById = async (req, res) => {
    try {
        const task = await TaskModel.getById(req.params.id);
        if (!task) {
            return res.status(404).json({ message: 'Task not found' });
        }
        res.json(task);
    } catch (err) {
        res.status(500).json({ message: err.message });
    }
};

exports.createTask = async (req, res) => {
    try {
        const { title, date, time } = req.body;
        if (!title || !date || !time) {
            return res.status(400).json({ message: 'Title, date, and time are required' });
        }
        const newTask = await TaskModel.create(req.body);
        res.status(201).json(newTask);
    } catch (err) {
        res.status(500).json({ message: err.message });
    }
};

exports.updateTask = async (req, res) => {
    try {
        const updatedTask = await TaskModel.update(req.params.id, req.body);
        if (!updatedTask) {
            return res.status(404).json({ message: 'Task not found' });
        }
        res.json(updatedTask);
    } catch (err) {
        res.status(500).json({ message: err.message });
    }
};

exports.deleteTask = async (req, res) => {
    try {
        const deletedTask = await TaskModel.delete(req.params.id);
        if (!deletedTask) {
            return res.status(404).json({ message: 'Task not found' });
        }
        res.json({ message: 'Task deleted successfully' });
    } catch (err) {
        res.status(500).json({ message: err.message });
    }
};
