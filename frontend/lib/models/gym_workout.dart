import 'package:cloud_firestore/cloud_firestore.dart';

/// Single set within an exercise (e.g. Set 1: 60kg x 10 reps)
class GymWorkoutSet {
  final int setNumber;
  final double weightKg;
  final int reps;
  final bool isWarmup;
  final bool isDropSet;
  final bool isCompleted;
  final double? rpe; // Rate of Perceived Exertion (1 to 10)

  const GymWorkoutSet({
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    this.isWarmup = false,
    this.isDropSet = false,
    this.isCompleted = true,
    this.rpe,
  });

  /// Computed volume for this set in kg
  double get volume => isCompleted && !isWarmup ? weightKg * reps : 0.0;

  Map<String, dynamic> toMap() {
    return {
      'setNumber': setNumber,
      'weightKg': weightKg,
      'reps': reps,
      'isWarmup': isWarmup,
      'isDropSet': isDropSet,
      'isCompleted': isCompleted,
      if (rpe != null) 'rpe': rpe,
    };
  }

  factory GymWorkoutSet.fromMap(Map<String, dynamic> map) {
    return GymWorkoutSet(
      setNumber: (map['setNumber'] as num?)?.toInt() ?? 1,
      weightKg: (map['weightKg'] as num?)?.toDouble() ?? 0.0,
      reps: (map['reps'] as num?)?.toInt() ?? 0,
      isWarmup: map['isWarmup'] == true,
      isDropSet: map['isDropSet'] == true,
      isCompleted: map['isCompleted'] != false,
      rpe: (map['rpe'] as num?)?.toDouble(),
    );
  }

  GymWorkoutSet copyWith({
    int? setNumber,
    double? weightKg,
    int? reps,
    bool? isWarmup,
    bool? isDropSet,
    bool? isCompleted,
    double? rpe,
  }) {
    return GymWorkoutSet(
      setNumber: setNumber ?? this.setNumber,
      weightKg: weightKg ?? this.weightKg,
      reps: reps ?? this.reps,
      isWarmup: isWarmup ?? this.isWarmup,
      isDropSet: isDropSet ?? this.isDropSet,
      isCompleted: isCompleted ?? this.isCompleted,
      rpe: rpe ?? this.rpe,
    );
  }
}

/// An exercise performed during a workout session with all its sets
class GymWorkoutExercise {
  final String exerciseId;
  final String exerciseName;
  final String bodyPart;
  final String targetMuscle;
  final List<GymWorkoutSet> sets;
  final int restSeconds; // e.g. 60, 90, 120
  final String? notes;

  const GymWorkoutExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.bodyPart,
    this.targetMuscle = '',
    required this.sets,
    this.restSeconds = 90,
    this.notes,
  });

  /// Total volume across all completed sets in kg
  double get totalVolume => sets.fold(0.0, (total, set) => total + set.volume);

  /// Best (heaviest) working set completed in this exercise
  GymWorkoutSet? get bestSet {
    final completedSets = sets.where((s) => s.isCompleted && !s.isWarmup).toList();
    if (completedSets.isEmpty) return null;
    completedSets.sort((a, b) => b.weightKg.compareTo(a.weightKg));
    return completedSets.first;
  }

  Map<String, dynamic> toMap() {
    return {
      'exerciseId': exerciseId,
      'exerciseName': exerciseName,
      'bodyPart': bodyPart,
      'targetMuscle': targetMuscle,
      'sets': sets.map((s) => s.toMap()).toList(),
      'restSeconds': restSeconds,
      if (notes != null) 'notes': notes,
    };
  }

  factory GymWorkoutExercise.fromMap(Map<String, dynamic> map) {
    return GymWorkoutExercise(
      exerciseId: map['exerciseId']?.toString() ?? '',
      exerciseName: map['exerciseName']?.toString() ?? '',
      bodyPart: map['bodyPart']?.toString() ?? '',
      targetMuscle: map['targetMuscle']?.toString() ?? '',
      sets: (map['sets'] as List<dynamic>?)
              ?.map((s) => GymWorkoutSet.fromMap(Map<String, dynamic>.from(s)))
              .toList() ??
          [],
      restSeconds: (map['restSeconds'] as num?)?.toInt() ?? 90,
      notes: map['notes']?.toString(),
    );
  }

  GymWorkoutExercise copyWith({
    String? exerciseId,
    String? exerciseName,
    String? bodyPart,
    String? targetMuscle,
    List<GymWorkoutSet>? sets,
    int? restSeconds,
    String? notes,
  }) {
    return GymWorkoutExercise(
      exerciseId: exerciseId ?? this.exerciseId,
      exerciseName: exerciseName ?? this.exerciseName,
      bodyPart: bodyPart ?? this.bodyPart,
      targetMuscle: targetMuscle ?? this.targetMuscle,
      sets: sets ?? this.sets,
      restSeconds: restSeconds ?? this.restSeconds,
      notes: notes ?? this.notes,
    );
  }
}

/// A complete logged workout session
class GymWorkout {
  final String id;
  final String userId;
  final String title; // e.g. "Push Day", "Chest & Triceps", "Full Body"
  final DateTime startedAt;
  final DateTime? completedAt;
  final int durationSeconds; // total active time
  final List<GymWorkoutExercise> exercises;
  final String? notes;

  const GymWorkout({
    required this.id,
    required this.userId,
    required this.title,
    required this.startedAt,
    this.completedAt,
    this.durationSeconds = 0,
    required this.exercises,
    this.notes,
  });

  /// Total workout volume across all exercises (kg)
  double get totalVolumeKg =>
      exercises.fold(0.0, (total, ex) => total + ex.totalVolume);

  /// Total completed sets in the session
  int get totalCompletedSets => exercises.fold(
      0, (total, ex) => total + ex.sets.where((s) => s.isCompleted && !s.isWarmup).length);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'title': title,
      'startedAt': Timestamp.fromDate(startedAt),
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'durationSeconds': durationSeconds,
      'exercises': exercises.map((e) => e.toMap()).toList(),
      'totalVolumeKg': totalVolumeKg,
      if (notes != null) 'notes': notes,
    };
  }

  factory GymWorkout.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return GymWorkout(
      id: docId ?? map['id']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Workout',
      startedAt: parseDate(map['startedAt']),
      completedAt: map['completedAt'] != null ? parseDate(map['completedAt']) : null,
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      exercises: (map['exercises'] as List<dynamic>?)
              ?.map((e) => GymWorkoutExercise.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      notes: map['notes']?.toString(),
    );
  }
}
