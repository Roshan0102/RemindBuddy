import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gym_workout.dart';
import '../models/personal_record.dart';
import '../models/body_weight_entry.dart';
import '../models/gym_profile.dart';

/// Core Service managing Gym & Workout tracking, Firestore synchronization,
/// automated PR detection, and bandwidth safety guards.
class GymService {
  static final GymService _instance = GymService._internal();
  factory GymService() => _instance;
  GymService._internal();

  FirebaseFirestore? _firestoreInstance;
  FirebaseAuth? _authInstance;

  FirebaseFirestore? get _firestore {
    try {
      return _firestoreInstance ?? FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseAuth? get _auth {
    try {
      return _authInstance ?? FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  String? get currentUserId {
    try {
      return _auth?.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  // Firestore Subcollection References (strictly isolated under users/{uid})
  CollectionReference<Map<String, dynamic>>? get _workoutsRef {
    final uid = currentUserId;
    final fs = _firestore;
    if (uid == null || fs == null) return null;
    return fs.collection('users').doc(uid).collection('gym_workouts');
  }

  CollectionReference<Map<String, dynamic>>? get _prsRef {
    final uid = currentUserId;
    final fs = _firestore;
    if (uid == null || fs == null) return null;
    return fs.collection('users').doc(uid).collection('gym_prs');
  }

  CollectionReference<Map<String, dynamic>>? get _bodyweightRef {
    final uid = currentUserId;
    final fs = _firestore;
    if (uid == null || fs == null) return null;
    return fs.collection('users').doc(uid).collection('gym_bodyweight');
  }

  DocumentReference<Map<String, dynamic>>? get _profileRef {
    final uid = currentUserId;
    final fs = _firestore;
    if (uid == null || fs == null) return null;
    return fs.collection('users').doc(uid).collection('settings').doc('gym_profile');
  }

  // ==========================================
  // WORKOUT LOGGING & HISTORY
  // ==========================================

  /// Stream of all logged workouts for current user, ordered by startedAt descending
  Stream<List<GymWorkout>> getWorkoutsStream() {
    final ref = _workoutsRef;
    if (ref == null) return Stream.value([]);

    return ref.orderBy('startedAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return GymWorkout.fromMap(doc.data(), docId: doc.id);
      }).toList();
    });
  }

  /// Save or update a finished workout, automatically evaluating Personal Records (PRs)
  Future<String> saveWorkout(GymWorkout workout) async {
    final ref = _workoutsRef;
    final uid = currentUserId;
    if (ref == null || uid == null) {
      throw Exception('User must be logged in to save workout');
    }

    final docRef = workout.id.isNotEmpty ? ref.doc(workout.id) : ref.doc();
    final workoutData = workout.toMap();
    workoutData['id'] = docRef.id;
    workoutData['userId'] = uid;

    await docRef.set(workoutData, SetOptions(merge: true));

    // Automatically check and update Personal Records (PRs) for each exercise performed
    await _evaluateAndUpdatePRs(workout, docRef.id);

    return docRef.id;
  }

  /// Delete a workout session
  Future<void> deleteWorkout(String workoutId) async {
    final ref = _workoutsRef;
    if (ref == null) return;
    await ref.doc(workoutId).delete();
  }

  /// Automatically calculates and updates PRs if the user hit a heavier weight or 1RM
  Future<void> _evaluateAndUpdatePRs(GymWorkout workout, String workoutId) async {
    final prsCollection = _prsRef;
    if (prsCollection == null) return;

    for (final exercise in workout.exercises) {
      final bestWorkingSet = exercise.bestSet;
      if (bestWorkingSet == null || bestWorkingSet.weightKg <= 0) continue;

      final est1RM = PersonalRecord.calculate1RM(bestWorkingSet.weightKg, bestWorkingSet.reps);

      try {
        final prDoc = await prsCollection.doc(exercise.exerciseId).get();
        if (!prDoc.exists) {
          // First time logging this exercise -> instant PR
          final newPR = PersonalRecord(
            exerciseId: exercise.exerciseId,
            exerciseName: exercise.exerciseName,
            maxWeight: bestWorkingSet.weightKg,
            repsAtMaxWeight: bestWorkingSet.reps,
            estimated1RM: est1RM,
            achievedAt: workout.startedAt,
            workoutId: workoutId,
          );
          await prsCollection.doc(exercise.exerciseId).set(newPR.toMap());
        } else {
          final existingPR = PersonalRecord.fromMap(prDoc.data()!);
          // If current set is heavier or achieved higher 1RM
          if (bestWorkingSet.weightKg > existingPR.maxWeight || est1RM > existingPR.estimated1RM) {
            final updatedPR = PersonalRecord(
              exerciseId: exercise.exerciseId,
              exerciseName: exercise.exerciseName,
              maxWeight: bestWorkingSet.weightKg > existingPR.maxWeight
                  ? bestWorkingSet.weightKg
                  : existingPR.maxWeight,
              repsAtMaxWeight: bestWorkingSet.weightKg >= existingPR.maxWeight
                  ? bestWorkingSet.reps
                  : existingPR.repsAtMaxWeight,
              estimated1RM: est1RM > existingPR.estimated1RM ? est1RM : existingPR.estimated1RM,
              achievedAt: workout.startedAt,
              workoutId: workoutId,
            );
            await prsCollection.doc(exercise.exerciseId).set(updatedPR.toMap(), SetOptions(merge: true));
          }
        }
      } catch (e) {
        debugPrint('Error updating PR for ${exercise.exerciseName}: $e');
      }
    }
  }

  /// Returns the user's previous working sets for given exercise IDs (for Progressive Overload pre-fill)
  Future<Map<String, List<GymWorkoutSet>>> getLastSetsForExercises(List<String> exerciseIds) async {
    final ref = _workoutsRef;
    if (ref == null || exerciseIds.isEmpty) return {};

    final Map<String, List<GymWorkoutSet>> result = {};
    try {
      // Query the last 15 workouts
      final querySnapshot = await ref.orderBy('startedAt', descending: true).limit(15).get();

      for (final doc in querySnapshot.docs) {
        final workout = GymWorkout.fromMap(doc.data(), docId: doc.id);
        for (final exercise in workout.exercises) {
          if (exerciseIds.contains(exercise.exerciseId) && !result.containsKey(exercise.exerciseId)) {
            final completedSets = exercise.sets.where((s) => s.isCompleted).toList();
            if (completedSets.isNotEmpty) {
              result[exercise.exerciseId] = completedSets;
            }
          }
        }
        if (result.length == exerciseIds.length) break;
      }
    } catch (e) {
      debugPrint('Error fetching previous exercise sets: $e');
    }
    return result;
  }

  // ==========================================
  // PERSONAL RECORDS (PRs)
  // ==========================================

  /// Stream of all personal records achieved by user
  Stream<List<PersonalRecord>> getPersonalRecordsStream() {
    final ref = _prsRef;
    if (ref == null) return Stream.value([]);

    return ref.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => PersonalRecord.fromMap(doc.data())).toList();
    });
  }

  // ==========================================
  // BODY WEIGHT TRACKING
  // ==========================================

  /// Stream of body weight entries ordered by date descending
  Stream<List<BodyWeightEntry>> getBodyWeightStream() {
    final ref = _bodyweightRef;
    if (ref == null) return Stream.value([]);

    return ref.orderBy('date', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return BodyWeightEntry.fromMap(doc.data(), docId: doc.id);
      }).toList();
    });
  }

  /// Add a new body weight entry
  Future<void> addBodyWeight(double weightKg, {String? note, DateTime? date}) async {
    final ref = _bodyweightRef;
    final uid = currentUserId;
    if (ref == null || uid == null) return;

    final entryDate = date ?? DateTime.now();
    final entry = BodyWeightEntry(
      id: '',
      userId: uid,
      weightKg: weightKg,
      date: entryDate,
      note: note,
    );

    final docRef = ref.doc();
    final map = entry.toMap();
    map['id'] = docRef.id;
    await docRef.set(map);
  }

  /// Delete a body weight entry
  Future<void> deleteBodyWeight(String id) async {
    final ref = _bodyweightRef;
    if (ref == null) return;
    await ref.doc(id).delete();
  }

  // ==========================================
  // GYM PROFILE & BANDWIDTH SAFEGUARD
  // ==========================================

  /// Stream of user gym preferences
  Stream<GymProfile> getGymProfileStream() {
    final ref = _profileRef;
    final uid = currentUserId;
    if (ref == null || uid == null) {
      return Stream.value(const GymProfile(userId: ''));
    }

    return ref.snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return GymProfile(userId: uid);
      }
      return GymProfile.fromMap(doc.data()!, userId: uid);
    });
  }

  /// Update user gym profile settings
  Future<void> updateGymProfile(GymProfile profile) async {
    final ref = _profileRef;
    if (ref == null) return;
    await ref.set(profile.toMap(), SetOptions(merge: true));
  }

  /// Bandwidth Safety Guard: checks whether streaming looping MP4 is allowed today
  Future<bool> canStreamVideoAnimation({int dailyLimitMb = 50}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
      final storedDate = prefs.getString('gym_bandwidth_date') ?? '';

      if (storedDate != todayStr) {
        // Reset counter for the new day
        await prefs.setString('gym_bandwidth_date', todayStr);
        await prefs.setInt('gym_bandwidth_bytes_today', 0);
        return true;
      }

      final bytesToday = prefs.getInt('gym_bandwidth_bytes_today') ?? 0;
      final maxBytes = dailyLimitMb * 1024 * 1024;
      return bytesToday < maxBytes;
    } catch (_) {
      return true;
    }
  }

  /// Records video download bytes into today's local counter
  Future<void> recordAnimationBandwidth(int bytes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      final storedDate = prefs.getString('gym_bandwidth_date') ?? '';

      int currentBytes = 0;
      if (storedDate == todayStr) {
        currentBytes = prefs.getInt('gym_bandwidth_bytes_today') ?? 0;
      } else {
        await prefs.setString('gym_bandwidth_date', todayStr);
      }

      await prefs.setInt('gym_bandwidth_bytes_today', currentBytes + bytes);
    } catch (_) {
      // Ignore cache write errors
    }
  }
}
