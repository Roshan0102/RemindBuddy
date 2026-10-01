---
name: code-review-guardian
description: >-
  Use this skill whenever asked to review code, run a code review (/code-review), or audit changes before committing in RemindBuddy. Enforces universal generalization, version synchronization, Flutter memory leak detection, and security rules.
---

# Code Review Guardian for RemindBuddy

This skill executes a rigorous, multi-point code review on RemindBuddy pull requests or local changes before committing or deploying.

---

## 1. Project-Level Invariants (Strict Enforcement)

* **Universal Generalization Check**:
  * Verify that **NO user names** (e.g. "Roshan"), personal emails, fixed phone numbers, or hardcoded sample resumes exist in application logic.
  * All profile attributes, alert preferences, and configurations MUST be read dynamically from the authenticated user's Firestore document (`users/{uid}`) or configured through the Admin screen.
  * If test fixtures are required, verify they are in separate test files (`test/`) and clearly labeled as mock fixtures.
* **4-File Version Synchronization Check**:
  * Before any production deployment or PR merge, confirm the patch version is incremented and identical across all 4 files:
    1. [`frontend/pubspec.yaml`](file:///home/roshan-axcess/Documents/RemindBuddy/frontend/pubspec.yaml) (`version: x.y.z+build`)
    2. [`frontend/lib/screens/main_screen.dart`](file:///home/roshan-axcess/Documents/RemindBuddy/frontend/lib/screens/main_screen.dart) (UI version display)
    3. [`frontend/lib/screens/settings_screen.dart`](file:///home/roshan-axcess/Documents/RemindBuddy/frontend/lib/screens/settings_screen.dart) (About/Version section)
    4. [`functions/package.json`](file:///home/roshan-axcess/Documents/RemindBuddy/functions/package.json) (`"version": "x.y.z"`)

---

## 2. Flutter / Dart Code Audit

* **Resource Disposal & Memory Leaks**:
  * Check every `StatefulWidget` that instantiates:
    * `TextEditingController` -> MUST call `controller.dispose()` in `dispose()`.
    * `AnimationController` -> MUST call `controller.dispose()` in `dispose()`.
    * `ScrollController` -> MUST call `controller.dispose()` in `dispose()`.
    * `StreamSubscription` (e.g. Firestore listener) -> MUST call `subscription.cancel()` in `dispose()`.
    * `FocusNode` -> MUST call `focusNode.dispose()` in `dispose()`.
* **Asynchronous Safety (`mounted` check)**:
  * Whenever `BuildContext` is accessed after an `await` (e.g., `Navigator.of(context)`, `ScaffoldMessenger.of(context)`), verify that `if (!mounted) return;` precedes the call.
* **Const Correctness**:
  * Ensure immutable widgets are prefixed with `const` to avoid redundant rebuild passes.

---

## 3. Firebase Cloud Functions / TypeScript Audit

* **Authentication & Authorization**:
  * Callable functions (`onCall`) MUST verify `if (!request.auth) throw new HttpsError('unauthenticated', ...);`.
  * Verify that a user cannot query or modify documents belonging to another user (`request.auth.uid === targetUid`).
* **Error Handling & Logging**:
  * All async operations in Cloud Functions MUST use `try/catch` and log structured error details using [`functions/src/utils/logger.ts`](file:///home/roshan-axcess/Documents/RemindBuddy/functions/src/utils/logger.ts).
* **Cost & Quota Safety**:
  * Schedulers and listeners must never trigger unbounded recursive Firestore writes or external API scraping loops.
  * Verify batch operations respect Firestore's 500-write limit per `batch.commit()`.

---

## 4. How to Execute a Review

1. Run `git diff HEAD` to capture all unstaged and staged modifications.
2. Check changes against the 3 sections above.
3. Output the review report structured into:
   * 🚨 **Blockers**: Violations of `AGENTS.md` (hardcoded names, missing version bump), critical memory leaks, unauthenticated Cloud Functions.
   * ⚠️ **Warnings**: Missing `const`, potential keyboard overflows, unhandled async exceptions.
   * ✅ **Approved Highlights**: Good abstractions, clean typing, proper error boundaries.
