import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../models/task.dart';
import '../models/task.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';

class AddTaskScreen extends StatefulWidget {
  final DateTime? selectedDate;

  const AddTaskScreen({super.key, this.selectedDate});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late DateTime _date;
  late TimeOfDay _time;
  String _repeat = 'none';
  bool _isAnnoying = false;


  @override
  void initState() {
    super.initState();
    _date = widget.selectedDate ?? DateTime.now();
    _time = TimeOfDay.now();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _date) {
      setState(() {
        _date = picked;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext builder) {
        return Container(
          height: MediaQuery.of(context).copyWith().size.height / 3,
          color: Colors.white,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  TextButton(
                    child: const Text('Done'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(() {}); // Refresh UI
                    },
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: DateTime(
                    DateTime.now().year,
                    DateTime.now().month,
                    DateTime.now().day,
                    _time.hour,
                    _time.minute,
                  ),
                  onDateTimeChanged: (DateTime newDateTime) {
                    setState(() {
                      _time = TimeOfDay.fromDateTime(newDateTime);
                    });
                  },
                  use24hFormat: false,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveTask() async {
    if (_formKey.currentState!.validate()) {
      final String dateStr = DateFormat('yyyy-MM-dd').format(_date);
      final String timeStr = '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

      final newTask = Task(
        title: _titleController.text,
        description: _descriptionController.text,
        date: dateStr,
        time: timeStr,
        repeat: _repeat,
        isAnnoying: _isAnnoying,
        // Sync fields default to unsynced
      );

      // 1. Save Locally (Offline First)
      try {
        final storage = StorageService(); // Singleton
        await storage.insertTask(newTask);
        
        // 2. Trigger Sync (Best Effort)
        // Access PB via AuthService
        final auth = AuthService();
        final syncService = SyncService(auth.pb);
        syncService.syncTasks(); // Fire and forget
        
        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save task: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Task')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text('Date: ${DateFormat('yyyy-MM-dd').format(_date)}'),
                  ),
                  TextButton(
                    onPressed: () => _selectDate(context),
                    child: const Text('Select Date'),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text('Time: ${_time.format(context)}'),
                  ),
                  TextButton(
                    onPressed: () => _selectTime(context),
                    child: const Text('Select Time'),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                value: _repeat.startsWith('custom') ? 'custom' : _repeat,
                decoration: const InputDecoration(labelText: 'Repeat'),
                items: ['none', 'daily', 'weekly', 'monthly', 'custom']
                    .map((label) => DropdownMenuItem(
                          value: label,
                          child: Text(label == 'custom' ? 'Custom (Every X Days)' : label),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    if (value == 'custom') {
                      _repeat = 'custom:10'; // Default to 10 days
                    } else {
                      _repeat = value!;
                    }
                  });
                },
              ),
              if (_repeat.startsWith('custom'))
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: TextFormField(
                    initialValue: _repeat.split(':')[1],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Repeat every (days)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _repeat = 'custom:$value';
                      });
                    },
                  ),
                ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Annoying Alarm (Nag Mode)'),
                subtitle: const Text('Keeps reminding until you say YES'),
                value: _isAnnoying,
                onChanged: (bool value) {
                  setState(() {
                    _isAnnoying = value;
                  });
                },
                secondary: const Icon(Icons.alarm_on, color: Colors.red),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveTask,
                child: const Text('Save Task'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
