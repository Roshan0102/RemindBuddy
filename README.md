# RemindBuddy 🔔

A smart reminder and task management app built with Flutter and Node.js.

## Features ✨

### 📅 Task Management
- Calendar-based task creation and viewing
- One-time and recurring reminders (daily, weekly, monthly)
- Custom repeat intervals
- Task synchronization with backend

### ⏰ Daily Reminders
- Separate section for recurring daily reminders
- Toggle reminders on/off without deleting
- "Annoying Mode" for persistent reminders
- Reliable notification system with battery optimization handling

### 📝 Secure Notes
- Create and manage notes
- PIN lock protection (default: 0000)
- Lock/unlock individual notes

### 🏆 Gold Price Tracking (New!)
- Automatic 22K gold price fetching from goodreturns.in
- Daily price notifications at 11 AM and 7 PM
- Historical price tracking (last 10 days)
- Price charts and trends

### 🎨 UI/UX
- Material Design 3
- Dark/Light theme toggle
- Beautiful drawer navigation
- Google Fonts integration
- Responsive design

## Tech Stack 🛠️

### Frontend
- **Flutter** - Cross-platform mobile framework
- **Dart** - Programming language
- **sqflite** - Local database
- **flutter_local_notifications** - Notification system
- **fl_chart** - Chart visualization
- **html** - Web scraping
- **google_fonts** - Typography

### Backend
- **Node.js** - Server runtime
- **Express** - Web framework
- **SQLite** - Database

## Setup Instructions 🚀

### Prerequisites
- Flutter SDK (>=3.3.0)
- Node.js (>=14.0.0)
- Android Studio (for Android development)

### Backend Setup

```bash
cd backend
npm install
npm start
```

The backend will run on `http://localhost:3000`

### Frontend Setup

```bash
cd frontend
flutter pub get
flutter run
```

## Building for Production 📦

### Android APK

```bash
cd frontend
flutter build apk --release
```

### Using Shorebird (OTA Updates)

```bash
cd frontend
shorebird release android --artifact apk
```

## Project Structure 📁

```
RemindBuddy/
├── frontend/           # Flutter mobile app
│   ├── lib/
│   │   ├── models/     # Data models
│   │   ├── screens/    # UI screens
│   │   ├── services/   # Business logic
│   │   └── main.dart   # Entry point
│   └── android/        # Android-specific code
├── backend/            # Node.js server
│   ├── server.js       # Main server file
│   └── package.json    # Dependencies
└── README.md           # This file
```

## Key Features Implementation 🔑

### Battery Optimization
The app requests battery optimization exemption to ensure reliable daily reminders. This is critical for Android devices with aggressive battery management.

### Notification System
- Uses `flutter_local_notifications` with exact alarms
- Handles timezone changes
- Re-schedules after device reboot
- Supports "Annoying Mode" with action buttons

### Gold Price Scraping
- Fetches 22K gold prices from goodreturns.in
- Uses proper HTML parsing with fallback methods
- Stores historical data for trend analysis
- Automatic notifications at scheduled times

## Database Schema 💾

### Tasks
- id, title, description, date, time, repeat, isAnnoying

### Notes
- id, title, content, date, isLocked

### Daily Reminders
- id, title, description, time, isActive, isAnnoying

### Gold Prices
- date, price22k, price24k, city

## Permissions 🔐

### Android
- `POST_NOTIFICATIONS` - Show notifications
- `SCHEDULE_EXACT_ALARM` - Schedule exact time alarms
- `USE_EXACT_ALARM` - Use exact alarms
- `RECEIVE_BOOT_COMPLETED` - Re-schedule after reboot
- `WAKE_LOCK` - Wake device for notifications
- `USE_FULL_SCREEN_INTENT` - Full-screen notifications
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` - Battery exemption
- `VIBRATE` - Vibration for notifications
- `INTERNET` - API calls and web scraping

## Version History 📝

### v1.0.31 (Current)
- ✅ Daily Reminders feature
- ✅ Gold Price tracking
- ✅ Battery optimization handling
- ✅ Drawer navigation
- ✅ Web compatibility fixes

### v1.0.30
- ✅ Annoying alarm mode
- ✅ PIN lock for notes
- ✅ Dark/Light theme
- ✅ Home screen widget
- ✅ Calendar UI improvements

## Testing 🧪

### Web Preview (UI Testing)
```bash
cd frontend
flutter run -d chrome
```

### Android Testing
```bash
cd frontend
flutter run
```

## Troubleshooting 🔧

### Build Errors
```bash
cd frontend
flutter clean
flutter pub get
flutter run
```

### Notifications Not Working
1. Check battery optimization is disabled
2. Verify exact alarm permissions granted
3. Check notification permissions
4. View logs using the debug icon in app

### Gold Price Fetching Issues
1. Test on Android device (not web)
2. Check internet connection
3. View console logs for detailed errors
4. Use test screen: Drawer → "🧪 Gold Price Test"

## Contributing 🤝

This is a personal project. Feel free to fork and modify for your own use.

## License 📄

Private project - All rights reserved.

## Contact 📧

For issues or questions, please create an issue in the repository.

---

**Made with ❤️ using Flutter**
