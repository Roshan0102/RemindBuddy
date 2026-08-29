import 'package:flutter/material.dart';
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
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
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
            stream: _storage.getIncomingBuddyRequestsStream(),
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
        stream: _storage.getAllCalendarRemindersStream(),
        builder: (context, allSnapshot) {
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
                        color: isDark ? Colors.white : Colors.black87,
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
                        color: Theme.of(context).primaryColor.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
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
                    Text(
                      '${allReminders.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay ?? DateTime.now())).length} Tasks',
                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
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

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 90, top: 4),
          itemCount: groupedReminders.length,
          itemBuilder: (context, index) {
            final grouped = groupedReminders[index];
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
          },
        );
      },
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
      final updated = r.copyWith(status: newStatus);
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
