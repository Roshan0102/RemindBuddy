import 'package:flutter/material.dart';
import '../models/gym_routine.dart';
import '../models/gym_profile.dart';
import '../services/gym_service.dart';
import 'gym_active_workout_screen.dart';

/// Screen for viewing and managing custom Gym Routines.
/// All routines are stored strictly under the authenticated user's collection: users/{uid}/gym_routines.
class GymDashboardScreen extends StatefulWidget {
  const GymDashboardScreen({super.key});

  @override
  State<GymDashboardScreen> createState() => _GymDashboardScreenState();
}

class _GymDashboardScreenState extends State<GymDashboardScreen> {
  final GymService _gymService = GymService();

  void _openRoutine(GymRoutine routine) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GymActiveWorkoutScreen(
          routine: routine,
          initialTitle: routine.name,
        ),
      ),
    );
  }

  Future<void> _showCreateRoutineDialog() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.playlist_add, color: Colors.blueAccent),
            SizedBox(width: 10),
            Text('New Custom Routine'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a name for your custom routine (e.g. "Chest & Triceps", "Heavy Leg Day"). You will pick exercises, set targets, and add video links next.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Routine Name',
                hintText: 'e.g. Push Day, Pull Hypertrophy',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                hintText: 'e.g. Incline focus with triceps finisher',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = titleCtrl.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx, {
                  'name': text,
                  'description': descCtrl.text.trim(),
                });
              }
            },
            child: const Text('Start Routine Builder'),
          ),
        ],
      ),
    );

    if (result != null && result['name']!.isNotEmpty) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GymActiveWorkoutScreen(
            initialTitle: result['name'],
            starterRoutine: GymRoutine(
              id: '',
              userId: _gymService.currentUserId ?? '',
              name: result['name']!,
              description: result['description']?.isNotEmpty == true ? result['description'] : null,
              exercises: const [],
              createdAt: DateTime.now(),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteRoutine(GymRoutine routine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Routine?'),
        content: Text('Are you sure you want to remove "${routine.name}" from your routines? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _gymService.deleteRoutine(routine.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Routine "${routine.name}" deleted.')),
        );
      }
    }
  }

  void _showSettingsDialog(GymProfile profile) {
    bool currentAnim = profile.showAnimations;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.tune, color: Colors.blueAccent),
                SizedBox(width: 10),
                Text('Gym Settings & Data'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Exercise Animations', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Stream looping demos via CDN (20 KB each)'),
                  value: currentAnim,
                  onChanged: (val) {
                    setDialogState(() {
                      currentAnim = val;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 20, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bandwidth Guard Active: Animations are cached locally so data is only downloaded once.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () async {
                  await _gymService.updateGymProfile(
                    profile.copyWith(showAnimations: currentAnim),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Workout Routines',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New Routine',
            onPressed: _showCreateRoutineDialog,
          ),
          StreamBuilder<GymProfile>(
            stream: _gymService.getGymProfileStream(),
            builder: (context, snapshot) {
              final profile = snapshot.data ?? const GymProfile(userId: '');
              return IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Gym Settings',
                onPressed: () => _showSettingsDialog(profile),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Routine'),
        onPressed: _showCreateRoutineDialog,
      ),
      body: StreamBuilder<List<GymRoutine>>(
        stream: _gymService.getRoutinesStream(),
        builder: (context, snapshot) {
          final routines = snapshot.data ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Card
                _buildRoutinesHeaderCard(context, routines.length),

                const SizedBox(height: 24),

                Row(
                  children: [
                    const Text(
                      'My Routines',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${routines.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Routines List / Empty State
                if (routines.isEmpty)
                  _buildEmptyRoutinesState(context)
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: routines.length,
                    itemBuilder: (context, index) {
                      final routine = routines[index];
                      return _buildRoutineCard(context, routine, index);
                    },
                  ),

                const SizedBox(height: 80), // Space for FAB
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRoutinesHeaderCard(BuildContext context, int routineCount) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E2838), const Color(0xFF161C26)]
              : [Colors.blue.shade700, Colors.indigo.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: isDark ? 0.3 : 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fitness_center, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ROUTINES LIBRARY',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      'Custom Workout Splits',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Build your custom splits, store exercises with video demonstration links, and track your sets.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 20),
            label: const Text(
              'Create New Routine',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.blue.shade900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            onPressed: _showCreateRoutineDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyRoutinesState(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF232731) : Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.playlist_add_check_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Workout Routines Yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Create custom routines to store your exercises, sets, weights, and video guides.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create First Routine'),
            onPressed: _showCreateRoutineDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildRoutineCard(BuildContext context, GymRoutine routine, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final colorPalette = [
      Colors.blue,
      Colors.purple,
      Colors.teal,
      Colors.orange,
      Colors.indigo,
      Colors.pinkAccent,
    ];
    final Color accentColor = colorPalette[index % colorPalette.length];

    final targetBodyParts = routine.exercises
        .map((e) => e.bodyPart)
        .where((bp) => bp.isNotEmpty)
        .toSet()
        .join(', ');

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      color: isDark ? const Color(0xFF232731) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: InkWell(
        onTap: () => _openRoutine(routine),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Title + Menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.fitness_center, color: accentColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          routine.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (routine.description != null && routine.description!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            routine.description!,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                    tooltip: 'Delete Routine',
                    onPressed: () => _confirmDeleteRoutine(routine),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Badges / Metrics Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${routine.exercises.length} exercises',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ),
                  if (targetBodyParts.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        targetBodyParts,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ],
                ],
              ),

              if (routine.exercises.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: routine.exercises.take(4).map((ex) {
                    final hasVideo = ex.videoUrl != null && ex.videoUrl!.isNotEmpty;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A1D24) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasVideo) ...[
                            const Icon(Icons.play_circle_fill, size: 12, color: Colors.redAccent),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            ex.exerciseName,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 14),

              // Open / Edit Button
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: const Text('Open & Edit Routine'),
                    onPressed: () => _openRoutine(routine),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
