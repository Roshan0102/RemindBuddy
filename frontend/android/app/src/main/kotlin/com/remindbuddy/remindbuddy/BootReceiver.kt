package com.remindbuddy.remindbuddy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val sharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val isEnabled = sharedPreferences.getBoolean("flutter.sleep_api_permission_granted", false)

            Log.d("BootReceiver", "Device rebooted. Sleep tracker permission granted: $isEnabled")

            if (isEnabled) {
                val serviceIntent = Intent(context, SleepTrackingService::class.java)
                try {
                    context.startService(serviceIntent)
                    Log.d("BootReceiver", "Successfully started SleepTrackingService on boot.")
                } catch (e: Exception) {
                    Log.e("BootReceiver", "Failed to start SleepTrackingService on boot: ${e.message}")
                }
            }
        }
    }
}
