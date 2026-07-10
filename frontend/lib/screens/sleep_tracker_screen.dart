import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class SleepTrackerScreen extends StatefulWidget {
  const SleepTrackerScreen({super.key});

  @override
  State<SleepTrackerScreen> createState() => _SleepTrackerScreenState();
}

class _SleepTrackerScreenState extends State<SleepTrackerScreen> {
  static const _channel = MethodChannel('com.remindbuddy/sleep_tracker');
  bool _permissionGranted = false;
  double _todaySleepDuration = 0.0;
  String _todayStartTime = '';
  String _todayEndTime = '';
  List<Map<String, dynamic>> _sleepHistory = [];
  List<String> _rawLogs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSleepData();
  }

  Future<void> _loadSleepData() async {
    final prefs = await SharedPreferences.getInstance();
    bool granted = false;
    if (kIsWeb) {
      granted = true;
    } else {
      try {
        granted = await _channel.invokeMethod<bool>('checkPermission') ?? false;
        await prefs.setBool('sleep_api_permission_granted', granted);
      } catch (e) {
        granted = prefs.getBool('sleep_api_permission_granted') ?? false;
      }
    }
    
    // Load local history list
    final historyStrings = prefs.getStringList('sleep_tracker_history') ?? [];
    List<Map<String, dynamic>> history = [];
    
    for (var str in historyStrings) {
      final parts = str.split('|');
      if (parts.length >= 4) {
        history.add({
          'date': parts[0],
          'startTime': parts[1],
          'endTime': parts[2],
          'duration': double.tryParse(parts[3]) ?? 0.0,
        });
      }
    }

    // Load raw logs
    final rawLogs = prefs.getStringList('sleep_tracker_raw_logs') ?? [];
    rawLogs.sort((a, b) => b.compareTo(a)); // Sort descending text (starts with date)

    // Sort history by date descending
    history.sort((a, b) => b['date'].compareTo(a['date']));

    // Determine today's/last night's sleep duration
    double todayDur = 0.0;
    String todayStart = '';
    String todayEnd = '';
    if (history.isNotEmpty) {
      todayDur = history.first['duration'];
      todayStart = history.first['startTime'];
      todayEnd = history.first['endTime'];
    }

    setState(() {
      _permissionGranted = granted;
      _sleepHistory = history;
      _rawLogs = rawLogs;
      _todaySleepDuration = todayDur;
      _todayStartTime = todayStart;
      _todayEndTime = todayEnd;
      _isLoading = false;
    });
  }



  Future<void> _requestPermission() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.directions_run, color: Colors.indigo, size: 28),
            const SizedBox(width: 8),
            Text('Activity Sensor Permission', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'RemindBuddy requires physical activity sensor permission to access the Android Sleep API.\n\nThis allows Play Services to detect sleep intervals efficiently using on-device sensors without draining the battery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Deny', style: GoogleFonts.outfit(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final bool granted = await _channel.invokeMethod<bool>('requestPermission') ?? false;
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('sleep_api_permission_granted', granted);
                
                if (granted) {
                  await _channel.invokeMethod('requestSleepUpdates');
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Android Sleep API updates successfully registered!'),
                      backgroundColor: Color(0xFF0D9488),
                    ),
                  );
                }
                
                setState(() {
                  _permissionGranted = granted;
                });
                _loadSleepData();
              } catch (e) {
                print("Error requesting permission or subscribing: $e");
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Allow', style: GoogleFonts.outfit()),
          ),
        ],
      ),
    );
  }

  Future<void> _simulateSleepEvent(double hours) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    
    // Choose start/end times depending on simulated hours
    String start = '11:00 PM';
    String end = '07:00 AM';
    if (hours < 6) {
      start = '01:00 AM';
      end = '06:30 AM';
    } else if (hours < 7) {
      start = '11:30 PM';
      end = '06:00 AM';
    } else {
      start = '10:30 PM';
      end = '07:00 AM';
    }

    final newRecord = '$dateStr|$start|$end|$hours';
    
    final prefs = await SharedPreferences.getInstance();
    final currentHistory = prefs.getStringList('sleep_tracker_history') ?? [];
    
    // Remove if there's already an entry for today
    currentHistory.removeWhere((item) => item.startsWith(dateStr));
    currentHistory.insert(0, newRecord);
    
    await prefs.setStringList('sleep_tracker_history', currentHistory);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Simulated a sleep event of $hours hours!'),
        backgroundColor: _getStatusColor(hours),
      ),
    );
    
    _loadSleepData();
  }

  Future<void> _clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sleep_tracker_history');
    await prefs.remove('sleep_tracker_raw_logs');
    await prefs.remove('sleep_api_permission_granted');
    if (!kIsWeb) {
      try {
        await _channel.invokeMethod('removeSleepUpdates');
      } catch (e) {
        print("Error removing sleep updates: $e");
      }
    }
    setState(() {
      _sleepHistory.clear();
      _rawLogs.clear();
      _todaySleepDuration = 0.0;
      _todayStartTime = '';
      _todayEndTime = '';
      _permissionGranted = kIsWeb;
    });
  }

  Color _getStatusColor(double hours) {
    if (hours >= 7.0) {
      return const Color(0xFF0D9488); // Teal (Good)
    } else if (hours >= 6.0) {
      return const Color(0xFFD97706); // Amber/Yellow (OK)
    } else {
      return const Color(0xFFDC2626); // Red (Bad)
    }
  }

  String _getStatusText(double hours) {
    if (hours >= 7.0) {
      return 'Good';
    } else if (hours >= 6.0) {
      return 'OK';
    } else {
      return 'Bad';
    }
  }

  String _getStatusDescription(double hours) {
    if (hours >= 7.0) {
      return 'Great sleep! Your body is fully recovered.';
    } else if (hours >= 6.0) {
      return 'Moderate sleep. Try going to bed earlier tonight.';
    } else {
      return 'Insufficient sleep. Your body needs more rest!';
    }
  }

  void _showRawLogsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Raw Sleep API Logs', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: _rawLogs.isEmpty
              ? const Center(child: Text('No raw events received yet.'))
              : ListView.builder(
                  itemCount: _rawLogs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text(
                        _rawLogs[index],
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? Colors.white70 : const Color(0xFF475569);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Sleep Tracker',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: _showRawLogsDialog,
            tooltip: 'View Raw API Logs',
          ),
          if (_sleepHistory.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Reset Tracker'),
                    content: const Text('Are you sure you want to clear all sleep history and reset permissions?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _clearAllData();
                        },
                        child: const Text('Reset', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
              tooltip: 'Reset sleep data',
            )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Permission Banner
            if (!_permissionGranted)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.indigo, Colors.blueAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.white, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'Sleep Tracker Inactive',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enable the low-power Android Sleep API to start tracking your sleep cycles automatically.',
                      style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _requestPermission,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.indigo,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Enable Tracking', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

            // Top Status Ring Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'Last Night\'s Sleep',
                    style: GoogleFonts.outfit(
                      color: subtextColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Circular Progress Ring
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: CircularProgressIndicator(
                          value: _todaySleepDuration > 0.0 ? (_todaySleepDuration / 10.0).clamp(0.0, 1.0) : 0.0,
                          strokeWidth: 14,
                          backgroundColor: Colors.grey.withOpacity(0.15),
                          color: _getStatusColor(_todaySleepDuration),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _todaySleepDuration > 0.0 ? '${_todaySleepDuration.toStringAsFixed(1)}h' : 'No Data',
                            style: GoogleFonts.outfit(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          if (_todaySleepDuration > 0.0) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getStatusColor(_todaySleepDuration).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                _getStatusText(_todaySleepDuration),
                                style: GoogleFonts.outfit(
                                  color: _getStatusColor(_todaySleepDuration),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (_todaySleepDuration > 0.0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.bedtime_outlined, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          '$_todayStartTime - $_todayEndTime',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: subtextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getStatusDescription(_todaySleepDuration),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: subtextColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ] else ...[
                    Text(
                      'No sleep cycles logged yet. Use the simulation tools below to test the dashboard.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: subtextColor,
                      ),
                    ),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Simulation Controls Card
            Text(
              'Simulation Tools',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Simulate a Sleep API Callback:',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: subtextColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _simulateSleepEvent(8.5),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488).withOpacity(0.1),
                            foregroundColor: const Color(0xFF0D9488),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('8.5h (Good)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _simulateSleepEvent(6.5),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706).withOpacity(0.1),
                            foregroundColor: const Color(0xFFD97706),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('6.5h (OK)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _simulateSleepEvent(5.0),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626).withOpacity(0.1),
                            foregroundColor: const Color(0xFFDC2626),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('5.0h (Bad)'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Sleep History logs
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sleep History Logs',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                Text(
                  '${_sleepHistory.length} Days logged',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: subtextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_sleepHistory.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: [
                      Icon(Icons.history, size: 48, color: Colors.grey.withOpacity(0.4)),
                      const SizedBox(height: 8),
                      Text(
                        'No history logged yet.',
                        style: GoogleFonts.outfit(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: cardBgColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(1.8),
                      2: FlexColumnWidth(1.0),
                      3: FlexColumnWidth(1.0),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      // Header Row
                      TableRow(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF334155) : Colors.grey[100],
                        ),
                        children: [
                          _buildTableHeader('Date'),
                          _buildTableHeader('Interval'),
                          _buildTableHeader('Duration'),
                          _buildTableHeader('Status'),
                        ],
                      ),
                      // Data Rows
                      ..._sleepHistory.map((log) {
                        final double duration = log['duration'];
                        final String rawDate = log['date'];
                        String displayDate = rawDate;
                        try {
                          final parsedDate = DateFormat('yyyy-MM-dd').parse(rawDate);
                          displayDate = DateFormat('MMM d, E').format(parsedDate);
                        } catch (_) {}

                        return TableRow(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.withOpacity(0.1)),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              child: Text(
                                displayDate,
                                style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                              child: Text(
                                '${log['startTime']} - ${log['endTime']}',
                                style: GoogleFonts.outfit(fontSize: 11, color: subtextColor),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                              child: Text(
                                '${duration.toStringAsFixed(1)} hrs',
                                style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500, color: textColor),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(duration).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _getStatusText(duration),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _getStatusColor(duration),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.grey[500],
        ),
      ),
    );
  }
}
