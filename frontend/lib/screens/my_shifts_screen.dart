import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/shift.dart';
import '../services/storage_service.dart';
import '../services/shift_service.dart';
import '../services/home_widget_service.dart';
import '../services/log_service.dart';
import '../widgets/web_image_viewer.dart';

class MyShiftsScreen extends StatefulWidget {
  final int initialTab;

  const MyShiftsScreen({super.key, this.initialTab = 0});

  @override
  State<MyShiftsScreen> createState() => _MyShiftsScreenState();
}

class _MyShiftsScreenState extends State<MyShiftsScreen> {
  final StorageService _storage = StorageService();
  final ShiftService _shiftService = ShiftService();
  final HomeWidgetService _homeWidgetService = HomeWidgetService();

  static final Map<String, List<Shift>> _cachedShifts = {};
  static final Map<String, Map<String, int>?> _cachedStats = {};
  static final Map<String, String?> _cachedRosterImages = {};

  List<Shift> _shifts = [];
  Map<String, int>? _statistics;
  bool _isLoading = true;
  bool _hasData = false;
  String? _rosterImageUrl;

  // Multi-month support
  DateTime _currentDate = DateTime.now();
  String get _selectedRosterMonth => DateFormat('yyyy-MM').format(_currentDate);

  @override
  void initState() {
    super.initState();
    final month = _selectedRosterMonth;
    if (_cachedShifts.containsKey(month) && _cachedShifts[month]!.isNotEmpty) {
      _shifts = _cachedShifts[month]!;
      _statistics = _cachedStats[month];
      _rosterImageUrl = _cachedRosterImages[month];
      _hasData = true;
      _isLoading = false;
      _homeWidgetService.updateShiftCalendarWidget(shifts: _shifts, monthDate: _currentDate);
    }
    _loadShifts(showLoader: !_hasData);
  }

  void _changeMonth(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentDate = DateTime(_currentDate.year, _currentDate.month + delta, 1);
      final month = _selectedRosterMonth;
      if (_cachedShifts.containsKey(month) && _cachedShifts[month]!.isNotEmpty) {
        _shifts = _cachedShifts[month]!;
        _statistics = _cachedStats[month];
        _rosterImageUrl = _cachedRosterImages[month];
        _hasData = true;
        _isLoading = false;
        _homeWidgetService.updateShiftCalendarWidget(shifts: _shifts, monthDate: _currentDate);
      }
    });
    _loadShifts(showLoader: !_hasData);
  }

  void _resetToCurrentMonth() {
    HapticFeedback.lightImpact();
    setState(() {
      _currentDate = DateTime.now();
    });
    _loadShifts();
  }

  Future<void> _loadShifts({bool showLoader = true}) async {
    final month = _selectedRosterMonth;
    if (showLoader && !_hasData) {
      setState(() => _isLoading = true);
    }

    try {
      final results = await Future.wait([
        _storage.getShiftMetadata(rosterMonth: month),
        _storage.getAllShifts(rosterMonth: month),
        _storage.getShiftStatistics(month, rosterMonth: month),
      ]);

      final metadata = results[0] as Map<String, dynamic>?;
      final shiftsData = results[1] as List<Map<String, dynamic>>;
      final stats = results[2] as Map<String, int>?;

      if (metadata != null && shiftsData.isNotEmpty) {
        final shifts = shiftsData.map((s) => Shift.fromJson(s)).toList();
        final imageUrl = metadata['roster_image_url'] as String?;

        _cachedShifts[month] = shifts;
        _cachedStats[month] = stats;
        _cachedRosterImages[month] = imageUrl;

        if (mounted && _selectedRosterMonth == month) {
          setState(() {
            _shifts = shifts;
            _statistics = stats;
            _rosterImageUrl = imageUrl;
            _hasData = true;
            _isLoading = false;
          });
          _homeWidgetService.updateShiftCalendarWidget(shifts: shifts, monthDate: _currentDate);
        }
      } else {
        _cachedShifts[month] = [];
        _cachedStats[month] = null;
        _cachedRosterImages[month] = null;
        if (mounted && _selectedRosterMonth == month) {
          setState(() {
            _shifts = [];
            _statistics = null;
            _rosterImageUrl = null;
            _hasData = false;
            _isLoading = false;
          });
          _homeWidgetService.updateShiftCalendarWidget(shifts: [], monthDate: _currentDate);
        }
      }
    } catch (e) {
      LogService().error('Failed to load shifts', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _getShiftColor(String shiftType) {
    switch (shiftType.toLowerCase()) {
      case 'morning':
        return const Color(0xFFF59E0B); // Amber / Gold
      case 'afternoon':
        return const Color(0xFF06B6D4); // Cyan / Azure
      case 'night':
        return const Color(0xFF8B5CF6); // Violet / Purple
      case 'week_off':
        return const Color(0xFF10B981); // Emerald Green
      default:
        return const Color(0xFF64748B); // Slate Grey
    }
  }

  IconData _getShiftIcon(String shiftType) {
    switch (shiftType.toLowerCase()) {
      case 'morning':
        return Icons.wb_sunny_rounded;
      case 'afternoon':
        return Icons.wb_twilight_rounded;
      case 'night':
        return Icons.nightlight_round;
      case 'week_off':
        return Icons.beach_access_rounded;
      default:
        return Icons.work_outline_rounded;
    }
  }

  String _getShiftShortName(String shiftType) {
    switch (shiftType.toLowerCase()) {
      case 'morning':
        return 'Morning';
      case 'afternoon':
        return 'Afternoon';
      case 'night':
        return 'Night';
      case 'week_off':
        return 'Off Day';
      default:
        return shiftType;
    }
  }

  Map<String, dynamic> _getNextShiftInfo() {
    if (_shifts.isEmpty) {
      return {
        'title': 'No shifts scheduled',
        'subtitle': 'Upload your monthly roster to get live shift alerts',
        'isOngoing': false,
        'color': const Color(0xFF6366F1),
      };
    }

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    // Look for today's shift first
    final todayShift = _shifts.firstWhere(
      (s) => s.date == todayStr,
      orElse: () => Shift(date: '', shiftType: 'none', isWeekOff: false),
    );

    if (todayShift.date.isNotEmpty) {
      if (todayShift.isWeekOff) {
        // Look for next working shift
        final nextWorkShift = _shifts.firstWhere(
          (s) => s.date.compareTo(todayStr) > 0 && !s.isWeekOff,
          orElse: () => Shift(date: '', shiftType: 'none', isWeekOff: false),
        );
        if (nextWorkShift.date.isNotEmpty) {
          final diffDays = DateTime.parse(nextWorkShift.date).difference(DateTime(now.year, now.month, now.day)).inDays;
          return {
            'title': 'Week Off — Enjoy Your Rest! 🌿',
            'subtitle': 'Next: ${nextWorkShift.getDisplayName()} in $diffDays day${diffDays > 1 ? 's' : ''}',
            'isOngoing': false,
            'color': const Color(0xFF10B981),
          };
        }
        return {
          'title': 'Week Off Today 🌿',
          'subtitle': 'No working shifts scheduled for today',
          'isOngoing': false,
          'color': const Color(0xFF10B981),
        };
      }

      // Working shift today: check start and end time
      if (todayShift.startTime != null && todayShift.endTime != null) {
        try {
          final startParts = todayShift.startTime!.split(':');
          final endParts = todayShift.endTime!.split(':');

          DateTime shiftStart = DateTime(
            now.year, now.month, now.day,
            int.parse(startParts[0]), int.parse(startParts[1]),
          );

          DateTime shiftEnd = DateTime(
            now.year, now.month, now.day,
            int.parse(endParts[0]), int.parse(endParts[1]),
          );

          // For night shifts ending next morning
          if (shiftEnd.isBefore(shiftStart)) {
            shiftEnd = shiftEnd.add(const Duration(days: 1));
          }

          if (now.isBefore(shiftStart)) {
            final diff = shiftStart.difference(now);
            final hours = diff.inHours;
            final mins = diff.inMinutes % 60;
            return {
              'title': '${todayShift.getDisplayName()} (${todayShift.startTime} - ${todayShift.endTime})',
              'subtitle': 'Starts in ${hours > 0 ? '${hours}h ' : ''}${mins}m',
              'isOngoing': false,
              'color': _getShiftColor(todayShift.shiftType),
            };
          } else if (now.isAfter(shiftStart) && now.isBefore(shiftEnd)) {
            final diff = shiftEnd.difference(now);
            final hours = diff.inHours;
            final mins = diff.inMinutes % 60;
            return {
              'title': 'Currently On Duty: ${todayShift.getDisplayName()} ⚡',
              'subtitle': 'Ends in ${hours > 0 ? '${hours}h ' : ''}${mins}m (${todayShift.endTime})',
              'isOngoing': true,
              'color': _getShiftColor(todayShift.shiftType),
            };
          }
        } catch (_) {}
      }
    }

    // Look for next upcoming shift starting tomorrow or later
    final nextShift = _shifts.firstWhere(
      (s) => s.date.compareTo(todayStr) > 0 && !s.isWeekOff,
      orElse: () => Shift(date: '', shiftType: 'none', isWeekOff: false),
    );

    if (nextShift.date.isNotEmpty) {
      final nextDate = DateTime.tryParse(nextShift.date);
      final daysDiff = nextDate != null
          ? nextDate.difference(DateTime(now.year, now.month, now.day)).inDays
          : 1;
      return {
        'title': 'Next Shift: ${nextShift.getDisplayName()} (${nextShift.getTimeRange()})',
        'subtitle': 'Starts in ${daysDiff == 1 ? 'Tomorrow' : '$daysDiff days'}',
        'isOngoing': false,
        'color': _getShiftColor(nextShift.shiftType),
      };
    }

    return {
      'title': 'Shift Schedule Up to Date',
      'subtitle': 'No upcoming shifts scheduled this month',
      'isOngoing': false,
      'color': const Color(0xFF6366F1),
    };
  }

  void _viewRosterImage() {
    if (_rosterImageUrl == null) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: kIsWeb
                    ? WebImageViewerWrapper(imageUrl: _rosterImageUrl!)
                    : Image.network(
                        _rosterImageUrl!,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.white,
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.broken_image, size: 64, color: Colors.red),
                                const SizedBox(height: 16),
                                Text(
                                  'Failed to load roster image',
                                  style: GoogleFonts.outfit(color: Colors.black),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.6),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadJSON() async {
    final TextEditingController nameController = TextEditingController();

    XFile? selectedImage;
    bool isScanning = false;
    bool isSaving = false;
    bool isPreviewMode = false;
    bool nameHasError = false;
    String errorMessage = '';

    String employeeName = '';
    String monthLabel = '';
    List<Shift> parsedShifts = [];

    final messenger = ScaffoldMessenger.of(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerDialogContext, setDialogState) {
          final isDark = Theme.of(dialogContext).brightness == Brightness.dark;

          if (!isPreviewMode) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.document_scanner_rounded, color: Color(0xFF38BDF8), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Scan Shift Roster',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Upload your roster sheet to automatically extract and schedule your monthly shifts.',
                      style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      style: GoogleFonts.outfit(),
                      onChanged: (val) {
                        if (nameHasError && val.trim().isNotEmpty) {
                          setDialogState(() => nameHasError = false);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Employee Name in Roster *',
                        hintText: 'e.g. Enter name as on roster',
                        errorText: nameHasError ? 'Employee name is compulsory' : null,
                        errorStyle: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.w600),
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final ImagePicker picker = ImagePicker();
                        final XFile? img = await picker.pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 1600,
                          maxHeight: 1600,
                          imageQuality: 82,
                        );
                        if (img != null) {
                          setDialogState(() {
                            selectedImage = img;
                            errorMessage = '';
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.photo_library_rounded),
                      label: Text(
                        selectedImage == null ? 'Select Roster Image' : 'Change Image',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (selectedImage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Selected: ${selectedImage!.name}',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF10B981),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        errorMessage,
                        style: GoogleFonts.outfit(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isScanning ? null : () => Navigator.pop(dialogContext),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey.shade600)),
                ),
                if (isScanning)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: () async {
                      setDialogState(() {
                        errorMessage = '';
                      });

                      if (nameController.text.trim().isEmpty) {
                        setDialogState(() {
                          nameHasError = true;
                          errorMessage = 'Please enter your name as written on the roster.';
                        });
                        return;
                      }
                      if (selectedImage == null) {
                        setDialogState(() => errorMessage = 'Please select a roster image to scan.');
                        return;
                      }

                      setDialogState(() => isScanning = true);
                      try {
                        final bytes = await selectedImage!.readAsBytes();
                        final base64Image = base64Encode(bytes);

                        final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
                          'analyzeRosterImage',
                          options: HttpsCallableOptions(timeout: const Duration(seconds: 180)),
                        );
                        final result = await callable.call(<String, dynamic>{
                          'image': base64Image,
                          'employeeName': nameController.text.trim(),
                        });

                        final data = result.data;
                        if (data != null) {
                          final roster = ShiftRoster.fromJson(data as Map);
                          setDialogState(() {
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
                        setDialogState(() {
                          errorMessage = 'Scanning failed: $e';
                          isScanning = false;
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Extract Shifts',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            );
          }

          // PREVIEW AND EDIT MODE
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(
              'Verify & Edit Shifts',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Employee: $employeeName',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Roster Month: $monthLabel',
                      style: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 14),
                    ),
                    const Divider(height: 24),
                    Text(
                      'Review/edit shifts for each day below:',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 260,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListView.separated(
                        itemCount: parsedShifts.length,
                        separatorBuilder: (context, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final shift = parsedShifts[index];
                          final validShiftType = [
                            'morning', 'afternoon', 'night', 'general', 'week_off'
                          ].contains(shift.shiftType) ? shift.shiftType : 'week_off';

                          return ListTile(
                            dense: true,
                            leading: Icon(
                              _getShiftIcon(shift.shiftType),
                              color: _getShiftColor(shift.shiftType),
                              size: 20,
                            ),
                            title: Text(
                              shift.date,
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                            ),
                            trailing: DropdownButton<String>(
                              value: validShiftType,
                              underline: const SizedBox(),
                              items: const [
                                DropdownMenuItem(value: 'morning', child: Text('Morning')),
                                DropdownMenuItem(value: 'afternoon', child: Text('Afternoon')),
                                DropdownMenuItem(value: 'night', child: Text('Night')),
                                DropdownMenuItem(value: 'general', child: Text('General')),
                                DropdownMenuItem(value: 'week_off', child: Text('Week Off')),
                              ],
                              onChanged: (newType) {
                                if (newType != null) {
                                  setDialogState(() {
                                    final isOff = newType == 'week_off';
                                    String? start;
                                    String? end;
                                    if (newType == 'morning') {
                                      start = '06:00';
                                      end = '14:00';
                                    } else if (newType == 'afternoon') {
                                      start = '14:00';
                                      end = '22:00';
                                    } else if (newType == 'night') {
                                      start = '22:00';
                                      end = '06:00';
                                    } else if (newType == 'general') {
                                      start = '09:00';
                                      end = '17:00';
                                    }
                                    parsedShifts[index] = Shift(
                                      date: shift.date,
                                      shiftType: newType,
                                      startTime: start,
                                      endTime: end,
                                      isWeekOff: isOff,
                                    );
                                  });
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    if (errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage,
                        style: GoogleFonts.outfit(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => setDialogState(() => isPreviewMode = false),
                child: Text('Back', style: GoogleFonts.outfit()),
              ),
              if (isSaving)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                ElevatedButton(
                  onPressed: () async {
                    setDialogState(() {
                      isSaving = true;
                      errorMessage = '';
                    });
                    try {
                      String rosterMonth = _selectedRosterMonth;
                      String updatedMonthLabel = DateFormat('MMMM yyyy').format(_currentDate);

                      String? rosterImageUrl;
                      if (selectedImage != null) {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          final ref = FirebaseStorage.instance
                              .ref()
                              .child('users/${user.uid}/rosters/$rosterMonth.jpg');
                          final bytes = await selectedImage!.readAsBytes();
                          await ref.putData(bytes);
                          rosterImageUrl = await ref.getDownloadURL();
                        }
                      }

                      final shiftsToSave = parsedShifts.map((s) {
                        final map = s.toMap();
                        if (map['date'].length >= 10) {
                          map['date'] = '$rosterMonth-${map['date'].substring(8, 10)}';
                        }
                        return map;
                      }).toList();

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
                        rosterImageUrl: rosterImageUrl,
                      );

                      await _shiftService.scheduleDailyShiftNotification();

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      await _loadShifts();

                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              '✅ Loaded ${parsedShifts.length} shifts for $employeeName ($rosterMonth)',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                            ),
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      }
                    } catch (e) {
                      setDialogState(() {
                        errorMessage = 'Save failed: $e';
                        isSaving = false;
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Save to Calendar', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear $_selectedRosterMonth Shifts?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'This will delete all shift data and cancel notifications for $_selectedRosterMonth.',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Clear', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
          SnackBar(
            content: Text('All shift data for $_selectedRosterMonth cleared', style: GoogleFonts.outfit()),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _editShiftDialog(Shift shift) async {
    HapticFeedback.selectionClick();
    String selectedType = shift.shiftType;

    final newShift = await showDialog<Shift>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: Text(
                'Edit Shift (${shift.date})',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: InputDecoration(
                      labelText: 'Shift Type',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'morning', child: Text('🌅 Morning (06:00 - 14:00)')),
                      DropdownMenuItem(value: 'afternoon', child: Text('☀️ Afternoon (14:00 - 22:00)')),
                      DropdownMenuItem(value: 'night', child: Text('🌙 Night (22:00 - 06:00)')),
                      DropdownMenuItem(value: 'week_off', child: Text('🏖️ Week Off (Rest)')),
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
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey.shade600)),
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
                      dialogCtx,
                      Shift(
                        date: shift.date,
                        shiftType: selectedType,
                        startTime: startTime,
                        endTime: endTime,
                        isWeekOff: isWeekOff,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Save', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
        await _shiftService.scheduleDailyShiftNotification();
        await _loadShifts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Shift updated for ${newShift.date}', style: GoogleFonts.outfit()),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
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

  // --- WIDGETS ---

  Widget _buildNextShiftHeroCard(bool isDark) {
    final info = _getNextShiftInfo();
    final Color accentColor = info['color'] as Color;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141A26) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: isDark ? 0.25 : 0.15),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  info['isOngoing'] == true ? Icons.bolt_rounded : Icons.schedule_rounded,
                  color: accentColor,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  info['title'] as String,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            info['subtitle'] as String,
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.grey.shade900,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNavigation(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161E2C) : const Color(0xFFEFF2F6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 26),
            onPressed: () => _changeMonth(-1),
            tooltip: 'Previous Month',
          ),
          GestureDetector(
            onTap: _resetToCurrentMonth,
            child: Column(
              children: [
                Text(
                  DateFormat('MMMM yyyy').format(_currentDate),
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Tap to return to today',
                  style: GoogleFonts.outfit(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 26),
            onPressed: () => _changeMonth(1),
            tooltip: 'Next Month',
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarHeatmap(bool isDark) {
    final year = _currentDate.year;
    final month = _currentDate.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    // Sunday is 0, Monday 1, etc.
    final firstWeekday = DateTime(year, month, 1).weekday % 7;

    final weekHeaders = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    final Map<String, Shift> shiftByDate = {
      for (var s in _shifts) s.date: s,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141A26) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Days of the week row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: weekHeaders.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // Monthly Calendar Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: firstWeekday + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (context, index) {
              if (index < firstWeekday) {
                return const SizedBox.shrink(); // Empty slot before 1st of month
              }

              final day = index - firstWeekday + 1;
              final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
              final isToday = dateStr == todayStr;
              final shift = shiftByDate[dateStr];

              Color cellColor = isDark ? const Color(0xFF1E2638) : const Color(0xFFF1F5F9);
              Color badgeColor = Colors.transparent;
              String badgeText = '';

              if (shift != null) {
                badgeColor = _getShiftColor(shift.shiftType);
                badgeText = _getShiftShortName(shift.shiftType);
              }

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (shift != null) {
                    _editShiftDialog(shift);
                  } else {
                    _editShiftDialog(
                      Shift(date: dateStr, shiftType: 'morning', startTime: '06:00', endTime: '14:00', isWeekOff: false),
                    );
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: cellColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isToday
                          ? const Color(0xFF38BDF8)
                          : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade200),
                      width: isToday ? 2.0 : 1.0,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Day Number
                      Text(
                        '$day',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                          color: isToday
                              ? const Color(0xFF38BDF8)
                              : (isDark ? Colors.grey.shade200 : Colors.grey.shade800),
                        ),
                      ),

                      // Shift Pill Tag
                      if (shift != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                          decoration: BoxDecoration(
                            color: badgeColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeText,
                            style: GoogleFonts.outfit(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        const SizedBox(height: 12),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),

          // Color Legend
          Wrap(
            spacing: 12,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _buildLegendItem('Morning', const Color(0xFFF59E0B)),
              _buildLegendItem('Afternoon', const Color(0xFF06B6D4)),
              _buildLegendItem('Night', const Color(0xFF8B5CF6)),
              _buildLegendItem('Off Day', const Color(0xFF10B981)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _buildStatsDashboard(bool isDark) {
    final int workingDays = _statistics?['total_working'] ?? _shifts.where((s) => !s.isWeekOff).length;
    final int offDays = _statistics?['week_off'] ?? _shifts.where((s) => s.isWeekOff).length;
    final int totalDays = workingDays + offDays;
    final double workRatio = totalDays == 0 ? 0.0 : (workingDays / totalDays);

    final int totalHours = workingDays * 8; // standard 8 hours per shift

    // Calculate current streak or pattern
    int currentStreak = 0;
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    for (var s in _shifts) {
      if (s.date.compareTo(todayStr) <= 0 && !s.isWeekOff) {
        currentStreak++;
      } else if (s.date.compareTo(todayStr) <= 0 && s.isWeekOff) {
        currentStreak = 0;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              // Monthly Hours Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141A26) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Monthly Hours',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$totalHours hrs',
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Shift Pattern',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentStreak > 0 ? '$currentStreak Days On' : 'Rest Active',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Work vs Off Gauge Card
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF141A26) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 76,
                        height: 76,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: workRatio,
                              strokeWidth: 8,
                              backgroundColor: const Color(0xFF10B981),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                            ),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$workingDays',
                                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Work',
                                    style: GoogleFonts.outfit(fontSize: 9, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildMiniIndicator('$workingDays Work', const Color(0xFF8B5CF6)),
                          _buildMiniIndicator('$offDays Off', const Color(0xFF10B981)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Shift Breakdown Bar (replacing temperature metric as requested)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141A26) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBreakdownCol('Morning', _statistics?['morning'] ?? 0, const Color(0xFFF59E0B)),
                _buildBreakdownCol('Afternoon', _statistics?['afternoon'] ?? 0, const Color(0xFF06B6D4)),
                _buildBreakdownCol('Night', _statistics?['night'] ?? 0, const Color(0xFF8B5CF6)),
                _buildBreakdownCol('Off Days', _statistics?['week_off'] ?? 0, const Color(0xFF10B981)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniIndicator(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildBreakdownCol(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          '$count',
          style: GoogleFonts.outfit(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildUpcomingList(bool isDark) {
    final today = DateTime.now();
    final upcomingShifts = _shifts.where((shift) {
      final shiftDate = DateTime.tryParse(shift.date);
      if (shiftDate == null) return false;
      return shiftDate.isAfter(today.subtract(const Duration(days: 1)));
    }).take(7).toList();

    if (upcomingShifts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141A26) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Next 7 Days Schedule',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Icon(Icons.calendar_today_rounded, size: 16, color: Colors.grey.shade500),
            ],
          ),
          const SizedBox(height: 12),
          ...upcomingShifts.map((shift) {
            final shiftDate = DateTime.parse(shift.date);
            final isToday = DateFormat('yyyy-MM-dd').format(shiftDate) == DateFormat('yyyy-MM-dd').format(today);
            final isTomorrow = DateFormat('yyyy-MM-dd').format(shiftDate) ==
                DateFormat('yyyy-MM-dd').format(today.add(const Duration(days: 1)));

            String dayLabel = DateFormat('EEE, MMM d').format(shiftDate);
            if (isToday) dayLabel = 'Today';
            if (isTomorrow) dayLabel = 'Tomorrow';

            final shiftColor = _getShiftColor(shift.shiftType);

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _editShiftDialog(shift),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: shiftColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_getShiftIcon(shift.shiftType), color: shiftColor, size: 18),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dayLabel,
                            style: GoogleFonts.outfit(
                              fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          if (shift.getTimeRange().isNotEmpty)
                            Text(
                              shift.getTimeRange(),
                              style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade500),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: shiftColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        shift.getDisplayName(),
                        style: GoogleFonts.outfit(
                          color: shiftColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F141C) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'My Shifts',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: -0.5),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          if (_hasData) ...[
            if (_rosterImageUrl != null)
              IconButton(
                icon: const Icon(Icons.photo_library_outlined),
                tooltip: 'View Original Roster Image',
                onPressed: _viewRosterImage,
              ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh Roster',
              onPressed: _loadShifts,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Clear Roster Data',
              onPressed: _clearData,
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadJSON,
        elevation: 3,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file_rounded),
        label: Text(
          _hasData ? 'Update Roster' : 'Upload Roster',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          _buildMonthNavigation(isDark),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
                : !_hasData
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.calendar_month_rounded, size: 64, color: primaryColor),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'No Shifts for $_selectedRosterMonth',
                                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Scan your monthly roster image or paste JSON to visualize your calendar heatmap.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade500),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: _uploadJSON,
                                icon: const Icon(Icons.add_a_photo_rounded),
                                label: Text(
                                  'Upload Roster',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadShifts,
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              _buildNextShiftHeroCard(isDark),
                              _buildCalendarHeatmap(isDark),
                              _buildStatsDashboard(isDark),
                              _buildUpcomingList(isDark),
                              const SizedBox(height: 96),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
