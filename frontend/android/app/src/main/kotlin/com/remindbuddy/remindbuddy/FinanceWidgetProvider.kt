package com.remindbuddy.remindbuddy

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

class FinanceWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val views = RemoteViews(context.packageName, R.layout.finance_widget_layout).apply {
                val balance = widgetData.getString("finance_balance", "₹0.00")
                val todayIn = widgetData.getString("finance_in", "↓ +₹0 In")
                val todayOut = widgetData.getString("finance_out", "↑ -₹0 Out")
                val bank = widgetData.getString("finance_bank", "Active Accounts")
                val time = widgetData.getString("finance_time", "Synced Today")

                setTextViewText(R.id.widget_finance_balance, balance)
                setTextViewText(R.id.widget_finance_in, todayIn)
                setTextViewText(R.id.widget_finance_out, todayOut)
                setTextViewText(R.id.widget_finance_bank, bank)
                setTextViewText(R.id.widget_finance_time, time)

                // Launch RemindBuddy on click
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("remindbuddy://feature/finance")
                )
                setOnClickPendingIntent(R.id.widget_finance_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
