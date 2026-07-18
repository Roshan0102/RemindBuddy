package com.remindbuddy.remindbuddy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SleepTrackingService : Service() {
    private val TAG = "SleepTrackingService"
    private var screenReceiver: ScreenStateReceiver? = null
    private val CHANNEL_ID = "sleep_tracker_channel"
    private val NOTIFICATION_ID = 1101

    companion object {
        fun logToPrefs(context: Context, message: String) {
            val sharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val rawLogSet = sharedPreferences.getStringSet("flutter.sleep_tracker_raw_logs", null) ?: emptySet()
            val newRawLogSet = HashSet(rawLogSet)
            val dfFull = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
            val nowStr = dfFull.format(Date())
            newRawLogSet.add("[$nowStr] $message")
            sharedPreferences.edit().putStringSet("flutter.sleep_tracker_raw_logs", newRawLogSet).apply()
            Log.d("SleepTrackerDebug", "[$nowStr] $message")
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "SleepTrackingService Created")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, getNotification())
        logToPrefs(this, "SleepTrackingService Created and running in Foreground.")

        screenReceiver = ScreenStateReceiver()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, filter)
        logToPrefs(this, "BroadcastReceiver registered for SCREEN_OFF and USER_PRESENT.")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "SleepTrackingService Started")
        
        // Ensure device lock state starts as unlocked initially since the user is starting tracking
        val sharedPreferences = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        sharedPreferences.edit().putBoolean("flutter.sleep_is_device_unlocked", true).apply()
        
        logToPrefs(this, "Service Started. Set initial isDeviceUnlocked = true")
        return START_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "SleepTrackingService Destroyed")
        logToPrefs(this, "SleepTrackingService Destroyed.")
        screenReceiver?.let {
            unregisterReceiver(it)
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Sleep Tracker Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps sleep tracking running in the background."
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun getNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        
        return builder
            .setContentTitle("Sleep Tracker Active")
            .setContentText("Monitoring sleep intervals based on lock state.")
            .setSmallIcon(android.R.drawable.ic_lock_idle_low_battery)
            .setOngoing(true)
            .build()
    }

    class ScreenStateReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (context == null || intent == null) return

            val action = intent.action
            val sharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            val dfDate = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val dfTime = SimpleDateFormat("h:mm a", Locale.US)

            // Get current state flags
            var isDeviceUnlocked = sharedPreferences.getBoolean("flutter.sleep_is_device_unlocked", false)
            var lastScreenOffTime = sharedPreferences.getLong("flutter.sleep_last_screen_off_time", 0L)

            if (action == Intent.ACTION_SCREEN_OFF) {
                logToPrefs(context, "ACTION_SCREEN_OFF received. Current state: isDeviceUnlocked=$isDeviceUnlocked")

                if (isDeviceUnlocked) {
                    lastScreenOffTime = System.currentTimeMillis()
                    isDeviceUnlocked = false

                    sharedPreferences.edit()
                        .putLong("flutter.sleep_last_screen_off_time", lastScreenOffTime)
                        .putBoolean("flutter.sleep_is_device_unlocked", isDeviceUnlocked)
                        .apply()

                    val offTimeStr = dfTime.format(Date(lastScreenOffTime))
                    logToPrefs(context, "Device locked. Registered lastScreenOffTime: $offTimeStr. State set to locked.")
                } else {
                    logToPrefs(context, "Screen turned off, but IGNORED because device was not unlocked first (likely a notification wake/glow).")
                }
            } else if (action == Intent.ACTION_USER_PRESENT) {
                val currentUnlockTime = System.currentTimeMillis()
                logToPrefs(context, "ACTION_USER_PRESENT (Device unlocked) received. Current state: lastScreenOffTime=${if (lastScreenOffTime > 0L) dfTime.format(Date(lastScreenOffTime)) else "0"}")

                if (lastScreenOffTime > 0L) {
                    val durationMs = currentUnlockTime - lastScreenOffTime
                    val durationHours = durationMs.toDouble() / 3600000.0
                    val durationHoursStr = String.format(Locale.US, "%.2f", durationHours)

                    logToPrefs(context, "Calculating sleep duration: $durationHoursStr hours.")

                    if (durationHours >= 3.5) {
                        val dateStr = dfDate.format(Date(lastScreenOffTime))
                        val startTimeStr = dfTime.format(Date(lastScreenOffTime))
                        val endTimeStr = dfTime.format(Date(currentUnlockTime))

                        val historySet = sharedPreferences.getStringSet("flutter.sleep_tracker_history", null) ?: emptySet()
                        val newHistorySet = HashSet(historySet)
                        
                        val recordStr = "$dateStr|$startTimeStr|$endTimeStr|$durationHoursStr"
                        newHistorySet.add(recordStr)

                        sharedPreferences.edit()
                            .putStringSet("flutter.sleep_tracker_history", newHistorySet)
                            .putLong("flutter.sleep_last_screen_off_time", 0L) // Reset to avoid duplicate recording
                            .apply()
                            
                        logToPrefs(context, "Sleep successfully recorded: $recordStr")
                    } else {
                        logToPrefs(context, "Inactivity duration ($durationHoursStr hrs) was below threshold (3.5 hrs). Resetting lock time.")
                        sharedPreferences.edit().putLong("flutter.sleep_last_screen_off_time", 0L).apply()
                    }
                } else {
                    logToPrefs(context, "Device unlocked, but no valid sleep start time was recorded.")
                }

                // Always mark as unlocked now that user is present
                isDeviceUnlocked = true
                sharedPreferences.edit()
                    .putBoolean("flutter.sleep_is_device_unlocked", isDeviceUnlocked)
                    .apply()
                logToPrefs(context, "State set to unlocked (isDeviceUnlocked = true).")
            }
        }
    }
}
