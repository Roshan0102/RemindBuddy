import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/exercise_model.dart';
import 'package:remindbuddy/widgets/gym/gym_rest_timer_widget.dart';
import 'package:remindbuddy/widgets/gym/exercise_demo_modal.dart';
import 'package:remindbuddy/widgets/gym/exercise_picker_dialog.dart';

void main() {
  group('Phase 2 - Gym Widgets & Active Workout UI Tests', () {
    testWidgets('GymRestTimerWidget displays countdown and adjusts time', (tester) async {
      bool dismissed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GymRestTimerWidget(
              initialSeconds: 90,
              onDismiss: () {
                dismissed = true;
              },
            ),
          ),
        ),
      );

      // Verify timer title and formatted time
      expect(find.text('REST TIMER'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);

      // Tap +30s button
      await tester.tap(find.text('+30s'));
      await tester.pump();
      expect(find.text('02:00'), findsOneWidget);

      // Tap -15s button
      await tester.tap(find.text('-15s'));
      await tester.pump();
      expect(find.text('01:45'), findsOneWidget);

      // Tap close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(dismissed, isTrue);
    });

    testWidgets('ExerciseDemoModal displays exercise info and instructions', (tester) async {
      const exercise = ExerciseModel(
        id: '0025',
        name: 'barbell bench press',
        bodyPart: 'chest',
        equipment: 'barbell',
        target: 'pectorals',
        description: 'Prime compound pressing movement for chest strength.',
        instructions: [
          'Lie flat on the bench.',
          'Grip the bar slightly wider than shoulders.',
          'Lower bar to mid-chest, then press back up.',
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExerciseDemoModal(exercise: exercise),
          ),
        ),
      );

      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.textContaining('Pectorals'), findsWidgets);
      expect(find.text('Prime compound pressing movement for chest strength.'), findsOneWidget);
      expect(find.text('Lie flat on the bench.'), findsOneWidget);
      expect(find.text('Lower bar to mid-chest, then press back up.'), findsOneWidget);
    });

    testWidgets('ExercisePickerDialog displays search bar, filter chips, and exercises', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExercisePickerDialog(),
          ),
        ),
      );

      expect(find.text('Select Exercise'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Verify filter chips exist
      expect(find.text('All'), findsWidgets);
      expect(find.text('Chest'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Barbell'), findsOneWidget);
      expect(find.text('Dumbbell'), findsOneWidget);

      // Verify at least one exercise is in the list
      expect(find.text('Barbell Bench Press'), findsOneWidget);
    });
  });
}
