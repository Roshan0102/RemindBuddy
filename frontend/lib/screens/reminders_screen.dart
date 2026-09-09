import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/storage_service.dart';
import 'add_task_screen.dart';
import '../models/calendar_reminder.dart';
import '../widgets/buddy_widgets.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _showPastReminders = false;
  final StorageService _storage = StorageService();
  late Stream<List<CalendarReminder>> _remindersStream;
  late Stream<List<Map<String, dynamic>>> _buddyRequestsStream;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _remindersStream = _storage.getAllCalendarRemindersStream();
    _buddyRequestsStream = _storage.getIncomingBuddyRequestsStream();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Reminders Calendar 📅',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _buddyRequestsStream,
            builder: (context, snapshot) {
              final requests = snapshot.data ?? [];
              final hasRequests = requests.isNotEmpty;
              return IconButton(
                icon: hasRequests
                    ? Badge(
                        label: Text(requests.length.toString()),
                        child: const Icon(Icons.people_outline),
                      )
                    : const Icon(Icons.people_outline),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    builder: (context) => BuddyRequestsSheet(),
                  );
                },
                tooltip: 'Buddy Link Requests',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const BuddySelectionDialog(),
              );
            },
            tooltip: 'Link a Buddy',
          ),
        ],
      ),
      body: StreamBuilder<List<CalendarReminder>>(
        stream: _remindersStream,
        builder: (context, allSnapshot) {
          if (allSnapshot.connectionState == ConnectionState.waiting && !allSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allReminders = allSnapshot.data ?? [];

          return Column(
            children: [
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                color: cardColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 6.0),
                  child: TableCalendar(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _focusedDay,
                    rowHeight: 44,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    eventLoader: (day) {
                      final dateStr = DateFormat('yyyy-MM-dd').format(day);
                      final dayReminders = allReminders
                          .where((r) =>
                              r.date == dateStr &&
                              r.status != 'completed' &&
                              r.status != 'expired')
                          .toList();
                      return GroupedCalendarReminder.groupList(dayReminders);
                    },
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = focusedDay;
                        _showPastReminders = false;
                      });
                    },
                    calendarStyle: CalendarStyle(
                      defaultTextStyle: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      weekendTextStyle: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        fontWeight: FontWeight.w600,
                      ),
                      outsideTextStyle: TextStyle(
                        color: isDark ? Colors.white30 : Colors.black26,
                        fontWeight: FontWeight.normal,
                      ),
                      disabledTextStyle: TextStyle(
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      todayTextStyle: TextStyle(
                        color: isDark ? Colors.cyanAccent : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                      selectedTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      markerDecoration: const BoxDecoration(
                        color: Colors.orangeAccent,
                        shape: BoxShape.circle,
                      ),
                      markerSize: 6,
                      markersAlignment: Alignment.bottomCenter,
                      todayDecoration: BoxDecoration(
                        color: isDark
                            ? Colors.cyan.withValues(alpha: 0.22)
                            : Theme.of(context).primaryColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? Colors.cyanAccent : Theme.of(context).primaryColor,
                          width: 1.8,
                        ),
                      ),
                      selectedDecoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2563EB) : Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      weekendStyle: TextStyle(
                        color: isDark ? const Color(0xFFFDBA74) : Colors.deepOrange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                      headerPadding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedDay == null
                          ? 'Today\'s Reminders'
                          : 'Reminders for ${DateFormat('MMM d, yyyy').format(_selectedDay!)}',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showPastReminders = !_showPastReminders;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF38BDF8).withValues(alpha: 0.15)
                                  : Theme.of(context).primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF38BDF8).withValues(alpha: 0.4)
                                    : Theme.of(context).primaryColor.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showPastReminders ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 14,
                                  color: isDark ? const Color(0xFF38BDF8) : Theme.of(context).primaryColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showPastReminders ? 'Hide' : 'Show',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: isDark ? const Color(0xFF38BDF8) : Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${allReminders.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay ?? DateTime.now())).length} Tasks',
                          style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 12),
              Expanded(
                child: _buildReminderList(),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddTaskScreen(selectedDate: _selectedDay),
            ),
          );
          if (result == true) {
            setState(() {});
          }
        },
        label: const Text('Add Reminder', style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildReminderList() {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDay ?? DateTime.now());

    return StreamBuilder<List<CalendarReminder>>(
      stream: _storage.getCalendarRemindersStream(dateStr),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final reminders = snapshot.data ?? [];
        final groupedReminders = GroupedCalendarReminder.groupList(reminders);

        if (groupedReminders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_available_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Text(
                  'No reminders for this day',
                  style: GoogleFonts.outfit(color: Colors.grey, fontSize: 15),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tap "+ Add Reminder" below to create one',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          );
        }

        final isDarkMode = Theme.of(context).brightness == Brightness.dark;

        // Separate reminders into upcoming/recent vs past sent (> 5 mins)
        final upcomingReminders = <GroupedCalendarReminder>[];
        final pastReminders = <GroupedCalendarReminder>[];

        for (final g in groupedReminders) {
          if (_isPastSentReminder(g)) {
            pastReminders.add(g);
          } else {
            upcomingReminders.add(g);
          }
        }

        if (upcomingReminders.isEmpty && pastReminders.isNotEmpty) {
          if (_showPastReminders) {
            return ListView(
              padding: const EdgeInsets.only(bottom: 90, top: 4),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Text(
                    'Past Reminders (${pastReminders.length})',
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                for (int i = 0; i < pastReminders.length; i++)
                  _buildReminderCard(pastReminders[i], i, isDarkMode),
              ],
            );
          }

          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.done_all_rounded, size: 36, color: Colors.green.withValues(alpha: 0.7)),
                  const SizedBox(height: 8),
                  Text(
                    'All upcoming reminders completed for this day',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${pastReminders.length} past reminder${pastReminders.length > 1 ? 's' : ''} hidden',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _showPastReminders = true;
                      });
                    },
                    icon: Icon(
                      Icons.visibility_outlined,
                      size: 15,
                      color: isDarkMode ? const Color(0xFF38BDF8) : Theme.of(context).primaryColor,
                    ),
                    label: Text(
                      'Show ${pastReminders.length} Past Reminder${pastReminders.length > 1 ? 's' : ''}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? const Color(0xFF38BDF8) : Theme.of(context).primaryColor,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: isDarkMode
                            ? const Color(0xFF38BDF8).withValues(alpha: 0.5)
                            : Theme.of(context).primaryColor.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 90, top: 4),
          children: [
            for (int i = 0; i < upcomingReminders.length; i++)
              _buildReminderCard(upcomingReminders[i], i, isDarkMode),
            if (pastReminders.isNotEmpty && _showPastReminders) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Past Reminders (${pastReminders.length})',
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
              for (int i = 0; i < pastReminders.length; i++)
                _buildReminderCard(pastReminders[i], upcomingReminders.length + i, isDarkMode),
            ],
          ],
        );
      },
    );
  }

  DateTime? _parseReminderDateTime(String dateStr, String timeStr) {
    try {
      final dateParts = dateStr.trim().split('-');
      if (dateParts.length < 3) return null;
      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      final cleanTime = timeStr.trim();
      final hasAmPm = cleanTime.toLowerCase().contains('am') || cleanTime.toLowerCase().contains('pm');

      if (hasAmPm) {
        final isPm = cleanTime.toLowerCase().contains('pm');
        final timeWithoutAmPm = cleanTime.replaceAll(RegExp(r'[a-zA-Z]'), '').trim();
        final parts = timeWithoutAmPm.split(':');
        var hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        if (isPm && hour < 12) hour += 12;
        if (!isPm && hour == 12) hour = 0;
        return DateTime(year, month, day, hour, minute);
      } else {
        final parts = cleanTime.split(':');
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return DateTime(year, month, day, hour, minute);
      }
    } catch (_) {
      return null;
    }
  }

  bool _isPastSentReminder(GroupedCalendarReminder grouped) {
    final isDone = grouped.status == 'completed' || grouped.status == 'expired';
    if (!isDone) return false;

    final now = DateTime.now();

    // 1. Check notifiedAt if present
    if (grouped.notifiedAt != null) {
      final diff = now.difference(grouped.notifiedAt!.toDate());
      return diff.inMinutes >= 5;
    }
    for (final r in grouped.originalReminders) {
      if (r.notifiedAt != null) {
        final diff = now.difference(r.notifiedAt!.toDate());
        return diff.inMinutes >= 5;
      }
    }

    // 2. Check scheduled date and time
    final scheduled = _parseReminderDateTime(grouped.date, grouped.time);
    if (scheduled != null) {
      final diff = now.difference(scheduled);
      return diff.inMinutes >= 5;
    }

    // Fallback: if completed/expired without timestamp, treat as past
    return true;
  }

  Widget _buildReminderCard(GroupedCalendarReminder grouped, int index, bool isDarkMode) {
    final isCompleted = (grouped.status == 'completed');
    final primaryId = grouped.primaryReminder.id ?? index.toString();

    return Dismissible(
      key: Key(primaryId),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20.0),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await _confirmDeleteGroup(grouped, silent: true);
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 1,
        color: isCompleted
            ? (isDarkMode ? Colors.green.withValues(alpha: 0.15) : Colors.green.shade50)
            : (isDarkMode ? const Color(0xFF1E293B) : Colors.white),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: InkWell(
            onTap: () => _toggleGroupStatus(grouped),
            child: _buildStatusIcon(grouped.status),
          ),
          title: Text(
            grouped.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
              color: isCompleted ? Colors.grey : (isDarkMode ? Colors.white : Colors.black87),
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (grouped.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  grouped.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.access_time_rounded, size: 12, color: Colors.blueAccent),
                        const SizedBox(width: 4),
                        Text(
                          grouped.time,
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...grouped.recipientUsernames.map((userLabel) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: userLabel.startsWith('from')
                              ? Colors.purple.shade50
                              : (userLabel == 'Myself' ? Colors.blue.shade50 : Colors.orange.shade50),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          userLabel,
                          style: TextStyle(
                            color: userLabel.startsWith('from')
                                ? Colors.purple.shade800
                                : (userLabel == 'Myself' ? Colors.blue.shade800 : Colors.orange.shade800),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )),
                ],
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                tooltip: 'Edit Reminder',
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddTaskScreen(
                        selectedDate: _selectedDay,
                        existingReminder: grouped.primaryReminder,
                      ),
                    ),
                  );
                  if (result == true) {
                    setState(() {});
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                tooltip: 'Delete Reminder',
                onPressed: () => _confirmDeleteGroup(grouped, silent: false),
              ),
            ],
          ),
          isThreeLine: true,
        ),
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'scheduled':
      case 'pending':
        return const Icon(Icons.alarm_rounded, color: Colors.blueAccent, size: 24);
      case 'notified':
        return const Icon(Icons.help_outline_rounded, color: Colors.amber, size: 24);
      case 'completed':
        return const Icon(Icons.check_circle_rounded, color: Colors.green, size: 24);
      case 'expired':
        return const Icon(Icons.history_rounded, color: Colors.grey, size: 24);
      case 'error':
        return const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 24);
      default:
        return const Icon(Icons.alarm_rounded, color: Colors.blueAccent, size: 24);
    }
  }

  Future<void> _toggleGroupStatus(GroupedCalendarReminder grouped) async {
    final newStatus = (grouped.status == 'completed') ? 'scheduled' : 'completed';
    for (final r in grouped.originalReminders) {
      final updated = r.copyWith(
        status: newStatus,
        notifiedAt: newStatus == 'completed' ? (r.notifiedAt ?? Timestamp.now()) : null,
      );
      await _storage.updateCalendarReminder(updated);
    }
    if (mounted) setState(() {});
  }

  Future<bool> _confirmDeleteGroup(GroupedCalendarReminder grouped, {bool silent = false}) async {
    bool? result = silent;

    if (!silent) {
      result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Delete Reminder?'),
          content: const Text('This will delete the reminder for all associated recipients.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    }

    if (result == true) {
      try {
        for (final r in grouped.originalReminders) {
          if (r.id != null) {
            await _storage.deleteCalendarReminder(r.id!);
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reminder deleted')),
          );
        }
        return true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
        return false;
      }
    }
    return false;
  }
}
