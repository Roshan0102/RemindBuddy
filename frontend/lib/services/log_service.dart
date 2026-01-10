import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';

class LogService {
  static final LogService _instance = LogService._internal();
  final List<String> _logs = [];
  final ValueNotifier<List<String>> logsNotifier = ValueNotifier([]);

  factory LogService() {
    return _instance;
  }

  LogService._internal();

  void log(String message) {
    final String timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    final String logEntry = '[$timestamp] $message';
    _logs.add(logEntry);
    logsNotifier.value = List.from(_logs); // Update listeners
    print(logEntry); // Also print to system console
  }

  void error(String message, [dynamic e]) {
    final String timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    final String logEntry = '🔴 [$timestamp] ERROR: $message ${e != null ? '($e)' : ''}';
    _logs.add(logEntry);
    logsNotifier.value = List.from(_logs);
    print(logEntry);
  }
  
  void clear() {
    _logs.clear();
    logsNotifier.value = [];
  }
}

class LogScreen extends StatelessWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => LogService().clear(),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () async {
              final String allLogs = LogService()._logs.join('\n');
              await Clipboard.setData(ClipboardData(text: allLogs));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logs copied to clipboard')),
                );
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: LogService().logsNotifier,
        builder: (context, logs, child) {
          return Column(
            children: [
              // Debug Panel
              Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.grey[200],
                width: double.infinity,
                child: StreamBuilder(
                  stream: Stream.periodic(const Duration(seconds: 1)),
                  builder: (context, snapshot) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🔧 Debug Info:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('App Time: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}'),
                        Text('Timezone: ${NotificationService.debugTimeZone}'),
                        Text('Init Status: ${NotificationService.isInitialized ? "Success" : "Pending/Failed"}'),
                        if (NotificationService.debugError != 'None')
                          Text('Error: ${NotificationService.debugError}', style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              onPressed: () => NotificationService().showImmediateNotification(),
                              child: const Text('🔔 Test'),
                            ),
                            ElevatedButton(
                              onPressed: () => NotificationService().checkPermissions(),
                              child: const Text('⏰ Perms'),
                            ),
                            ElevatedButton(
                              onPressed: () => NotificationService().checkPendingNotifications(),
                              child: const Text('📋 Pending'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Go to Settings > Apps > RemindBuddy > Battery > Unrestricted'),
                                duration: Duration(seconds: 5),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                          child: const Text('🔋 Fix Battery Settings', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    );
                  }
                ),
              ),
              Expanded(
                child: logs.isEmpty
                  ? const Center(child: Text('No logs yet.'))
                  : ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final isError = log.contains('🔴');
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          color: index % 2 == 0 ? Colors.grey[100] : Colors.white,
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              color: isError ? Colors.red : Colors.black87,
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ],
          );
        },
      ),
    );
  }
}
