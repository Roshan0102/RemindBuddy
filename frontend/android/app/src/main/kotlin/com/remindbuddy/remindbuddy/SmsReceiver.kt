package com.remindbuddy.remindbuddy

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import io.flutter.plugin.common.EventChannel

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
                
                eventSink?.success(smsMap)
            }
        }
    }
}
