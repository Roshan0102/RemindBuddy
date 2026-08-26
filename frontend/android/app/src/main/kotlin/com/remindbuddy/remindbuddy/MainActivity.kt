package com.remindbuddy.remindbuddy

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.app.AlarmManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.PendingIntent
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.SleepSegmentRequest
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import android.provider.Telephony

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.remindbuddy/battery"
    private var permissionResult: MethodChannel.Result? = null
    private val ACTIVITY_RECOGNITION_REQUEST_CODE = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // SMS Stream EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.remindbuddy/sms_stream").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    SmsReceiver.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    SmsReceiver.eventSink = null
                }
            }
        )

        // SMS Inbox Scanner MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.remindbuddy/sms_scanner").setMethodCallHandler { call, result ->
            when (call.method) {
                "scanSmsInbox" -> {
                    val days = call.argument<Int>("days") ?: 30
                    val smsList = scanSmsInbox(days)
                    result.success(smsList)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // SMS Background Buffer MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.remindbuddy/sms_buffer").setMethodCallHandler { call, result ->
            when (call.method) {
                "getAndClearPendingSms" -> {
                    try {
                        val prefs = getSharedPreferences("remindbuddy_sms_buffer", Context.MODE_PRIVATE)
                        val existingJsonStr = prefs.getString("pending_sms", "[]") ?: "[]"
                        val jsonArray = org.json.JSONArray(existingJsonStr)

                        val list = mutableListOf<Map<String, Any>>()
                        for (i in 0 until jsonArray.length()) {
                            val obj = jsonArray.getJSONObject(i)
                            list.add(mapOf(
                                "sender" to obj.optString("sender"),
                                "body" to obj.optString("body"),
                                "timestamp" to obj.optLong("timestamp")
                            ))
                        }

                        // Clear buffer once retrieved
                        prefs.edit().remove("pending_sms").apply()
                        result.success(list)
                    } catch (e: Exception) {
                        result.error("BUFFER_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isBatteryOptimizationEnabled" -> {
                    result.success(isBatteryOptimizationEnabled())
                }
                "requestDisableBatteryOptimization" -> {
                    requestDisableBatteryOptimization()
                    result.success(null)
                }
                "isExactAlarmPermissionGranted" -> {
                    result.success(isExactAlarmPermissionGranted())
                }
                "requestExactAlarmPermission" -> {
                    requestExactAlarmPermission()
                    result.success(null)
                }
                "openAutostartSettings" -> {
                    openAutostartSettings()
                    result.success(null)
                }
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.remindbuddy/sleep_tracker").setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    result.success(hasActivityRecognitionPermission())
                }
                "requestPermission" -> {
                    requestActivityRecognitionPermission(result)
                }
                "requestSleepUpdates" -> {
                    requestSleepUpdates(result)
                }
                "removeSleepUpdates" -> {
                    removeSleepUpdates(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getSleepPendingIntent(): PendingIntent {
        val intent = Intent(this, SleepReceiver::class.java)
        return PendingIntent.getBroadcast(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )
    }

    private fun requestSleepUpdates(result: MethodChannel.Result) {
        try {
            val serviceIntent = Intent(this, SleepTrackingService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }
            SleepTrackingService.logToPrefs(this, "requestSleepUpdates called: service start intent sent.")
            result.success(true)
        } catch (e: Exception) {
            SleepTrackingService.logToPrefs(this, "requestSleepUpdates failed to start service: ${e.message}")
            result.error("UNKNOWN_ERROR", e.message ?: "Failed to start sleep updates", null)
        }
    }

    private fun removeSleepUpdates(result: MethodChannel.Result) {
        try {
            val serviceIntent = Intent(this, SleepTrackingService::class.java)
            stopService(serviceIntent)
            SleepTrackingService.logToPrefs(this, "removeSleepUpdates called: service stop intent sent.")
            result.success(true)
        } catch (e: Exception) {
            SleepTrackingService.logToPrefs(this, "removeSleepUpdates failed to stop service: ${e.message}")
            result.error("UNKNOWN_ERROR", e.message ?: "Failed to remove sleep updates", null)
        }
    }

    private fun isBatteryOptimizationEnabled(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            return !powerManager.isIgnoringBatteryOptimizations(packageName)
        }
        return false
    }

    private fun requestDisableBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent()
            if (!isBatteryOptimizationEnabled()) return 
            intent.action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
            intent.data = Uri.parse("package:$packageName")
            startActivity(intent)
        }
    }

    private fun isExactAlarmPermissionGranted(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            return alarmManager.canScheduleExactAlarms()
        }
        return true
    }

    private fun requestExactAlarmPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent().apply {
                action = Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        }
    }

    private fun openAutostartSettings() {
        val intent = Intent()
        val manufacturers = arrayOf(
            // Vivo / iQOO
            arrayOf("com.iqoo.secure", "com.iqoo.secure.ui.asset.AppAutoStartServiceManager"),
            arrayOf("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            arrayOf("com.iqoo.secure", "com.iqoo.secure.MainGuideActivity")
        )

        for (m in manufacturers) {
            try {
                intent.setClassName(m[0], m[1])
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                return
            } catch (e: Exception) {}
        }

        // Fallback to app settings
        openAppSettings()
    }

    private fun openNotificationSettings() {
        val intent = Intent()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intent.action = Settings.ACTION_APP_NOTIFICATION_SETTINGS
            intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            intent.action = "android.settings.APP_NOTIFICATION_SETTINGS"
            intent.putExtra("app_package", packageName)
            intent.putExtra("app_uid", applicationInfo.uid)
        }
        startActivity(intent)
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
        intent.data = Uri.parse("package:$packageName")
        startActivity(intent)
    }

    private fun hasActivityRecognitionPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestActivityRecognitionPermission(result: MethodChannel.Result) {
        if (hasActivityRecognitionPermission()) {
            result.success(true)
            return
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            permissionResult = result
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
                ACTIVITY_RECOGNITION_REQUEST_CODE
            )
        } else {
            result.success(true)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == ACTIVITY_RECOGNITION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    private fun scanSmsInbox(days: Int): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        try {
            val daysLong = if (days <= 0) 30L else days.toLong()
            val millisInPeriod = daysLong * 24L * 60L * 60L * 1000L
            val cutoffTime = System.currentTimeMillis() - millisInPeriod
            val uri = Telephony.Sms.Inbox.CONTENT_URI
            val projection = arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE)
            val selection = "${Telephony.Sms.DATE} >= ?"
            val selectionArgs = arrayOf(cutoffTime.toString())
            val sortOrder = "${Telephony.Sms.DATE} DESC"

            val cursor = contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)
            cursor?.use { c ->
                val addressIdx = c.getColumnIndex(Telephony.Sms.ADDRESS)
                val bodyIdx = c.getColumnIndex(Telephony.Sms.BODY)
                val dateIdx = c.getColumnIndex(Telephony.Sms.DATE)

                while (c.moveToNext()) {
                    val address = if (addressIdx >= 0) c.getString(addressIdx) ?: "" else ""
                    val body = if (bodyIdx >= 0) c.getString(bodyIdx) ?: "" else ""
                    val date = if (dateIdx >= 0) c.getLong(dateIdx) else 0L

                    result.add(
                        mapOf(
                            "sender" to address,
                            "body" to body,
                            "timestamp" to date
                        )
                    )
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return result
    }
}
