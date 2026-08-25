package com.remindbuddy.remindbuddy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject

class SmsReceiver : BroadcastReceiver() {
    companion object {
        var eventSink: EventChannel.EventSink? = null
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            for (sms in messages) {
                val sender = sms.originatingAddress ?: ""
                val body = sms.messageBody ?: ""
                val timestamp = sms.timestampMillis

                val smsMap = mapOf(
                    "sender" to sender,
                    "body" to body,
                    "timestamp" to timestamp
                )
                
                if (eventSink != null) {
                    // App is active in foreground
                    eventSink?.success(smsMap)
                } else if (context != null) {
                    // App is closed/terminated - store in background buffer
                    saveSmsToBuffer(context, sender, body, timestamp)
                }
            }
        }
    }

    private fun saveSmsToBuffer(context: Context, sender: String, body: String, timestamp: Long) {
        try {
            val prefs = context.getSharedPreferences("remindbuddy_sms_buffer", Context.MODE_PRIVATE)
            val existingJsonStr = prefs.getString("pending_sms", "[]") ?: "[]"
            val jsonArray = JSONArray(existingJsonStr)

            val jsonObj = JSONObject().apply {
                put("sender", sender)
                put("body", body)
                put("timestamp", timestamp)
            }

            jsonArray.put(jsonObj)
            prefs.edit().putString("pending_sms", jsonArray.toString()).apply()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
