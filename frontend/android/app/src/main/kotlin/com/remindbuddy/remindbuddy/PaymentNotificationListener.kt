package com.remindbuddy.remindbuddy

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject

class PaymentNotificationListener : NotificationListenerService() {
    companion object {
        var eventSink: EventChannel.EventSink? = null

        // Whitelist of Top Indian UPI & Payment App package IDs
        val SUPPORTED_UPI_PACKAGES = mapOf(
            "com.google.android.apps.nbu.paisa.user" to "GPay", // Official Google Pay India (Tez)
            "com.google.android.apps.npx" to "GPay",
            "com.google.android.apps.walletnfcrel" to "GPay",
            "com.phonepe.app" to "PhonePe",
            "net.one97.paytm" to "Paytm",
            "com.dreamplug.androidapp" to "CRED",
            "in.super.money" to "Super.money",
            "in.org.npci.upiapp" to "BHIM",
            "in.amazon.mShop.android.shopping" to "Amazon Pay",
            "com.amazon.mShop.android.shopping" to "Amazon Pay",
            "com.naviapp" to "Navi",
            "tech.fyle.navi" to "Navi",
            "money.jupiter" to "Jupiter",
            "com.tatadigital.tcp" to "Tata Neu",
            "com.whatsapp" to "WhatsApp Pay",
            "com.whatsapp.w4b" to "WhatsApp Pay",
            "com.freecharge.android" to "Freecharge",
            "com.mobikwik_new" to "MobiKwik",
            "money.fi.banking" to "Fi Money",
            "org.cosmic.slice" to "Slice",
            "indwin.c3.shareapp" to "Slice",
            "com.slice" to "Slice",
            "com.myairtelapp" to "Airtel Pay",
            "com.samsung.android.spay" to "Samsung Wallet",
            "com.samsung.android.spaymini" to "Samsung Wallet",
            "com.jio.myjio" to "JioPay"
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val packageName = sbn.packageName ?: return
        val appName = SUPPORTED_UPI_PACKAGES[packageName] ?: return

        val extras = sbn.notification?.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString() ?: ""

        // Combine body text preferring full bigText if available
        val fullBody = if (bigText.isNotEmpty()) bigText else text
        if (title.isEmpty() && fullBody.isEmpty()) return

        val timestamp = sbn.postTime

        val notifMap = mapOf(
            "packageName" to packageName,
            "appName" to appName,
            "title" to title,
            "text" to text,
            "bigText" to bigText,
            "fullBody" to fullBody,
            "subText" to subText,
            "timestamp" to timestamp
        )

        if (eventSink != null) {
            // App is running in foreground
            eventSink?.success(notifMap)
        } else {
            // App is closed or in background - buffer notification locally
            saveNotificationToBuffer(this, packageName, appName, title, fullBody, timestamp)
        }
    }

    private fun saveNotificationToBuffer(
        context: Context,
        packageName: String,
        appName: String,
        title: String,
        body: String,
        timestamp: Long
    ) {
        try {
            val prefs = context.getSharedPreferences("remindbuddy_notification_buffer", Context.MODE_PRIVATE)
            val existingJsonStr = prefs.getString("pending_payment_notifications", "[]") ?: "[]"
            val jsonArray = JSONArray(existingJsonStr)

            val jsonObj = JSONObject().apply {
                put("packageName", packageName)
                put("appName", appName)
                put("title", title)
                put("body", body)
                put("timestamp", timestamp)
            }

            jsonArray.put(jsonObj)
            prefs.edit().putString("pending_payment_notifications", jsonArray.toString()).apply()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
