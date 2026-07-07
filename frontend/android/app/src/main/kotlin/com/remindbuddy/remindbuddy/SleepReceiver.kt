package com.remindbuddy.remindbuddy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.SleepSegmentEvent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SleepReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        if (SleepSegmentEvent.hasEvents(intent)) {
            val events = SleepSegmentEvent.extractEvents(intent)
            val sharedPreferences = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val historySet = sharedPreferences.getStringSet("flutter.sleep_tracker_history", null) ?: emptySet()
            val newHistorySet = HashSet(historySet)

            val dfDate = SimpleDateFormat("yyyy-MM-dd", Locale.US)
            val dfTime = SimpleDateFormat("h:mm a", Locale.US)

            for (event in events) {
                if (event.status == SleepSegmentEvent.STATUS_SUCCESSFUL) {
                    val startMillis = event.startTimeMillis
                    val endMillis = event.endTimeMillis
                    val durationMs = endMillis - startMillis
                    val durationHours = durationMs.toDouble() / 3600000.0

                    val dateStr = dfDate.format(Date(startMillis))
                    val startTimeStr = dfTime.format(Date(startMillis))
                    val endTimeStr = dfTime.format(Date(endMillis))
                    val durationHoursStr = String.format(Locale.US, "%.1f", durationHours)

                    val recordStr = "$dateStr|$startTimeStr|$endTimeStr|$durationHoursStr"
                    newHistorySet.add(recordStr)
                }
            }

            sharedPreferences.edit()
                .putStringSet("flutter.sleep_tracker_history", newHistorySet)
                .apply()
        }
    }
}
