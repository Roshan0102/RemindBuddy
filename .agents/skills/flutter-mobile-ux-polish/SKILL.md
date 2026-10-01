---
name: flutter-mobile-ux-polish
description: >-
  Use this skill whenever designing, modifying, or reviewing Flutter UI components, screens, or themes in RemindBuddy to ensure world-class, premium mobile UX, Material 3 compliance, smooth animations, safe-area ergonomics, and haptic feedback.
---

# Flutter Mobile UX Polish & Design System for RemindBuddy

This skill guides the design, implementation, and audit of Flutter UI components in RemindBuddy to guarantee a responsive, fluid, and visually stunning mobile experience.

---

## 1. Material 3 & Modern Visual Polish

* **Surfaces & Cards**:
  * Use `Card`, `Container`, or `Material` with `surfaceContainerLowest`, `surfaceContainer`, or `surfaceContainerHigh` tints rather than flat solid backgrounds.
  * Use consistent border radii across the app (`BorderRadius.circular(16)` or `24` for cards and dialogs; `12` for chips and text inputs).
  * Use subtle borders (`theme.colorScheme.outlineVariant.withValues(alpha: 0.3)`) to separate surfaces without heavy shadows.
* **Typography Hierarchy**:
  * Headlines: `titleLarge` / `titleMedium` with `FontWeight.w600` or `w700`.
  * Supporting details: `bodyMedium` or `bodySmall` with `colorScheme.onSurfaceVariant`.
  * Number displays (finance balances, gold prices): Tabular figures (`FontFeature.tabularFigures()`) or semi-bold weights for scannability.
* **Dark / Light Theme Parity**:
  * Always use `Theme.of(context).colorScheme` tokens. Never hardcode colors like `Colors.black`, `Colors.white`, or arbitrary hex codes unless specifically required for branding.

---

## 2. Micro-Interactions & Haptic Feedback

* **Touch Feedback**:
  * Integrate subtle haptic feedback for user actions:
    ```dart
    import 'package:flutter/services.dart';

    // On primary button tap, tab change, or switch toggle:
    HapticFeedback.lightImpact();

    // On destructive actions or alarms:
    HapticFeedback.mediumImpact();

    // On completing a task, checkmark, or successful save:
    HapticFeedback.selectionClick();
    ```
* **Interactive States**:
  * Wrap custom touchable containers in `InkWell` with a bounded `borderRadius` so the Material splash respects the rounded corners.

---

## 3. Ergonomics & Layout Robustness

* **Safe Area & Virtual Keyboards**:
  * Always account for system navigation bars and camera notches using `SafeArea`.
  * For screens with text fields or forms, set `resizeToAvoidBottomInset: true` on `Scaffold` and wrap content in `SingleChildScrollView(physics: const BouncingScrollPhysics())`.
  * When using floating bottom action bars or custom sheets, add `MediaQuery.viewInsetsOf(context).bottom` to prevent the keyboard from covering inputs.
* **Bottom Sheets & Modals**:
  * Use `showModalBottomSheet` with `isScrollControlled: true` and `useSafeArea: true`.
  * Always include a standard top drag handle:
    ```dart
    Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    )
    ```

---

## 4. Loading, Empty, and Error States

* **Never Show Blank Screens**:
  * For asynchronous data from Firestore (tasks, transactions, shifts):
    * **Loading**: Use sleek shimmer/skeleton loaders (`Skeletonizer` or shimmer placeholders matching the shape of target cards) instead of a lone centered spinner.
    * **Empty**: Display a themed vector icon, a friendly headline (e.g., "No tasks for today"), and an immediate action button (e.g., "Add Task").
    * **Error**: Show an inline warning with a "Retry" button.

---

## 5. Verification Checklist

Before finalizing any UI screen in RemindBuddy:
1. Verify both Dark and Light themes render cleanly with readable contrast.
2. Verify virtual keyboard appearance does not cause yellow/black overflow bars (`RenderFlex overflowed`).
3. Verify tap targets are at least 48x48 logical pixels.
4. Verify animations use `Curves.easeOutCubic` or `Curves.fastOutSlowIn` with durations between 200ms–350ms.
