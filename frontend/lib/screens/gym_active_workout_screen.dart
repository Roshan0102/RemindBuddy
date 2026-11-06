import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/exercise_model.dart';
import '../models/gym_workout.dart';
import '../models/gym_routine.dart';
import '../services/gym_service.dart';
import '../services/gym_exercise_catalog.dart';
import '../services/gym_video_launcher.dart';
import '../widgets/gym/exercise_picker_dialog.dart';
import '../widgets/gym/exercise_demo_modal.dart';

/// Screen for viewing, customizing, and executing a user's custom Gym Routine.
/// Stores exercises, sets, weights, previous weights, reps, and multiple form video links.
/// Changes are saved into the user's isolated Firestore collection: users/{uid}/gym_routines.
class GymActiveWorkoutScreen extends StatefulWidget {
  final String? initialTitle;
  final List<ExerciseModel>? starterExercises;
  final GymRoutine? starterRoutine;
  final GymRoutine? routine;

  const GymActiveWorkoutScreen({
    super.key,
    this.initialTitle,
    this.starterExercises,
    this.starterRoutine,
    this.routine,
  });

  @override
  State<GymActiveWorkoutScreen> createState() => _GymActiveWorkoutScreenState();
}

class _GymActiveWorkoutScreenState extends State<GymActiveWorkoutScreen> {
  final GymService _gymService = GymService();
  late TextEditingController _titleController;
  late TextEditingController _descController;

  // Active exercises in this routine
  final List<GymWorkoutExercise> _exercises = [];

  // Baseline weights when the routine was opened (used to move value to Previous when changed)
  // Key: exerciseIndex_setIndex -> loaded weightKg
  final Map<String, double> _baselineWeights = {};

  // Exact signature of loaded state to detect real changes
  String _initialSignature = '';
  bool _isSaving = false;

  // Active routine reference if opened from an existing routine
  GymRoutine? _activeRoutine;

  @override
  void initState() {
    super.initState();
    _activeRoutine = widget.routine ?? widget.starterRoutine;
    final defaultTitle = _activeRoutine?.name ??
        widget.initialTitle ??
        'New Routine';
    _titleController = TextEditingController(text: defaultTitle);
    _descController = TextEditingController(text: _activeRoutine?.description ?? '');

    // Populate exercises from routine or starter list synchronously
    if (_activeRoutine != null && _activeRoutine!.exercises.isNotEmpty) {
      for (final rex in _activeRoutine!.exercises) {
        _addRoutineExerciseInternal(rex);
      }
    } else if (widget.starterExercises != null && widget.starterExercises!.isNotEmpty) {
      for (final ex in widget.starterExercises!) {
        _addStarterExerciseInternal(ex);
      }
    }

    // Capture initial signature after initial state setup
    _initialSignature = _generateStateSignature();
  }

  /// Computes a deterministic hash string of all editable state to verify actual user modifications
  String _generateStateSignature() {
    final sb = StringBuffer();
    sb.write('${_titleController.text.trim()}||${_descController.text.trim()}||');
    for (int i = 0; i < _exercises.length; i++) {
      final ex = _exercises[i];
      sb.write('${ex.exerciseId}::${ex.videoUrls.join(",")}::');
      for (final s in ex.sets) {
        sb.write('${s.setNumber}_${s.weightKg}_${s.previousWeightKg}_${s.reps}_${s.isCompleted};');
      }
      sb.write('|');
    }
    return sb.toString();
  }

  /// Returns true ONLY if user made actual changes to the routine
  bool get _hasUnsavedChanges {
    return _generateStateSignature() != _initialSignature;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickAndAddExercise() async {
    final selected = await ExercisePickerDialog.show(context);
    if (selected != null) {
      _addExerciseInternal(selected);
    }
  }

  Future<void> _addExerciseInternal(ExerciseModel exercise) async {
    // Check if exercise is already in the routine
    if (_exercises.any((e) => e.exerciseId == exercise.formattedId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${exercise.displayName} is already in this routine!'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Check if user has saved custom video URLs for this exercise
    List<String> customVideos = [];
    try {
      customVideos = await _gymService.getCustomExerciseVideoUrls(exercise.formattedId);
    } catch (_) {}

    final initialSets = [
      const GymWorkoutSet(setNumber: 1, weightKg: 0, reps: 10, isCompleted: false),
      const GymWorkoutSet(setNumber: 2, weightKg: 0, reps: 10, isCompleted: false),
      const GymWorkoutSet(setNumber: 3, weightKg: 0, reps: 10, isCompleted: false),
    ];

    if (!mounted) return;
    setState(() {
      final newIndex = _exercises.length;
      for (int s = 0; s < initialSets.length; s++) {
        _baselineWeights['${newIndex}_$s'] = initialSets[s].weightKg;
      }

      _exercises.add(GymWorkoutExercise(
        exerciseId: exercise.formattedId,
        exerciseName: exercise.displayName,
        bodyPart: exercise.bodyPart,
        targetMuscle: exercise.target,
        sets: initialSets,
        restSeconds: 90,
        videoUrls: customVideos,
      ));
    });
  }

  void _addRoutineExerciseInternal(GymRoutineExercise rex) {
    if (_exercises.any((e) => e.exerciseId == rex.exerciseId)) return;

    List<String> videos = List<String>.from(rex.videoUrls);
    if (videos.isEmpty && rex.videoUrl != null && rex.videoUrl!.isNotEmpty) {
      videos.add(rex.videoUrl!);
    }

    final List<GymWorkoutSet> initialSets = [];
    if (rex.sets != null && rex.sets!.isNotEmpty) {
      for (final s in rex.sets!) {
        initialSets.add(s.copyWith());
      }
    } else {
      final setCount = rex.defaultSets > 0 ? rex.defaultSets : 3;
      for (int i = 1; i <= setCount; i++) {
        initialSets.add(GymWorkoutSet(setNumber: i, weightKg: 0, reps: 10, isCompleted: false));
      }
    }

    final newIndex = _exercises.length;
    for (int s = 0; s < initialSets.length; s++) {
      _baselineWeights['${newIndex}_$s'] = initialSets[s].weightKg;
    }

    _exercises.add(GymWorkoutExercise(
      exerciseId: rex.exerciseId,
      exerciseName: rex.exerciseName,
      bodyPart: rex.bodyPart,
      targetMuscle: rex.targetMuscle,
      sets: initialSets,
      restSeconds: rex.restSeconds > 0 ? rex.restSeconds : 90,
      videoUrls: videos,
    ));

    if (videos.isEmpty) {
      _fetchExerciseVideosInBackground(newIndex, rex.exerciseId);
    }
  }

  void _addStarterExerciseInternal(ExerciseModel exercise) {
    if (_exercises.any((e) => e.exerciseId == exercise.formattedId)) return;

    final initialSets = [
      const GymWorkoutSet(setNumber: 1, weightKg: 0, reps: 10, isCompleted: false),
      const GymWorkoutSet(setNumber: 2, weightKg: 0, reps: 10, isCompleted: false),
      const GymWorkoutSet(setNumber: 3, weightKg: 0, reps: 10, isCompleted: false),
    ];

    final newIndex = _exercises.length;
    for (int s = 0; s < initialSets.length; s++) {
      _baselineWeights['${newIndex}_$s'] = initialSets[s].weightKg;
    }

    _exercises.add(GymWorkoutExercise(
      exerciseId: exercise.formattedId,
      exerciseName: exercise.displayName,
      bodyPart: exercise.bodyPart,
      targetMuscle: exercise.target,
      sets: initialSets,
      restSeconds: 90,
      videoUrls: const [],
    ));

    _fetchExerciseVideosInBackground(newIndex, exercise.formattedId);
  }

  Future<void> _fetchExerciseVideosInBackground(int exIndex, String exerciseId) async {
    try {
      final fetched = await _gymService.getCustomExerciseVideoUrls(exerciseId);
      if (fetched.isNotEmpty && mounted && exIndex < _exercises.length) {
        final wasClean = !_hasUnsavedChanges;
        setState(() {
          _exercises[exIndex] = _exercises[exIndex].copyWith(videoUrls: fetched);
          if (wasClean) {
            _initialSignature = _generateStateSignature();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _showAddVideoDialog(int exIndex) async {
    final exercise = _exercises[exIndex];
    final controller = TextEditingController();

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
                'Add Form Video Link',
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
              'Add a YouTube, Instagram Reel, or form video demonstration for ${exercise.exerciseName}.',
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
                    'You can add multiple videos (e.g. angle demos, variations).',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              ],
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
              final val = controller.text.trim();
              if (val.isNotEmpty) {
                Navigator.pop(ctx, val);
              }
            },
            child: const Text('Add Video'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final updatedUrls = List<String>.from(exercise.videoUrls)..add(result);
      setState(() {
        _exercises[exIndex] = exercise.copyWith(videoUrls: updatedUrls);
      });

      // Persist to user's isolated collection users/{uid}/gym_exercise_links/{exerciseId}
      await _gymService.saveCustomExerciseVideoUrls(exercise.exerciseId, updatedUrls);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video link added for this exercise!')),
        );
      }
    }
  }

  Future<void> _removeVideoUrl(int exIndex, int videoIndex) async {
    final exercise = _exercises[exIndex];
    final updatedUrls = List<String>.from(exercise.videoUrls)..removeAt(videoIndex);

    setState(() {
      _exercises[exIndex] = exercise.copyWith(videoUrls: updatedUrls);
    });

    await _gymService.saveCustomExerciseVideoUrls(exercise.exerciseId, updatedUrls);
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

  void _updateSet(
    int exerciseIndex,
    int setIndex, {
    double? weight,
    int? reps,
    bool? completed,
  }) {
    final exercise = _exercises[exerciseIndex];
    final current = exercise.sets[setIndex];

    double? newPrevious = current.previousWeightKg;
    final baseline = _baselineWeights['${exerciseIndex}_$setIndex'] ?? 0.0;

    // If changing weight from the baseline saved value, move the baseline to previous
    if (weight != null) {
      if (baseline > 0 && weight != baseline) {
        newPrevious = baseline;
      }
    }

    final updated = current.copyWith(
      weightKg: weight ?? current.weightKg,
      reps: reps ?? current.reps,
      isCompleted: completed ?? current.isCompleted,
      previousWeightKg: newPrevious,
    );

    // Subtle feedback when toggling completion, NO timer triggered
    if (completed != null) {
      HapticFeedback.selectionClick();
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

  /// Saves or updates the routine in the user's isolated Firestore collection: users/{uid}/gym_routines
  Future<bool> _saveRoutine() async {
    final name = _titleController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name for the routine.')),
      );
      return false;
    }

    if (_exercises.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one exercise to the routine before saving.')),
      );
      return false;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final isExisting = _activeRoutine != null && _activeRoutine!.id.isNotEmpty;
      final routineId = isExisting ? _activeRoutine!.id : '';

      final routine = GymRoutine(
        id: routineId,
        userId: _gymService.currentUserId ?? '',
        name: name,
        description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
        exercises: _exercises.map((e) {
          return GymRoutineExercise(
            exerciseId: e.exerciseId,
            exerciseName: e.exerciseName,
            bodyPart: e.bodyPart,
            targetMuscle: e.targetMuscle,
            defaultSets: e.sets.isNotEmpty ? e.sets.length : 3,
            videoUrls: e.videoUrls,
            sets: e.sets,
          );
        }).toList(),
        createdAt: _activeRoutine?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final savedId = await _gymService.saveRoutine(routine);

      if (mounted) {
        setState(() {
          _activeRoutine = routine.copyWith(id: savedId);
          _isSaving = false;
          // Update baselines with newly saved values
          for (int e = 0; e < _exercises.length; e++) {
            for (int s = 0; s < _exercises[e].sets.length; s++) {
              _baselineWeights['${e}_$s'] = _exercises[e].sets[s].weightKg;
            }
          }
          // Reset change tracking signature so it won't ask to save on back press
          _initialSignature = _generateStateSignature();
        });

        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isExisting
                        ? 'Routine "$name" updated successfully!'
                        : 'Routine "$name" saved to your routines!',
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save routine: $e')),
        );
      }
      return false;
    }
  }

  /// Intercepts back navigation. If changes were made, asks "Save Changes or Discard?"
  /// If no changes were made, immediately returns true (no prompt shown).
  Future<bool> _handleBackPress() async {
    if (!_hasUnsavedChanges) {
      return true; // No unsaved changes, allow immediate pop without prompting
    }

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.save_outlined, color: Colors.blueAccent),
            SizedBox(width: 10),
            Text('Save Changes?'),
          ],
        ),
        content: const Text(
          'You have unsaved changes to this routine. Do you want to save your changes or discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (choice == 'save') {
      final success = await _saveRoutine();
      return success; // Allow pop only if saved successfully
    } else if (choice == 'discard') {
      return true; // Discard changes and pop screen
    }

    return false; // Cancel or stay on screen
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _handleBackPress();
        if (shouldPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldPop = await _handleBackPress();
              if (shouldPop && context.mounted) {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            _activeRoutine != null && _activeRoutine!.id.isNotEmpty
                ? 'Edit Routine'
                : 'Routine Details',
            style: const TextStyle(fontWeight: FontWeight.bold),
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
              ),
          ],
        ),
        body: Column(
          children: [
            // Routine Header: Name & Description editor
            _buildRoutineMetaHeader(isDark, theme),

            // Exercises List
            Expanded(
              child: _exercises.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: 90,
                      ),
                      itemCount: _exercises.length,
                      itemBuilder: (context, exIndex) {
                        return _buildExerciseCard(exIndex);
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
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Save Changes'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _saveRoutine,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoutineMetaHeader(bool isDark, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D24) : Colors.grey.shade50,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleController,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              hintText: 'Routine Name (e.g. Chest & Triceps)',
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descController,
            style: TextStyle(fontSize: 13, color: isDark ? Colors.grey[400] : Colors.grey[700]),
            decoration: const InputDecoration(
              hintText: 'Add an optional description or target split...',
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
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
              'No exercises in this routine',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap "+ Add Exercise" below to build your routine movements with sets and video links.',
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

                // Options button
                IconButton(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onPressed: () => _showExerciseOptions(exIndex),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Multiple Videos Section (YouTube, Instagram, Web)
            _buildVideoLinksSection(exIndex, exercise, isDark),

            const SizedBox(height: 12),

            // Sets Table Header
            const Row(
              children: [
                SizedBox(
                  width: 32,
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
                  width: 40,
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
              return _buildSetRow(exIndex, setIndex, set);
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoLinksSection(int exIndex, GymWorkoutExercise exercise, bool isDark) {
    final urls = exercise.videoUrls;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (urls.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ...List.generate(urls.length, (vIdx) {
                final url = urls[vIdx];
                final platformColor = GymVideoLauncher.getPlatformColor(url);
                final platformIcon = GymVideoLauncher.getPlatformIcon(url);
                final platformLabel = GymVideoLauncher.getPlatformLabel(url);

                return InkWell(
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await GymVideoLauncher.launchVideo(url);
                    if (!ok && mounted) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Could not open video link.')),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: platformColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: platformColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(platformIcon, size: 13, color: platformColor),
                        const SizedBox(width: 4),
                        Text(
                          urls.length > 1 ? '$platformLabel #${vIdx + 1}' : platformLabel,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: platformColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _removeVideoUrl(exIndex, vIdx),
                          borderRadius: BorderRadius.circular(10),
                          child: Icon(
                            Icons.close,
                            size: 13,
                            color: platformColor.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              InkWell(
                onTap: () => _showAddVideoDialog(exIndex),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 13, color: Colors.blueAccent),
                      SizedBox(width: 3),
                      Text(
                        '+ Add Video',
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
          )
        else
          InkWell(
            onTap: () => _showAddVideoDialog(exIndex),
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
    );
  }

  Widget _buildSetRow(
    int exIndex,
    int setIndex,
    GymWorkoutSet set,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String prevText;
    if (set.previousWeightKg != null && set.previousWeightKg! > 0) {
      final prevW = set.previousWeightKg!;
      prevText = '${prevW.toStringAsFixed(prevW % 1 == 0 ? 0 : 1)} kg';
    } else {
      prevText = '-';
    }

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
              width: 32,
              child: Text(
                '${set.setNumber}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ),

            // Previous Weight
            Expanded(
              flex: 3,
              child: Text(
                prevText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),

            // Weight Input (KG)
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

            // Checkbox: NO TIMER TRIGGERED
            SizedBox(
              width: 40,
              child: IconButton(
                icon: Icon(
                  set.isCompleted ? Icons.check_circle : Icons.check_circle_outline,
                  color: set.isCompleted ? Colors.green : Colors.grey[400],
                  size: 24,
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_library_outlined, color: Colors.blueAccent),
              title: const Text('Add Another Video Link'),
              subtitle: const Text(
                'Attach YouTube or Instagram Reel demonstration',
                style: TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showAddVideoDialog(exIndex);
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
}
