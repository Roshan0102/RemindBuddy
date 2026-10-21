import 'package:cloud_firestore/cloud_firestore.dart';

/// Tracks Personal Records (PRs) per exercise with Estimated 1-Rep Max (1RM)
class PersonalRecord {
  final String exerciseId;
  final String exerciseName;
  final double maxWeight; // in kg
  final int repsAtMaxWeight;
  final double estimated1RM; // in kg (via Epley formula)
  final DateTime achievedAt;
  final String? workoutId;

  const PersonalRecord({
    required this.exerciseId,
    required this.exerciseName,
    required this.maxWeight,
    required this.repsAtMaxWeight,
    required this.estimated1RM,
    required this.achievedAt,
    this.workoutId,
  });

  /// Epley formula for estimated 1-Rep Max: weight * (1 + reps / 30)
  static double calculate1RM(double weight, int reps) {
    if (reps <= 1) return weight;
    return double.parse((weight * (1 + reps / 30.0)).toStringAsFixed(1));
  }

  Map<String, dynamic> toMap() {
    return {
      'exerciseId': exerciseId,
      'exerciseName': exerciseName,
      'maxWeight': maxWeight,
      'repsAtMaxWeight': repsAtMaxWeight,
      'estimated1RM': estimated1RM,
      'achievedAt': Timestamp.fromDate(achievedAt),
      if (workoutId != null) 'workoutId': workoutId,
    };
  }

  factory PersonalRecord.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return PersonalRecord(
      exerciseId: map['exerciseId']?.toString() ?? '',
      exerciseName: map['exerciseName']?.toString() ?? '',
      maxWeight: (map['maxWeight'] as num?)?.toDouble() ?? 0.0,
      repsAtMaxWeight: (map['repsAtMaxWeight'] as num?)?.toInt() ?? 1,
      estimated1RM: (map['estimated1RM'] as num?)?.toDouble() ?? 0.0,
      achievedAt: parseDate(map['achievedAt']),
      workoutId: map['workoutId']?.toString(),
    );
  }
}
