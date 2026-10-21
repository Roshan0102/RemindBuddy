import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/exercise_model.dart';
import 'package:remindbuddy/models/gym_workout.dart';
import 'package:remindbuddy/models/personal_record.dart';
import 'package:remindbuddy/models/body_weight_entry.dart';
import 'package:remindbuddy/models/gym_profile.dart';
import 'package:remindbuddy/services/gym_exercise_catalog.dart';

void main() {
  group('Phase 1 - Gym Models & Logic Tests', () {
    test('ExerciseModel formats IDs and generates correct Global Edge CDN URLs', () {
      const exercise = ExerciseModel(
        id: '25',
        name: 'barbell bench press',
        bodyPart: 'chest',
        equipment: 'barbell',
        target: 'pectorals',
      );

      expect(exercise.formattedId, '0025');
      expect(exercise.displayName, 'Barbell Bench Press');
      expect(
        exercise.clipUrl,
        'https://cdn.jsdelivr.net/gh/DuarteSantos8/openGym@main/catalogue/media/clip/0025.mp4',
      );
      expect(
        exercise.stillUrl,
        'https://cdn.jsdelivr.net/gh/DuarteSantos8/openGym@main/catalogue/media/still/0025.webp',
      );

      final map = exercise.toMap();
      final revived = ExerciseModel.fromMap(map);
      expect(revived.id, '25');
      expect(revived.name, 'barbell bench press');
      expect(revived.target, 'pectorals');
    });

    test('PersonalRecord calculates Estimated 1-Rep Max correctly via Epley formula', () {
      // 100 kg for 10 reps: 100 * (1 + 10/30) = 133.3 kg
      final est1RM = PersonalRecord.calculate1RM(100.0, 10);
      expect(est1RM, 133.3);

      // 60 kg for 1 rep: should equal 60.0 kg
      expect(PersonalRecord.calculate1RM(60.0, 1), 60.0);

      // 80 kg for 5 reps: 80 * (1 + 5/30) = 93.3 kg
      expect(PersonalRecord.calculate1RM(80.0, 5), 93.3);
    });

    test('GymWorkoutSet and GymWorkout calculate volumes and best set properly', () {
      const set1 = GymWorkoutSet(setNumber: 1, weightKg: 60, reps: 10, isWarmup: true);
      const set2 = GymWorkoutSet(setNumber: 2, weightKg: 80, reps: 8, isWarmup: false);
      const set3 = GymWorkoutSet(setNumber: 3, weightKg: 90, reps: 5, isWarmup: false);

      // Warmup set volume must be 0
      expect(set1.volume, 0.0);
      // Working sets volume: 80*8 = 640, 90*5 = 450
      expect(set2.volume, 640.0);
      expect(set3.volume, 450.0);

      const exercise = GymWorkoutExercise(
        exerciseId: '0025',
        exerciseName: 'Barbell Bench Press',
        bodyPart: 'chest',
        sets: [set1, set2, set3],
      );

      expect(exercise.totalVolume, 1090.0);
      expect(exercise.bestSet?.weightKg, 90.0);

      final workout = GymWorkout(
        id: 'test-w1',
        userId: 'user-123',
        title: 'Push Day',
        startedAt: DateTime.now(),
        exercises: [exercise],
      );

      expect(workout.totalVolumeKg, 1090.0);
      expect(workout.totalCompletedSets, 2);
    });

    test('BodyWeightEntry and GymProfile serialize and deserialize correctly', () {
      final now = DateTime.now();
      final bw = BodyWeightEntry(
        id: 'bw-1',
        userId: 'user-123',
        weightKg: 74.5,
        date: now,
        note: 'Morning weigh-in',
      );

      final bwMap = bw.toMap();
      expect(bwMap['weightKg'], 74.5);
      expect(bwMap['note'], 'Morning weigh-in');

      const profile = GymProfile(
        userId: 'user-123',
        weightUnit: 'kg',
        activeSplit: 'Push Pull Legs',
        showAnimations: true,
        dailyBandwidthLimitMb: 50,
      );

      final pMap = profile.toMap();
      final revivedProfile = GymProfile.fromMap(pMap, userId: 'user-123');
      expect(revivedProfile.activeSplit, 'Push Pull Legs');
      expect(revivedProfile.showAnimations, true);
    });

    test('GymExerciseCatalog provides rich curated exercises and filters correctly', () {
      expect(GymExerciseCatalog.exercises.length, greaterThanOrEqualTo(20));

      final benchPress = GymExerciseCatalog.findById('0025');
      expect(benchPress, isNotNull);
      expect(benchPress!.name, 'barbell bench press');

      final chestExercises = GymExerciseCatalog.filterByBodyPart('chest');
      expect(chestExercises.length, greaterThanOrEqualTo(5));
      for (final e in chestExercises) {
        expect(e.bodyPart.toLowerCase(), 'chest');
      }

      final barbellExercises = GymExerciseCatalog.filterByEquipment('barbell');
      expect(barbellExercises.length, greaterThanOrEqualTo(5));

      final searchResults = GymExerciseCatalog.search('squat');
      expect(searchResults.any((e) => e.name.contains('squat')), isTrue);
    });
  });
}
