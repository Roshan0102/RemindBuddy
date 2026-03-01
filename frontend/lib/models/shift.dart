class Shift {
  final String date;
  final String shiftType; // 'morning', 'afternoon', 'night', 'week_off'
  final String? startTime;
  final String? endTime;
  final bool isWeekOff;

  Shift({
    required this.date,
    required this.shiftType,
    this.startTime,
    this.endTime,
    required this.isWeekOff,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      date: json['date'] as String,
      shiftType: json['shift_type'] as String,
      startTime: json['start_time'] as String?,
      endTime: json['end_time'] as String?,
      isWeekOff: json['is_week_off'] == true || json['is_week_off'] == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'shift_type': shiftType,
      'start_time': startTime,
      'end_time': endTime,
      'is_week_off': isWeekOff ? 1 : 0,
    };
  }

  factory Shift.fromMap(Map<String, dynamic> map) {
    return Shift(
      date: map['date'] as String,
      shiftType: map['shift_type'] as String,
      startTime: map['start_time'] as String?,
      endTime: map['end_time'] as String?,
      isWeekOff: map['is_week_off'] == 1,
    );
  }

  String getDisplayName() {
    switch (shiftType) {
      case 'morning':
        return 'Morning Shift';
      case 'afternoon':
        return 'Afternoon Shift';
      case 'night':
        return 'Night Shift';
      case 'week_off':
        return 'Week Off';
      default:
        return shiftType;
    }
  }

  String getTimeRange() {
    if (isWeekOff || startTime == null || endTime == null) {
      return '';
    }
    return '$startTime - $endTime';
  }
}

class ShiftRoster {
  final String employeeName;
  final String month;
  final List<Shift> shifts;

  ShiftRoster({
    required this.employeeName,
    required this.month,
    required this.shifts,
  });

  factory ShiftRoster.fromJson(Map<String, dynamic> json) {
    return ShiftRoster(
      employeeName: json['employee_name'] as String,
      month: json['month'] as String,
      shifts: (json['shifts'] as List)
          .map((shift) => Shift.fromJson(shift as Map<String, dynamic>))
          .toList(),
    );
  }
}
