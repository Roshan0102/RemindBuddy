# RemindBuddy 🔔

RemindBuddy is a premium, feature-rich productivity companion built with **Flutter** and **Firebase**. It provides a seamless experience for managing tasks, notes, shifts, and tracking gold prices with real-time synchronization across devices.

## Hub of Features ✨

### 📅 Smart Task Management
- **Firebase Sync**: All tasks are stored in Firestore and synced instantly across your devices.
- **Calendar Integration**: View and manage tasks via an intuitive calendar interface.
- **Recurring Reminders**: Set one-time or repeating tasks (daily, weekly, monthly).
- **Annoying Mode**: Optional persistent alarms that ensure you never miss critical tasks.

### ⏰ Daily Reminders
- Dedicated dashboard for recurring daily habit tracking.
- Toggle reminders active/inactive without deletion.
- Intelligent notification system that handles timezones and device reboots.
- Built-in battery optimization handling to ensure reliability.

### 📝 Secured Note-Taking
- Standard and PIN-locked notes (Default PIN: 0000).
- Real-time Firestore persistence.
- Full-screen editing experience with Markdown-like simplicity.

### 🏆 Gold Price Tracking
- **Automated Scraping**: Real-time 22K gold price fetching from multiple sources (GoodReturns, BankBazaar).
- **History & Trends**: Track price changes over the last 10-20 days.
- **Visual Analytics**: Interactive charts powered by `fl_chart`.
- **Scheduled Notifications**: Receive price updates at 11 AM and 7 PM daily.

### 🏥 Shift Management (My Shifts)
- **Roster Support**: Upload and view monthly shift rosters (JSON format).
- **Calendar View**: Visual representation of your work schedule.
- **Automatic Notifications**: 10 PM reminders for next-day shifts.

### 🎨 Premium UI/UX
- **Modern Aesthetics**: Sleek Material 3 design with a curated color palette.
- **Dynamic Themes**: Seamless Dark and Light mode support.
- **Fluid Navigation**: intuitive drawer and bottom navigation.
- **Cross-Platform**: Optimized for Android, with supporting builds for Web and Linux.

## Tech Stack 🛠️

### Core
- **Framework**: [Flutter](https://flutter.dev/) (SDK 3.41.0+)
- **Language**: [Dart](https://dart.dev/)
- **Backend/Database**: [Firebase](https://firebase.google.com/) (Firestore & Authentication)
- **CI/CD**: GitHub Actions & [Shorebird](https://shorebird.dev/) (OTA Updates)

### Key Packages
- `cloud_firestore` & `firebase_auth`: For real-time data and user management.
- `flutter_local_notifications`: High-reliability notification engine.
- `fl_chart`: For beautiful data visualization.
- `flutter_inappwebview` & `html`: For robust gold price scraping.
- `shared_preferences`: For local settings persistence.

## Project Structure 📁

```
RemindBuddy/
├── frontend/           # The complete Flutter application
│   ├── lib/
│   │   ├── models/     # Firestore-compatible data models
│   │   ├── screens/    # Modern UI implementation
│   │   ├── services/   # Core business logic (Auth, Storage, Gold, etc.)
│   │   └── main.dart   # App entry point
│   ├── android/        # Native Android configuration (Firebase/Notifications)
│   └── web/            # Flutter Web configuration
├── .github/            # GitHub Actions (CI/CD Workflows)
└── README.md           # You are here
```

## Setup & Implementation 🚀

### 1. Prerequisites
- Flutter SDK (>=3.3.0)
- Firebase Account (with Firestore & Auth enabled)
- Android Studio (for native Android builds)

### 2. Initialization
```bash
git clone https://github.com/Roshan0102/RemindBuddy.git
cd RemindBuddy/frontend
flutter pub get
```

### 3. Firebase Configuration
Ensure you place your `google-services.json` in `frontend/android/app/`.

### 4. Running the App
```bash
# Debug on your connected device
flutter run

# Test on Web
flutter run -d chrome
```

## Building & Deployment 📦

### Android APK Build
The project uses GitHub Actions to automate APK generation. Every push to `main` triggers a build that:
1. Validates the code.
2. Builds the APK via **Shorebird**.
3. Uploads the artifact for download.

### Over-The-Air (OTA) Updates
We use **Shorebird** to push hot-fixes and UI updates directly to user devices without requiring a full APK re-installation.

## Permissions & Reliability 🔐
The app is designed for "High-Reliability" notifications on Android, requesting:
- `SCHEDULE_EXACT_ALARM`
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
- `RECEIVE_BOOT_COMPLETED`

---
**Made with ❤️ for peak productivity.**
