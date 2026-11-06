import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/gym_routine.dart';
import 'package:remindbuddy/models/gym_workout.dart';
import 'package:remindbuddy/services/gym_video_launcher.dart';

void main() {
  group('Gym Custom Routines & Video Links Tests', () {
    test('GymWorkoutExercise correctly serializes and deserializes custom videoUrl', () {
      const exercise = GymWorkoutExercise(
        exerciseId: '0025',
        exerciseName: 'Barbell Bench Press',
        bodyPart: 'chest',
        targetMuscle: 'pectorals',
        sets: [
          GymWorkoutSet(setNumber: 1, weightKg: 80, reps: 10, isCompleted: true),
        ],
        videoUrl: 'https://instagram.com/reel/abc123xyz',
      );

      final map = exercise.toMap();
      expect(map['videoUrl'], 'https://instagram.com/reel/abc123xyz');

      final revived = GymWorkoutExercise.fromMap(map);
      expect(revived.exerciseId, '0025');
      expect(revived.exerciseName, 'Barbell Bench Press');
      expect(revived.videoUrl, 'https://instagram.com/reel/abc123xyz');

      // Test copyWith
      final updated = revived.copyWith(videoUrl: 'https://youtu.be/testvideo');
      expect(updated.videoUrl, 'https://youtu.be/testvideo');
      expect(updated.exerciseName, 'Barbell Bench Press');
    });

    test('GymRoutine correctly saves and restores custom split exercises and metadata', () {
      final now = DateTime.now();
      final routine = GymRoutine(
        id: 'routine_123',
        userId: 'test_user_456',
        name: 'Chest & Triceps Blast',
        description: 'Heavy bench with incline finisher',
        exercises: const [
          GymRoutineExercise(
            exerciseId: '0025',
            exerciseName: 'Barbell Bench Press',
            bodyPart: 'chest',
            targetMuscle: 'pectorals',
            defaultSets: 4,
            restSeconds: 120,
            videoUrl: 'https://youtu.be/benchpress101',
          ),
          GymRoutineExercise(
            exerciseId: '0070',
            exerciseName: 'Cable Triceps Pushdown',
            bodyPart: 'arms',
            targetMuscle: 'triceps',
            defaultSets: 3,
            restSeconds: 60,
          ),
        ],
        createdAt: now,
      );

      final map = routine.toMap();
      expect(map['name'], 'Chest & Triceps Blast');
      expect(map['userId'], 'test_user_456');
      expect((map['exercises'] as List).length, 2);

      final revived = GymRoutine.fromMap(map, docId: 'routine_123');
      expect(revived.id, 'routine_123');
      expect(revived.userId, 'test_user_456');
      expect(revived.name, 'Chest & Triceps Blast');
      expect(revived.exercises.length, 2);
      expect(revived.exercises[0].exerciseId, '0025');
      expect(revived.exercises[0].videoUrl, 'https://youtu.be/benchpress101');
      expect(revived.exercises[0].defaultSets, 4);
      expect(revived.exercises[1].defaultSets, 3);
    });

    test('GymVideoLauncher sanitizes URLs and identifies platforms properly', () {
      // URL sanitization (auto prepends https:// if missing)
      expect(
        GymVideoLauncher.sanitizeUrl('instagram.com/reel/xyz123'),
        'https://instagram.com/reel/xyz123',
      );
      expect(
        GymVideoLauncher.sanitizeUrl('youtu.be/abcdef'),
        'https://youtu.be/abcdef',
      );
      expect(GymVideoLauncher.sanitizeUrl(null), isNull);
      expect(GymVideoLauncher.sanitizeUrl(''), isNull);

      // YouTube detection
      expect(GymVideoLauncher.isYouTube('https://www.youtube.com/watch?v=123'), isTrue);
      expect(GymVideoLauncher.isYouTube('https://youtu.be/123'), isTrue);
      expect(GymVideoLauncher.isYouTube('https://instagram.com/reel/123'), isFalse);

      // Instagram detection
      expect(GymVideoLauncher.isInstagram('https://www.instagram.com/reel/123'), isTrue);
      expect(GymVideoLauncher.isInstagram('https://instagram.com/p/123'), isTrue);
      expect(GymVideoLauncher.isInstagram('https://youtube.com/123'), isFalse);

      // Platform labels
      expect(
        GymVideoLauncher.getPlatformLabel('https://www.youtube.com/watch?v=123'),
        'Watch on YouTube',
      );
      expect(
        GymVideoLauncher.getPlatformLabel('https://instagram.com/reel/123'),
        'Watch on Instagram',
      );
      expect(
        GymVideoLauncher.getPlatformLabel('https://mysite.com/video.mp4'),
        'Watch Form Video',
      );
    });

    test('GymRoutineExercise preserves and deserializes custom sets with weights and reps', () {
      const exercise = GymRoutineExercise(
        exerciseId: '0025',
        exerciseName: 'Barbell Bench Press',
        bodyPart: 'chest',
        targetMuscle: 'pectorals',
        defaultSets: 3,
        videoUrl: 'https://youtu.be/bench123',
        sets: [
          GymWorkoutSet(setNumber: 1, weightKg: 70, reps: 10, isCompleted: true),
          GymWorkoutSet(setNumber: 2, weightKg: 80, reps: 8, isCompleted: true),
          GymWorkoutSet(setNumber: 3, weightKg: 90, reps: 5, isCompleted: false),
        ],
      );

      final map = exercise.toMap();
      expect(map['videoUrl'], 'https://youtu.be/bench123');
      expect((map['sets'] as List).length, 3);
      expect((map['sets'] as List)[1]['weightKg'], 80.0);
      expect((map['sets'] as List)[1]['reps'], 8);

      final restored = GymRoutineExercise.fromMap(map);
      expect(restored.exerciseName, 'Barbell Bench Press');
      expect(restored.videoUrl, 'https://youtu.be/bench123');
      expect(restored.sets, isNotNull);
      expect(restored.sets!.length, 3);
      expect(restored.sets![0].weightKg, 70.0);
      expect(restored.sets![1].weightKg, 80.0);
      expect(restored.sets![2].weightKg, 90.0);
      expect(restored.sets![0].isCompleted, isTrue);
      expect(restored.sets![2].isCompleted, isFalse);
    });

    test('GymWorkoutSet preserves previousWeightKg for progressive tracking', () {
      const set = GymWorkoutSet(
        setNumber: 1,
        weightKg: 85.0,
        reps: 8,
        previousWeightKg: 80.0,
        isCompleted: true,
      );

      final map = set.toMap();
      expect(map['weightKg'], 85.0);
      expect(map['previousWeightKg'], 80.0);

      final revived = GymWorkoutSet.fromMap(map);
      expect(revived.weightKg, 85.0);
      expect(revived.previousWeightKg, 80.0);
    });

    test('GymRoutineExercise supports multiple video URLs and preserves them', () {
      const exercise = GymRoutineExercise(
        exerciseId: '0025',
        exerciseName: 'Barbell Bench Press',
        bodyPart: 'chest',
        videoUrls: [
          'https://youtu.be/bench_form_101',
          'https://instagram.com/reel/incline_tips_456',
        ],
      );

      final map = exercise.toMap();
      expect((map['videoUrls'] as List).length, 2);
      expect(map['videoUrl'], 'https://youtu.be/bench_form_101');

      final revived = GymRoutineExercise.fromMap(map);
      expect(revived.videoUrls.length, 2);
      expect(revived.videoUrls[0], 'https://youtu.be/bench_form_101');
      expect(revived.videoUrls[1], 'https://instagram.com/reel/incline_tips_456');
      expect(revived.videoUrl, 'https://youtu.be/bench_form_101');
    });
  });
}
