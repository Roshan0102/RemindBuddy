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
            PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )
    }

    private fun requestSleepUpdates(result: MethodChannel.Result) {
        try {
            ActivityRecognition.getClient(this)
                .requestSleepSegmentUpdates(getSleepPendingIntent(), SleepSegmentRequest.getDefaultSleepSegmentRequest())
                .addOnSuccessListener {
                    result.success(true)
                }
                .addOnFailureListener { e: Exception ->
                    result.error("SLEEP_API_ERROR", e.message, null)
                }
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "Activity Recognition permission is required", null)
        } catch (e: Exception) {
            result.error("UNKNOWN_ERROR", e.message ?: "Failed to start sleep updates", null)
        }
    }

    private fun removeSleepUpdates(result: MethodChannel.Result) {
        try {
            ActivityRecognition.getClient(this)
                .removeSleepSegmentUpdates(getSleepPendingIntent())
                .addOnSuccessListener {
                    result.success(true)
                }
                .addOnFailureListener { e: Exception ->
                    result.error("SLEEP_API_ERROR", e.message, null)
                }
        } catch (e: Exception) {
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
}
