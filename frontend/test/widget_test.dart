import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/shift.dart';

void main() {
  group('Shift Model Tests', () {
    test('Shift.fromJson correctly parses morning shift', () {
      final json = {
        'date': '2026-08-29',
        'shift_type': 'morning',
        'start_time': '06:00',
        'end_time': '14:00',
        'is_week_off': false,
      };

      final shift = Shift.fromJson(json);

      expect(shift.date, '2026-08-29');
      expect(shift.shiftType, 'morning');
      expect(shift.startTime, '06:00');
      expect(shift.endTime, '14:00');
      expect(shift.isWeekOff, isFalse);
      expect(shift.getDisplayName(), 'Morning Shift');
      expect(shift.getTimeRange(), '06:00 - 14:00');
    });

    test('Shift.fromJson correctly parses week off', () {
      final json = {
        'date': '2026-08-30',
        'shift_type': 'week_off',
        'is_week_off': true,
      };

      final shift = Shift.fromJson(json);

      expect(shift.date, '2026-08-30');
      expect(shift.shiftType, 'week_off');
      expect(shift.isWeekOff, isTrue);
      expect(shift.getDisplayName(), 'Week Off');
      expect(shift.getTimeRange(), '');
    });

    test('ShiftRoster.fromJson parses complete roster', () {
      final json = {
        'employee_name': 'Roshan J',
        'month': 'August 2026',
        'shifts': [
          {
            'date': '2026-08-29',
            'shift_type': 'morning',
            'start_time': '06:00',
            'end_time': '14:00',
            'is_week_off': false,
          },
          {
            'date': '2026-08-30',
            'shift_type': 'week_off',
            'is_week_off': true,
          }
        ],
      };

      final roster = ShiftRoster.fromJson(json);

      expect(roster.employeeName, 'Roshan J');
      expect(roster.month, 'August 2026');
      expect(roster.shifts.length, 2);
    });
  });
}
