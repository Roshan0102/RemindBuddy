import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/shift.dart';
import '../services/storage_service.dart';
import '../services/shift_service.dart';
import '../services/log_service.dart';

class MyShiftsScreen extends StatefulWidget {
  const MyShiftsScreen({super.key});

  @override
  State<MyShiftsScreen> createState() => _MyShiftsScreenState();
}

class _MyShiftsScreenState extends State<MyShiftsScreen> {
  final StorageService _storage = StorageService();
  final ShiftService _shiftService = ShiftService();
  
  List<Shift> _shifts = [];
  Map<String, String>? _metadata;
  Map<String, int>? _statistics;
  bool _isLoading = true;
  bool _hasData = false;

  @override
  void initState() {
    super.initState();
    _loadShifts();
  }

  Future<void> _loadShifts() async {
    setState(() => _isLoading = true);
    
    try {
      final metadata = await _storage.getShiftMetadata();
      final shiftsData = await _storage.getAllShifts();
      
      if (metadata != null && shiftsData.isNotEmpty) {
        final shifts = shiftsData.map((s) => Shift.fromMap(s)).toList();
        
        // Parse month string to get YYYY-MM format for database query
        // metadata['month'] is like "February 2026"
        String monthForQuery = _parseMonthForQuery(metadata['month']!);
        final stats = await _storage.getShiftStatistics(monthForQuery);
        
        setState(() {
          _metadata = metadata;
          _shifts = shifts;
          _statistics = stats;
          _hasData = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _hasData = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      LogService().error('Failed to load shifts', e);
      setState(() => _isLoading = false);
    }
  }

  /// Parse month string like "February 2026" to "2026-02" format
  String _parseMonthForQuery(String monthStr) {
    try {
      // monthStr is like "February 2026"
      final parts = monthStr.split(' ');
      if (parts.length == 2) {
        final monthName = parts[0];
        final year = parts[1];
        
        // Convert month name to number
        final monthNames = [
          'January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December'
        ];
        
        final monthIndex = monthNames.indexOf(monthName) + 1;
        if (monthIndex > 0) {
          return '$year-${monthIndex.toString().padLeft(2, '0')}';
        }
      }
    } catch (e) {
      LogService().error('Error parsing month', e);
    }
    
    // Fallback: return current month
    return DateFormat('yyyy-MM').format(DateTime.now());
  }

  Future<void> _uploadJSON() async {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Upload Shift Roster'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste your JSON roster data below:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: '{\n  "employee_name": "...",\n  "month": "...",\n  "shifts": [...]\n}',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final jsonData = json.decode(controller.text);
                final roster = ShiftRoster.fromJson(jsonData);
                
                // Save to database
                final shiftsToSave = roster.shifts.map((s) => s.toMap()).toList();
                await _storage.saveShiftRoster(
                  roster.employeeName,
                  roster.month,
                  shiftsToSave,
                );
                
                // Schedule notifications
                await _shiftService.scheduleDailyShiftNotification();
                await _shiftService.scheduleAllAmlaReminders();
                
                Navigator.pop(context);
                _loadShifts();
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ Loaded ${roster.shifts.length} shifts for ${roster.month}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Error: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Shifts?'),
        content: const Text('This will delete all shift data and cancel notifications.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.clearAllShifts();
      await _shiftService.cancelAllShiftNotifications();
      _loadShifts();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All shift data cleared')),
        );
      }
    }
  }

  Color _getShiftColor(String shiftType) {
    switch (shiftType) {
      case 'morning':
        return Colors.orange;
      case 'afternoon':
        return Colors.blue;
      case 'night':
        return Colors.indigo;
      case 'week_off':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getShiftIcon(String shiftType) {
    switch (shiftType) {
      case 'morning':
        return Icons.wb_sunny;
      case 'afternoon':
        return Icons.wb_twilight;
      case 'night':
        return Icons.nightlight_round;
      case 'week_off':
        return Icons.beach_access;
      default:
        return Icons.work;
    }
  }

  Widget _buildStatisticsCard() {
    if (_statistics == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Month Statistics - ${_metadata!['month']}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Morning', _statistics!['morning']!, Colors.orange),
                _buildStatItem('Afternoon', _statistics!['afternoon']!, Colors.blue),
                _buildStatItem('Night', _statistics!['night']!, Colors.indigo),
                _buildStatItem('Week Off', _statistics!['week_off']!, Colors.green),
              ],
            ),
            const Divider(height: 24),
            Text(
              'Total Working Days: ${_statistics!['total_working']}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildUpcomingShifts() {
    final today = DateTime.now();
    final upcomingShifts = _shifts.where((shift) {
      final shiftDate = DateTime.parse(shift.date);
      return shiftDate.isAfter(today.subtract(const Duration(days: 1)));
    }).take(7).toList();

    if (upcomingShifts.isEmpty) {
      return const Card(
        margin: EdgeInsets.all(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No upcoming shifts'),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Next 7 Days',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ...upcomingShifts.map((shift) {
            final shiftDate = DateTime.parse(shift.date);
            final isToday = DateFormat('yyyy-MM-dd').format(shiftDate) == 
                           DateFormat('yyyy-MM-dd').format(today);
            final isTomorrow = DateFormat('yyyy-MM-dd').format(shiftDate) == 
                              DateFormat('yyyy-MM-dd').format(today.add(const Duration(days: 1)));

            String dayLabel = DateFormat('EEE, MMM d').format(shiftDate);
            if (isToday) dayLabel = 'Today';
            if (isTomorrow) dayLabel = 'Tomorrow';

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: _getShiftColor(shift.shiftType).withOpacity(0.2),
                child: Icon(
                  _getShiftIcon(shift.shiftType),
                  color: _getShiftColor(shift.shiftType),
                ),
              ),
              title: Text(
                dayLabel,
                style: TextStyle(
                  fontWeight: isToday || isTomorrow ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Text(shift.getTimeRange()),
              trailing: Text(
                shift.getDisplayName(),
                style: TextStyle(
                  color: _getShiftColor(shift.shiftType),
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAllShiftsCalendar() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'All Shifts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_shifts.length} days',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: ListView.builder(
              itemCount: _shifts.length,
              itemBuilder: (context, index) {
                final shift = _shifts[index];
                final shiftDate = DateTime.parse(shift.date);

                return ListTile(
                  dense: true,
                  leading: Icon(
                    _getShiftIcon(shift.shiftType),
                    color: _getShiftColor(shift.shiftType),
                    size: 20,
                  ),
                  title: Text(
                    DateFormat('EEE, MMM d').format(shiftDate),
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    shift.getTimeRange(),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getShiftColor(shift.shiftType).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      shift.shiftType.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getShiftColor(shift.shiftType),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Shifts'),
        actions: [
          if (_hasData)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadShifts,
              tooltip: 'Refresh',
            ),
          if (_hasData)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearData,
              tooltip: 'Clear All Data',
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadJSON,
        icon: const Icon(Icons.upload_file),
        label: Text(_hasData ? 'Update Roster' : 'Upload Roster'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_hasData
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_month, size: 80, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No shift data yet',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Upload your roster JSON to get started',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildStatisticsCard(),
                      _buildUpcomingShifts(),
                      _buildAllShiftsCalendar(),
                      const SizedBox(height: 80), // Space for FAB
                    ],
                  ),
                ),
    );
  }
}
