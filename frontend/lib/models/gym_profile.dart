/// Gym preferences and settings per user
class GymProfile {
  final String userId;
  final String weightUnit; // 'kg' or 'lbs'
  final String activeSplit; // 'Push Pull Legs', 'Upper Lower', 'Full Body', 'Bro Split', 'Custom'
  final int weeklyGoalDays; // e.g. 3, 4, 5, 6
  final bool showAnimations; // whether to stream looping MP4s or show still images
  final int dailyBandwidthLimitMb; // safety guard cap

  const GymProfile({
    required this.userId,
    this.weightUnit = 'kg',
    this.activeSplit = 'Push Pull Legs',
    this.weeklyGoalDays = 4,
    this.showAnimations = true,
    this.dailyBandwidthLimitMb = 50,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'weightUnit': weightUnit,
      'activeSplit': activeSplit,
      'weeklyGoalDays': weeklyGoalDays,
      'showAnimations': showAnimations,
      'dailyBandwidthLimitMb': dailyBandwidthLimitMb,
    };
  }

  factory GymProfile.fromMap(Map<String, dynamic> map, {String? userId}) {
    return GymProfile(
      userId: userId ?? map['userId']?.toString() ?? '',
      weightUnit: map['weightUnit']?.toString() ?? 'kg',
      activeSplit: map['activeSplit']?.toString() ?? 'Push Pull Legs',
      weeklyGoalDays: (map['weeklyGoalDays'] as num?)?.toInt() ?? 4,
      showAnimations: map['showAnimations'] != false,
      dailyBandwidthLimitMb: (map['dailyBandwidthLimitMb'] as num?)?.toInt() ?? 50,
    );
  }

  GymProfile copyWith({
    String? userId,
    String? weightUnit,
    String? activeSplit,
    int? weeklyGoalDays,
    bool? showAnimations,
    int? dailyBandwidthLimitMb,
  }) {
    return GymProfile(
      userId: userId ?? this.userId,
      weightUnit: weightUnit ?? this.weightUnit,
      activeSplit: activeSplit ?? this.activeSplit,
      weeklyGoalDays: weeklyGoalDays ?? this.weeklyGoalDays,
      showAnimations: showAnimations ?? this.showAnimations,
      dailyBandwidthLimitMb: dailyBandwidthLimitMb ?? this.dailyBandwidthLimitMb,
    );
  }
}
