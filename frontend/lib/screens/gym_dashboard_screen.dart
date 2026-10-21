import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/gym_workout.dart';
import '../models/personal_record.dart';
import '../models/body_weight_entry.dart';
import '../models/gym_profile.dart';
import '../models/exercise_model.dart';
import '../services/gym_service.dart';
import '../services/gym_exercise_catalog.dart';
import '../widgets/gym/gym_workout_detail_modal.dart';
import 'gym_active_workout_screen.dart';

/// Main Dashboard screen for the Gym & Workout Tracker module.
/// Provides real-time workout logging, personal record (PR) trophies,
/// body weight tracking, and split presets.
class GymDashboardScreen extends StatefulWidget {
  const GymDashboardScreen({super.key});

  @override
  State<GymDashboardScreen> createState() => _GymDashboardScreenState();
}

class _GymDashboardScreenState extends State<GymDashboardScreen> {
  final GymService _gymService = GymService();

  void _startWorkout({String? title, List<ExerciseModel>? starterExercises}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GymActiveWorkoutScreen(
          initialTitle: title,
          starterExercises: starterExercises,
        ),
      ),
    );
  }

  void _showLogWeightDialog() {
    final weightController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.monitor_weight_outlined, color: Colors.blueAccent),
            SizedBox(width: 10),
            Text('Log Body Weight'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Weight (kg)',
                hintText: 'e.g. 75.5',
                suffixText: 'kg',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: InputDecoration(
                labelText: 'Note (Optional)',
                hintText: 'e.g. morning, fasting',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final weight = double.tryParse(weightController.text.trim());
              if (weight != null && weight > 0) {
                await _gymService.addBodyWeight(
                  weight,
                  note: noteController.text.trim().isNotEmpty
                      ? noteController.text.trim()
                      : null,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Body weight logged!')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
          'Gym & Workouts',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Card: Quick Start & Weekly Stats
            _buildHeroCard(context),

            const SizedBox(height: 20),

            // Quick Split Starter Bar
            _buildSplitPresetsBar(context),

            const SizedBox(height: 24),

            // Personal Records (PRs) Showcase
            _buildPRsShowcase(context),

            const SizedBox(height: 24),

            // Body Weight Tracker Card
            _buildBodyWeightCard(context),

            const SizedBox(height: 24),

            // Workout History Feed
            _buildWorkoutHistoryFeed(context),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<List<GymWorkout>>(
      stream: _gymService.getWorkoutsStream(),
      builder: (context, snapshot) {
        final workouts = snapshot.data ?? [];

        // Calculate this week's workouts
        final now = DateTime.now();
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final thisWeekWorkouts = workouts.where((w) {
          return w.startedAt.isAfter(DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day));
        }).toList();

        final double weekVolume = thisWeekWorkouts.fold(
          0.0,
          (total, w) => total + w.totalVolumeKg,
        );

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
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'READY TO TRAIN?',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        'Workout Tracker',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Stats Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildWhiteStat('THIS WEEK', '${thisWeekWorkouts.length} sessions'),
                  Container(width: 1, height: 30, color: Colors.white24),
                  _buildWhiteStat('VOLUME', '${(weekVolume / 1000).toStringAsFixed(1)}k kg'),
                  Container(width: 1, height: 30, color: Colors.white24),
                  _buildWhiteStat('TOTAL LOGS', '${workouts.length}'),
                ],
              ),

              const SizedBox(height: 18),

              // Big Start Workout CTA
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                  label: const Text(
                    'Start Empty Workout',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue.shade900,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => _startWorkout(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWhiteStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSplitPresetsBar(BuildContext context) {
    final splits = [
      {
        'title': 'Push Day',
        'subtitle': 'Chest, Shoulders & Triceps',
        'icon': Icons.arrow_upward,
        'color': Colors.orange,
        'exercises': ['0025', '0033', '0070', '0334', '0201'],
      },
      {
        'title': 'Pull Day',
        'subtitle': 'Back, Rear Delts & Biceps',
        'icon': Icons.arrow_downward,
        'color': Colors.blue,
        'exercises': ['0027', '0022', '0150', '0160', '0031'],
      },
      {
        'title': 'Leg Day',
        'subtitle': 'Quads, Hamstrings & Glutes',
        'icon': Icons.directions_run,
        'color': Colors.green,
        'exercises': ['0043', '0585', '0584', '0085', '0016'],
      },
      {
        'title': 'Upper Body',
        'subtitle': 'Complete Upper Torso',
        'icon': Icons.fitness_center,
        'color': Colors.purple,
        'exercises': ['0025', '0150', '0070', '0305', '0038'],
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Splits & Routines',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 105,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: splits.length,
            itemBuilder: (context, idx) {
              final split = splits[idx];
              final Color color = split['color'] as Color;

              return Container(
                width: 170,
                margin: const EdgeInsets.only(right: 12),
                child: InkWell(
                  onTap: () {
                    final exerciseIds = split['exercises'] as List<String>;
                    final exerciseModels = exerciseIds
                        .map((id) => GymExerciseCatalog.findById(id))
                        .whereType<ExerciseModel>()
                        .toList();

                    _startWorkout(
                      title: split['title'] as String,
                      starterExercises: exerciseModels,
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Icon(split['icon'] as IconData, size: 18, color: color),
                            const Spacer(),
                            Icon(Icons.play_circle_fill, size: 20, color: color),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          split['title'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          split['subtitle'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPRsShowcase(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<List<PersonalRecord>>(
      stream: _gymService.getPersonalRecordsStream(),
      builder: (context, snapshot) {
        final prs = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Personal Records (PRs)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${prs.length} Records',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (prs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF232731) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.workspace_premium_outlined, color: Colors.amber, size: 32),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Complete your first workout to unlock PR trophies and estimated 1-Rep Max badges!',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 115,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: prs.length,
                  itemBuilder: (context, index) {
                    final pr = prs[index];
                    return Container(
                      width: 160,
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF232731) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.emoji_events, color: Colors.amber, size: 16),
                              const Spacer(),
                              Text(
                                '${pr.estimated1RM} kg 1RM',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            pr.exerciseName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Text(
                            '${pr.maxWeight} kg × ${pr.repsAtMaxWeight} reps',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),
                          Text(
                            DateFormat('MMM d, y').format(pr.achievedAt),
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBodyWeightCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<List<BodyWeightEntry>>(
      stream: _gymService.getBodyWeightStream(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? [];
        final latest = entries.isNotEmpty ? entries.first : null;

        return Card(
          elevation: 0,
          color: isDark ? const Color(0xFF232731) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.monitor_weight_outlined, color: Colors.green, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Body Weight Tracking',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      if (latest != null)
                        Text(
                          '${latest.weightKg} kg (${DateFormat('MMM d').format(latest.date)})',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        )
                      else
                        const Text(
                          'No weigh-ins yet',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Log Weight'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: _showLogWeightDialog,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWorkoutHistoryFeed(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return StreamBuilder<List<GymWorkout>>(
      stream: _gymService.getWorkoutsStream(),
      builder: (context, snapshot) {
        final workouts = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Workout History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${workouts.length} total',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (workouts.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF232731) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey[200]!),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.event_note_outlined, size: 40, color: Colors.grey),
                    SizedBox(height: 10),
                    Text(
                      'No past workouts found',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Hit "Start Empty Workout" above to log your session!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: workouts.length,
                itemBuilder: (context, index) {
                  final workout = workouts[index];
                  final durationMinutes = (workout.durationSeconds / 60).round();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    color: isDark ? const Color(0xFF232731) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                      ),
                    ),
                    child: InkWell(
                      onTap: () {
                        GymWorkoutDetailModal.show(context, workout, onDeleted: () {
                          setState(() {});
                        });
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        workout.title,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        DateFormat('EEEE, MMM d, y').format(workout.startedAt),
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${durationMinutes}m',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // Volume & completed sets summary
                            Row(
                              children: [
                                const Icon(Icons.fitness_center, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  '${workout.totalVolumeKg.toStringAsFixed(1)} kg volume',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 14),
                                const Icon(Icons.check_circle_outline, size: 14, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  '${workout.totalCompletedSets} sets',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // Exercise name preview chips
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: workout.exercises.take(4).map((ex) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1A1D24) : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    ex.exerciseName,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
