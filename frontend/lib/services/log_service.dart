import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'notification_service.dart';
import 'battery_optimization_service.dart';
import 'foreground_task_service.dart';

class LogService {
  static final LogService _instance = LogService._internal();
  final List<String> _logs = [];
  final ValueNotifier<List<String>> logsNotifier = ValueNotifier([]);

  factory LogService() {
    return _instance;
  }

  LogService._internal();

  // Helper for background tasks where we might not want to init the full service
  static void staticLog(String message) {
     final String timestamp = DateFormat('HH:mm:ss').format(DateTime.now());
     print('[$timestamp] $message');
  }

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

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  bool _isForegroundRunning = false;
  int _lastTick = 0;
  String _lastTime = 'N/A';

  @override
  void initState() {
    super.initState();
    _checkServiceStatus();
    
    // Listen for data from foreground task
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    super.dispose();
  }

  void _onReceiveTaskData(Object data) {
    if (data is Map<String, dynamic>) {
      setState(() {
        _lastTick = data['tick'] ?? 0;
        _lastTime = data['time'] ?? 'N/A';
      });
    }
  }

  Future<void> _checkServiceStatus() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (mounted) {
      setState(() {
        _isForegroundRunning = running;
      });
    }
  }

  Future<void> _toggleForegroundService() async {
    if (_isForegroundRunning) {
      await ForegroundTaskService().stopService();
    } else {
      ForegroundTaskService().init();
      await ForegroundTaskService().startService();
    }
    await _checkServiceStatus();
  }

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
                        const Divider(),
                        // *** Foreground Service Status ***
                        Row(
                          children: [
                            Icon(
                              _isForegroundRunning ? Icons.check_circle : Icons.error,
                              color: _isForegroundRunning ? Colors.green : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Foreground Service: ${_isForegroundRunning ? "RUNNING ✅" : "STOPPED ❌"}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isForegroundRunning ? Colors.green[800] : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        if (_isForegroundRunning)
                          Text('  Last Tick: #$_lastTick at $_lastTime', 
                               style: const TextStyle(fontSize: 12)),
                        const Text('  Gold fetch: every 3 min (TEST MODE)', 
                             style: TextStyle(fontSize: 11, color: Colors.orange)),
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              onPressed: _toggleForegroundService,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isForegroundRunning ? Colors.red : Colors.green,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(_isForegroundRunning ? '⏹️ Stop Service' : '▶️ Start Service'),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                await _checkServiceStatus();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Service: ${_isForegroundRunning ? "Running" : "Stopped"}')),
                                  );
                                }
                              },
                              child: const Text('🔄 Refresh'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => BatteryOptimizationService.showOptimizationPanel(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('⚙️ Fix Background Issues'),
                        ),
                      ],
                    );
                  }
                ),
              ),
              // Filter buttons for logs
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
            // Show all
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
