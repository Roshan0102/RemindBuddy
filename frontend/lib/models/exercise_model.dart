/// Model representing an exercise in the Gym Catalogue.
/// Compatible with the MIT-licensed ExerciseDB dataset and openGym media CDN.
class ExerciseModel {
  final String id; // e.g. "0001", "0025"
  final String name; // e.g. "3/4 sit-up", "barbell bench press"
  final String bodyPart; // e.g. "chest", "back", "upper legs", "waist", "shoulders", "upper arms"
  final String equipment; // e.g. "barbell", "dumbbell", "cable", "body weight", "machine"
  final String target; // e.g. "pectorals", "abs", "lats", "biceps", "triceps", "quads"
  final List<String> secondaryMuscles;
  final String category; // e.g. "strength", "calisthenics", "cardio", "stretching"
  final String description;
  final List<String> instructions;

  const ExerciseModel({
    required this.id,
    required this.name,
    required this.bodyPart,
    required this.equipment,
    required this.target,
    this.secondaryMuscles = const [],
    this.category = 'strength',
    this.description = '',
    this.instructions = const [],
  });

  /// 4-digit formatted ID for CDN asset lookup (e.g. "1" -> "0001")
  String get formattedId => id.padLeft(4, '0');

  /// Global Edge CDN URL for the looping animation MP4 (20-40 KB)
  String get clipUrl =>
      'https://cdn.jsdelivr.net/gh/DuarteSantos8/openGym@main/catalogue/media/clip/$formattedId.mp4';

  /// Global Edge CDN URL for the thumbnail WebP image (~5 KB)
  String get stillUrl =>
      'https://cdn.jsdelivr.net/gh/DuarteSantos8/openGym@main/catalogue/media/still/$formattedId.webp';

  /// Human-friendly display title in Title Case
  String get displayName {
    if (name.isEmpty) return '';
    return name
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }

  /// Capitalized target muscle group
  String get displayTarget =>
      target.isNotEmpty ? '${target[0].toUpperCase()}${target.substring(1)}' : '';

  /// Capitalized equipment name
  String get displayEquipment =>
      equipment.isNotEmpty ? '${equipment[0].toUpperCase()}${equipment.substring(1)}' : '';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'bodyPart': bodyPart,
      'equipment': equipment,
      'target': target,
      'secondaryMuscles': secondaryMuscles,
      'category': category,
      'description': description,
      'instructions': instructions,
    };
  }

  factory ExerciseModel.fromMap(Map<String, dynamic> map) {
    return ExerciseModel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      bodyPart: map['bodyPart']?.toString() ?? '',
      equipment: map['equipment']?.toString() ?? '',
      target: map['target']?.toString() ?? '',
      secondaryMuscles: (map['secondaryMuscles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      category: map['category']?.toString() ?? 'strength',
      description: map['description']?.toString() ?? '',
      instructions: (map['instructions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}
