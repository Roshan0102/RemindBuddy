import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/storage_service.dart';
import '../models/notification_history.dart';

class NotificationHistoryScreen extends StatelessWidget {
  const NotificationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final StorageService storage = StorageService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification History'),
      ),
      body: StreamBuilder<List<NotificationHistory>>(
        stream: storage.getNotificationHistoryStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final notifications = snapshot.data ?? [];
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none_outlined,
                    size: 80,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No notifications in the last 24 hours',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notif = notifications[index];
              return Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Colors.grey.withValues(alpha: 0.1),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTypeIcon(notif.type, context),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notif.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              notif.body,
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.8) ?? Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              DateFormat('hh:mm a • d MMM yyyy').format(notif.timestamp),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTypeIcon(String type, BuildContext context) {
    IconData iconData;
    Color iconColor;

    switch (type) {
      case 'CALENDAR_REMINDER':
        iconData = Icons.calendar_today_outlined;
        iconColor = Colors.orange;
        break;
      case 'DAILY_REMINDER':
        iconData = Icons.alarm_outlined;
        iconColor = Colors.blue;
        break;
      case 'SHIFT_REMINDER':
        iconData = Icons.work_outline;
        iconColor = Colors.purple;
        break;
      case 'GOLD_PRICE':
      case 'GOLD_CHIT_ADVICE':
        iconData = Icons.monetization_on_outlined;
        iconColor = Colors.amber.shade700;
        break;
      case 'TECH_EVENTS':
        iconData = Icons.event_outlined;
        iconColor = Colors.green;
        break;
      case 'WALKIN_DRIVES':
        iconData = Icons.directions_walk_outlined;
        iconColor = Colors.lightBlue;
        break;
      default:
        iconData = Icons.notifications_active_outlined;
        iconColor = Theme.of(context).primaryColor;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        color: iconColor,
        size: 22,
      ),
    );
  }
}
