import 'package:cloud_firestore/cloud_firestore.dart';
import 'gym_workout.dart';

/// Template for an exercise inside a user's custom workout routine
class GymRoutineExercise {
  final String exerciseId;
  final String exerciseName;
  final String bodyPart;
  final String targetMuscle;
  final int defaultSets;
  final int restSeconds;
  final String? videoUrl;
  final List<String> videoUrls;
  final List<GymWorkoutSet>? sets;

  const GymRoutineExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.bodyPart,
    this.targetMuscle = '',
    this.defaultSets = 3,
    this.restSeconds = 90,
    this.videoUrl,
    this.videoUrls = const [],
    this.sets,
  });

  Map<String, dynamic> toMap() {
    final resolvedUrls = videoUrls.isNotEmpty
        ? videoUrls
        : (videoUrl != null && videoUrl!.trim().isNotEmpty ? [videoUrl!.trim()] : <String>[]);

    return {
      'exerciseId': exerciseId,
      'exerciseName': exerciseName,
      'bodyPart': bodyPart,
      'targetMuscle': targetMuscle,
      'defaultSets': defaultSets,
      'restSeconds': restSeconds,
      if (resolvedUrls.isNotEmpty) 'videoUrl': resolvedUrls.first,
      if (resolvedUrls.isNotEmpty) 'videoUrls': resolvedUrls,
      if (sets != null && sets!.isNotEmpty) 'sets': sets!.map((s) => s.toMap()).toList(),
    };
  }

  factory GymRoutineExercise.fromMap(Map<String, dynamic> map) {
    final rawList = (map['videoUrls'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];
    if (rawList.isEmpty && map['videoUrl'] != null && map['videoUrl'].toString().trim().isNotEmpty) {
      rawList.add(map['videoUrl'].toString().trim());
    }

    return GymRoutineExercise(
      exerciseId: map['exerciseId']?.toString() ?? '',
      exerciseName: map['exerciseName']?.toString() ?? '',
      bodyPart: map['bodyPart']?.toString() ?? '',
      targetMuscle: map['targetMuscle']?.toString() ?? '',
      defaultSets: (map['defaultSets'] as num?)?.toInt() ?? 3,
      restSeconds: (map['restSeconds'] as num?)?.toInt() ?? 90,
      videoUrl: rawList.isNotEmpty ? rawList.first : null,
      videoUrls: rawList,
      sets: (map['sets'] as List<dynamic>?)
          ?.map((s) => GymWorkoutSet.fromMap(Map<String, dynamic>.from(s)))
          .toList(),
    );
  }

  GymRoutineExercise copyWith({
    String? exerciseId,
    String? exerciseName,
    String? bodyPart,
    String? targetMuscle,
    int? defaultSets,
    int? restSeconds,
    String? videoUrl,
    List<String>? videoUrls,
    List<GymWorkoutSet>? sets,
  }) {
    final updatedUrls = videoUrls ?? this.videoUrls;
    return GymRoutineExercise(
      exerciseId: exerciseId ?? this.exerciseId,
      exerciseName: exerciseName ?? this.exerciseName,
      bodyPart: bodyPart ?? this.bodyPart,
      targetMuscle: targetMuscle ?? this.targetMuscle,
      defaultSets: defaultSets ?? this.defaultSets,
      restSeconds: restSeconds ?? this.restSeconds,
      videoUrl: videoUrl ?? (updatedUrls.isNotEmpty ? updatedUrls.first : this.videoUrl),
      videoUrls: updatedUrls,
      sets: sets ?? this.sets,
    );
  }
}

/// A user-created custom workout routine / split template (e.g. "Chest & Triceps", "Heavy Leg Day")
class GymRoutine {
  final String id;
  final String userId;
  final String name;
  final String? description;
  final List<GymRoutineExercise> exercises;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const GymRoutine({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    required this.exercises,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      if (description != null) 'description': description,
      'exercises': exercises.map((e) => e.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  factory GymRoutine.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return GymRoutine(
      id: docId ?? map['id']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Custom Routine',
      description: map['description']?.toString(),
      exercises: (map['exercises'] as List<dynamic>?)
              ?.map((e) => GymRoutineExercise.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      createdAt: parseDate(map['createdAt']),
      updatedAt: map['updatedAt'] != null ? parseDate(map['updatedAt']) : null,
    );
  }

  GymRoutine copyWith({
    String? id,
    String? userId,
    String? name,
    String? description,
    List<GymRoutineExercise>? exercises,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GymRoutine(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      description: description ?? this.description,
      exercises: exercises ?? this.exercises,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
