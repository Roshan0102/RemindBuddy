import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FeatureLogEntry {
  final String id;
  final String feature; // 'auto_apply', 'cold_outreach', 'tech_events', 'walkin_drives'
  final String featureTitle;
  final String status; // 'success', 'no_results', 'skipped', 'error'
  final int count;
  final String message;
  final String scheduledSlot;
  final List<String> details;
  final DateTime timestamp;
  final bool isManual;

  FeatureLogEntry({
    required this.id,
    required this.feature,
    required this.featureTitle,
    required this.status,
    required this.count,
    required this.message,
    required this.scheduledSlot,
    required this.details,
    required this.timestamp,
    this.isManual = false,
  });

  factory FeatureLogEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime ts = DateTime.now();
    final rawTs = data['timestamp'];
    if (rawTs is Timestamp) {
      ts = rawTs.toDate();
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    }

    return FeatureLogEntry(
      id: doc.id,
      feature: data['feature']?.toString() ?? 'auto_apply',
      featureTitle: data['featureTitle']?.toString() ?? 'Automation Feature',
      status: data['status']?.toString() ?? 'success',
      count: (data['count'] as num?)?.toInt() ?? 0,
      message: data['message']?.toString() ?? '',
      scheduledSlot: data['scheduledSlot']?.toString() ?? '',
      details: List<String>.from(data['details'] ?? []),
      timestamp: ts,
      isManual: data['isManual'] == true,
    );
  }
}

class FeatureLogsScreen extends StatefulWidget {
  final String title;
  final List<String> allowedFeatures;

  const FeatureLogsScreen({
    super.key,
    required this.title,
    required this.allowedFeatures,
  });

  @override
  State<FeatureLogsScreen> createState() => _FeatureLogsScreenState();
}

class _FeatureLogsScreenState extends State<FeatureLogsScreen> {
  String _selectedFilter = 'all';
  bool _isLoadingFallback = true;
  List<FeatureLogEntry> _synthesizedFallbackLogs = [];

  @override
  void initState() {
    super.initState();
    _loadHistoricalFallback();
  }

  /// Synthesizes historical runs from existing user timestamps and collections
  /// if fewer than 10 logs are present in Firestore.
  Future<void> _loadHistoricalFallback() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingFallback = false);
      return;
    }

    try {
      final userDocSnap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final uData = userDocSnap.data() ?? {};

      final List<FeatureLogEntry> fallbacks = [];

      // 1. Auto-Apply Fallback Synthesizer
      if (widget.allowedFeatures.contains('auto_apply')) {
        final jobsLastRan = uData['jobsLastRan'];
        final jobsLastApplied = uData['jobsLastApplied'];

        DateTime? lastRanDt;
        if (jobsLastRan is Timestamp) lastRanDt = jobsLastRan.toDate();

        // Check recent auto-applied applications
        final appsSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('job_applications')
            .where('isAutoApplied', isEqualTo: true)
            .orderBy('appliedAt', descending: true)
            .limit(10)
            .get();

        if (appsSnap.docs.isNotEmpty) {
          final Map<String, List<Map<String, dynamic>>> appsByDaySlot = {};
          for (final d in appsSnap.docs) {
            final ad = d.data();
            final at = ad['appliedAt'];
            DateTime dt = DateTime.now();
            if (at is Timestamp) dt = at.toDate();
            final key = DateFormat('yyyy-MM-dd_a').format(dt);
            appsByDaySlot.putIfAbsent(key, () => []).add(ad);
          }

          appsByDaySlot.forEach((slotKey, appList) {
            final firstAt = appList.first['appliedAt'];
            DateTime dt = DateTime.now();
            if (firstAt is Timestamp) dt = firstAt.toDate();

            final slotTime = dt.hour >= 16 ? '10:00 PM' : '10:00 AM';
            final compNames = appList.map((a) => "${a['jobTitle'] ?? 'Developer'} at ${a['companyName'] ?? 'Company'}").toList();

            fallbacks.add(FeatureLogEntry(
              id: 'fallback_auto_$slotKey',
              feature: 'auto_apply',
              featureTitle: 'Auto-Apply Agent',
              status: 'success',
              count: appList.length,
              message: 'Auto-applied to ${appList.length} job(s): ${compNames.take(2).join(', ')}',
              scheduledSlot: slotTime,
              details: compNames,
              timestamp: dt,
            ));
          });
        }

        // Add the most recent lastRan entry if not covered
        if (lastRanDt != null && fallbacks.where((f) => f.feature == 'auto_apply').isEmpty) {
          fallbacks.add(FeatureLogEntry(
            id: 'fallback_auto_last_ran',
            feature: 'auto_apply',
            featureTitle: 'Auto-Apply Agent',
            status: jobsLastApplied != null ? 'success' : 'no_results',
            count: jobsLastApplied != null ? 1 : 0,
            message: jobsLastApplied != null
                ? 'Auto-applied to matching verified openings.'
                : '0 fresh matching jobs found with recruiter emails for this run.',
            scheduledSlot: lastRanDt.hour >= 16 ? '10:00 PM' : '10:00 AM',
            details: [],
            timestamp: lastRanDt,
          ));
        }
      }

      // 2. Cold Outreach Fallback Synthesizer
      if (widget.allowedFeatures.contains('cold_outreach')) {
        final leadsSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('networking_leads')
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();

        if (leadsSnap.docs.isNotEmpty) {
          final Map<String, List<Map<String, dynamic>>> leadsByDay = {};
          for (final d in leadsSnap.docs) {
            final ld = d.data();
            final ct = ld['createdAt'];
            DateTime dt = DateTime.now();
            if (ct is Timestamp) dt = ct.toDate();
            final key = DateFormat('yyyy-MM-dd').format(dt);
            leadsByDay.putIfAbsent(key, () => []).add(ld);
          }

          leadsByDay.forEach((dayKey, leadList) {
            final firstCt = leadList.first['createdAt'];
            DateTime dt = DateTime.now();
            if (firstCt is Timestamp) dt = firstCt.toDate();

            final details = leadList.map((l) => "${l['name'] ?? 'Founder'} (${l['currentRole'] ?? 'CTO'} at ${l['companyName'] ?? 'Startup'})").toList();
            final emailsSent = leadList.where((l) => l['emailSent'] == true).length;

            fallbacks.add(FeatureLogEntry(
              id: 'fallback_lead_$dayKey',
              feature: 'cold_outreach',
              featureTitle: 'Cold Outreach',
              status: 'success',
              count: leadList.length,
              message: emailsSent > 0
                  ? 'Auto-dispatched $emailsSent startup pitch(es) via email. ${leadList.length} LinkedIn notes ready.'
                  : 'Discovered ${leadList.length} startup leader(s). LinkedIn notes ready!',
              scheduledSlot: '11:30 AM',
              details: details,
              timestamp: dt,
            ));
          });
        }
      }

      // 3. Tech Events Fallback Synthesizer
      if (widget.allowedFeatures.contains('tech_events')) {
        final eventsSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('events')
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();

        final eventsLastRan = uData['eventsLastRan'];
        DateTime? lastRanDt;
        if (eventsLastRan is Timestamp) lastRanDt = eventsLastRan.toDate();

        if (eventsSnap.docs.isNotEmpty) {
          final Map<String, List<Map<String, dynamic>>> eventsByDay = {};
          for (final d in eventsSnap.docs) {
            final ed = d.data();
            final ct = ed['createdAt'];
            DateTime dt = DateTime.now();
            if (ct is Timestamp) dt = ct.toDate();
            final key = DateFormat('yyyy-MM-dd').format(dt);
            eventsByDay.putIfAbsent(key, () => []).add(ed);
          }

          eventsByDay.forEach((dayKey, eventList) {
            final firstCt = eventList.first['createdAt'];
            DateTime dt = DateTime.now();
            if (firstCt is Timestamp) dt = firstCt.toDate();

            final details = eventList.map((e) => "${e['title'] ?? 'Tech Event'} (${e['location'] ?? 'Bengaluru'})").toList();

            fallbacks.add(FeatureLogEntry(
              id: 'fallback_event_$dayKey',
              feature: 'tech_events',
              featureTitle: 'Tech Events',
              status: 'success',
              count: eventList.length,
              message: 'Found ${eventList.length} new tech event(s) and meetup(s).',
              scheduledSlot: '07:00 PM',
              details: details,
              timestamp: dt,
            ));
          });
        } else if (lastRanDt != null) {
          fallbacks.add(FeatureLogEntry(
            id: 'fallback_event_last_ran',
            feature: 'tech_events',
            featureTitle: 'Tech Events',
            status: 'no_results',
            count: 0,
            message: '0 new tech events found for this run.',
            scheduledSlot: '07:00 PM',
            details: [],
            timestamp: lastRanDt,
          ));
        }
      }

      // 4. Walk-In Drives Fallback Synthesizer
      if (widget.allowedFeatures.contains('walkin_drives')) {
        final walkinsSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('walkins')
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();

        final walkinsLastRan = uData['walkinsLastRan'];
        DateTime? lastRanDt;
        if (walkinsLastRan is Timestamp) lastRanDt = walkinsLastRan.toDate();

        if (walkinsSnap.docs.isNotEmpty) {
          final Map<String, List<Map<String, dynamic>>> walkinsByDay = {};
          for (final d in walkinsSnap.docs) {
            final wd = d.data();
            final ct = wd['createdAt'];
            DateTime dt = DateTime.now();
            if (ct is Timestamp) dt = ct.toDate();
            final key = DateFormat('yyyy-MM-dd').format(dt);
            walkinsByDay.putIfAbsent(key, () => []).add(wd);
          }

          walkinsByDay.forEach((dayKey, walkinList) {
            final firstCt = walkinList.first['createdAt'];
            DateTime dt = DateTime.now();
            if (firstCt is Timestamp) dt = firstCt.toDate();

            final details = walkinList.map((w) => "${w['title'] ?? w['role'] ?? 'Walk-In'} at ${w['company'] ?? 'Company'}").toList();

            fallbacks.add(FeatureLogEntry(
              id: 'fallback_walkin_$dayKey',
              feature: 'walkin_drives',
              featureTitle: 'Walk-In Drives',
              status: 'success',
              count: walkinList.length,
              message: 'Found ${walkinList.length} new walk-in drive(s).',
              scheduledSlot: '08:00 PM',
              details: details,
              timestamp: dt,
            ));
          });
        } else if (lastRanDt != null) {
          fallbacks.add(FeatureLogEntry(
            id: 'fallback_walkin_last_ran',
            feature: 'walkin_drives',
            featureTitle: 'Walk-In Drives',
            status: 'no_results',
            count: 0,
            message: '0 new walk-in drives found for this run.',
            scheduledSlot: '08:00 PM',
            details: [],
            timestamp: lastRanDt,
          ));
        }
      }

      fallbacks.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      if (mounted) {
        setState(() {
          _synthesizedFallbackLogs = fallbacks;
          _isLoadingFallback = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading fallback logs: $e");
      if (mounted) setState(() => _isLoadingFallback = false);
    }
  }

  Color _getFeatureColor(String feature) {
    switch (feature) {
      case 'auto_apply':
        return Colors.blueAccent;
      case 'cold_outreach':
        return Colors.tealAccent;
      case 'tech_events':
        return Colors.purpleAccent;
      case 'walkin_drives':
        return Colors.amber;
      default:
        return Colors.cyan;
    }
  }

  IconData _getFeatureIcon(String feature) {
    switch (feature) {
      case 'auto_apply':
        return Icons.bolt_rounded;
      case 'cold_outreach':
        return Icons.people_alt_rounded;
      case 'tech_events':
        return Icons.event_available_rounded;
      case 'walkin_drives':
        return Icons.business_center_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  Widget _buildScheduleInfoBanner(bool isDark) {
    String scheduleInfo = '';
    if (widget.allowedFeatures.contains('auto_apply') && widget.allowedFeatures.contains('cold_outreach')) {
      scheduleInfo = '⚡ Auto-Apply runs twice daily at 10:00 AM & 10:00 PM IST.\n🚀 Cold Outreach Startup Radar runs daily at 11:30 AM IST.';
    } else if (widget.allowedFeatures.contains('tech_events')) {
      scheduleInfo = '📅 Scheduled Run: Scans tech meetups & conferences daily at 7:00 PM IST.';
    } else if (widget.allowedFeatures.contains('walkin_drives')) {
      scheduleInfo = '💼 Scheduled Run: Scans verified walk-in drives daily at 8:00 PM IST.';
    }

    if (scheduleInfo.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2638) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.blueAccent.withValues(alpha: 0.25) : Colors.blue.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, size: 20, color: isDark ? Colors.blueAccent : Colors.blue[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              scheduleInfo,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.blue[100] : const Color(0xFF1E3A8A),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(bool isDark) {
    if (widget.allowedFeatures.length <= 1) return const SizedBox.shrink();

    final options = [
      {'key': 'all', 'label': 'All Logs'},
      if (widget.allowedFeatures.contains('auto_apply')) {'key': 'auto_apply', 'label': 'Auto-Apply'},
      if (widget.allowedFeatures.contains('cold_outreach')) {'key': 'cold_outreach', 'label': 'Cold Outreach'},
      if (widget.allowedFeatures.contains('tech_events')) {'key': 'tech_events', 'label': 'Tech Events'},
      if (widget.allowedFeatures.contains('walkin_drives')) {'key': 'walkin_drives', 'label': 'Walk-Ins'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: options.map((opt) {
          final isSelected = _selectedFilter == opt['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(opt['label']!),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) setState(() => _selectedFilter = opt['key']!);
              },
              backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              selectedColor: Colors.blueAccent.withValues(alpha: 0.25),
              labelStyle: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.white : Colors.blueAccent)
                    : (isDark ? Colors.grey[400] : Colors.grey[700]),
              ),
              side: BorderSide(
                color: isSelected
                    ? Colors.blueAccent
                    : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLogCard(FeatureLogEntry log, bool isDark) {
    final featureColor = _getFeatureColor(log.feature);
    final featureIcon = _getFeatureIcon(log.feature);

    // Format Date & Time: Month in short form, day, time (e.g. Sep 10, 10:02 AM)
    final dateStr = DateFormat('MMM d, h:mm a').format(log.timestamp);

    // Status styling
    Color statusBg;
    Color statusFg;
    String statusLabel;
    IconData statusIcon;

    if (log.status == 'error') {
      statusBg = isDark ? const Color(0xFF3B1212) : const Color(0xFFFEE2E2);
      statusFg = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
      statusLabel = log.message.toLowerCase().contains('api') ? 'API Error' : 'Error';
      statusIcon = Icons.error_outline_rounded;
    } else if (log.status == 'skipped') {
      statusBg = isDark ? const Color(0xFF3F2B07) : const Color(0xFFFEF3C7);
      statusFg = isDark ? Colors.amberAccent : const Color(0xFFB45309);
      statusLabel = 'Skipped';
      statusIcon = Icons.warning_amber_rounded;
    } else if (log.count > 0) {
      statusBg = isDark ? const Color(0xFF0F3820) : const Color(0xFFDCFCE7);
      statusFg = isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
      statusIcon = Icons.check_circle_rounded;
      if (log.feature == 'auto_apply') {
        statusLabel = '${log.count} ${log.count == 1 ? "Job" : "Jobs"} Applied';
      } else if (log.feature == 'cold_outreach') {
        statusLabel = '${log.count} ${log.count == 1 ? "Startup" : "Startups"} Pitched';
      } else if (log.feature == 'tech_events') {
        statusLabel = '${log.count} ${log.count == 1 ? "Event" : "Events"} Found';
      } else {
        statusLabel = '${log.count} ${log.count == 1 ? "Drive" : "Drives"} Found';
      }
    } else {
      statusBg = isDark ? const Color(0xFF1A2638) : const Color(0xFFF1F5F9);
      statusFg = isDark ? Colors.blue[200]! : const Color(0xFF475569);
      statusIcon = Icons.info_outline_rounded;
      if (log.feature == 'auto_apply') {
        statusLabel = '0 Jobs Fetched';
      } else if (log.feature == 'cold_outreach') {
        statusLabel = '0 Startups Found';
      } else if (log.feature == 'tech_events') {
        statusLabel = '0 Events Found';
      } else {
        statusLabel = '0 Drives Found';
      }
    }

    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Feature Icon + Title & Scheduled Slot + Date
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: featureColor.withValues(alpha: isDark ? 0.2 : 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(featureIcon, color: featureColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.featureTitle,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            log.isManual ? Icons.bolt_rounded : Icons.alarm_rounded,
                            size: 13,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            log.isManual
                                ? 'Manual Trigger'
                                : (log.scheduledSlot.isNotEmpty ? 'Slot: ${log.scheduledSlot} IST' : 'Scheduled Run'),
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Date & Time Chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 11, color: isDark ? Colors.grey[300] : Colors.grey[700]),
                      const SizedBox(width: 5),
                      Text(
                        dateStr,
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[200] : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Status Badge + Message
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusFg),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: statusFg,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    log.message,
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      color: isDark ? Colors.grey[300] : const Color(0xFF334155),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),

            // Optional Details (List of applied jobs, companies, or events)
            if (log.details.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF171717) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: log.details.take(4).map((d) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ', style: TextStyle(color: featureColor, fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(
                              d,
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                color: isDark ? Colors.grey[400] : Colors.grey[700],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    if (user == null) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(title: Text(widget.title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold))),
        body: Center(child: Text('Please log in to view execution logs.', style: GoogleFonts.outfit())),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Logs',
            onPressed: () {
              setState(() => _isLoadingFallback = true);
              _loadHistoricalFallback();
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('feature_logs')
            .orderBy('timestamp', descending: true)
            .limit(30)
            .snapshots(),
        builder: (context, snapshot) {
          final List<FeatureLogEntry> realLogs = [];

          if (snapshot.hasData && snapshot.data != null) {
            for (final doc in snapshot.data!.docs) {
              final entry = FeatureLogEntry.fromFirestore(doc);
              if (widget.allowedFeatures.contains(entry.feature)) {
                realLogs.add(entry);
              }
            }
          }

          // Combine real logs with synthesized historical fallback logs if fewer than 10 entries exist
          final List<FeatureLogEntry> displayLogs = [...realLogs];

          if (displayLogs.length < 10 && _synthesizedFallbackLogs.isNotEmpty) {
            for (final fallback in _synthesizedFallbackLogs) {
              // Avoid duplicate logs within 1 hour of an existing real log
              final alreadyExists = displayLogs.any((l) =>
                  l.feature == fallback.feature &&
                  l.timestamp.difference(fallback.timestamp).abs().inMinutes < 60);
              if (!alreadyExists) {
                displayLogs.add(fallback);
              }
              if (displayLogs.length >= 10) break;
            }
          }

          displayLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          // Apply in-memory filter if selected
          final filteredLogs = _selectedFilter == 'all'
              ? displayLogs
              : displayLogs.where((l) => l.feature == _selectedFilter).toList();

          final isStillLoading = snapshot.connectionState == ConnectionState.waiting && _isLoadingFallback;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildScheduleInfoBanner(isDark),
              _buildFilterChips(isDark),
              if (isStillLoading) ...[
                const SizedBox(height: 60),
                const Center(child: CircularProgressIndicator()),
              ] else if (filteredLogs.isEmpty) ...[
                const SizedBox(height: 60),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.history_rounded, size: 64, color: isDark ? Colors.grey[700] : Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No Execution Logs Yet',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Automated runs will record their execution results here.',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 4),
                  child: Text(
                    'Last ${filteredLogs.take(10).length} Executions',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
                ...filteredLogs.take(10).map((log) => _buildLogCard(log, isDark)),
              ],
            ],
          );
        },
      ),
    );
  }
}
