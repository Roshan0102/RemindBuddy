
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/storage_service.dart';
import '../models/calendar_reminder.dart';

class AddTaskScreen extends StatefulWidget {
  final DateTime? selectedDate;
  final CalendarReminder? existingReminder;

  const AddTaskScreen({super.key, this.selectedDate, this.existingReminder});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _occurrencesController = TextEditingController();
  late DateTime _date;
  late TimeOfDay _time;
  bool _isSaving = false;
  bool _isRecurring = false;
  int _recurrenceValue = 1;
  String _recurrenceUnit = 'days';
  int? _occurrencesLimit;

  bool _snoozeEnabled = false;
  int _snoozeIntervalMinutes = 15;
  int _maxSnoozeCount = 3;

  List<Map<String, dynamic>> _approvedBuddies = [];
  bool _isLoadingBuddies = true;
  StreamSubscription? _buddiesSubscription;
  String? _myUid;
  final Set<String> _selectedRecipients = {};

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser?.uid;
    if (widget.existingReminder != null) {
      final r = widget.existingReminder!;
      _titleController.text = r.title;
      _descriptionController.text = r.description;
      _date = DateFormat('yyyy-MM-dd').parse(r.date);
      final timeParts = r.time.split(':');
      _time = TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      );
      _isRecurring = r.isRecurring;
      _recurrenceValue = r.recurrenceValue;
      _recurrenceUnit = r.recurrenceUnit;
      _occurrencesLimit = r.remainingOccurrences;
      _snoozeEnabled = r.snoozeEnabled;
      _snoozeIntervalMinutes = r.snoozeIntervalMinutes;
      _maxSnoozeCount = r.maxSnoozeCount;
      if (_occurrencesLimit != null) {
        _occurrencesController.text = _occurrencesLimit.toString();
      }
      if (_myUid != null) {
        _selectedRecipients.add(_myUid!);
      }
    } else {
      _date = widget.selectedDate ?? DateTime.now();
      _time = TimeOfDay.now();
      _snoozeEnabled = false;
      _snoozeIntervalMinutes = 15;
      _maxSnoozeCount = 3;
      if (_myUid != null) {
        _selectedRecipients.add(_myUid!);
      }
    }
    _loadBuddies();
  }

  void _loadBuddies() {
    _buddiesSubscription = StorageService().getApprovedBuddiesStream().listen((buddies) {
      if (mounted) {
        setState(() {
          _approvedBuddies = buddies;
          _isLoadingBuddies = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _buddiesSubscription?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _occurrencesController.dispose();
    super.dispose();
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
    if (widget.existingReminder == null && _selectedRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one recipient.')),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      setState(() { _isSaving = true; });
      final String dateStr = DateFormat('yyyy-MM-dd').format(_date);
      final String timeStr = '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

      try {
        final storage = StorageService();
        if (widget.existingReminder != null) {
          final updated = widget.existingReminder!.copyWith(
            title: _titleController.text,
            description: _descriptionController.text,
            date: dateStr,
            time: timeStr,
            isRecurring: _isRecurring,
            recurrenceValue: _recurrenceValue,
            recurrenceUnit: _recurrenceUnit,
            remainingOccurrences: _occurrencesLimit,
            status: 'pending',
            snoozeEnabled: _snoozeEnabled,
            snoozeIntervalMinutes: _snoozeIntervalMinutes,
            maxSnoozeCount: _maxSnoozeCount,
            currentSnoozeCount: 0,
          );
          await storage.updateCalendarReminder(updated);
        } else {
          for (final recipientUid in _selectedRecipients) {
            String? targetUsername;
            if (recipientUid != _myUid) {
              final buddy = _approvedBuddies.firstWhere(
                (b) => b['receiverUid'] == recipientUid,
                orElse: () => <String, dynamic>{},
              );
              targetUsername = buddy['receiverUsername'] as String?;
            }

            await storage.insertCalendarReminder(
              _titleController.text, 
              _descriptionController.text, 
              dateStr, 
              timeStr,
              isRecurring: _isRecurring,
              recurrenceValue: _recurrenceValue,
              recurrenceUnit: _recurrenceUnit,
              remainingOccurrences: _occurrencesLimit,
              targetUid: recipientUid == _myUid ? null : recipientUid,
              targetUsername: targetUsername,
              snoozeEnabled: _snoozeEnabled,
              snoozeIntervalMinutes: _snoozeIntervalMinutes,
              maxSnoozeCount: _maxSnoozeCount,
              currentSnoozeCount: 0,
            );
          }
        }
        
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
      appBar: AppBar(title: Text(widget.existingReminder != null ? 'Edit Reminder' : 'Add Reminder')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (widget.existingReminder == null && !_isLoadingBuddies) ...[
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recipients',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Who should receive this reminder notification?',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          title: const Text('Myself (You)'),
                          value: _selectedRecipients.contains(_myUid),
                          activeColor: Theme.of(context).primaryColor,
                          onChanged: (bool? checked) {
                            if (_myUid == null) return;
                            setState(() {
                              if (checked == true) {
                                _selectedRecipients.add(_myUid!);
                              } else {
                                if (_selectedRecipients.length > 1) {
                                  _selectedRecipients.remove(_myUid);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('At least one recipient must be selected.')),
                                  );
                                }
                              }
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_approvedBuddies.isNotEmpty) ...[
                          const Divider(),
                          ..._approvedBuddies.map((buddy) {
                            final buddyUid = buddy['receiverUid'] as String;
                            final buddyUsername = buddy['receiverUsername'] as String? ?? 'User';
                            return CheckboxListTile(
                              title: Text('@$buddyUsername'),
                              value: _selectedRecipients.contains(buddyUid),
                              activeColor: Theme.of(context).primaryColor,
                              onChanged: (bool? checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedRecipients.add(buddyUid);
                                  } else {
                                    if (_selectedRecipients.length > 1) {
                                      _selectedRecipients.remove(buddyUid);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('At least one recipient must be selected.')),
                                      );
                                    }
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
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
              const SizedBox(height: 16),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.withOpacity(0.15)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: const Text('Recurring Reminder', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text('Repeat this reminder at a custom interval'),
                        secondary: Icon(
                          _isRecurring ? Icons.repeat_one_on : Icons.repeat, 
                          color: _isRecurring ? Theme.of(context).primaryColor : Colors.grey
                        ),
                        value: _isRecurring,
                        onChanged: (bool value) {
                          setState(() {
                            _isRecurring = value;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_isRecurring) ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                initialValue: _recurrenceValue.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Every',
                                  hintText: 'e.g. 10',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _recurrenceValue = int.tryParse(val) ?? 1;
                                  });
                                },
                                validator: (value) {
                                  if (_isRecurring) {
                                    if (value == null || value.isEmpty) {
                                      return 'Required';
                                    }
                                    final n = int.tryParse(value);
                                    if (n == null || n <= 0) {
                                      return 'Must be > 0';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                value: _recurrenceUnit,
                                decoration: const InputDecoration(
                                  labelText: 'Unit',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'minutes', child: Text('Minutes')),
                                  DropdownMenuItem(value: 'hours', child: Text('Hours')),
                                  DropdownMenuItem(value: 'days', child: Text('Days')),
                                  DropdownMenuItem(value: 'weeks', child: Text('Weeks')),
                                  DropdownMenuItem(value: 'months', child: Text('Months')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _recurrenceUnit = val;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _occurrencesController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Number of occurrences (optional)',
                            hintText: 'e.g. 10 (Leave blank for infinite)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.pin),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _occurrencesLimit = int.tryParse(val);
                            });
                          },
                          validator: (value) {
                            if (_isRecurring && value != null && value.isNotEmpty) {
                              final n = int.tryParse(value);
                              if (n == null || n <= 0) {
                                return 'Must be a positive number';
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Text(
                            _occurrencesLimit == null
                                ? 'Will repeat every $_recurrenceValue ${_recurrenceValue == 1 ? (_recurrenceUnit == 'minutes' ? 'minute' : _recurrenceUnit == 'hours' ? 'hour' : _recurrenceUnit == 'days' ? 'day' : _recurrenceUnit == 'weeks' ? 'week' : 'month') : _recurrenceUnit} indefinitely after each completion.'
                                : 'Will repeat every $_recurrenceValue ${_recurrenceValue == 1 ? (_recurrenceUnit == 'minutes' ? 'minute' : _recurrenceUnit == 'hours' ? 'hour' : _recurrenceUnit == 'days' ? 'day' : _recurrenceUnit == 'weeks' ? 'week' : 'month') : _recurrenceUnit} for $_occurrencesLimit occurrences.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade800,
                              fontWeight: FontWeight.w500
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.withOpacity(0.15)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: const Text('Enable Snooze', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text('Repeat notifications if not marked done'),
                        secondary: Icon(
                          _snoozeEnabled ? Icons.snooze_outlined : Icons.snooze_rounded,
                          color: _snoozeEnabled ? Theme.of(context).primaryColor : Colors.grey,
                        ),
                        value: _snoozeEnabled,
                        onChanged: (bool value) {
                          setState(() {
                            _snoozeEnabled = value;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_snoozeEnabled) ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: _snoozeIntervalMinutes.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Interval (minutes)',
                                  hintText: 'e.g. 15',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _snoozeIntervalMinutes = int.tryParse(val) ?? 15;
                                  });
                                },
                                validator: (value) {
                                  if (_snoozeEnabled) {
                                    if (value == null || value.isEmpty) {
                                      return 'Required';
                                    }
                                    final n = int.tryParse(value);
                                    if (n == null || n <= 0) {
                                      return 'Must be > 0';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue: _maxSnoozeCount.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Max repeats',
                                  hintText: 'e.g. 3',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _maxSnoozeCount = int.tryParse(val) ?? 3;
                                  });
                                },
                                validator: (value) {
                                  if (_snoozeEnabled) {
                                    if (value == null || value.isEmpty) {
                                      return 'Required';
                                    }
                                    final n = int.tryParse(value);
                                    if (n == null || n <= 0) {
                                      return 'Must be > 0';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
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
                    : Text(widget.existingReminder != null ? 'Save Changes' : 'Schedule Reminder', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
