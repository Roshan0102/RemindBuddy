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
  bool _isWalkInConfigured = false;
  List<String> _walkinRoles = [];
  String _walkinLocation = '';
  DateTime? _walkinsLastUpdated;
  DateTime? _walkinsLastRan;

  StreamSubscription<DocumentSnapshot>? _userSubscription;
  Stream<QuerySnapshot>? _walkinsStream;

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
        final hasWalkinConfigured = (data['isWalkinConfigured'] == true) ||
            (data['walkinLocation'] != null && data['walkinRoles'] != null);

        final walkinRoles = data['walkinRoles'] != null
            ? List<String>.from(data['walkinRoles'])
            : <String>[];
        final walkinLocation = (data['walkinLocation'] ?? '').toString();

        final walkinsLastUpdatedVal = data['walkinsLastUpdated'];
        DateTime? walkinsLastUpdated;
        if (walkinsLastUpdatedVal is Timestamp) {
          walkinsLastUpdated = walkinsLastUpdatedVal.toDate();
        } else if (walkinsLastUpdatedVal is String) {
          walkinsLastUpdated = DateTime.tryParse(walkinsLastUpdatedVal);
        }

        final walkinsLastRanVal = data['walkinsLastRan'];
        DateTime? walkinsLastRan;
        if (walkinsLastRanVal is Timestamp) {
          walkinsLastRan = walkinsLastRanVal.toDate();
        } else if (walkinsLastRanVal is String) {
          walkinsLastRan = DateTime.tryParse(walkinsLastRanVal);
        }

        if (mounted) {
          setState(() {
            _isWalkInConfigured = hasWalkinConfigured;
            _walkinRoles = walkinRoles;
            _walkinLocation = walkinLocation;
            _walkinsLastUpdated = walkinsLastUpdated;
            _walkinsLastRan = walkinsLastRan;
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
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('fetchUserWalkInDrives');
      final result = await callable.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Successfully loaded ${result.data['count'] ?? 0} walk-in drives'),
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Walk-In Drives?'),
        content: const Text('This will delete all saved walk-in job drives for your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
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
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All walk-in drives cleared')),
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
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
              onPressed: isSavingRoles ? null : () => Navigator.pop(context),
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
                          _isWalkInConfigured = true;
                        });

                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Walk-In preferences saved! Fetching matching drives...'),
                          ),
                        );
                        _triggerFetchWalkIns();
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save preferences: $e'), backgroundColor: Colors.red),
                        );
                      } finally {
                        if (mounted) {
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
        title: Text('Walk-In Job Drives 💼', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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
                            activeColor: Colors.blueAccent,
                            onChanged: (val) => setState(() => _showPastWalkIns = val),
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
                      final todayStr = DateFormat('yyyy-MM-DD').format(DateTime.now());

                      final filteredDocs = docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final notInterested = data['notInterested'] as bool? ?? false;
                        if (notInterested) return false;

                        final dateStr = (data['date'] ?? '').toString().trim();
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
                                  if (link.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: () async {
                                          final uri = Uri.parse(link);
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                                          }
                                        },
                                        icon: const Icon(Icons.open_in_new, size: 16),
                                        label: const Text('View Drive Details'),
                                      ),
                                    ),
                                  ],
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
