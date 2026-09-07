package com.remindbuddy.remindbuddy

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

class ShiftCalendarWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val thisWidget = ComponentName(context, ShiftCalendarWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
        if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
            onUpdate(context, appWidgetManager, appWidgetIds)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val views = RemoteViews(context.packageName, R.layout.shift_calendar_widget_layout).apply {
                val monthTitle = widgetData.getString("shift_calendar_month", "This Month")
                setTextViewText(R.id.widget_shift_calendar_month, monthTitle)

                val imagePath = widgetData.getString("shift_calendar_image_path", null)
                if (imagePath != null && File(imagePath).exists()) {
                    try {
                        val bitmap = BitmapFactory.decodeFile(imagePath)
                        if (bitmap != null) {
                            setImageViewBitmap(R.id.widget_shift_calendar_image, bitmap)
                            setViewVisibility(R.id.widget_shift_calendar_image, View.VISIBLE)
                            setViewVisibility(R.id.widget_shift_calendar_empty, View.GONE)
                        } else {
                            setViewVisibility(R.id.widget_shift_calendar_image, View.GONE)
                            setViewVisibility(R.id.widget_shift_calendar_empty, View.VISIBLE)
                        }
                    } catch (e: Exception) {
                        setViewVisibility(R.id.widget_shift_calendar_image, View.GONE)
                        setViewVisibility(R.id.widget_shift_calendar_empty, View.VISIBLE)
                    }
                } else {
                    setViewVisibility(R.id.widget_shift_calendar_image, View.GONE)
                    setViewVisibility(R.id.widget_shift_calendar_empty, View.VISIBLE)
                }

                // Launch RemindBuddy directly on shift screen on click
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("remindbuddy://feature/shifts")
                )
                setOnClickPendingIntent(R.id.widget_shift_calendar_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
