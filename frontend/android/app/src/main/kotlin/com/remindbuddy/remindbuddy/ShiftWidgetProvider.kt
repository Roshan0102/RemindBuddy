package com.remindbuddy.remindbuddy

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

class ShiftWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val thisWidget = ComponentName(context, ShiftWidgetProvider::class.java)
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
            val views = RemoteViews(context.packageName, R.layout.shift_widget_layout).apply {
                val shiftName = widgetData.getString("shift_name", "Week Off 🏖️")
                val shiftTime = widgetData.getString("shift_time", "Off Duty")
                val shiftTomorrow = widgetData.getString("shift_tomorrow", "Tomorrow: Week Off")
                val shiftDate = widgetData.getString("shift_date", "Today")

                setTextViewText(R.id.widget_shift_name, shiftName)
                setTextViewText(R.id.widget_shift_time, shiftTime)
                setTextViewText(R.id.widget_shift_tomorrow, shiftTomorrow)
                setTextViewText(R.id.widget_shift_date, shiftDate)

                // Launch RemindBuddy on click
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("remindbuddy://feature/shifts")
                )
                setOnClickPendingIntent(R.id.widget_shift_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
