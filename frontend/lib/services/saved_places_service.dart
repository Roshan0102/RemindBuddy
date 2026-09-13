import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/saved_place.dart';

class SavedPlacesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? _placesRef() {
    final uid = _uid;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('saved_places');
  }

  Stream<List<SavedPlace>> getSavedPlacesStream() {
    final ref = _placesRef();
    if (ref == null) return const Stream.empty();

    return ref.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => SavedPlace.fromMap(doc.data(), doc.id)).toList();
    });
  }

  Future<String?> savePlace(SavedPlace place) async {
    final ref = _placesRef();
    if (ref == null) return null;

    if (place.id != null && place.id!.isNotEmpty) {
      await ref.doc(place.id).set(place.toMap(), SetOptions(merge: true));
      return place.id;
    } else {
      final doc = await ref.add(place.toMap());
      return doc.id;
    }
  }

  Future<void> deletePlace(String placeId) async {
    final ref = _placesRef();
    if (ref == null) return;
    await ref.doc(placeId).delete();
  }

  Future<Position?> getCurrentPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied.');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied.');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return null;
    }
  }

  static const List<Map<String, dynamic>> defaultPresets = [
    {
      'name': 'My PG',
      'icon': 'building',
      'radius': 50.0,
      'description': 'Hostel / PG residence',
    },
    {
      'name': 'Office',
      'icon': 'work',
      'radius': 100.0,
      'description': 'Workplace / Campus',
    },
    {
      'name': 'Home',
      'icon': 'home',
      'radius': 75.0,
      'description': 'Home residence',
    },
    {
      'name': 'Supermarket',
      'icon': 'cart',
      'radius': 75.0,
      'description': 'Grocery / Mall',
    },
    {
      'name': 'Gym',
      'icon': 'fitness',
      'radius': 50.0,
      'description': 'Workout center',
    },
  ];
}
