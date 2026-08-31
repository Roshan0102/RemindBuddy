package com.remindbuddy.remindbuddy

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

class FinanceWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val thisWidget = ComponentName(context, FinanceWidgetProvider::class.java)
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
            val views = RemoteViews(context.packageName, R.layout.finance_widget_layout).apply {
                val balance = widgetData.getString("finance_balance", "Total: ₹0")
                val todayIn = widgetData.getString("finance_in", "+₹0")
                val todayOut = widgetData.getString("finance_out", "-₹0")
                val time = widgetData.getString("finance_time", "Synced Today")

                val acc1Name = widgetData.getString("finance_acc1_name", "")
                val acc1Bal = widgetData.getString("finance_acc1_bal", "")
                val acc2Name = widgetData.getString("finance_acc2_name", "")
                val acc2Bal = widgetData.getString("finance_acc2_bal", "")
                val acc3Name = widgetData.getString("finance_acc3_name", "")
                val acc3Bal = widgetData.getString("finance_acc3_bal", "")
                val acc4Name = widgetData.getString("finance_acc4_name", "")
                val acc4Bal = widgetData.getString("finance_acc4_bal", "")

                setTextViewText(R.id.widget_finance_balance, balance)
                setTextViewText(R.id.widget_finance_in, todayIn)
                setTextViewText(R.id.widget_finance_out, todayOut)
                setTextViewText(R.id.widget_finance_time, time)

                // Account 1
                if (!acc1Name.isNullOrEmpty()) {
                    setViewVisibility(R.id.widget_finance_acc1_row, View.VISIBLE)
                    setTextViewText(R.id.widget_finance_acc1_name, acc1Name)
                    setTextViewText(R.id.widget_finance_acc1_bal, acc1Bal)
                } else {
                    setViewVisibility(R.id.widget_finance_acc1_row, View.VISIBLE)
                    setTextViewText(R.id.widget_finance_acc1_name, "No Connected Accounts")
                    setTextViewText(R.id.widget_finance_acc1_bal, "₹0")
                }

                // Account 2
                if (!acc2Name.isNullOrEmpty()) {
                    setViewVisibility(R.id.widget_finance_acc2_row, View.VISIBLE)
                    setTextViewText(R.id.widget_finance_acc2_name, acc2Name)
                    setTextViewText(R.id.widget_finance_acc2_bal, acc2Bal)
                } else {
                    setViewVisibility(R.id.widget_finance_acc2_row, View.GONE)
                }

                // Account 3
                if (!acc3Name.isNullOrEmpty()) {
                    setViewVisibility(R.id.widget_finance_acc3_row, View.VISIBLE)
                    setTextViewText(R.id.widget_finance_acc3_name, acc3Name)
                    setTextViewText(R.id.widget_finance_acc3_bal, acc3Bal)
                } else {
                    setViewVisibility(R.id.widget_finance_acc3_row, View.GONE)
                }

                // Account 4
                if (!acc4Name.isNullOrEmpty()) {
                    setViewVisibility(R.id.widget_finance_acc4_row, View.VISIBLE)
                    setTextViewText(R.id.widget_finance_acc4_name, acc4Name)
                    setTextViewText(R.id.widget_finance_acc4_bal, acc4Bal)
                } else {
                    setViewVisibility(R.id.widget_finance_acc4_row, View.GONE)
                }

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
