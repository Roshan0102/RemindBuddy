package com.remindbuddy.remindbuddy

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.IBinder
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SleepTrackingService : Service() {
    private val TAG = "SleepTrackingService"
    private var screenReceiver: ScreenStateReceiver? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "SleepTrackingService Created")
        screenReceiver = ScreenStateReceiver()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, filter)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "SleepTrackingService Started")
        return START_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "SleepTrackingService Destroyed")
        screenReceiver?.let {
            unregisterReceiver(it)
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    class ScreenStateReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (context == null || intent == null) return

            val action = intent.action
            val sharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            val dfDate = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val dfTime = SimpleDateFormat("h:mm a", Locale.US)
            val dfFull = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
            val nowStr = dfFull.format(Date())

            // Get current state flags
            var isDeviceUnlocked = sharedPreferences.getBoolean("flutter.sleep_is_device_unlocked", false)
            var lastScreenOffTime = sharedPreferences.getLong("flutter.sleep_last_screen_off_time", 0L)

            if (action == Intent.ACTION_SCREEN_OFF) {
                // Only register screen off if the device was actually unlocked first (prevents notification wakes from messing it up)
                if (isDeviceUnlocked) {
                    lastScreenOffTime = System.currentTimeMillis()
                    isDeviceUnlocked = false

                    sharedPreferences.edit()
                        .putLong("flutter.sleep_last_screen_off_time", lastScreenOffTime)
                        .putBoolean("flutter.sleep_is_device_unlocked", isDeviceUnlocked)
                        .apply()

                    Log.d("ScreenStateReceiver", "Screen turned off. Registered lastScreenOffTime: ${dfTime.format(Date(lastScreenOffTime))}")
                    
                    // Log step for debugging
                    val rawLogSet = sharedPreferences.getStringSet("flutter.sleep_tracker_raw_logs", null) ?: emptySet()
                    val newRawLogSet = HashSet(rawLogSet)
                    newRawLogSet.add("[$nowStr] Screen locked (Start Sleep window).")
                    sharedPreferences.edit().putStringSet("flutter.sleep_tracker_raw_logs", newRawLogSet).apply()
                } else {
                    Log.d("ScreenStateReceiver", "Screen turned off, but ignored because device was not unlocked (e.g. Notification wake/glow).")
                }
            } else if (action == Intent.ACTION_USER_PRESENT) {
                val currentUnlockTime = System.currentTimeMillis()
                
                // Log step for debugging
                val rawLogSet = sharedPreferences.getStringSet("flutter.sleep_tracker_raw_logs", null) ?: emptySet()
                val newRawLogSet = HashSet(rawLogSet)
                newRawLogSet.add("[$nowStr] Device unlocked (Wake up).")

                if (lastScreenOffTime > 0L) {
                    val durationMs = currentUnlockTime - lastScreenOffTime
                    val durationHours = durationMs.toDouble() / 3600000.0

                    Log.d("ScreenStateReceiver", "Device unlocked. Duration: $durationHours hours")

                    if (durationHours >= 3.5) {
                        val dateStr = dfDate.format(Date(lastScreenOffTime))
                        val startTimeStr = dfTime.format(Date(lastScreenOffTime))
                        val endTimeStr = dfTime.format(Date(currentUnlockTime))
                        val durationHoursStr = String.format(Locale.US, "%.1f", durationHours)

                        val historySet = sharedPreferences.getStringSet("flutter.sleep_tracker_history", null) ?: emptySet()
                        val newHistorySet = HashSet(historySet)
                        
                        val recordStr = "$dateStr|$startTimeStr|$endTimeStr|$durationHoursStr"
                        newHistorySet.add(recordStr)

                        newRawLogSet.add("[$nowStr] Sleep detected: $durationHoursStr hrs ($startTimeStr to $endTimeStr).")

                        sharedPreferences.edit()
                            .putStringSet("flutter.sleep_tracker_history", newHistorySet)
                            .putLong("flutter.sleep_last_screen_off_time", 0L) // Reset to avoid duplicate recording
                            .apply()
                            
                        Log.d("ScreenStateReceiver", "Successfully saved sleep record: $recordStr")
                    } else {
                        Log.d("ScreenStateReceiver", "Inactivity duration ($durationHours hrs) was below threshold (3.5 hrs). Ignored.")
                        // If it's a short lock period, reset lastScreenOffTime to 0 or leave it?
                        // If we leave it, short unlocks during the night might break sleep tracking.
                        // Resetting it ensures we only count continuous sleep blocks.
                        sharedPreferences.edit().putLong("flutter.sleep_last_screen_off_time", 0L).apply()
                    }
                }

                // Always mark as unlocked now that user is present
                isDeviceUnlocked = true
                sharedPreferences.edit()
                    .putBoolean("flutter.sleep_is_device_unlocked", isDeviceUnlocked)
                    .putStringSet("flutter.sleep_tracker_raw_logs", newRawLogSet)
                    .apply()
            }
        }
    }
}
