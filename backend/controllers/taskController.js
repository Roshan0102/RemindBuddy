const TaskModel = require('../models/taskModel');

exports.getAllTasks = (req, res) => {
    const { date } = req.query;
    if (date) {
        const tasks = TaskModel.getByDate(date);
        return res.json(tasks);
    }
    const tasks = TaskModel.getAll();
    res.json(tasks);
};

exports.getTaskById = (req, res) => {
    const task = TaskModel.getById(req.params.id);
    if (!task) {
        return res.status(404).json({ message: 'Task not found' });
    }
    res.json(task);
};

exports.createTask = (req, res) => {
    const { title, date, time } = req.body;
    if (!title || !date || !time) {
        return res.status(400).json({ message: 'Title, date, and time are required' });
    }
    const newTask = TaskModel.create(req.body);
    res.status(201).json(newTask);
};

exports.updateTask = (req, res) => {
    const updatedTask = TaskModel.update(req.params.id, req.body);
    if (!updatedTask) {
        return res.status(404).json({ message: 'Task not found' });
    }
    res.json(updatedTask);
};

exports.deleteTask = (req, res) => {
    const deletedTask = TaskModel.delete(req.params.id);
    if (!deletedTask) {
        return res.status(404).json({ message: 'Task not found' });
    }
    res.json({ message: 'Task deleted successfully' });
};
