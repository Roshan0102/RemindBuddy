import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/log_service.dart';

class TechEventsScreen extends StatefulWidget {
  const TechEventsScreen({super.key});

  @override
  State<TechEventsScreen> createState() => _TechEventsScreenState();
}

class _TechEventsScreenState extends State<TechEventsScreen> {
  bool _showPastEvents = false;
  bool _isFetchingEvents = false;
  bool _isEventsConfigured = false;
  List<String> _eventInterests = [];
  String _eventLocation = '';
  String _eventMode = 'In-Person'; // 'In-Person', 'Online', 'Both'
  DateTime? _eventsLastUpdated;
  DateTime? _eventsLastRan;

  StreamSubscription<DocumentSnapshot>? _userSubscription;
  Stream<QuerySnapshot>? _eventsStream;

  @override
  void initState() {
    super.initState();
    _listenToUserAndEvents();
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

  void _listenToUserAndEvents() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _eventsStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('events')
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
        final hasEventsConfigured = (data['isEventsConfigured'] == true) ||
            (data['eventLocation'] != null &&
                data['eventInterests'] != null &&
                data['eventMode'] != null);

        final interests = data['eventInterests'] != null
            ? List<String>.from(data['eventInterests'])
            : <String>[];
        final location = (data['eventLocation'] ?? '').toString();
        final mode = (data['eventMode'] ?? 'In-Person').toString();

        final lastUpdatedVal = data['eventsLastUpdated'];
        DateTime? lastUpdated;
        if (lastUpdatedVal is Timestamp) {
          lastUpdated = lastUpdatedVal.toDate();
        } else if (lastUpdatedVal is String) {
          lastUpdated = DateTime.tryParse(lastUpdatedVal);
        }

        final eventsLastRanVal = data['eventsLastRan'];
        DateTime? eventsLastRan;
        if (eventsLastRanVal is Timestamp) {
          eventsLastRan = eventsLastRanVal.toDate();
        } else if (eventsLastRanVal is String) {
          eventsLastRan = DateTime.tryParse(eventsLastRanVal);
        }

        if (mounted) {
          setState(() {
            _isEventsConfigured = hasEventsConfigured;
            _eventInterests = interests;
            _eventLocation = location;
            _eventMode = mode;
            _eventsLastUpdated = lastUpdated;
            _eventsLastRan = eventsLastRan;
          });
        }
      }
    }, onError: (e) {
      LogService().error("Error listening to events preferences", e);
    });
  }

  Future<void> _triggerFetchEvents() async {
    setState(() => _isFetchingEvents = true);
    try {
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('fetchUserTechEvents');
      final result = await callable.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Successfully loaded ${result.data['count'] ?? 0} tech events'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed to fetch events: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isFetchingEvents = false);
      }
    }
  }

  Future<void> _clearAllEvents() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Tech Events?'),
        content: const Text('This will delete all saved tech events for your account.'),
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
          .collection('events')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All tech events cleared')),
        );
      }
    }
  }

  Future<void> _editInterestsDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final List<String> availableInterests = [
      'Cloud & DevOps',
      'AI & Machine Learning',
      'Agentic AI & GenAI',
      'SRE & Infrastructure',
      'Kubernetes & Containers',
      'AWS / GCP / Azure',
      'Mobile & Flutter',
      'Frontend & Web3',
    ];

    List<String> tempSelected = List.from(_eventInterests);
    String tempLocation = _eventLocation.isEmpty ? 'Bengaluru' : _eventLocation;
    String tempMode = _eventMode;
    final locationController = TextEditingController(text: tempLocation);
    final interestsController = TextEditingController(text: _eventInterests.join(', '));
    bool isSavingInterests = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.tune_rounded, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text('Tech Event Preferences', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
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
                    hintText: 'e.g. Bengaluru, Remote, All',
                    prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Event Format', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: tempMode,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'In-Person', child: Text('In-Person Only')),
                    DropdownMenuItem(value: 'Online', child: Text('Online / Webinars Only')),
                    DropdownMenuItem(value: 'Both', child: Text('Both (In-Person & Online)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => tempMode = val);
                  },
                ),
                const SizedBox(height: 14),
                const Text('Preferred Topics & Technologies (comma-separated)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: interestsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Flutter, AI/ML, Cloud Computing, DevOps, Web3, Python',
                    prefixIcon: Icon(Icons.category_outlined, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSavingInterests ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: isSavingInterests
                  ? null
                  : () async {
                      setDialogState(() => isSavingInterests = true);
                      try {
                        final list = interestsController.text
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();

                        final loc = locationController.text.trim().isEmpty ? 'Bengaluru' : locationController.text.trim();
                        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                          'eventInterests': list,
                          'eventLocation': loc,
                          'eventMode': tempMode,
                          'isEventsConfigured': true,
                        }, SetOptions(merge: true));

                        setState(() {
                          _eventInterests = list;
                          _eventLocation = loc;
                          _eventMode = tempMode;
                          _isEventsConfigured = true;
                        });

                        Navigator.pop(context);

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Event preferences saved! Fetching matching events...'),
                          ),
                        );
                        _triggerFetchEvents();
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save preferences: $e'), backgroundColor: Colors.red),
                        );
                      } finally {
                        if (mounted) {
                          setDialogState(() => isSavingInterests = false);
                        }
                      }
                    },
              child: isSavingInterests
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markNotInterested(List<String> eventDocIds) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final batch = FirebaseFirestore.instance.batch();
    for (var id in eventDocIds) {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('events')
          .doc(id);
      batch.update(docRef, {'notInterested': true});
    }
    await batch.commit();
  }

  Future<void> _toggleGroupInterested(List<String> eventDocIds, bool currentlyInterested) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || eventDocIds.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    final collection = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('events');
    for (final id in eventDocIds) {
      batch.update(collection.doc(id), {'isInterested': !currentlyInterested});
    }
    await batch.commit();
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
        title: Text('Tech Events', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Event Preferences',
            onPressed: _editInterestsDialog,
          ),
          IconButton(
            icon: _isFetchingEvents
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Fetch Fresh Events',
            onPressed: _isFetchingEvents ? null : _triggerFetchEvents,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
            tooltip: 'Clear All Events',
            onPressed: _clearAllEvents,
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Please log in to view tech events.'))
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
                          const Icon(Icons.event_outlined, size: 18, color: Colors.blueAccent),
                          const SizedBox(width: 8),
                          Text(
                            _eventLocation.isEmpty ? 'All Locations' : _eventLocation,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          Chip(
                            label: Text(_eventMode, style: const TextStyle(fontSize: 10, color: Colors.blueAccent)),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.blueAccent.withOpacity(0.1),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text('Show Past', style: TextStyle(fontSize: 12, color: subtextColor)),
                          Switch(
                            value: _showPastEvents,
                            activeColor: Colors.blueAccent,
                            onChanged: (val) => setState(() => _showPastEvents = val),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _eventsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final allDocs = snapshot.data?.docs ?? [];
                      final todayStr = DateFormat('yyyy-MM-DD').format(DateTime.now());

                      final Map<String, List<QueryDocumentSnapshot>> groupsMap = {};

                      for (final doc in allDocs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final title = (data['title'] ?? 'No Title').toString().trim();
                        final dateStr = (data['date'] ?? '').toString().trim();
                        final notInterested = data['notInterested'] as bool? ?? false;

                        if (notInterested || dateStr.isEmpty) continue;

                        final loc = (data['location'] ?? '').toString();
                        final isOnline = loc.toLowerCase().contains('online') ||
                            loc.toLowerCase().contains('virtual') ||
                            loc.toLowerCase().contains('webinar');

                        if (_eventMode == 'In-Person' && isOnline) continue;
                        if (_eventMode == 'Online' && !isOnline) continue;
                        if (_eventMode != 'Online' && !_isLocationMatch(loc, _eventLocation)) continue;

                        final key = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
                        groupsMap.putIfAbsent(key, () => []).add(doc);
                      }

                      final List<Map<String, dynamic>> groupedEvents = [];

                      for (final entry in groupsMap.entries) {
                        final docs = entry.value;
                        if (docs.isEmpty) continue;

                        final Set<String> dateSet = {};
                        final List<String> docIds = [];
                        bool isInterestedGroup = false;
                        String repTitle = '';
                        String repTimings = '';
                        String repLocation = '';
                        String repRegLink = '';

                        for (final doc in docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          final dateStr = (data['date'] ?? '').toString().trim();
                          if (dateStr.isNotEmpty) dateSet.add(dateStr);
                          docIds.add(doc.id);
                          if (repTitle.isEmpty) repTitle = (data['title'] ?? '').toString();
                          if (repTimings.isEmpty) repTimings = (data['timings'] ?? '').toString();
                          if (repLocation.isEmpty) repLocation = (data['location'] ?? '').toString();
                          if (repRegLink.isEmpty) repRegLink = (data['registrationLink'] ?? '').toString();
                          if (data['isInterested'] == true) isInterestedGroup = true;
                        }

                        final sortedDates = dateSet.toList()..sort();
                        final latestDate = sortedDates.isNotEmpty ? sortedDates.last : '';
                        final isPast = latestDate.compareTo(todayStr) < 0;

                        if (isPast && !_showPastEvents) continue;

                        groupedEvents.add({
                          'title': repTitle,
                          'dates': sortedDates,
                          'timings': repTimings,
                          'location': repLocation,
                          'registrationLink': repRegLink,
                          'isInterested': isInterestedGroup,
                          'docIds': docIds,
                          'isPast': isPast,
                        });
                      }

                      if (groupedEvents.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event_busy, size: 64, color: subtextColor),
                              const SizedBox(height: 16),
                              Text('No tech events found for your filters.', style: TextStyle(color: subtextColor)),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _triggerFetchEvents,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Fetch Events'),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: groupedEvents.length,
                        itemBuilder: (context, index) {
                          final item = groupedEvents[index];
                          final title = item['title'] as String;
                          final sortedDates = item['dates'] as List<String>;
                          final timings = item['timings'] as String;
                          final location = item['location'] as String;
                          final regLink = item['registrationLink'] as String;
                          final isInterested = item['isInterested'] as bool;
                          final docIds = item['docIds'] as List<String>;
                          final isPast = item['isPast'] as bool;

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
                                        child: Text(
                                          title,
                                          style: GoogleFonts.outfit(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: isPast ? Colors.grey : textColor,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          isInterested ? Icons.star : Icons.star_border,
                                          color: isInterested ? Colors.amber : Colors.grey,
                                        ),
                                        onPressed: () => _toggleGroupInterested(docIds, isInterested),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: sortedDates.map<Widget>((d) {
                                      final dt = DateTime.tryParse(d);
                                      final formatted = dt != null ? DateFormat('MMM d, yyyy').format(dt) : d;
                                      return Chip(
                                        label: Text(formatted, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
                                        backgroundColor: Colors.green.shade50,
                                        visualDensity: VisualDensity.compact,
                                      );
                                    }).toList(),
                                  ),
                                  const SizedBox(height: 8),
                                  if (location.isNotEmpty)
                                    Row(
                                      children: [
                                        Icon(Icons.location_on_outlined, size: 16, color: Colors.green.shade700),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(location, style: TextStyle(fontSize: 13, color: subtextColor)),
                                        ),
                                      ],
                                    ),
                                  if (timings.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.access_time, size: 16, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text(timings, style: TextStyle(fontSize: 12, color: subtextColor)),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: isInterested ? Colors.amber.shade900 : Colors.green.shade700,
                                            side: BorderSide(color: isInterested ? Colors.amber : Colors.green.shade400),
                                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                          ),
                                          onPressed: () => _toggleGroupInterested(docIds, isInterested),
                                          icon: Icon(
                                            isInterested ? Icons.star : Icons.star_border,
                                            size: 18,
                                            color: isInterested ? Colors.amber.shade800 : Colors.green.shade700,
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
                                              title: const Text('Hide Event'),
                                              content: const Text('Mark this event as Not Interested? It will be hidden from your list.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hide', style: TextStyle(color: Colors.red))),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            await _markNotInterested(docIds);
                                          }
                                        },
                                        icon: const Icon(Icons.block, size: 16, color: Colors.red),
                                        label: const Text('Ignore', style: TextStyle(fontSize: 12)),
                                      ),
                                      if (regLink.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green.shade700,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                          ),
                                          onPressed: () async {
                                            final uri = Uri.parse(regLink);
                                            if (await canLaunchUrl(uri)) {
                                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                                            }
                                          },
                                          icon: const Icon(Icons.open_in_new, size: 14),
                                          label: const Text('Register', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
