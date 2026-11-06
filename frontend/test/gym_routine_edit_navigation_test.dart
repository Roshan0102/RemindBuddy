import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/gym_routine.dart';
import 'package:remindbuddy/models/gym_workout.dart';
import 'package:remindbuddy/screens/gym_active_workout_screen.dart';

void main() {
  group('GymActiveWorkoutScreen Navigation & Previous Weight Tests', () {
    testWidgets('Tapping back with no changes pops immediately without showing save dialog', (tester) async {
      final routine = GymRoutine(
        id: 'r1',
        userId: 'u1',
        name: 'Leg Day',
        description: 'Squat focus',
        exercises: const [
          GymRoutineExercise(
            exerciseId: '0025',
            exerciseName: 'Barbell Squat',
            bodyPart: 'legs',
            sets: [
              GymWorkoutSet(setNumber: 1, weightKg: 100, reps: 5, isCompleted: false),
            ],
          ),
        ],
        createdAt: DateTime(2026, 1, 1),
      );

      bool popped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GymActiveWorkoutScreen(routine: routine),
                    ),
                  );
                  popped = true;
                },
                child: const Text('Open Routine'),
              ),
            ),
          ),
        ),
      );

      // Open screen
      await tester.tap(find.text('Open Routine'));
      await tester.pumpAndSettle();

      expect(find.text('Leg Day'), findsOneWidget);
      expect(find.text('Barbell Squat'), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Verify popped immediately with no dialog
      expect(find.text('Save Changes?'), findsNothing);
      expect(popped, isTrue);
    });

    testWidgets('Tapping back after making changes prompts Save Changes? dialog', (tester) async {
      final routine = GymRoutine(
        id: 'r1',
        userId: 'u1',
        name: 'Push Day',
        exercises: const [],
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GymActiveWorkoutScreen(routine: routine),
        ),
      );
      await tester.pumpAndSettle();

      // Edit title
      await tester.enterText(find.byType(TextField).first, 'Push Day - Hypertrophy');
      await tester.pumpAndSettle();

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Verify dialog appears
      expect(find.text('Save Changes?'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Save Changes')), findsOneWidget);
      expect(find.text('Keep Training'), findsNothing);
    });

    testWidgets('Editing set KG moves loaded baseline to PREVIOUS column', (tester) async {
      final routine = GymRoutine(
        id: 'r1',
        userId: 'u1',
        name: 'Bench Workout',
        exercises: const [
          GymRoutineExercise(
            exerciseId: '0025',
            exerciseName: 'Barbell Bench Press',
            bodyPart: 'chest',
            sets: [
              GymWorkoutSet(setNumber: 1, weightKg: 80, reps: 10, isCompleted: false),
            ],
          ),
        ],
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GymActiveWorkoutScreen(routine: routine),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial row shows '-' in PREVIOUS and 80 in KG
      expect(find.text('PREVIOUS'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
      expect(find.text('80.0'), findsOneWidget);

      // Edit weight to 85.0
      await tester.enterText(find.widgetWithText(TextFormField, '80.0'), '85');
      await tester.pumpAndSettle();

      // Verify PREVIOUS now shows 80 kg
      expect(find.text('80 kg'), findsOneWidget);
    });
  });
}
