package com.remindbuddy.remindbuddy

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

class GoldWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val views = RemoteViews(context.packageName, R.layout.gold_widget_layout).apply {
                val rate22kGram = widgetData.getString("gold_22k_gram", "₹0/g")
                val rate22kSovereign = widgetData.getString("gold_22k_sovereign", "₹0 (8g)")
                val change = widgetData.getString("gold_change", "Live Rates")
                val time = widgetData.getString("gold_time", "Updated Today")

                setTextViewText(R.id.widget_gold_22k_gram, rate22kGram)
                setTextViewText(R.id.widget_gold_22k_sovereign, rate22kSovereign)
                setTextViewText(R.id.widget_gold_change, change)
                setTextViewText(R.id.widget_gold_time, time)

                // Launch RemindBuddy on click
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("remindbuddy://feature/gold")
                )
                setOnClickPendingIntent(R.id.widget_gold_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
