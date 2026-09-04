
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
      final now = DateTime.now();
      _date = widget.selectedDate ?? DateTime(now.year, now.month, now.day);
      final defaultTime = now.add(const Duration(minutes: 5));
      _time = TimeOfDay(hour: defaultTime.hour, minute: defaultTime.minute);
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialDate = _date.isBefore(today) ? today : _date;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        // If today is selected and currently chosen time is already in the past, adjust time forward
        if (picked.year == today.year && picked.month == today.month && picked.day == today.day) {
          final nowTime = TimeOfDay.now();
          final isPast = _time.hour < nowTime.hour || (_time.hour == nowTime.hour && _time.minute <= nowTime.minute);
          if (isPast) {
            final futureTime = DateTime.now().add(const Duration(minutes: 5));
            _time = TimeOfDay(hour: futureTime.hour, minute: futureTime.minute);
          }
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final isToday = _date.year == now.year && _date.month == now.month && _date.day == now.day;

    TimeOfDay initialTime = _time;
    final selectedDateTime = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    if (isToday && selectedDateTime.isBefore(now)) {
      final futureTime = now.add(const Duration(minutes: 5));
      initialTime = TimeOfDay(hour: futureTime.hour, minute: futureTime.minute);
    }
    TimeOfDay tempTime = initialTime;

    showModalBottomSheet(
      context: context,
      builder: (BuildContext builder) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final isTempPast = isToday &&
                DateTime(_date.year, _date.month, _date.day, tempTime.hour, tempTime.minute)
                    .isBefore(DateTime.now());

            return CupertinoTheme(
              data: CupertinoThemeData(
                brightness: isDarkMode ? Brightness.dark : Brightness.light,
              ),
              child: Container(
                height: MediaQuery.of(context).size.height / 3 + 40,
                color: isDarkMode ? Colors.grey[900] : Colors.white,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            child: const Text('Cancel'),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          if (isTempPast)
                            const Text(
                              'Time is in the past',
                              style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          TextButton(
                            child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              final pickedDateTime = DateTime(_date.year, _date.month, _date.day, tempTime.hour, tempTime.minute);
                              if (isToday && pickedDateTime.isBefore(DateTime.now())) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Cannot select a past time for today. Please choose a future time.'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                                return;
                              }
                              setState(() {
                                _time = tempTime;
                              });
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: CupertinoDatePicker(
                        mode: CupertinoDatePickerMode.time,
                        initialDateTime: DateTime(
                          now.year,
                          now.month,
                          now.day,
                          initialTime.hour,
                          initialTime.minute,
                        ),
                        onDateTimeChanged: (DateTime newDateTime) {
                          setModalState(() {
                            tempTime = TimeOfDay.fromDateTime(newDateTime);
                          });
                        },
                        use24hFormat: false,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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

    final now = DateTime.now();
    final isToday = _date.year == now.year && _date.month == now.month && _date.day == now.day;
    final scheduledDateTime = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

    if (isToday && scheduledDateTime.isBefore(now.add(const Duration(seconds: 30)))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot schedule a reminder for a past time. Please select a future time.'),
          backgroundColor: Colors.redAccent,
        ),
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
            taskId: widget.existingReminder!.taskId,
          );
          await storage.updateCalendarReminder(updated);
        } else {
          for (final recipientUid in _selectedRecipients) {
            String? targetUsername;
            if (recipientUid != _myUid) {
              final buddy = _approvedBuddies.firstWhere(
                (b) => b['receiverUid'] == recipientUid || b['uid'] == recipientUid || b['senderUid'] == recipientUid,
                orElse: () => <String, dynamic>{},
              );
              targetUsername = (buddy['receiverUsername'] ?? buddy['username'] ?? buddy['senderUsername']) as String?;
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
                        Builder(
                          builder: (context) {
                            final bool isDark = Theme.of(context).brightness == Brightness.dark;
                            return CheckboxListTile(
                              title: const Text('Myself (You)'),
                              value: _selectedRecipients.contains(_myUid),
                              activeColor: Colors.blueAccent,
                              checkColor: Colors.white,
                              side: BorderSide(color: isDark ? Colors.white70 : Colors.black45, width: 1.5),
                              fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return Colors.blueAccent;
                                }
                                return isDark ? Colors.white10 : null;
                              }),
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
                            );
                          },
                        ),
                        if (_approvedBuddies.isNotEmpty) ...[
                          const Divider(),
                          ..._approvedBuddies.map((buddy) {
                            final buddyUid = buddy['receiverUid'] as String;
                            final buddyUsername = buddy['receiverUsername'] as String? ?? 'User';
                            return Builder(
                              builder: (context) {
                                final bool isDark = Theme.of(context).brightness == Brightness.dark;
                                return CheckboxListTile(
                                  title: Text('@$buddyUsername'),
                                  value: _selectedRecipients.contains(buddyUid),
                                  activeColor: Colors.blueAccent,
                                  checkColor: Colors.white,
                                  side: BorderSide(color: isDark ? Colors.white70 : Colors.black45, width: 1.5),
                                  fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return Colors.blueAccent;
                                    }
                                    return isDark ? Colors.white10 : null;
                                  }),
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
                              },
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
                        subtitle: (_date.year == DateTime.now().year &&
                                _date.month == DateTime.now().month &&
                                _date.day == DateTime.now().day &&
                                DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute).isBefore(DateTime.now()))
                            ? const Text('Past time selected - please choose a future time', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600))
                            : null,
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
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
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
                                initialValue: _recurrenceUnit,
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
                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: const Text('Auto-Snooze Reminder ⏰', style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: const Text('Automatically repeat notification if not acknowledged'),
                        secondary: Icon(
                          _snoozeEnabled ? Icons.snooze : Icons.snooze_outlined,
                          color: _snoozeEnabled ? Colors.orangeAccent : Colors.grey,
                        ),
                        value: _snoozeEnabled,
                        onChanged: (bool val) {
                          setState(() {
                            _snoozeEnabled = val;
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
                                  labelText: 'Interval (Mins)',
                                  hintText: 'e.g. 1',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  prefixIcon: Icon(Icons.timer_outlined),
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _snoozeIntervalMinutes = int.tryParse(val) ?? 15;
                                  });
                                },
                                validator: (val) {
                                  if (_snoozeEnabled) {
                                    final n = int.tryParse(val ?? '');
                                    if (n == null || n <= 0) return 'Min 1 min';
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
                                  labelText: 'Max Repeats (Count)',
                                  hintText: 'e.g. 3',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  prefixIcon: Icon(Icons.repeat_outlined),
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    _maxSnoozeCount = int.tryParse(val) ?? 3;
                                  });
                                },
                                validator: (val) {
                                  if (_snoozeEnabled) {
                                    final n = int.tryParse(val ?? '');
                                    if (n == null || n <= 0) return 'Min 1';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: Text(
                            'Will repeat notification every $_snoozeIntervalMinutes min(s) up to $_maxSnoozeCount times until marked Done.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
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
