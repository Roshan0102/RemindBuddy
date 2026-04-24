
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../services/storage_service.dart';

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
  bool _isSaving = false;


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
      setState(() { _isSaving = true; });
      final String dateStr = DateFormat('yyyy-MM-dd').format(_date);
      final String timeStr = '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

      try {
        final storage = StorageService();
        await storage.insertCalendarReminder(
          _titleController.text, 
          _descriptionController.text, 
          dateStr, 
          timeStr
        );
        
        if (mounted) {
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          setState(() { _isSaving = false; });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save reminder: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Reminder')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Doctor Appointment',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Add some details...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.calendar_today),
                        title: Text('Date: ${DateFormat('yyyy-MM-dd').format(_date)}'),
                        trailing: const Icon(Icons.edit),
                        onTap: () => _selectDate(context),
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.access_time),
                        title: Text('Time: ${_time.format(context)}'),
                        trailing: const Icon(Icons.edit),
                        onTap: () => _selectTime(context),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isSaving ? null : _saveTask,
                  child: _isSaving 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : const Text('Schedule Reminder', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
