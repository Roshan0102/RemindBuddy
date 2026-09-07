import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/daily_reminder.dart';
import '../services/storage_service.dart';

class DailyRemindersScreen extends StatefulWidget {
  const DailyRemindersScreen({super.key});

  @override
  State<DailyRemindersScreen> createState() => _DailyRemindersScreenState();
}

class _DailyRemindersScreenState extends State<DailyRemindersScreen> {
  final StorageService _storageService = StorageService();
  String _selectedFilter = 'All'; // 'All', 'Pending', 'Completed'

  String _getTodayDateStr() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  Future<void> _toggleCompletedToday(DailyReminder reminder) async {
    HapticFeedback.mediumImpact();
    final today = _getTodayDateStr();
    final isAlreadyCompleted = reminder.lastCompletedDate == today;

    final updated = reminder.copyWith(
      lastCompletedDate: isAlreadyCompleted ? '' : today,
    );

    await _storageService.updateDailyReminder(updated);

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isAlreadyCompleted ? Icons.undo_rounded : Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isAlreadyCompleted
                      ? 'Marked "${reminder.title}" as pending'
                      : 'Completed "${reminder.title}" for today! 🎯',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: isAlreadyCompleted ? Colors.blueGrey.shade800 : const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleReminderActive(DailyReminder reminder) async {
    HapticFeedback.selectionClick();
    final newState = !reminder.isActive;
    await _storageService.toggleDailyReminderActive(reminder.id!, newState);
  }

  Future<void> _deleteReminder(DailyReminder reminder) async {
    HapticFeedback.heavyImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Habit?',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${reminder.title}" from your daily schedule?',
          style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey.shade700),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Delete', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && reminder.id != null) {
      await _storageService.deleteDailyReminder(reminder.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Habit removed', style: GoogleFonts.outfit()),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _showAddOrEditSheet([DailyReminder? existingReminder]) async {
    HapticFeedback.lightImpact();
    final isEditing = existingReminder != null;
    final titleController = TextEditingController(text: existingReminder?.title ?? '');
    final descriptionController = TextEditingController(text: existingReminder?.description ?? '');

    TimeOfDay selectedTime = isEditing
        ? TimeOfDay(
            hour: int.parse(existingReminder.time.split(':')[0]),
            minute: int.parse(existingReminder.time.split(':')[1]),
          )
        : const TimeOfDay(hour: 8, minute: 0);

    bool isSaving = false;

    final presetSuggestions = [
      '💧 Drink 500ml Water',
      '💊 Morning Vitamins',
      '🧘 10m Meditation',
      '🏃 Daily 30m Workout',
      '📖 Read 15 Pages',
      '🌙 Plan Tomorrow',
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (innerCtx, setSheetState) {
          final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
          final primaryColor = Theme.of(sheetCtx).colorScheme.primary;

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              top: 12,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2430) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Edit Daily Habit' : 'Create Daily Habit',
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Build momentum with consistent reminders',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Quick Suggestion Chips (when creating new)
                  if (!isEditing) ...[
                    Text(
                      'QUICK SUGGESTIONS',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: presetSuggestions.map((suggestion) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(
                                suggestion,
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              backgroundColor: isDark
                                  ? const Color(0xFF283142)
                                  : const Color(0xFFF1F5F9),
                              elevation: 0,
                              pressElevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.grey.shade200,
                                ),
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setSheetState(() {
                                  titleController.text = suggestion;
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Title Field
                  TextField(
                    controller: titleController,
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      labelText: 'Habit Title',
                      hintText: 'e.g. Morning 15m Meditation',
                      prefixIcon: const Icon(Icons.track_changes_rounded),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF262F3E) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: primaryColor, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Description Field
                  TextField(
                    controller: descriptionController,
                    maxLines: 2,
                    style: GoogleFonts.outfit(fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Notes or Subtext (Optional)',
                      hintText: 'Add instructions, motivation or context...',
                      prefixIcon: const Icon(Icons.notes_rounded),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF262F3E) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: primaryColor, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Time Selection Section
                  Text(
                    'SCHEDULE TIME',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Time presets row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildTimePresetChip(
                        label: '🌅 Morning (08:00 AM)',
                        time: const TimeOfDay(hour: 8, minute: 0),
                        currentTime: selectedTime,
                        onTap: (t) => setSheetState(() => selectedTime = t),
                        isDark: isDark,
                        primaryColor: primaryColor,
                      ),
                      _buildTimePresetChip(
                        label: '☀️ Noon (12:30 PM)',
                        time: const TimeOfDay(hour: 12, minute: 30),
                        currentTime: selectedTime,
                        onTap: (t) => setSheetState(() => selectedTime = t),
                        isDark: isDark,
                        primaryColor: primaryColor,
                      ),
                      _buildTimePresetChip(
                        label: '🌇 Evening (06:00 PM)',
                        time: const TimeOfDay(hour: 18, minute: 0),
                        currentTime: selectedTime,
                        onTap: (t) => setSheetState(() => selectedTime = t),
                        isDark: isDark,
                        primaryColor: primaryColor,
                      ),
                      _buildTimePresetChip(
                        label: '🌙 Night (09:30 PM)',
                        time: const TimeOfDay(hour: 21, minute: 30),
                        currentTime: selectedTime,
                        onTap: (t) => setSheetState(() => selectedTime = t),
                        isDark: isDark,
                        primaryColor: primaryColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Custom Time Picker Pill
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      final picked = await showTimePicker(
                        context: sheetCtx,
                        initialTime: selectedTime,
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              timePickerTheme: TimePickerThemeData(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setSheetState(() => selectedTime = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF262F3E) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.3),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.alarm_rounded, color: primaryColor, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Trigger Time',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _formatTimeOfDay(selectedTime),
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Change',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, color: primaryColor, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const SizedBox(height: 20),

                  // Save Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              if (titleController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Please provide a habit title',
                                      style: GoogleFonts.outfit(),
                                    ),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                                return;
                              }

                              setSheetState(() => isSaving = true);
                              try {
                                final timeStr =
                                    '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

                                final reminder = existingReminder != null
                                    ? existingReminder.copyWith(
                                        title: titleController.text.trim(),
                                        description: descriptionController.text.trim(),
                                        time: timeStr,
                                        isAnnoying: false,
                                        snoozeEnabled: false,
                                      )
                                    : DailyReminder(
                                        title: titleController.text.trim(),
                                        description: descriptionController.text.trim(),
                                        time: timeStr,
                                        isActive: true,
                                        isAnnoying: false,
                                        snoozeEnabled: false,
                                      );

                                if (isEditing) {
                                  await _storageService.updateDailyReminder(reminder);
                                } else {
                                  await _storageService.insertDailyReminder(reminder);
                                }

                                if (sheetCtx.mounted) {
                                  Navigator.pop(sheetCtx);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        isEditing ? 'Habit updated! ✨' : 'New habit activated! 🚀',
                                        style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                                      ),
                                      backgroundColor: const Color(0xFF10B981),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (innerCtx.mounted) {
                                  setSheetState(() => isSaving = false);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isEditing ? 'Update Daily Habit' : 'Activate Habit',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimePresetChip({
    required String label,
    required TimeOfDay time,
    required TimeOfDay currentTime,
    required Function(TimeOfDay) onTap,
    required bool isDark,
    required Color primaryColor,
  }) {
    final isSelected = currentTime.hour == time.hour && currentTime.minute == time.minute;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600)),
      selected: isSelected,
      selectedColor: primaryColor.withValues(alpha: 0.18),
      backgroundColor: isDark ? const Color(0xFF283142) : const Color(0xFFF1F5F9),
      side: BorderSide(
        color: isSelected ? primaryColor : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200),
      ),
      onSelected: (sel) {
        if (sel) {
          HapticFeedback.selectionClick();
          onTap(time);
        }
      },
    );
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final hour = tod.hour;
    final minute = tod.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$hour12:$minute $period';
  }

  String _formatTime(String time24) {
    try {
      final parts = time24.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[parts.length - 1];
      final period = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$hour12:$minute $period';
    } catch (_) {
      return time24;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final todayDateStr = _getTodayDateStr();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F141C) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Daily Routines',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Add Routine',
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, color: primaryColor, size: 22),
            ),
            onPressed: () => _showAddOrEditSheet(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<DailyReminder>>(
        stream: _storageService.getDailyRemindersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2.5),
            );
          }

          final allReminders = snapshot.data ?? [];

          // Sort reminders by time
          allReminders.sort((a, b) => a.time.compareTo(b.time));

          final completedReminders = allReminders.where((r) => r.lastCompletedDate == todayDateStr).toList();
          final pendingReminders = allReminders.where((r) => r.lastCompletedDate != todayDateStr).toList();

          List<DailyReminder> displayReminders = allReminders;
          if (_selectedFilter == 'Pending') {
            displayReminders = pendingReminders;
          } else if (_selectedFilter == 'Completed') {
            displayReminders = completedReminders;
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Hero Progress Header
              if (allReminders.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: _buildProgressHeroBanner(
                      total: allReminders.length,
                      completed: completedReminders.length,
                      isDark: isDark,
                      primaryColor: primaryColor,
                    ),
                  ),
                ),

              // Filter Chips Row
              if (allReminders.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        _buildFilterPill(
                          label: 'All (${allReminders.length})',
                          filterKey: 'All',
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          label: 'Pending (${pendingReminders.length})',
                          filterKey: 'Pending',
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                        const SizedBox(width: 8),
                        _buildFilterPill(
                          label: 'Done (${completedReminders.length})',
                          filterKey: 'Completed',
                          isDark: isDark,
                          primaryColor: primaryColor,
                        ),
                      ],
                    ),
                  ),
                ),

              // Reminders List or Filter Empty State
              if (allReminders.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(isDark, primaryColor),
                )
              else if (displayReminders.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _selectedFilter == 'Completed'
                              ? Icons.check_circle_outline_rounded
                              : Icons.task_alt_rounded,
                          size: 52,
                          color: Colors.grey.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _selectedFilter == 'Completed'
                              ? 'No routines marked done today yet'
                              : 'All daily routines are done! 🎉',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 96),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final reminder = displayReminders[index];
                        final isCompleted = reminder.lastCompletedDate == todayDateStr;
                        return _buildReminderCard(
                          reminder: reminder,
                          isCompletedToday: isCompleted,
                          isDark: isDark,
                          primaryColor: primaryColor,
                        );
                      },
                      childCount: displayReminders.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOrEditSheet(),
        elevation: 3,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'New Routine',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildFilterPill({
    required String label,
    required String filterKey,
    required bool isDark,
    required Color primaryColor,
  }) {
    final isSelected = _selectedFilter == filterKey;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = filterKey);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor
              : (isDark ? const Color(0xFF1E2430) : const Color(0xFFEFF2F6)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressHeroBanner({
    required int total,
    required int completed,
    required bool isDark,
    required Color primaryColor,
  }) {
    final double progress = total == 0 ? 0.0 : (completed / total);
    final int percent = (progress * 100).toInt();

    String motivationalMessage;
    if (progress == 1.0) {
      motivationalMessage = 'Unstoppable! All daily goals completed! 🏆';
    } else if (progress >= 0.5) {
      motivationalMessage = 'Great momentum! Over halfway there! ⚡';
    } else if (completed > 0) {
      motivationalMessage = 'Good start! Keep crushing your day! 💪';
    } else {
      motivationalMessage = 'Ready to conquer today? Start checking off habits!';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFF1E40AF), const Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF3B82F6)).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular Progress Indicator
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                ),
                Center(
                  child: Text(
                    '$percent%',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),

          // Progress Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$completed of $total Done',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (progress == 1.0)
                      const Icon(Icons.stars_rounded, color: Colors.amberAccent, size: 18),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  motivationalMessage,
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard({
    required DailyReminder reminder,
    required bool isCompletedToday,
    required bool isDark,
    required Color primaryColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2230) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCompletedToday
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200),
          width: isCompletedToday ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showAddOrEditSheet(reminder),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Interactive Checkbox Button
                GestureDetector(
                  onTap: () => _toggleCompletedToday(reminder),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(top: 2, right: 14),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCompletedToday
                          ? const Color(0xFF10B981)
                          : (isDark ? const Color(0xFF263042) : Colors.grey.shade100),
                      border: Border.all(
                        color: isCompletedToday
                            ? const Color(0xFF10B981)
                            : (reminder.isActive ? primaryColor.withValues(alpha: 0.5) : Colors.grey.shade400),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isCompletedToday
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                          : (reminder.isActive
                              ? null
                              : Icon(Icons.pause_rounded, color: Colors.grey.shade400, size: 16)),
                    ),
                  ),
                ),

                // Title, Subtitle, & Badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              reminder.title,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                decoration: isCompletedToday
                                    ? TextDecoration.lineThrough
                                    : (!reminder.isActive ? TextDecoration.lineThrough : null),
                                color: isCompletedToday
                                    ? Colors.grey.shade500
                                    : (!reminder.isActive
                                        ? Colors.grey.shade500
                                        : (isDark ? Colors.white : Colors.grey.shade900)),
                              ),
                            ),
                          ),
                          if (isCompletedToday)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Done ✨',
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF10B981),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (reminder.description.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          reminder.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),

                      // Pill tags row: Time, Snooze, Persistent
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Time Pill
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.access_time_filled_rounded, size: 13, color: primaryColor),
                                const SizedBox(width: 4),
                                Text(
                                  _formatTime(reminder.time),
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Trailing Switch and Options Menu
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: reminder.isActive,
                        onChanged: (_) => _toggleReminderActive(reminder),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.grey.shade500,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onSelected: (val) {
                        if (val == 'edit') {
                          _showAddOrEditSheet(reminder);
                        } else if (val == 'delete') {
                          _deleteReminder(reminder);
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_rounded, size: 18, color: Colors.grey.shade700),
                              const SizedBox(width: 8),
                              Text('Edit', style: GoogleFonts.outfit(fontSize: 14)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                              const SizedBox(width: 8),
                              Text('Delete', style: GoogleFonts.outfit(fontSize: 14, color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color primaryColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryColor.withValues(alpha: 0.15),
                    primaryColor.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.alarm_on_rounded, size: 64, color: primaryColor),
            ),
            const SizedBox(height: 20),
            Text(
              'No Daily Routines Yet',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set recurring daily habits like drinking water, medications, or fitness routines to stay on top of your day.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddOrEditSheet(),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Create First Habit',
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
    );
  }
}
