import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/log_service.dart';

class WalkInDrivesScreen extends StatefulWidget {
  const WalkInDrivesScreen({super.key});

  @override
  State<WalkInDrivesScreen> createState() => _WalkInDrivesScreenState();
}

class _WalkInDrivesScreenState extends State<WalkInDrivesScreen> {
  bool _showPastWalkIns = false;
  bool _isFetchingWalkIns = false;
  List<String> _walkinRoles = [];
  String _walkinLocation = '';
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _lastRan;
  DateTime? _lastUpdated;

  StreamSubscription<DocumentSnapshot>? _userSubscription;
  Stream<QuerySnapshot>? _walkinsStream;

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return 'Today at ${DateFormat('hh:mm a').format(dt)}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.day == yesterday.day && dt.month == yesterday.month && dt.year == yesterday.year) {
      return 'Yesterday at ${DateFormat('hh:mm a').format(dt)}';
    }
    return DateFormat('dd MMM, hh:mm a').format(dt);
  }

  @override
  void initState() {
    super.initState();
    _listenToUserAndWalkins();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  bool _isLocationMatch(String itemLocation, String targetLocation) {
    final itemLoc = itemLocation.toLowerCase().trim();
    final target = targetLocation.toLowerCase().trim();
    if (target.isEmpty || target == 'all' || target == 'any') return true;

    if (target.contains('bengaluru') || target.contains('bangalore') || target.contains('blr')) {
      return itemLoc.contains('bengaluru') ||
          itemLoc.contains('bangalore') ||
          itemLoc.contains('blr') ||
          itemLoc.contains('electronic city') ||
          itemLoc.contains('hsr') ||
          itemLoc.contains('koramangala') ||
          itemLoc.contains('indiranagar') ||
          itemLoc.contains('manyata') ||
          itemLoc.contains('whitefield') ||
          itemLoc.contains('marathahalli');
    }

    return itemLoc.contains(target);
  }

  void _listenToUserAndWalkins() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _walkinsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('walkins')
        .orderBy('date', descending: false)
        .snapshots();

    _userSubscription?.cancel();
    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final walkinRoles = data['walkinRoles'] != null
            ? List<String>.from(data['walkinRoles'])
            : <String>[];
        final walkinLocation = (data['walkinLocation'] ?? '').toString();

        DateTime? lastRan;
        final ranVal = data['walkinsLastRan'];
        if (ranVal is Timestamp) {
          lastRan = ranVal.toDate();
        }

        DateTime? lastUpdated;
        final updatedVal = data['walkinsLastUpdated'];
        if (updatedVal is Timestamp) {
          lastUpdated = updatedVal.toDate();
        }

        if (mounted) {
          setState(() {
            _walkinRoles = walkinRoles;
            _walkinLocation = walkinLocation;
            _lastRan = lastRan;
            _lastUpdated = lastUpdated;
          });
        }
      }
    }, onError: (e) {
      LogService().error("Error listening to walkin preferences", e);
    });
  }

  Future<void> _triggerFetchWalkIns() async {
    setState(() => _isFetchingWalkIns = true);
    try {
      dynamic result;
      try {
        final HttpsCallable callable =
            FirebaseFunctions.instance.httpsCallable('fetchUserWalkIns');
        result = await callable.call();
      } catch (err) {
        // Fallback to fetchUserWalkInDrives if alias exists
        final HttpsCallable fallbackCallable =
            FirebaseFunctions.instance.httpsCallable('fetchUserWalkInDrives');
        result = await fallbackCallable.call();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Successfully loaded ${result.data?['count'] ?? 0} walk-in drives'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed to fetch walk-ins: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingWalkIns = false);
      }
    }
  }

  Future<void> _clearAllWalkins() async {
    final monthStr = DateFormat('MMMM yyyy').format(_selectedMonth);
    final monthPrefix = DateFormat('yyyy-MM').format(_selectedMonth);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear $monthStr Walk-In Drives?'),
        content: Text('This will delete all saved walk-in job drives for $monthStr.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Clear $monthStr'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('walkins')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      int count = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final dateStr = (data['date'] ?? '').toString().trim();
        if (dateStr.startsWith(monthPrefix)) {
          batch.delete(doc.reference);
          count++;
        }
      }

      if (count > 0) {
        await batch.commit();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cleared $count walk-in drive(s) for $monthStr')),
        );
      }
    }
  }

  Future<void> _editWalkinRolesDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final rolesController = TextEditingController(text: _walkinRoles.join(', '));
    final locationController = TextEditingController(
        text: _walkinLocation.isEmpty ? 'Bengaluru' : _walkinLocation);
    bool isSavingRoles = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (innerCtx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.work_history_rounded, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text('Walk-In Job Preferences', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Preferred Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Bengaluru, Hyderabad, Chennai, All',
                    prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Preferred Job Roles (comma-separated)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: rolesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'e.g. DevOps, Cloud Engineer, Software Developer, SRE, QA',
                    prefixIcon: Icon(Icons.work_outline, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSavingRoles ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSavingRoles
                  ? null
                  : () async {
                      setDialogState(() => isSavingRoles = true);
                      try {
                        final list = rolesController.text
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();

                        final loc = locationController.text.trim().isEmpty ? 'Bengaluru' : locationController.text.trim();

                        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                          'walkinRoles': list,
                          'walkinLocation': loc,
                          'isWalkinConfigured': true,
                        }, SetOptions(merge: true));

                        setState(() {
                          _walkinRoles = list;
                          _walkinLocation = loc;
                        });

                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Walk-In preferences saved! Fetching matching drives...'),
                            ),
                          );
                          _triggerFetchWalkIns();
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to save preferences: $e'), backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        if (innerCtx.mounted) {
                          setDialogState(() => isSavingRoles = false);
                        }
                      }
                    },
              child: isSavingRoles
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleWalkinInterested(String docId, bool currentlyInterested) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('walkins')
        .doc(docId)
        .update({'isInterested': !currentlyInterested});
  }

  Future<void> _markWalkinNotInterested(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('walkins')
        .doc(docId)
        .update({'notInterested': true});
  }

  Widget _buildMonthSelector(bool isDark) {
    final monthFormat = DateFormat('MMMM yyyy');
    final isCurrentMonth = _selectedMonth.year == DateTime.now().year && _selectedMonth.month == DateTime.now().month;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.blue.shade50,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.blue.shade100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous Month',
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
              });
            },
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, size: 18, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  Text(
                    monthFormat.format(_selectedMonth),
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (isCurrentMonth) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Current', style: TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next Month',
            onPressed: () {
              setState(() {
                _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
              });
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
    final cardBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Walk-In Drives', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Job Preferences',
            onPressed: _editWalkinRolesDialog,
          ),
          IconButton(
            icon: _isFetchingWalkIns
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Fetch Fresh Walk-Ins',
            onPressed: _isFetchingWalkIns ? null : _triggerFetchWalkIns,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            tooltip: 'Clear All Walk-Ins',
            onPressed: _clearAllWalkins,
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Please log in to view walk-in job drives.'))
          : Column(
              children: [
                _buildMonthSelector(isDark),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 18, color: Colors.blueAccent),
                          const SizedBox(width: 8),
                          Text(
                            _walkinLocation.isEmpty ? 'All Locations' : _walkinLocation,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text('Show Past', style: TextStyle(fontSize: 12, color: subtextColor)),
                          Switch(
                            value: _showPastWalkIns,
                            activeThumbColor: Colors.blueAccent,
                            onChanged: (val) => setState(() => _showPastWalkIns = val),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161F30) : const Color(0xFFEFF6FF),
                    border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.blue.shade100)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.history_toggle_off_rounded, size: 13, color: isDark ? Colors.white60 : Colors.blueGrey),
                          const SizedBox(width: 4),
                          Text(
                            'Last Ran: ${_formatTimestamp(_lastRan)}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.blueGrey.shade700),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.update_rounded, size: 13, color: isDark ? Colors.tealAccent : const Color(0xFF0D9488)),
                          const SizedBox(width: 4),
                          Text(
                            'Last Updated: ${_formatTimestamp(_lastUpdated)}',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.tealAccent : const Color(0xFF0D9488)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _walkinsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snapshot.data?.docs ?? [];
                      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                      final selectedMonthPrefix = DateFormat('yyyy-MM').format(_selectedMonth);

                      final filteredDocs = docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final notInterested = data['notInterested'] as bool? ?? false;
                        if (notInterested) return false;

                        final dateStr = (data['date'] ?? '').toString().trim();
                        if (!dateStr.startsWith(selectedMonthPrefix)) return false;

                        final isPast = dateStr.isNotEmpty && dateStr.compareTo(todayStr) < 0;
                        if (isPast && !_showPastWalkIns) return false;

                        final loc = (data['location'] ?? '').toString();
                        if (!_isLocationMatch(loc, _walkinLocation)) return false;

                        return true;
                      }).toList();

                      if (filteredDocs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.directions_walk, size: 64, color: subtextColor),
                              const SizedBox(height: 16),
                              Text('No walk-in drives found for your preferences.', style: TextStyle(color: subtextColor)),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _triggerFetchWalkIns,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Fetch Walk-Ins'),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: filteredDocs.length,
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final title = (data['title'] ?? 'Walk-In Drive').toString();
                          final company = (data['company'] ?? '').toString();
                          final dateStr = (data['date'] ?? '').toString();
                          final timings = (data['timings'] ?? '').toString();
                          final location = (data['location'] ?? '').toString();
                          final roles = (data['roles'] ?? '').toString();
                          final experience = (data['experience'] ?? '').toString();
                          final venue = (data['venue'] ?? '').toString();
                          final isInterested = data['isInterested'] as bool? ?? false;
                          final link = (data['registrationLink'] ?? '').toString();

                          final dt = DateTime.tryParse(dateStr);
                          final formattedDate = dt != null ? DateFormat('EEE, MMM d, yyyy').format(dt) : dateStr;

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            color: cardBgColor,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              company.isNotEmpty ? company : title,
                                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
                                            ),
                                            if (company.isNotEmpty && title != company)
                                              Text(title, style: TextStyle(fontSize: 13, color: subtextColor)),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          isInterested ? Icons.star : Icons.star_border,
                                          color: isInterested ? Colors.amber : Colors.grey,
                                        ),
                                        onPressed: () => _toggleWalkinInterested(doc.id, isInterested),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_month, size: 16, color: Colors.blueAccent),
                                      const SizedBox(width: 4),
                                      Text(formattedDate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      if (timings.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Text('($timings)', style: TextStyle(fontSize: 12, color: subtextColor)),
                                      ],
                                    ],
                                  ),
                                  if (roles.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(Icons.work_outline, size: 16, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text('Roles: $roles', style: TextStyle(fontSize: 13, color: textColor))),
                                      ],
                                    ),
                                  ],
                                  if (experience.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.badge_outlined, size: 16, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text('Exp: $experience', style: TextStyle(fontSize: 12, color: subtextColor)),
                                      ],
                                    ),
                                  ],
                                  if (location.isNotEmpty || venue.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.location_on_outlined, size: 16, color: Colors.blueAccent),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            venue.isNotEmpty ? '$location — $venue' : location,
                                            style: TextStyle(fontSize: 12, color: subtextColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: isInterested ? Colors.amber.shade900 : Colors.blue.shade700,
                                            side: BorderSide(color: isInterested ? Colors.amber : Colors.blue.shade400),
                                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                          ),
                                          onPressed: () => _toggleWalkinInterested(doc.id, isInterested),
                                          icon: Icon(
                                            isInterested ? Icons.star : Icons.star_border,
                                            size: 18,
                                            color: isInterested ? Colors.amber.shade800 : Colors.blue.shade700,
                                          ),
                                          label: Text(
                                            isInterested ? 'Interested ⭐' : 'Mark Interested',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red.shade700,
                                          side: BorderSide(color: Colors.red.shade200),
                                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                        ),
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Hide Drive'),
                                              content: const Text('Mark this walk-in drive as Not Interested? It will be hidden from your list.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hide', style: TextStyle(color: Colors.red))),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            await _markWalkinNotInterested(doc.id);
                                          }
                                        },
                                        icon: const Icon(Icons.block, size: 16, color: Colors.red),
                                        label: const Text('Ignore', style: TextStyle(fontSize: 12)),
                                      ),
                                      if (link.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.blue.shade700,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                          ),
                                          onPressed: () async {
                                            final uri = Uri.parse(link);
                                            if (await canLaunchUrl(uri)) {
                                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                                            }
                                          },
                                          icon: const Icon(Icons.open_in_new, size: 14),
                                          label: const Text('Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
