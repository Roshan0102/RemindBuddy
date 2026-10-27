import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/exercise_model.dart';
import '../models/gym_workout.dart';
import '../models/gym_routine.dart';
import '../services/gym_service.dart';
import '../services/gym_exercise_catalog.dart';
import '../services/gym_video_launcher.dart';
import '../widgets/gym/exercise_picker_dialog.dart';
import '../widgets/gym/exercise_demo_modal.dart';
import '../widgets/gym/gym_rest_timer_widget.dart';

/// Screen for tracking a live active workout session in real-time.
/// Features set-by-set weight logging, progressive overload pre-filling,
/// interactive rest timers, and automatic PR calculations.
class GymActiveWorkoutScreen extends StatefulWidget {
  final String? initialTitle;
  final List<ExerciseModel>? starterExercises;
  final GymRoutine? starterRoutine;

  const GymActiveWorkoutScreen({
    super.key,
    this.initialTitle,
    this.starterExercises,
    this.starterRoutine,
  });

  @override
  State<GymActiveWorkoutScreen> createState() => _GymActiveWorkoutScreenState();
}

class _GymActiveWorkoutScreenState extends State<GymActiveWorkoutScreen> {
  final GymService _gymService = GymService();
  late TextEditingController _titleController;
  final TextEditingController _notesController = TextEditingController();

  final DateTime _startedAt = DateTime.now();
  int _durationSeconds = 0;
  Timer? _durationTimer;

  // Active exercises in this workout
  final List<GymWorkoutExercise> _exercises = [];

  // Previous sets for progressive overload lookup: exerciseId -> list of sets
  final Map<String, List<GymWorkoutSet>> _previousSets = {};

  // Rest Timer state
  int? _activeRestSeconds;

  bool _isSaving = false;

  // Track active routine if started from a routine preset
  GymRoutine? _activeRoutine;

  @override
  void initState() {
    super.initState();
    _activeRoutine = widget.starterRoutine;
    final defaultTitle = widget.initialTitle ??
        (widget.starterRoutine != null
            ? widget.starterRoutine!.name
            : 'Workout - ${DateFormat('EEEE, MMM d').format(DateTime.now())}');
    _titleController = TextEditingController(text: defaultTitle);

    _startDurationTimer();

    // Populate initial exercises from routine or starter list
    if (widget.starterRoutine != null && widget.starterRoutine!.exercises.isNotEmpty) {
      for (final rex in widget.starterRoutine!.exercises) {
        _addRoutineExerciseInternal(rex);
      }
    } else if (widget.starterExercises != null && widget.starterExercises!.isNotEmpty) {
      for (final ex in widget.starterExercises!) {
        _addExerciseInternal(ex);
      }
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _durationSeconds++;
        });
      }
    });
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _pickAndAddExercise() async {
    final selected = await ExercisePickerDialog.show(context);
    if (selected != null) {
      _addExerciseInternal(selected);
    }
  }

  Future<void> _addExerciseInternal(ExerciseModel exercise) async {
    // Check if exercise is already in the workout
    if (_exercises.any((e) => e.exerciseId == exercise.formattedId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${exercise.displayName} is already in this workout!'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Try fetching previous sets from Firestore for progressive overload prefill
    try {
      final prevMap = await _gymService.getLastSetsForExercises([exercise.formattedId]);
      if (mounted && prevMap.isNotEmpty) {
        setState(() {
          _previousSets.addAll(prevMap);
        });
      }
    } catch (_) {}

    // Check if user has a custom video URL saved for this exercise
    String? customVideo;
    try {
      customVideo = await _gymService.getCustomExerciseVideoUrl(exercise.formattedId);
    } catch (_) {}

    final prevSets = _previousSets[exercise.formattedId];

    // Default sets: either pre-fill from last time or create 3 fresh sets
    final List<GymWorkoutSet> initialSets = [];
    if (prevSets != null && prevSets.isNotEmpty) {
      for (int i = 0; i < prevSets.length; i++) {
        final p = prevSets[i];
        initialSets.add(GymWorkoutSet(
          setNumber: i + 1,
          weightKg: p.weightKg,
          reps: p.reps,
          isCompleted: false,
          isWarmup: p.isWarmup,
        ));
      }
    } else {
      initialSets.addAll([
        const GymWorkoutSet(setNumber: 1, weightKg: 0, reps: 10, isCompleted: false),
        const GymWorkoutSet(setNumber: 2, weightKg: 0, reps: 10, isCompleted: false),
        const GymWorkoutSet(setNumber: 3, weightKg: 0, reps: 10, isCompleted: false),
      ]);
    }

    if (!mounted) return;
    setState(() {
      _exercises.add(GymWorkoutExercise(
        exerciseId: exercise.formattedId,
        exerciseName: exercise.displayName,
        bodyPart: exercise.bodyPart,
        targetMuscle: exercise.target,
        sets: initialSets,
        restSeconds: 90,
        videoUrl: customVideo,
      ));
    });
  }

  Future<void> _addRoutineExerciseInternal(GymRoutineExercise rex) async {
    if (_exercises.any((e) => e.exerciseId == rex.exerciseId)) return;

    try {
      final prevMap = await _gymService.getLastSetsForExercises([rex.exerciseId]);
      if (mounted && prevMap.isNotEmpty) {
        setState(() {
          _previousSets.addAll(prevMap);
        });
      }
    } catch (_) {}

    String? customVideo = rex.videoUrl;
    if (customVideo == null || customVideo.isEmpty) {
      try {
        customVideo = await _gymService.getCustomExerciseVideoUrl(rex.exerciseId);
      } catch (_) {}
    }

    final prevSets = _previousSets[rex.exerciseId];
    final List<GymWorkoutSet> initialSets = [];
    if (prevSets != null && prevSets.isNotEmpty) {
      for (int i = 0; i < prevSets.length; i++) {
        final p = prevSets[i];
        initialSets.add(GymWorkoutSet(
          setNumber: i + 1,
          weightKg: p.weightKg,
          reps: p.reps,
          isCompleted: false,
          isWarmup: p.isWarmup,
        ));
      }
    } else {
      final setCount = rex.defaultSets > 0 ? rex.defaultSets : 3;
      for (int i = 1; i <= setCount; i++) {
        initialSets.add(GymWorkoutSet(setNumber: i, weightKg: 0, reps: 10, isCompleted: false));
      }
    }

    if (!mounted) return;
    setState(() {
      _exercises.add(GymWorkoutExercise(
        exerciseId: rex.exerciseId,
        exerciseName: rex.exerciseName,
        bodyPart: rex.bodyPart,
        targetMuscle: rex.targetMuscle,
        sets: initialSets,
        restSeconds: rex.restSeconds > 0 ? rex.restSeconds : 90,
        videoUrl: customVideo,
      ));
    });
  }

  Future<void> _promptEditVideoUrl(int exIndex) async {
    final exercise = _exercises[exIndex];
    final controller = TextEditingController(text: exercise.videoUrl ?? '');

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.video_collection_outlined, color: Colors.blueAccent),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Exercise Video Link',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add your YouTube, Instagram Reel, or form video link for ${exercise.exerciseName}.',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Video URL',
                hintText: 'https://youtu.be/... or instagram.com/reel/...',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Opens in YouTube / Instagram app on phones, or web browser.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (exercise.videoUrl != null && exercise.videoUrl!.isNotEmpty)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Remove Link'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save Link'),
          ),
        ],
      ),
    );

    if (result != null) {
      final newUrl = result.isEmpty ? null : result;
      setState(() {
        _exercises[exIndex] = exercise.copyWith(videoUrl: newUrl);
      });
      // Save permanently for this exercise under users/{uid}/gym_exercise_links/{exerciseId}
      if (newUrl != null && newUrl.isNotEmpty) {
        await _gymService.saveCustomExerciseVideoUrl(exercise.exerciseId, newUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video link saved for this exercise!')),
          );
        }
      }
    }
  }

  Future<void> _saveAsRoutine() async {
    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one exercise before saving as a routine.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final isExistingRoutine = _activeRoutine != null && _activeRoutine!.id.isNotEmpty;
    final initialName = _activeRoutine != null && _activeRoutine!.name.isNotEmpty
        ? _activeRoutine!.name
        : (_titleController.text.trim().isNotEmpty && !_titleController.text.startsWith('Workout -')
            ? _titleController.text.trim()
            : '');
    final initialDesc = _activeRoutine?.description ?? '';

    final titleCtrl = TextEditingController(text: initialName);
    final descCtrl = TextEditingController(text: initialDesc);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(isExistingRoutine ? Icons.edit_note_rounded : Icons.bookmark_add, color: Colors.blueAccent),
            const SizedBox(width: 10),
            Text(isExistingRoutine ? 'Update Routine' : 'Save as Routine'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isExistingRoutine
                    ? 'Update "${_activeRoutine!.name}" with the newly added exercises and sets.'
                    : 'Save these exercises as a reusable routine in "Quick Splits & Routines" on your Gym Dashboard.',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Routine Name',
                  hintText: 'e.g. Chest & Triceps, Heavy Legs',
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
              const SizedBox(height: 16),
              Text(
                'Included Exercises (${_exercises.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              ...List.generate(_exercises.length, (i) {
                final ex = _exercises[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.check, size: 14, color: Colors.green),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${ex.exerciseName} (${ex.sets.length} sets)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (titleCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a name for the routine.'),
                    duration: Duration(seconds: 3),
                  ),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Text(isExistingRoutine ? 'Update Routine' : 'Save Routine'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final name = titleCtrl.text.trim();
      final routineId = _activeRoutine != null ? _activeRoutine!.id : '';
      final routine = GymRoutine(
        id: routineId,
        userId: _gymService.currentUserId ?? '',
        name: name,
        description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
        exercises: _exercises.map((e) {
          return GymRoutineExercise(
            exerciseId: e.exerciseId,
            exerciseName: e.exerciseName,
            bodyPart: e.bodyPart,
            targetMuscle: e.targetMuscle,
            defaultSets: e.sets.isNotEmpty ? e.sets.length : 3,
            restSeconds: e.restSeconds,
            videoUrl: e.videoUrl,
          );
        }).toList(),
        createdAt: _activeRoutine?.createdAt ?? DateTime.now(),
      );

      try {
        final savedId = await _gymService.saveRoutine(routine);
        setState(() {
          _activeRoutine = routine.copyWith(id: savedId);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isExistingRoutine
                  ? 'Routine "$name" updated successfully!'
                  : 'Routine "$name" saved to Quick Splits & Routines!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save routine: $e'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  void _addSetToExercise(int exerciseIndex) {
    final exercise = _exercises[exerciseIndex];
    final lastSet = exercise.sets.isNotEmpty ? exercise.sets.last : null;

    final newSet = GymWorkoutSet(
      setNumber: exercise.sets.length + 1,
      weightKg: lastSet?.weightKg ?? 0,
      reps: lastSet?.reps ?? 10,
      isCompleted: false,
    );

    setState(() {
      final updatedSets = List<GymWorkoutSet>.from(exercise.sets)..add(newSet);
      _exercises[exerciseIndex] = exercise.copyWith(sets: updatedSets);
    });
  }

  void _deleteSet(int exerciseIndex, int setIndex) {
    final exercise = _exercises[exerciseIndex];
    if (exercise.sets.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least one set is required per exercise.'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    final updatedSets = List<GymWorkoutSet>.from(exercise.sets)..removeAt(setIndex);
    // Renumber remaining sets
    for (int i = 0; i < updatedSets.length; i++) {
      updatedSets[i] = updatedSets[i].copyWith(setNumber: i + 1);
    }

    setState(() {
      _exercises[exerciseIndex] = exercise.copyWith(sets: updatedSets);
    });
  }

  void _updateSet(int exerciseIndex, int setIndex, {double? weight, int? reps, bool? completed}) {
    final exercise = _exercises[exerciseIndex];
    final current = exercise.sets[setIndex];

    final updated = current.copyWith(
      weightKg: weight ?? current.weightKg,
      reps: reps ?? current.reps,
      isCompleted: completed ?? current.isCompleted,
    );

    // If checked as completed, trigger Rest Timer automatically
    if (completed == true) {
      HapticFeedback.lightImpact();
      setState(() {
        _activeRestSeconds = exercise.restSeconds;
      });
    }

    setState(() {
      final updatedSets = List<GymWorkoutSet>.from(exercise.sets);
      updatedSets[setIndex] = updated;
      _exercises[exerciseIndex] = exercise.copyWith(sets: updatedSets);
    });
  }

  void _removeExercise(int exerciseIndex) {
    setState(() {
      _exercises.removeAt(exerciseIndex);
    });
  }

  Future<void> _finishWorkout() async {
    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise to save the workout.')),
      );
      return;
    }

    final totalCompleted = _exercises.fold(
      0,
      (total, ex) => total + ex.sets.where((s) => s.isCompleted && !s.isWarmup).length,
    );

    if (totalCompleted == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete at least one set before finishing!')),
      );
      return;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final double totalVolume = _exercises.fold(0.0, (total, ex) => total + ex.totalVolume);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber, size: 28),
            SizedBox(width: 10),
            Text('Finish Workout?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF14171E) : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('DURATION', _formatDuration(_durationSeconds)),
                  _buildStatItem('VOLUME', '${totalVolume.toStringAsFixed(1)} kg'),
                  _buildStatItem('SETS', '$totalCompleted'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                hintText: 'Workout notes (e.g. felt strong on bench press)',
                filled: true,
                fillColor: isDark ? const Color(0xFF282C37) : Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Resume Workout'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Save & Finish'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (shouldSave != true) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final workout = GymWorkout(
        id: '',
        userId: _gymService.currentUserId ?? '',
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : 'Workout',
        startedAt: _startedAt,
        completedAt: DateTime.now(),
        durationSeconds: _durationSeconds,
        exercises: _exercises,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      await _gymService.saveWorkout(workout);

      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Text('Workout saved! Great work today 💪'),
              ],
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving workout: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Future<bool> _onWillPop() async {
    if (_exercises.isEmpty) return true;

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Workout?'),
        content: const Text(
          'Are you sure you want to exit? Your active workout progress will not be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Training'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: _exercises.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final discard = await _onWillPop();
        if (discard && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.timer, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(_durationSeconds),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            if (_isSaving)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.bookmark_add_outlined),
                tooltip: 'Save as Routine',
                onPressed: _saveAsRoutine,
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Finish'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: _finishWorkout,
                ),
              ),
            ],
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _exercises.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 12,
                            bottom: 100, // Space for floating timer and add button
                          ),
                          itemCount: _exercises.length,
                          itemBuilder: (context, exIndex) {
                            return _buildExerciseCard(exIndex);
                          },
                        ),
                ),
              ],
            ),

            // Bottom Floating Rest Timer
            if (_activeRestSeconds != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 80,
                child: GymRestTimerWidget(
                  initialSeconds: _activeRestSeconds!,
                  onDismiss: () {
                    setState(() {
                      _activeRestSeconds = null;
                    });
                  },
                ),
              ),
          ],
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E222A) : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
              ),
            ),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Exercise'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _pickAndAddExercise,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.bookmark_outline),
                  label: const Text('Save Routine'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _saveAsRoutine,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fitness_center,
                size: 56,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No exercises added yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "+ Add Exercise" below to pick your movements for today’s session.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add First Exercise'),
              onPressed: _pickAndAddExercise,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseCard(int exIndex) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final exercise = _exercises[exIndex];
    final catalogModel = GymExerciseCatalog.findById(exercise.exerciseId);

    final previousList = _previousSets[exercise.exerciseId] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      color: isDark ? const Color(0xFF232731) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exercise Header
            Row(
              children: [
                // Thumbnail
                if (catalogModel != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 44,
                      height: 44,
                      color: isDark ? const Color(0xFF1A1D24) : Colors.grey[100],
                      child: Image.network(
                        catalogModel.stillUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.fitness_center),
                      ),
                    ),
                  ),

                const SizedBox(width: 12),

                // Name & Target
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.exerciseName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${exercise.bodyPart.toUpperCase()} • ${exercise.targetMuscle.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Custom Form Video Action Button (YouTube, IG, Web)
                      if (exercise.videoUrl != null && exercise.videoUrl!.isNotEmpty)
                        InkWell(
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final ok = await GymVideoLauncher.launchVideo(exercise.videoUrl!);
                            if (!ok && mounted) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Could not open video. Check the link in exercise options.')),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: GymVideoLauncher.getPlatformColor(exercise.videoUrl).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: GymVideoLauncher.getPlatformColor(exercise.videoUrl).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  GymVideoLauncher.getPlatformIcon(exercise.videoUrl),
                                  size: 13,
                                  color: GymVideoLauncher.getPlatformColor(exercise.videoUrl),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  GymVideoLauncher.getPlatformLabel(exercise.videoUrl),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: GymVideoLauncher.getPlatformColor(exercise.videoUrl),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        InkWell(
                          onTap: () => _promptEditVideoUrl(exIndex),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey[800] : Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.video_call_outlined, size: 13, color: Colors.blueAccent),
                                SizedBox(width: 4),
                                Text(
                                  '+ Add Form Video',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Info / Form demo button
                if (catalogModel != null)
                  IconButton(
                    icon: const Icon(Icons.help_outline, color: Colors.grey, size: 20),
                    tooltip: 'Exercise Guide',
                    onPressed: () {
                      ExerciseDemoModal.show(context, catalogModel);
                    },
                  ),

                // Delete exercise button
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onPressed: () => _showExerciseOptions(exIndex),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Sets Table Header
            const Row(
              children: [
                SizedBox(
                  width: 38,
                  child: Text(
                    'SET',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'PREVIOUS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'KG',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'REPS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Center(
                    child: Icon(Icons.check, size: 16, color: Colors.grey),
                  ),
                ),
              ],
            ),

            const Divider(height: 12),

            // Sets List
            ...List.generate(exercise.sets.length, (setIndex) {
              final set = exercise.sets[setIndex];
              final prevSet = setIndex < previousList.length ? previousList[setIndex] : null;

              return _buildSetRow(exIndex, setIndex, set, prevSet);
            }),

            const SizedBox(height: 8),

            // Add Set Button
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Set'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: () => _addSetToExercise(exIndex),
                ),
                const Spacer(),
                // Rest Interval chip
                InkWell(
                  onTap: () => _showRestTimerPicker(exIndex),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E222A) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 14, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          '${exercise.restSeconds}s Rest',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetRow(
    int exIndex,
    int setIndex,
    GymWorkoutSet set,
    GymWorkoutSet? prevSet,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final prevText = prevSet != null
        ? '${prevSet.weightKg > 0 ? "${prevSet.weightKg}kg × " : ""}${prevSet.reps}'
        : '-';

    return Dismissible(
      key: ValueKey('set_${exIndex}_${set.setNumber}_$setIndex'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete, color: Colors.white, size: 20),
      ),
      onDismissed: (_) => _deleteSet(exIndex, setIndex),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: set.isCompleted
              ? (isDark ? const Color(0xFF1E382B) : const Color(0xFFE8F5E9))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
          // Set Number
          SizedBox(
            width: 38,
            child: Text(
              '${set.setNumber}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
          ),

          // Previous Set
          Expanded(
            flex: 3,
            child: Text(
              prevText,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),

          // Weight Input
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              height: 38,
              child: TextFormField(
                initialValue: set.weightKg > 0 ? set.weightKg.toString() : '',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: '0',
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A1D24) : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val) ?? 0.0;
                  _updateSet(exIndex, setIndex, weight: parsed);
                },
              ),
            ),
          ),

          // Reps Input
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              height: 38,
              child: TextFormField(
                initialValue: set.reps > 0 ? set.reps.toString() : '',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  hintText: '0',
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1A1D24) : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  final parsed = int.tryParse(val) ?? 0;
                  _updateSet(exIndex, setIndex, reps: parsed);
                },
              ),
            ),
          ),

          // Checkbox / Complete Button
          SizedBox(
            width: 44,
            child: IconButton(
              icon: Icon(
                set.isCompleted ? Icons.check_circle : Icons.check_circle_outline,
                color: set.isCompleted ? Colors.green : Colors.grey[400],
                size: 26,
              ),
              onPressed: () {
                _updateSet(exIndex, setIndex, completed: !set.isCompleted);
              },
            ),
          ),
        ],
      ),
    ),
  );
  }

  void _showExerciseOptions(int exIndex) {
    final exercise = _exercises[exIndex];
    final hasVideo = exercise.videoUrl != null && exercise.videoUrl!.isNotEmpty;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasVideo)
              ListTile(
                leading: Icon(
                  GymVideoLauncher.getPlatformIcon(exercise.videoUrl),
                  color: GymVideoLauncher.getPlatformColor(exercise.videoUrl),
                ),
                title: Text(
                  GymVideoLauncher.getPlatformLabel(exercise.videoUrl),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: GymVideoLauncher.getPlatformColor(exercise.videoUrl),
                  ),
                ),
                subtitle: Text(
                  exercise.videoUrl!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  GymVideoLauncher.launchVideo(exercise.videoUrl!);
                },
              ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined, color: Colors.blueAccent),
              title: Text(hasVideo ? 'Change Video Link' : 'Add Form Video Link'),
              subtitle: Text(
                hasVideo ? 'Update YouTube or Instagram Reel link' : 'Attach your 30s form demo video',
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _promptEditVideoUrl(exIndex);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Adjust Rest Timer'),
              onTap: () {
                Navigator.pop(ctx);
                _showRestTimerPicker(exIndex);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove Exercise', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _removeExercise(exIndex);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRestTimerPicker(int exIndex) {
    final current = _exercises[exIndex].restSeconds;
    final options = [30, 45, 60, 90, 120, 150, 180];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Default Rest Timer for this Exercise',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ...options.map((sec) {
              return ListTile(
                title: Text('$sec seconds'),
                trailing: current == sec ? const Icon(Icons.check, color: Colors.blue) : null,
                onTap: () {
                  setState(() {
                    _exercises[exIndex] = _exercises[exIndex].copyWith(restSeconds: sec);
                  });
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}
