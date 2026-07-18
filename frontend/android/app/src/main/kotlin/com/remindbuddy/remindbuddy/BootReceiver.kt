package com.remindbuddy.remindbuddy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val sharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isEnabled = sharedPreferences.getBoolean("flutter.sleep_api_permission_granted", false)

            SleepTrackingService.logToPrefs(context, "Device rebooted (ACTION_BOOT_COMPLETED received). Sleep tracker enabled flag: $isEnabled")

            if (isEnabled) {
                val serviceIntent = Intent(context, SleepTrackingService::class.java)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }
                    SleepTrackingService.logToPrefs(context, "Successfully sent startForegroundService request from BootReceiver.")
                } catch (e: Exception) {
                    SleepTrackingService.logToPrefs(context, "Failed to start SleepTrackingService on boot: ${e.message}")
                }
            }
        }
    }
}
