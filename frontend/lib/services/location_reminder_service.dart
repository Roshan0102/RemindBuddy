import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/calendar_reminder.dart';
import 'notification_service.dart';

class LocationReminderService {
  static final LocationReminderService _instance = LocationReminderService._internal();
  factory LocationReminderService() => _instance;
  LocationReminderService._internal();

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<CalendarReminder>>? _remindersSubscription;

  List<CalendarReminder> _activeLocationReminders = [];
  final Set<String> _insideGeofenceReminderIds = {};
  Position? _lastKnownPosition;

  Position? get lastKnownPosition => _lastKnownPosition;
  bool get isMonitoring => _positionSubscription != null;

  void init() {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _startListeningToReminders(user.uid);
      } else {
        stopMonitoring();
        _activeLocationReminders.clear();
        _insideGeofenceReminderIds.clear();
      }
    });
  }

  void _startListeningToReminders(String uid) {
    _remindersSubscription?.cancel();
    _remindersSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('calendar_reminders')
        .where('isLocationBased', isEqualTo: true)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs.map((d) => CalendarReminder.fromMap(d.data(), d.id)).toList())
        .listen((reminders) {
      _activeLocationReminders = reminders;
      if (reminders.isNotEmpty) {
        startMonitoring();
        checkCurrentLocationNow();
      } else {
        stopMonitoring();
      }
    });
  }

  Future<void> startMonitoring() async {
    if (_positionSubscription != null) return;

    try {
      final hasPermission = await _checkAndRequestPermission();
      if (!hasPermission) {
        debugPrint('[LocationReminderService] Location permission not granted');
        return;
      }

      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15, // trigger update when moved ~15m
      );

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (position) {
          _lastKnownPosition = position;
          _evaluateProximity(position);
        },
        onError: (err) {
          debugPrint('[LocationReminderService] Position stream error: $err');
        },
      );
      debugPrint('[LocationReminderService] Location monitoring started');
    } catch (e) {
      debugPrint('[LocationReminderService] Could not start monitoring: $e');
    }
  }

  void stopMonitoring() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    debugPrint('[LocationReminderService] Location monitoring stopped');
  }

  Future<bool> _checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  Future<void> checkCurrentLocationNow() async {
    try {
      final hasPermission = await _checkAndRequestPermission();
      if (!hasPermission) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _lastKnownPosition = position;
      await _evaluateProximity(position);
    } catch (e) {
      debugPrint('[LocationReminderService] checkCurrentLocationNow error: $e');
    }
  }

  Future<void> _evaluateProximity(Position position) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _activeLocationReminders.isEmpty) return;

    for (final reminder in _activeLocationReminders) {
      if (reminder.latitude == null || reminder.longitude == null || reminder.id == null) {
        continue;
      }

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        reminder.latitude!,
        reminder.longitude!,
      );

      final radius = reminder.radiusMeters;
      final reminderId = reminder.id!;
      final isInside = distance <= radius;
      final wasInside = _insideGeofenceReminderIds.contains(reminderId);

      if (reminder.triggerCondition == 'enter') {
        if (isInside && !wasInside) {
          _insideGeofenceReminderIds.add(reminderId);
          await _triggerReminderAlert(reminder, user.uid, 'arrived');
        } else if (!isInside && distance > (radius + 25)) {
          // Exited geofence buffer zone
          _insideGeofenceReminderIds.remove(reminderId);
        }
      } else if (reminder.triggerCondition == 'exit') {
        if (!isInside && wasInside) {
          _insideGeofenceReminderIds.remove(reminderId);
          await _triggerReminderAlert(reminder, user.uid, 'left');
        } else if (isInside) {
          _insideGeofenceReminderIds.add(reminderId);
        }
      }
    }
  }

  Future<void> _triggerReminderAlert(CalendarReminder reminder, String uid, String action) async {
    final locationName = reminder.locationName?.isNotEmpty == true ? reminder.locationName! : 'target location';
    final actionText = action == 'arrived' ? 'Arrived at' : 'Left';
    final title = '📍 $actionText $locationName!';
    final body = reminder.title.isNotEmpty ? reminder.title : reminder.description;

    debugPrint('[LocationReminderService] TRIGGERING ALERT: $title - $body');

    try {
      await NotificationService().showNotification(
        id: reminder.id.hashCode,
        title: title,
        body: body,
        payload: 'LOCATION_REMINDER|${reminder.id}|$uid',
      );
    } catch (e) {
      debugPrint('[LocationReminderService] Notification error: $e');
    }

    try {
      // Mark reminder as triggered and completed in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('calendar_reminders')
          .doc(reminder.id)
          .update({
        'isLocationTriggered': true,
        'status': 'completed',
        'notifiedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[LocationReminderService] Error updating reminder triggered status: $e');
    }
  }

  double? getDistanceTo(double targetLat, double targetLng) {
    final pos = _lastKnownPosition;
    if (pos == null) return null;
    return Geolocator.distanceBetween(pos.latitude, pos.longitude, targetLat, targetLng);
  }

  String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()}m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
  }

  void dispose() {
    _positionSubscription?.cancel();
    _remindersSubscription?.cancel();
  }
}
