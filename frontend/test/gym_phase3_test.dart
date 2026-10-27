import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/gym_workout.dart';
import 'package:remindbuddy/widgets/gym/gym_workout_detail_modal.dart';
import 'package:remindbuddy/screens/gym_dashboard_screen.dart';

void main() {
  group('Phase 3 & 4 - Gym Dashboard & Workout Details UI Tests', () {
    testWidgets('GymWorkoutDetailModal renders complete session breakdown', (tester) async {
      final workout = GymWorkout(
        id: 'test-workout-1',
        userId: 'user-test',
        title: 'Push Hypertrophy',
        startedAt: DateTime(2026, 10, 20, 10, 30),
        durationSeconds: 3600,
        notes: 'Felt strong on bench press today.',
        exercises: const [
          GymWorkoutExercise(
            exerciseId: '0025',
            exerciseName: 'Barbell Bench Press',
            bodyPart: 'chest',
            sets: [
              GymWorkoutSet(setNumber: 1, weightKg: 60, reps: 12, isCompleted: true, isWarmup: true),
              GymWorkoutSet(setNumber: 2, weightKg: 90, reps: 8, isCompleted: true),
              GymWorkoutSet(setNumber: 3, weightKg: 100, reps: 5, isCompleted: true),
            ],
          ),
          GymWorkoutExercise(
            exerciseId: '0070',
            exerciseName: 'Dumbbell Shoulder Press',
            bodyPart: 'shoulders',
            sets: [
              GymWorkoutSet(setNumber: 1, weightKg: 24, reps: 10, isCompleted: true),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GymWorkoutDetailModal(workout: workout),
          ),
        ),
      );

      // Verify title & notes
      expect(find.text('Push Hypertrophy'), findsOneWidget);
      expect(find.text('Felt strong on bench press today.'), findsOneWidget);

      // Verify metrics
      expect(find.text('DURATION'), findsOneWidget);
      expect(find.text('1h 0m'), findsOneWidget);
      expect(find.text('VOLUME'), findsOneWidget);
      expect(find.text('SETS'), findsOneWidget);

      // Verify exercise names and sets
      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.text('Dumbbell Shoulder Press'), findsOneWidget);
      expect(find.text('WARMUP'), findsOneWidget);
      expect(find.textContaining('100.0 kg × 5 reps'), findsOneWidget);
    });

    testWidgets('GymDashboardScreen renders hero card, split presets, PR showcase, and history feed', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GymDashboardScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header & Hero Card
      expect(find.text('Gym & Workouts'), findsOneWidget);
      expect(find.text('READY TO TRAIN?'), findsOneWidget);
      expect(find.text('Start Empty Workout'), findsOneWidget);

      // Verify Quick Split Presets
      expect(find.text('Quick Splits & Routines'), findsOneWidget);
      expect(find.text('Build Your Custom Routine'), findsOneWidget);

      // Verify PR Showcase & Body Weight Tracker
      expect(find.text('Personal Records (PRs)'), findsOneWidget);
      expect(find.text('Body Weight Tracking'), findsOneWidget);
      expect(find.text('Log Weight'), findsOneWidget);

      // Verify Workout History Feed
      expect(find.text('Workout History'), findsOneWidget);
    });
  });
}
