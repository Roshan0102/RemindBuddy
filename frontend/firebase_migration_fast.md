# RemindBuddy Firebase Migration Plan (Fast Track)

## Phase 1: Firebase Project Discovery & Registration
1. Access Firebase Console and create a new project called `RemindBuddy`.
2. Register the Android App: provide the Application ID (e.g., `com.axcess.remindbuddy`).
3. Download `google-services.json` and place it in `android/app/`.
4. Configure `build.gradle` (project-level) to include the Google Services classpath.
5. Configure `build.gradle` (app-level) to apply the Google Services plugin.

## Phase 2: Dependency & Service Swaps
1. Add essential Firebase packages to `pubspec.yaml`:
   ```yaml
   firebase_core: ^2.24.2
   firebase_auth: ^4.15.3
   cloud_firestore: ^4.13.6
   ```
2. Remove `pocketbase: ^0.18.0` from `pubspec.yaml`.
3. Update `main.dart` to strictly initialize Firebase natively: `await Firebase.initializeApp();`
4. Delete `pb_migration_service.dart`, `pb_debug_logger.dart`, and your `SyncService` completely (Firebase handles offline caching automatically, eliminating complex SQFlite diffing modules).

## Phase 3: Authentication Overhaul
1. Enable **Email/Password Authentication** in Firebase Console -> Build -> Authentication.
2. Refactor `AuthService`: 
   * Convert PocketBase `authWithPassword` to `FirebaseAuth.instance.signInWithEmailAndPassword`.
   * Switch the token getter to pull `currentUser?.uid`.
3. Update `LoginScreen` and `SignupScreen` logic bindings.

## Phase 4: Data Models & Firestore Migration
1. Enable **Cloud Firestore** in the Firebase Console (in Test Mode to start).
2. Modify Dart Models (`Task`, `Note`, `DailyReminder`, `Shift`):
   * Add a `fromFirestore(DocumentSnapshot doc)` factory.
   * Add a `toFirestore()` converter mapping.
3. Overhaul `StorageService`:
   * Point all read/write paths (`getTasks`, `insertNote`, `saveShiftsData`) directly to Firestore pathing (`FirebaseFirestore.instance.collection('tasks').doc().set()`).
   * Retire the SQFlite instance bindings immediately.

## Phase 5: Notification Triggers (The Edge Case)
1. Re-validate `AppInitService` and `AndroidAlarmManager` with Firebase snapshots. Your offline SQFlite queries will be replaced with Firebase query loops for scheduling.
2. Final QA: Boot the app, authenticate natively via Google, and inject dummy shift data. 
