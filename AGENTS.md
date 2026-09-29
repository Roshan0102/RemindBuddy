# Project Guidelines & Agent Instructions for RemindBuddy

## 1. Absolute Rule: Universal Generalization for All Users
- **Never Build for a Single User**: Any user name (e.g. "Roshan"), profile data, or resume example provided by the user is **strictly a test reproduction case**.
- **Completely Generic Implementations**: All Cloud Functions, AI prompts, PDF templates, ATS parsers, scrapers, and Flutter screens must work identically and seamlessly for ANY user, ANY profession (Engineering, Design, Marketing, QA, Management, etc.), and ANY experience tier.
- **Dynamic Configuration**: User variations must always be read dynamically from the user's Firestore document (`users/{uid}`) or configured through the Admin screen. Never hardcode user names, emails, or single-user overrides.

## 2. Versioning & Deployments
- Before pushing to GitHub, bump the patch version across `pubspec.yaml`, `main_screen.dart`, `settings_screen.dart`, and `functions/package.json`.
