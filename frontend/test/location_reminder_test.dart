import 'package:flutter_test/flutter_test.dart';
import 'package:remindbuddy/models/saved_place.dart';
import 'package:remindbuddy/models/calendar_reminder.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('SavedPlace Model Tests', () {
    test('SavedPlace.fromMap correctly parses place data with defaults', () {
      final map = {
        'name': 'My PG',
        'latitude': 12.9716,
        'longitude': 77.5946,
        'radiusMeters': 50.0,
        'iconName': 'home',
        'address': 'Koramangala 4th Block',
      };

      final place = SavedPlace.fromMap(map, 'pg_123');

      expect(place.id, 'pg_123');
      expect(place.name, 'My PG');
      expect(place.latitude, 12.9716);
      expect(place.longitude, 77.5946);
      expect(place.radiusMeters, 50.0);
      expect(place.iconName, 'home');
      expect(place.address, 'Koramangala 4th Block');
    });

    test('SavedPlace.toMap preserves fields accurately', () {
      const place = SavedPlace(
        name: 'Work Office',
        latitude: 12.9279,
        longitude: 77.6271,
        radiusMeters: 75.0,
        iconName: 'briefcase',
        address: 'HSR Layout',
      );

      final map = place.toMap();

      expect(map['name'], 'Work Office');
      expect(map['latitude'], 12.9279);
      expect(map['longitude'], 77.6271);
      expect(map['radiusMeters'], 75.0);
      expect(map['iconName'], 'briefcase');
      expect(map['address'], 'HSR Layout');
    });
  });

  group('CalendarReminder Location-Based Tests', () {
    test('CalendarReminder.fromMap parses location-based reminder correctly', () {
      final map = {
        'title': 'Pick up Amazon parcel from front desk',
        'description': 'Check package at PG veranda',
        'date': '2026-09-13',
        'time': '18:00',
        'status': 'pending',
        'isLocationBased': true,
        'locationName': 'My PG',
        'latitude': 12.9716,
        'longitude': 77.5946,
        'radiusMeters': 50.0,
        'triggerCondition': 'enter',
        'isLocationTriggered': false,
        'savedPlaceId': 'pg_123',
      };

      final reminder = CalendarReminder.fromMap(map, 'rem_456');

      expect(reminder.id, 'rem_456');
      expect(reminder.isLocationBased, isTrue);
      expect(reminder.locationName, 'My PG');
      expect(reminder.latitude, 12.9716);
      expect(reminder.longitude, 77.5946);
      expect(reminder.radiusMeters, 50.0);
      expect(reminder.triggerCondition, 'enter');
      expect(reminder.isLocationTriggered, isFalse);
      expect(reminder.savedPlaceId, 'pg_123');
    });

    test('CalendarReminder.toMap serializes location-based fields', () {
      final reminder = CalendarReminder(
        id: 'rem_789',
        title: 'Lock PG door and turn off geyser',
        description: 'Leaving PG morning routine',
        date: '2026-09-13',
        time: '09:00',
        isLocationBased: true,
        locationName: 'My PG',
        latitude: 12.9716,
        longitude: 77.5946,
        radiusMeters: 50.0,
        triggerCondition: 'exit',
        isLocationTriggered: false,
      );

      final map = reminder.toMap();

      expect(map['isLocationBased'], isTrue);
      expect(map['locationName'], 'My PG');
      expect(map['latitude'], 12.9716);
      expect(map['longitude'], 77.5946);
      expect(map['radiusMeters'], 50.0);
      expect(map['triggerCondition'], 'exit');
      expect(map['isLocationTriggered'], isFalse);
    });

    test('Geolocator geofence distance calculation detects within 50m radius', () {
      // PG coordinates
      const pgLat = 12.971600;
      const pgLng = 77.594600;

      // Position ~20 meters away (approx 0.00018 degrees latitude is ~20m)
      const nearLat = 12.971750;
      const nearLng = 77.594600;

      final distanceMeters = Geolocator.distanceBetween(pgLat, pgLng, nearLat, nearLng);

      expect(distanceMeters, lessThan(50.0));

      // Position 150 meters away
      const farLat = 12.973000;
      const farLng = 77.594600;

      final farDistanceMeters = Geolocator.distanceBetween(pgLat, pgLng, farLat, farLng);
      expect(farDistanceMeters, greaterThan(50.0));
    });
  });

  group('CalendarReminder Continuous Alarm Mode Tests', () {
    test('CalendarReminder.fromMap parses continuous alarm mode and custom audio correctly', () {
      final map = {
        'title': 'Wake up and take thyroid medicine',
        'description': 'Continuous morning alarm',
        'date': '2026-09-14',
        'time': '07:00',
        'status': 'pending',
        'isAlarmMode': true,
        'alarmSound': 'custom',
        'customAudioPath': '/storage/emulated/0/Music/morning_alarm.mp3',
        'customAudioName': 'morning_alarm.mp3',
      };

      final reminder = CalendarReminder.fromMap(map, 'alarm_101');

      expect(reminder.id, 'alarm_101');
      expect(reminder.isAlarmMode, isTrue);
      expect(reminder.alarmSound, 'custom');
      expect(reminder.customAudioPath, '/storage/emulated/0/Music/morning_alarm.mp3');
      expect(reminder.customAudioName, 'morning_alarm.mp3');
    });

    test('CalendarReminder.toMap serializes continuous alarm mode fields accurately', () {
      final reminder = CalendarReminder(
        id: 'alarm_102',
        title: 'Emergency Server Maintenance',
        description: 'Check high CPU usage',
        date: '2026-09-14',
        time: '02:00',
        isAlarmMode: true,
        alarmSound: 'alarm_siren',
      );

      final map = reminder.toMap();

      expect(map['isAlarmMode'], isTrue);
      expect(map['alarmSound'], 'alarm_siren');
      expect(map['customAudioPath'], isNull);
      expect(map['customAudioName'], isNull);
    });

    test('CalendarReminder defaults alarm mode to false and alarmSound to digital', () {
      final reminder = CalendarReminder(
        id: 'standard_103',
        title: 'Regular notification task',
        description: 'Standard description',
        date: '2026-09-14',
        time: '12:00',
      );

      expect(reminder.isAlarmMode, isFalse);
      expect(reminder.alarmSound, 'digital');
      expect(reminder.customAudioPath, isNull);
      expect(reminder.customAudioName, isNull);
    });

    test('CalendarReminder.copyWith allows toggling alarm mode and sound', () {
      final original = CalendarReminder(
        id: 'rem_104',
        title: 'Dentist appointment',
        description: 'Regular checkup',
        date: '2026-09-15',
        time: '15:30',
        isAlarmMode: false,
      );

      final updated = original.copyWith(
        isAlarmMode: true,
        alarmSound: 'alarm_chime',
      );

      expect(updated.id, 'rem_104');
      expect(updated.isAlarmMode, isTrue);
      expect(updated.alarmSound, 'alarm_chime');
    });
  });
}

