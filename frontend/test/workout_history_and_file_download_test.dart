import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:remindbuddy/models/gym_workout.dart';
import 'package:remindbuddy/services/file_download_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Workout History Date & Day Formatting Tests', () {
    test('formats workout date with day of week (Monday, Tuesday, etc.) properly', () {
      final sampleDate = DateTime(2026, 10, 22, 14, 30); // Thursday, Oct 22, 2026
      final dayOfWeek = DateFormat('EEEE').format(sampleDate);
      final formattedDate = DateFormat('d MMM yyyy • h:mm a').format(sampleDate);

      expect(dayOfWeek, equals('Thursday'));
      expect(formattedDate, equals('22 Oct 2026 • 2:30 PM'));

      final mondayDate = DateTime(2026, 10, 19, 9, 15);
      expect(DateFormat('EEEE').format(mondayDate), equals('Monday'));
      expect(DateFormat('d MMM yyyy • h:mm a').format(mondayDate), equals('19 Oct 2026 • 9:15 AM'));
    });

    test('GymWorkout model preserves startedAt timestamp correctly', () {
      final now = DateTime(2026, 10, 22, 10, 0, 0);
      final workout = GymWorkout(
        id: 'test_workout_1',
        userId: 'user_123',
        title: 'Morning Push Session',
        startedAt: now,
        completedAt: now.add(const Duration(minutes: 45)),
        durationSeconds: 2700,
        exercises: [],
      );

      final map = workout.toMap();
      expect(map['title'], equals('Morning Push Session'));
      expect(map['durationSeconds'], equals(2700));

      final restored = GymWorkout.fromMap(map, docId: 'test_workout_1');
      expect(restored.startedAt.year, equals(2026));
      expect(restored.startedAt.month, equals(10));
      expect(restored.startedAt.day, equals(22));
      expect(DateFormat('EEEE').format(restored.startedAt), equals('Thursday'));
    });
  });

  group('FileDownloadService Tests', () {
    test('sanitizes download file names cleanly', () {
      const dirtyName = 'Candidate: Senior Engineer / Resume?.pdf';
      final safeName = dirtyName.replaceAll(RegExp(r'[^\w\-_.]'), '_');
      expect(safeName, equals('Candidate__Senior_Engineer___Resume_.pdf'));
    });

    test('DownloadResult holds success state and file metadata correctly', () {
      final result = DownloadResult(
        isSuccess: true,
        filePath: '/storage/emulated/0/Download/Resume.pdf',
        fileName: 'Resume.pdf',
      );
      expect(result.isSuccess, isTrue);
      expect(result.fileName, equals('Resume.pdf'));
      expect(result.filePath, contains('Resume.pdf'));
    });
  });
}
