# RemindBuddy Firebase Migration Plan

## Phase 1: Foundation & Authentication (Zero App Breakage)
**Goal:** Setup Firebase in the background alongside PocketBase, migrating user login.

1. Create a Firebase Project and configure it for Android/iOS.
2. Add `firebase_core` and `firebase_auth` to `pubspec.yaml`.
3. Create a wrapper `FirebaseAuthService` that sits next to the PocketBase `AuthService`.
4. Update `AuthScreen`: When a user logs in, they log in to **both** PocketBase AND Firebase. If they sign up, they sign up on both.
5. **Outcome:** Your app still functions exactly the same, but new auth state is duplicated perfectly.

## Phase 2: Dual-Writing Simple Collections
**Goal:** Pick a simple feature (e.g., Notes or Checklists) and migrate its storage to Firestore, while temporarily keeping PocketBase as a fallback.

1. Add `cloud_firestore` to `pubspec.yaml`.
2. Configure a new `FirebaseSyncService` (or similar interface) specifically for Notes.
3. Modify `NotesScreen`: 
   * Reads from Firestore first.
   * On save/edit, write to Firestore natively.
4. **Outcome:** The Notes feature now uses Firebase exclusively, but everything else (Tasks, Shifts, Daily Reminders) still runs on PocketBase. 

## Phase 3: Complex Collections (Tasks & Reminders with Alarms)
**Goal:** Migrate data reliant on tight Android Notifications.

1. Migrate Tasks to Firestore.
2. Migrate Daily Reminders to Firestore.
3. Update `AppInitService` and native alarms to trigger off Firestore listener updates instead of `SQLite` diff loops.
4. **Outcome:** Time-sensitive alerts now run completely off Google's infrastructure.

## Phase 4: Shift Roster & Firebase Cloud Messaging (FCM)
**Goal:** Eliminate battery-constrained Android Alarm Manager limitations.

1. Migrate the Shift JSON metadata and schedules to Firestore.
2. Install `firebase_messaging`.
3. Implement FCM push notifications (which are free and wake the phone perfectly, bypassing all standard Android battery limitations natively!).  
4. **Outcome:** Complete notification robustness.

## Phase 5: The Cleanup (Sunsetting PocketBase)
**Goal:** Delete the old code and shut down the Linux server!

1. Strip out `pb_migration_service.dart`, `pb_debug_logger.dart`, and `sync_service.dart`.
2. Detach the PocketBase SDK.
3. Perform a final test of Auth, Tasks, Gold Scheduler, and Shifts.
4. Shut down the IP `35.237.49.45` server to stop paying the cloud bill.
