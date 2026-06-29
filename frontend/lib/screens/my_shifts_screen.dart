import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/shift.dart';
import '../services/storage_service.dart';
import '../services/shift_service.dart';
import '../services/log_service.dart';

class MyShiftsScreen extends StatefulWidget {
  const MyShiftsScreen({super.key});

  @override
  State<MyShiftsScreen> createState() => _MyShiftsScreenState();
}

class _MyShiftsScreenState extends State<MyShiftsScreen> {
  final StorageService _storage = StorageService();
  final ShiftService _shiftService = ShiftService();
  
  List<Shift> _shifts = [];

  Map<String, int>? _statistics;
  bool _isLoading = true;
  bool _hasData = false;
  
  // Multi-month support
  DateTime _currentDate = DateTime.now();
  String get _selectedRosterMonth => DateFormat('yyyy-MM').format(_currentDate);

  int _selectedTab = 0; // 0 for Schedule, 1 for Events
  bool _isEventsEnabled = false;
  bool _isFetchingEvents = false;
  List<String> _eventInterests = ['Cloud', 'Devops', 'AI', 'Agentic AI'];
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  @override
  void initState() {
    super.initState();
    _loadShifts();
    _listenToEventsPermission();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  void _listenToEventsPermission() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final enabledModules = List<String>.from(data['enabledModules'] ?? ['gold']);
        final interests = List<String>.from(data['eventInterests'] ?? ['Cloud', 'Devops', 'AI', 'Agentic AI']);
        if (mounted) {
          setState(() {
            _isEventsEnabled = enabledModules.contains('events');
            _eventInterests = interests;
          });
        }
      }
    }, onError: (e) {
      LogService().error("Error listening to events permission/interests", e);
    });
  }

  Future<void> _triggerFetchEvents() async {
    setState(() => _isFetchingEvents = true);
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('fetchUserTechEvents');
      final result = await callable.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Successfully loaded ${result.data['count'] ?? 0} tech events'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed to fetch events: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingEvents = false);
      }
    }
  }

  Future<void> _editInterestsDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final controller = TextEditingController(text: _eventInterests.join(', '));
    bool isSavingInterests = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Tech Interests'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter tags you are interested in (comma separated):',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Interests',
                  hintText: 'e.g. Cloud, Devops, AI, Agentic AI, testing',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSavingInterests ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSavingInterests
                  ? null
                  : () async {
                      setDialogState(() => isSavingInterests = true);
                      try {
                        final list = controller.text
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();
                        
                        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                          'eventInterests': list,
                        }, SetOptions(merge: true));

                        setState(() {
                          _eventInterests = list;
                        });

                        Navigator.pop(context);

                        // Prompt user to refresh
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Interests saved! Fetching new events...'),
                          ),
                        );
                        _triggerFetchEvents();
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save interests: $e'), backgroundColor: Colors.red),
                        );
                      } finally {
                        setDialogState(() => isSavingInterests = false);
                      }
                    },
              child: isSavingInterests
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
  
  void _changeMonth(int delta) {
    setState(() {
      _currentDate = DateTime(_currentDate.year, _currentDate.month + delta, 1);
    });
    _loadShifts();
  }

  void _changeYear(int delta) {
    setState(() {
      _currentDate = DateTime(_currentDate.year + delta, _currentDate.month, 1);
    });
    _loadShifts();
  }

  Future<void> _loadShifts() async {
    setState(() => _isLoading = true);
    
    try {
      final metadata = await _storage.getShiftMetadata(rosterMonth: _selectedRosterMonth);
      final shiftsData = await _storage.getAllShifts(rosterMonth: _selectedRosterMonth);
      
      if (metadata != null && shiftsData.isNotEmpty) {
        final shifts = shiftsData.map((s) => Shift.fromMap(s)).toList();
        
        String monthForQuery = _selectedRosterMonth;
        final stats = await _storage.getShiftStatistics(monthForQuery, rosterMonth: _selectedRosterMonth);
        
        setState(() {

          _shifts = shifts;
          _statistics = stats;
          _hasData = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _hasData = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      LogService().error('Failed to load shifts', e);
      setState(() => _isLoading = false);
    }
  }
  


  Future<void> _uploadJSON() async {
    final TextEditingController jsonController = TextEditingController();
    final TextEditingController nameController = TextEditingController(
      text: FirebaseAuth.instance.currentUser?.displayName ?? 'Roshan J'
    );
    
    XFile? selectedImage;
    bool isScanning = false;
    bool isSaving = false;
    bool isPreviewMode = false;
    int currentTab = 0; // 0 for Image, 1 for JSON
    String errorMessage = '';
    
    String employeeName = '';
    String monthLabel = '';
    List<Shift> parsedShifts = [];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          if (!isPreviewMode) {
            return AlertDialog(
              title: const Text('Upload Shift Roster'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Tab toggle
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Scan Image', textAlign: TextAlign.center),
                            selected: currentTab == 0,
                            onSelected: (selected) {
                              if (selected) setState(() => currentTab = 0);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Paste JSON', textAlign: TextAlign.center),
                            selected: currentTab == 1,
                            onSelected: (selected) {
                              if (selected) setState(() => currentTab = 1);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (currentTab == 0) ...[
                      // Image upload form
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Employee Name in Roster',
                          hintText: 'e.g. Roshan J',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final ImagePicker picker = ImagePicker();
                          final XFile? img = await picker.pickImage(source: ImageSource.gallery);
                          if (img != null) {
                            setState(() {
                              selectedImage = img;
                              errorMessage = '';
                            });
                          }
                        },
                        icon: const Icon(Icons.photo_library),
                        label: Text(selectedImage == null ? 'Select Roster Image' : 'Change Image'),
                      ),
                      if (selectedImage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Selected: ${selectedImage!.name}',
                          style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.green),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ] else ...[
                      // JSON upload form
                      const Text(
                        'Paste your JSON roster data below:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: jsonController,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          hintText: '{\n  "employee_name": "...",\n  "month": "...",\n  "shifts": [...]\n}',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        errorMessage,
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isScanning ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                if (isScanning)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  ElevatedButton(
                    onPressed: () async {
                      setState(() {
                        errorMessage = '';
                      });

                      if (currentTab == 0) {
                        if (nameController.text.trim().isEmpty) {
                          setState(() => errorMessage = 'Please enter employee name.');
                          return;
                        }
                        if (selectedImage == null) {
                          setState(() => errorMessage = 'Please select a roster image.');
                          return;
                        }

                        setState(() => isScanning = true);
                        try {
                          final bytes = await selectedImage!.readAsBytes();
                          final base64Image = base64Encode(bytes);

                          final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('analyzeRosterImage');
                          final result = await callable.call(<String, dynamic>{
                            'image': base64Image,
                            'employeeName': nameController.text.trim(),
                          });

                          final data = result.data;
                          if (data != null) {
                            final roster = ShiftRoster.fromJson(data as Map);
                            setState(() {
                              parsedShifts = roster.shifts;
                              employeeName = roster.employeeName;
                              monthLabel = roster.month;
                              isPreviewMode = true;
                              isScanning = false;
                            });
                          } else {
                            throw Exception('Received empty result from server.');
                          }
                        } catch (e) {
                          setState(() {
                            errorMessage = 'Scanning failed: $e';
                            isScanning = false;
                          });
                        }
                      } else {
                        if (jsonController.text.trim().isEmpty) {
                          setState(() => errorMessage = 'Please paste JSON roster data.');
                          return;
                        }

                        try {
                          final jsonData = json.decode(jsonController.text.trim());
                          final roster = ShiftRoster.fromJson(jsonData);
                          setState(() {
                            parsedShifts = roster.shifts;
                            employeeName = roster.employeeName;
                            monthLabel = roster.month;
                            isPreviewMode = true;
                          });
                        } catch (e) {
                          setState(() {
                            errorMessage = 'Invalid JSON: $e';
                          });
                        }
                      }
                    },
                    child: Text(currentTab == 0 ? 'Extract Shifts' : 'Parse JSON'),
                  ),
              ],
            );
          }

          // PREVIEW AND EDIT MODE
          return AlertDialog(
            title: const Text('Verify & Edit Shifts'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Employee: $employeeName',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Roster Month: $monthLabel',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const Divider(height: 24),
                    const Text(
                      'Review/edit shifts for each day below:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 320),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: parsedShifts.length,
                        itemBuilder: (context, index) {
                          final shift = parsedShifts[index];
                          // Try formatting date nicely if possible
                          String displayDate = shift.date;
                          try {
                            final dateObj = DateTime.parse(shift.date);
                            displayDate = DateFormat('EEE, MMM d').format(dateObj);
                          } catch (_) {}

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(displayDate, style: const TextStyle(fontWeight: FontWeight.bold)),
                                DropdownButton<String>(
                                  value: shift.shiftType,
                                  underline: const SizedBox(),
                                  items: const [
                                    DropdownMenuItem(value: 'morning', child: Text('Morning')),
                                    DropdownMenuItem(value: 'afternoon', child: Text('Afternoon')),
                                    DropdownMenuItem(value: 'night', child: Text('Night')),
                                    DropdownMenuItem(value: 'week_off', child: Text('Week Off')),
                                  ],
                                  onChanged: (newVal) {
                                    if (newVal != null) {
                                      setState(() {
                                        final isWeekOff = newVal == 'week_off';
                                        String? start;
                                        String? end;
                                        if (newVal == 'morning') {
                                          start = '06:00';
                                          end = '14:00';
                                        } else if (newVal == 'afternoon') {
                                          start = '14:00';
                                          end = '22:00';
                                        } else if (newVal == 'night') {
                                          start = '22:00';
                                          end = '06:00';
                                        }

                                        parsedShifts[index] = Shift(
                                          date: shift.date,
                                          shiftType: newVal,
                                          startTime: start,
                                          endTime: end,
                                          isWeekOff: isWeekOff,
                                        );
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage,
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () {
                        setState(() {
                          isPreviewMode = false;
                          errorMessage = '';
                        });
                      },
                child: const Text('Back'),
              ),
              if (isSaving)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      isSaving = true;
                      errorMessage = '';
                    });
                    try {
                      // Extract roster month directly from UI selection
                      String rosterMonth = _selectedRosterMonth;
                      String updatedMonthLabel = DateFormat('MMMM yyyy').format(_currentDate);

                      // Rewrite the shift dates to match the selected month/year.
                      final shiftsToSave = parsedShifts.map((s) {
                        final map = s.toMap();
                        if (map['date'].length >= 10) {
                          map['date'] = '$rosterMonth-${map['date'].substring(8, 10)}';
                        }
                        return map;
                      }).toList();

                      // Rewrite the original JSON payload too so when it's pushed, it has the correct dates!
                      final Map<String, dynamic> rewrittenJson = {
                        'employee_name': employeeName,
                        'month': updatedMonthLabel,
                        'shifts': parsedShifts.map((s) {
                          return {
                            'date': s.date.length >= 10 ? '$rosterMonth-${s.date.substring(8, 10)}' : s.date,
                            'shift_type': s.shiftType,
                            'start_time': s.startTime,
                            'end_time': s.endTime,
                            'is_week_off': s.isWeekOff,
                          };
                        }).toList(),
                      };
                      final String newJsonString = json.encode(rewrittenJson);

                      await _storage.saveShiftRoster(
                        employeeName,
                        updatedMonthLabel,
                        shiftsToSave,
                        rosterMonth: rosterMonth,
                        rawJson: newJsonString,
                      );

                      // Schedule notifications
                      await _shiftService.scheduleDailyShiftNotification();

                      if (mounted) {
                        Navigator.pop(context);
                      }
                      await _loadShifts(); // Reload current view

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('✅ Loaded ${parsedShifts.length} shifts for $employeeName ($rosterMonth)'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      setState(() {
                        errorMessage = 'Save failed: $e';
                        isSaving = false;
                      });
                    }
                  },
                  child: const Text('Save to Calendar'),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _clearData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear $_selectedRosterMonth Shifts?'),
        content: Text('This will delete all shift data and cancel notifications for $_selectedRosterMonth.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.clearAllShifts(rosterMonth: _selectedRosterMonth);
      await _shiftService.cancelAllShiftNotifications();
      
      await _loadShifts();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('All shift data for $_selectedRosterMonth cleared')),
        );
      }
    }
  }

  Color _getShiftColor(String shiftType) {
    switch (shiftType) {
      case 'morning':
        return Colors.orange;
      case 'afternoon':
        return Colors.blue;
      case 'night':
        return Colors.indigo;
      case 'week_off':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getShiftIcon(String shiftType) {
    switch (shiftType) {
      case 'morning':
        return Icons.wb_sunny;
      case 'afternoon':
        return Icons.wb_twilight;
      case 'night':
        return Icons.nightlight_round;
      case 'week_off':
        return Icons.beach_access;
      default:
        return Icons.work;
    }
  }

  Widget _buildStatisticsCard() {
    if (_statistics == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Month Statistics',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Morning', _statistics!['morning']!, Colors.orange),
                _buildStatItem('Afternoon', _statistics!['afternoon']!, Colors.blue),
                _buildStatItem('Night', _statistics!['night']!, Colors.indigo),
                _buildStatItem('Week Off', _statistics!['week_off']!, Colors.green),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Total Working Days: ${_statistics!['total_working']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildUpcomingShifts() {
    final today = DateTime.now();
    final upcomingShifts = _shifts.where((shift) {
      final shiftDate = DateTime.parse(shift.date);
      return shiftDate.isAfter(today.subtract(const Duration(days: 1)));
    }).take(7).toList();

    if (upcomingShifts.isEmpty) {
      return const Card(
        margin: EdgeInsets.all(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No upcoming shifts'),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Next 7 Days',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...upcomingShifts.map((shift) {
            final shiftDate = DateTime.parse(shift.date);
            final isToday = DateFormat('yyyy-MM-dd').format(shiftDate) == 
                           DateFormat('yyyy-MM-dd').format(today);
            final isTomorrow = DateFormat('yyyy-MM-dd').format(shiftDate) == 
                              DateFormat('yyyy-MM-dd').format(today.add(const Duration(days: 1)));

            String dayLabel = DateFormat('EEE, MMM d').format(shiftDate);
            if (isToday) dayLabel = 'Today';
            if (isTomorrow) dayLabel = 'Tomorrow';

            return ListTile(
              onTap: () => _editShiftDialog(shift),
              leading: CircleAvatar(
                backgroundColor: _getShiftColor(shift.shiftType).withOpacity(0.2),
                child: Icon(
                  _getShiftIcon(shift.shiftType),
                  color: _getShiftColor(shift.shiftType),
                ),
              ),
              title: Text(
                dayLabel,
                style: TextStyle(
                  fontWeight: isToday || isTomorrow ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Text(shift.getTimeRange()),
              trailing: Text(
                shift.getDisplayName(),
                style: TextStyle(
                  color: _getShiftColor(shift.shiftType),
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAllShiftsCalendar() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'All Shifts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_shifts.length} days',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: ListView.builder(
              itemCount: _shifts.length,
              itemBuilder: (context, index) {
                final shift = _shifts[index];
                final shiftDate = DateTime.parse(shift.date);

                return ListTile(
                  onTap: () => _editShiftDialog(shift),
                  dense: true,
                  leading: Icon(
                    _getShiftIcon(shift.shiftType),
                    color: _getShiftColor(shift.shiftType),
                    size: 20,
                  ),
                  title: Text(
                    DateFormat('EEE, MMM d').format(shiftDate),
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    shift.getTimeRange(),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getShiftColor(shift.shiftType).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      shift.shiftType.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getShiftColor(shift.shiftType),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editShiftDialog(Shift shift) async {
    String selectedType = shift.shiftType;
    
    final newShift = await showDialog<Shift>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit Shift on ${shift.date}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Shift Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'morning', child: Text('Morning (06:00 - 14:00)')),
                      DropdownMenuItem(value: 'afternoon', child: Text('Afternoon (14:00 - 22:00)')),
                      DropdownMenuItem(value: 'night', child: Text('Night (22:00 - 06:00)')),
                      DropdownMenuItem(value: 'week_off', child: Text('Week Off')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedType = val);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final isWeekOff = selectedType == 'week_off';
                    String? startTime;
                    String? endTime;
                    if (selectedType == 'morning') {
                      startTime = '06:00';
                      endTime = '14:00';
                    } else if (selectedType == 'afternoon') {
                      startTime = '14:00';
                      endTime = '22:00';
                    } else if (selectedType == 'night') {
                      startTime = '22:00';
                      endTime = '06:00';
                    }
                    
                    Navigator.pop(
                      context,
                      Shift(
                        date: shift.date,
                        shiftType: selectedType,
                        startTime: startTime,
                        endTime: endTime,
                        isWeekOff: isWeekOff,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (newShift != null) {
      setState(() => _isLoading = true);
      try {
        await _storage.updateSingleShift(newShift.date, newShift.toMap());
        await _shiftService.scheduleDailyShiftNotification(); // Reschedule
        await _loadShifts(); // Reload list
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Shift updated for ${newShift.date}')),
          );
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update shift: $e')),
          );
        }
      }
    }
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_double_arrow_left, color: Colors.teal, size: 20),
                onPressed: () => _changeYear(-1),
                tooltip: 'Previous Year',
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_left, color: Colors.teal, size: 28),
                onPressed: () => _changeMonth(-1),
                tooltip: 'Previous Month',
              ),
            ],
          ),
          Column(
            children: [
              Text(
                DateFormat('MMMM').format(_currentDate).toUpperCase(),
                style: const TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.w900, 
                  color: Colors.teal,
                  letterSpacing: 1.2
                ),
              ),
              Text(
                DateFormat('yyyy').format(_currentDate),
                style: TextStyle(
                  fontSize: 14, 
                  fontWeight: FontWeight.w500, 
                  color: Colors.teal.withOpacity(0.7),
                  letterSpacing: 4.0
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_right, color: Colors.teal, size: 28),
                onPressed: () => _changeMonth(1),
                tooltip: 'Next Month',
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_double_arrow_right, color: Colors.teal, size: 20),
                onPressed: () => _changeYear(1),
                tooltip: 'Next Year',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal : Colors.teal.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? Colors.teal : Colors.teal.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.teal,
          ),
        ),
      ),
    );
  }

  Widget _buildEventsView() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please log in first.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('events')
          .orderBy('date', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error loading events: ${snapshot.error}'));
        }

        final allDocs = snapshot.data?.docs ?? [];
        
        // Filter events that match the currently selected month and year (_selectedRosterMonth format: yyyy-MM)
        final monthEvents = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final dateStr = data['date'] as String? ?? '';
          return dateStr.startsWith(_selectedRosterMonth);
        }).toList();

        if (monthEvents.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No events found for ${DateFormat('MMMM yyyy').format(_currentDate)}',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Interests: ${_eventInterests.join(", ")}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _triggerFetchEvents,
                    icon: const Icon(Icons.sync),
                    label: const Text('Fetch Events via AI'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: monthEvents.length,
          itemBuilder: (context, index) {
            final data = monthEvents[index].data() as Map<String, dynamic>;
            final title = data['title'] ?? 'No Title';
            final dateStr = data['date'] ?? '';
            final timings = data['timings'] ?? 'No timings';
            final location = data['location'] ?? 'No location';
            final regLink = data['registrationLink'] ?? '';

            // Format date nicely: YYYY-MM-DD to "EEE, MMM d"
            String formattedDate = dateStr;
            try {
              final parsed = DateTime.parse(dateStr);
              formattedDate = DateFormat('EEEE, MMMM d').format(parsed);
            } catch (_) {}

            // Determine user shift for this day
            String shiftLabel = 'no data';
            Color shiftBadgeColor = Colors.grey;

            if (_hasData) {
              final shiftOnDay = _shifts.firstWhere(
                (s) => s.date == dateStr,
                orElse: () => Shift(date: dateStr, shiftType: 'week_off', isWeekOff: true),
              );

              if (shiftOnDay.shiftType == 'morning') {
                shiftLabel = 'Morning';
                shiftBadgeColor = Colors.orange;
              } else if (shiftOnDay.shiftType == 'afternoon') {
                shiftLabel = 'Afternoon';
                shiftBadgeColor = Colors.blue;
              } else if (shiftOnDay.shiftType == 'night') {
                shiftLabel = 'Night';
                shiftBadgeColor = Colors.indigo;
              } else if (shiftOnDay.shiftType == 'week_off' || shiftOnDay.isWeekOff) {
                shiftLabel = 'Week Off';
                shiftBadgeColor = Colors.green;
              } else if (shiftOnDay.shiftType == 'none') {
                shiftLabel = 'Week Off';
                shiftBadgeColor = Colors.green;
              } else {
                shiftLabel = shiftOnDay.getDisplayName();
                shiftBadgeColor = _getShiftColor(shiftOnDay.shiftType);
              }
            }

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.withOpacity(0.15)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: shiftLabel == 'no data'
                                ? Colors.grey.shade100
                                : shiftBadgeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: shiftLabel == 'no data'
                                  ? Colors.grey.shade300
                                  : shiftBadgeColor.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            shiftLabel == 'no data' ? 'Shift: No Data' : 'Shift: $shiftLabel',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: shiftLabel == 'no data' ? Colors.grey : shiftBadgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.calendar_month, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          formattedDate,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          timings,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            location,
                            style: const TextStyle(fontSize: 13, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                    if (regLink.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _launchURL(regLink),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Register Here'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.teal,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open link: $urlString')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error launching link: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('My Shifts'),
            if (_isEventsEnabled) ...[
              const SizedBox(width: 12),
              _buildTabButton('Schedule', 0),
              const SizedBox(width: 6),
              _buildTabButton('Events', 1),
            ],
          ],
        ),
        actions: [
          if (_selectedTab == 0 && _hasData) ...[
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadShifts,
              tooltip: 'Refresh Roster',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearData,
              tooltip: 'Clear All Roster Data',
            ),
          ] else if (_selectedTab == 1) ...[
            if (_isFetchingEvents)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal),
                ),
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.interests_outlined),
                onPressed: _editInterestsDialog,
                tooltip: 'Edit Interests',
              ),
              IconButton(
                icon: const Icon(Icons.sync),
                onPressed: _triggerFetchEvents,
                tooltip: 'Sync Events Now',
              ),
            ]
          ],
        ],
      ),
      floatingActionButton: _selectedTab == 0
          ? FloatingActionButton.extended(
              onPressed: _uploadJSON,
              icon: const Icon(Icons.upload_file),
              label: Text(_hasData ? 'Update Roster' : 'Upload Roster'),
            )
          : null,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _selectedTab == 0
                ? (_isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : !_hasData
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.calendar_month, size: 80, color: Colors.grey[300]),
                                const SizedBox(height: 16),
                                Text(
                                  'No shift data yet',
                                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Upload your roster JSON for this month',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                _buildStatisticsCard(),
                                _buildUpcomingShifts(),
                                _buildAllShiftsCalendar(),
                                const SizedBox(height: 80), // Space for FAB
                              ],
                            ),
                          ))
                : _buildEventsView(),
          ),
        ],
      ),
    );
  }
}
