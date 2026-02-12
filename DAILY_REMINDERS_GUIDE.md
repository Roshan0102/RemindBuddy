# RemindBuddy - Daily Reminders Feature

## 🎉 What's New

### ✨ Daily Reminders Feature
A dedicated section for managing **recurring daily reminders** that fire every day at the same time!

### 🔧 Key Improvements

1. **Separate Daily Reminders Management**
   - Access via the new **drawer menu** (☰ icon in top-left)
   - Create, edit, delete, and toggle daily reminders
   - Independent from calendar-based one-time tasks

2. **Reliable Notification System**
   - Uses `DateTimeComponents.time` for true daily repeats
   - Battery optimization handling to prevent Android from killing reminders
   - Exact alarm permissions for precise timing

3. **Better UI/UX**
   - Beautiful drawer navigation with gradient header
   - Material Design 3 components
   - Toggle reminders on/off without deleting them
   - Visual indicators for active/inactive reminders

4. **Annoying Mode Support**
   - Works with daily reminders too!
   - Keeps nagging until you mark as done

---

## 🚀 Testing the App (Without Building to Phone)

### Option 1: Flutter Web Preview (Recommended for UI Testing)

This lets you see the UI in your browser without building to a phone!

```bash
cd /home/roshan-axcess/Documents/RemindBuddy/frontend

# Run the app in Chrome
flutter run -d chrome

# Or run on a specific port
flutter run -d chrome --web-port=8080
```

**Note:** Notifications won't work in web mode, but you can test all the UI:
- Navigation drawer
- Daily reminders screen
- Add/edit/delete reminders
- Toggle active/inactive
- Calendar view
- Notes

### Option 2: Android Emulator (Full Feature Testing)

If you have Android Studio installed with an emulator:

```bash
cd /home/roshan-axcess/Documents/RemindBuddy/frontend

# List available devices
flutter devices

# Run on emulator
flutter run
```

### Option 3: Hot Reload During Development

Once the app is running (web or emulator), you can make changes and see them instantly:

1. Make code changes in your editor
2. Press `r` in the terminal for hot reload
3. Press `R` for hot restart (if hot reload doesn't work)
4. Press `q` to quit

---

## 📱 How to Use Daily Reminders

### Creating a Daily Reminder

1. Open the app
2. Tap the **☰ menu icon** (top-left)
3. Select **"Daily Reminders"**
4. Tap the **"+ Add Reminder"** button
5. Fill in:
   - **Title**: e.g., "Take Vitamins"
   - **Description**: e.g., "Don't forget your daily vitamins!"
   - **Time**: Select the time (e.g., 10:30 PM)
   - **Annoying Mode**: Toggle if you want persistent reminders
6. Tap **"Save"**

### Managing Reminders

- **Toggle On/Off**: Use the switch to temporarily disable without deleting
- **Edit**: Tap the ⋮ menu → Edit
- **Delete**: Tap the ⋮ menu → Delete

### Why Daily Reminders Stopped Working (Your Issue)

The reminders likely stopped due to:

1. **Battery Optimization**: Android killed the app to save battery
2. **Missing Permissions**: Exact alarm permissions might have been revoked
3. **App Updates**: Sometimes notifications get cleared during updates

### How We Fixed It

1. **Added Battery Optimization Handling**
   - App now requests exemption from battery optimization
   - Shows a helpful dialog explaining why it's needed

2. **Improved Notification Scheduling**
   - Uses `DateTimeComponents.time` for reliable daily repeats
   - Properly handles timezone changes
   - Re-schedules on device reboot

3. **Separate Daily Reminders**
   - No longer tied to specific dates
   - Stored separately in database
   - Can be toggled on/off without deletion

---

## 🔍 Debugging Daily Reminders

### Check Pending Notifications

The app has a built-in log viewer:

1. On the Reminders screen, tap the **bug icon** (🐛) at the bottom
2. Look for entries like:
   ```
   Scheduling Daily Reminder 100001: "Take Vitamins"
   - Time: 22:30
   - First occurrence: 2026-02-12 22:30:00
   - SUCCESS: Daily reminder scheduled
   ```

### Verify Battery Optimization

1. Open Android Settings
2. Go to **Apps** → **RemindBuddy** → **Battery**
3. Ensure it's set to **"Don't optimize"** or **"Unrestricted"**

### Check Exact Alarm Permission

1. Open Android Settings
2. Go to **Apps** → **Special app access** → **Alarms & reminders**
3. Ensure **RemindBuddy** is **allowed**

---

## 🏗️ Architecture Changes

### New Files Created

1. **`lib/models/daily_reminder.dart`**
   - Model for daily reminders
   - Separate from Task model

2. **`lib/screens/daily_reminders_screen.dart`**
   - Full CRUD UI for daily reminders
   - Beautiful Material Design 3 interface

3. **`lib/services/battery_optimization_service.dart`**
   - Handles battery optimization checks
   - Shows educational dialogs

### Modified Files

1. **`lib/services/storage_service.dart`**
   - Added `daily_reminders` table
   - CRUD methods for daily reminders
   - Database version upgraded to 4

2. **`lib/services/notification_service.dart`**
   - New `scheduleDailyReminder()` method
   - Uses `DateTimeComponents.time` for daily repeats

3. **`lib/screens/main_screen.dart`**
   - Added drawer navigation
   - Links to Daily Reminders screen

4. **`lib/screens/home_screen.dart`**
   - Fixed `_getTasksForDay()` build error

5. **`android/app/src/main/kotlin/.../MainActivity.kt`**
   - Added native battery optimization handling

6. **`android/app/src/main/AndroidManifest.xml`**
   - Added `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission

---

## 🎨 UI Preview Commands

### Quick Start for UI Testing

```bash
# Terminal 1: Start the backend (if needed)
cd /home/roshan-axcess/Documents/RemindBuddy/backend
npm start

# Terminal 2: Start the Flutter web app
cd /home/roshan-axcess/Documents/RemindBuddy/frontend
flutter run -d chrome
```

### What You Can Test in Web Mode

✅ Navigation drawer
✅ Daily Reminders screen UI
✅ Add/Edit/Delete reminders
✅ Toggle active/inactive
✅ Calendar view
✅ Notes screen
✅ Theme toggle (dark/light)

❌ Actual notifications (web doesn't support native notifications)
❌ Battery optimization (Android-only feature)

---

## 📊 Database Schema

### New Table: `daily_reminders`

```sql
CREATE TABLE daily_reminders(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT,
  description TEXT,
  time TEXT,           -- HH:MM format (24-hour)
  isActive INTEGER,    -- 1 = active, 0 = inactive
  isAnnoying INTEGER   -- 1 = annoying mode, 0 = normal
)
```

---

## 🐛 Known Limitations

1. **Web Preview**: Notifications don't work in web mode (browser limitation)
2. **First Launch**: You may need to manually grant exact alarm permissions
3. **Battery Optimization**: Some manufacturers (Xiaomi, OnePlus) have extra aggressive settings

---

## 🔜 Next Steps

Before building for production:

1. **Test all features in web mode** for UI/UX
2. **Test on Android emulator** for full functionality
3. **Test battery optimization dialog**
4. **Verify daily reminders fire correctly**
5. **Test annoying mode**
6. **Check logs for any errors**

Once everything is verified:

```bash
# Build release APK
cd /home/roshan-axcess/Documents/RemindBuddy/frontend
flutter build apk --release

# Or use Shorebird for OTA updates
shorebird release android --artifact apk
```

---

## 💡 Tips for Reliable Daily Reminders

1. **Always disable battery optimization** when prompted
2. **Keep the app updated** to get the latest fixes
3. **Check logs** if reminders stop working
4. **Use annoying mode** for critical reminders
5. **Test with a near-future time** first (e.g., 2 minutes from now)

---

## 📞 Support

If daily reminders still don't work:

1. Check the logs (🐛 icon)
2. Verify all permissions are granted
3. Try deleting and re-creating the reminder
4. Restart your phone
5. Check if "Do Not Disturb" is blocking notifications

---

**Happy Reminding! 🎉**
