import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
            onPressed: () {
              // TODO: Implement copy to clipboard
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied (simulated)')),
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: LogService().logsNotifier,
        builder: (context, logs, child) {
          if (logs.isEmpty) {
            return const Center(child: Text('No logs yet.'));
          }
          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              // Show newest at bottom, or reverse here if preferred
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
          );
        },
      ),
    );
  }
}
