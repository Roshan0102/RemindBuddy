import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class LogService {
  static final LogService _instance = LogService._internal();
  final List<String> _logs = [];
  final ValueNotifier<List<String>> logsNotifier = ValueNotifier([]);

  factory LogService() {
    return _instance;
  }

  LogService._internal();

  static void staticLog(String message) {
     final String timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
     print('[$timestamp] $message');
  }

  void log(String message) {
    final String timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
    final String logEntry = '[$timestamp] $message';
    _logs.add(logEntry);
    logsNotifier.value = List.from(_logs);
    print(logEntry);
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

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Colors.grey[300],
                child: Row(
                  children: [
                    const Text('Filter: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    _buildFilterChip(logs, 'All', null),
                    _buildFilterChip(logs, '🌕 Gold', '[GOLD]'),
                    _buildFilterChip(logs, '📅 Shift', '[SHIFT]'),
                    _buildFilterChip(logs, '❌ Errors', 'ERROR'),
                  ],
                ),
              ),
              Expanded(
                child: logs.isEmpty
                  ? const Center(child: Text('No logs yet.'))
                  : ListView.builder(
                      itemCount: logs.length,
                      reverse: true, // Most recent first
                      itemBuilder: (context, index) {
                        final reversedIndex = logs.length - 1 - index;
                        final log = logs[reversedIndex];
                        final isError = log.contains('🔴') || log.contains('❌') || log.contains('FATAL');
                        final isGold = log.contains('[GOLD]');
                        final isShift = log.contains('[SHIFT]');
                        final isTick = log.contains('TICK');

                        Color bgColor;
                        if (isError) {
                          bgColor = Colors.red[50]!;
                        } else if (isGold) {
                          bgColor = Colors.amber[50]!;
                        } else if (isShift) {
                          bgColor = Colors.blue[50]!;
                        } else if (isTick) {
                          bgColor = Colors.green[50]!;
                        } else {
                          bgColor = index % 2 == 0 ? Colors.grey[100]! : Colors.white;
                        }

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          color: bgColor,
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
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

  Widget _buildFilterChip(List<String> allLogs, String label, String? filterKey) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () {
          if (filterKey == null) {
            LogService().logsNotifier.value = List.from(LogService()._logs);
          } else {
            final filtered = LogService()._logs.where((l) => l.contains(filterKey)).toList();
            LogService().logsNotifier.value = filtered;
          }
        },
        child: Chip(
          label: Text(label, style: const TextStyle(fontSize: 10)),
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
