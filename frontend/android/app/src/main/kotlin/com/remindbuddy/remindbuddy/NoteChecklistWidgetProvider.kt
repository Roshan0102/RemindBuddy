package com.remindbuddy.remindbuddy

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject

class NoteChecklistWidgetProvider : AppWidgetProvider() {

    companion object {
        const val ACTION_TOGGLE_CHECKLIST_ITEM = "com.remindbuddy.remindbuddy.ACTION_TOGGLE_CHECKLIST_ITEM"
        const val ACTION_RESET_CHECKLIST = "com.remindbuddy.remindbuddy.ACTION_RESET_CHECKLIST"
        const val EXTRA_ITEM_INDEX = "com.remindbuddy.remindbuddy.EXTRA_ITEM_INDEX"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val thisWidget = ComponentName(context, NoteChecklistWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)

        when (intent.action) {
            ACTION_TOGGLE_CHECKLIST_ITEM -> {
                val itemIndex = intent.getIntExtra(EXTRA_ITEM_INDEX, -1)
                if (itemIndex >= 0) {
                    toggleItem(context, itemIndex)
                    if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_checklist_list)
                    }
                }
            }
            ACTION_RESET_CHECKLIST -> {
                resetChecklist(context)
                if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                    appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_checklist_list)
                }
            }
            AppWidgetManager.ACTION_APPWIDGET_UPDATE -> {
                if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                    onUpdate(context, appWidgetManager, appWidgetIds)
                }
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)

        for (appWidgetId in appWidgetIds) {
            val title = widgetData?.getString("note_widget_title", null) ?: "Office Checklist"
            val noteId = widgetData?.getString("note_widget_id", null) ?: ""

            val views = RemoteViews(context.packageName, R.layout.note_checklist_widget_layout).apply {
                setTextViewText(R.id.widget_note_title, title)
                setEmptyView(R.id.widget_checklist_list, R.id.widget_checklist_empty)

                // 1. Bind RemoteViewsService to ListView
                val serviceIntent = Intent(context, NoteChecklistWidgetService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    data = Uri.parse("content://com.remindbuddy.remindbuddy/note_checklist_widget/$appWidgetId")
                }
                setRemoteAdapter(R.id.widget_checklist_list, serviceIntent)

                // 2. Set PendingIntent template for ListView item toggling
                val toggleIntent = Intent(context, NoteChecklistWidgetProvider::class.java).apply {
                    action = ACTION_TOGGLE_CHECKLIST_ITEM
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                }
                val toggleFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val togglePendingIntent = PendingIntent.getBroadcast(
                    context,
                    200,
                    toggleIntent,
                    toggleFlags
                )
                setPendingIntentTemplate(R.id.widget_checklist_list, togglePendingIntent)

                // 3. Reset Button PendingIntent
                val resetIntent = Intent(context, NoteChecklistWidgetProvider::class.java).apply {
                    action = ACTION_RESET_CHECKLIST
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                }
                val resetFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val resetPendingIntent = PendingIntent.getBroadcast(
                    context,
                    201,
                    resetIntent,
                    resetFlags
                )
                setOnClickPendingIntent(R.id.widget_note_reset_btn, resetPendingIntent)

                // 4. Header Click (Open note in app)
                val targetUri = if (noteId.isNotEmpty()) {
                    Uri.parse("remindbuddy://feature/notes?noteId=$noteId")
                } else {
                    Uri.parse("remindbuddy://feature/notes")
                }
                val openNotePendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    targetUri
                )
                setOnClickPendingIntent(R.id.widget_note_header, openNotePendingIntent)
                setOnClickPendingIntent(R.id.widget_note_open_btn, openNotePendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_checklist_list)
        }
    }

    private fun toggleItem(context: Context, index: Int) {
        try {
            val widgetData = HomeWidgetPlugin.getData(context) ?: return
            val jsonStr = widgetData.getString("note_widget_items", "[]") ?: "[]"
            val jsonArray = JSONArray(jsonStr)

            if (index in 0 until jsonArray.length()) {
                val item = jsonArray.getJSONObject(index)
                val current = item.optBoolean("isChecked", false)
                item.put("isChecked", !current)
                jsonArray.put(index, item)

                widgetData.edit().putString("note_widget_items", jsonArray.toString()).apply()
                // Mark that widget has modified data to be synced when Flutter opens/checks
                widgetData.edit().putBoolean("note_widget_dirty", true).apply()
                Log.d("NoteChecklistWidget", "Toggled item $index to ${!current}")
            }
        } catch (e: Exception) {
            Log.e("NoteChecklistWidget", "Error toggling item: $e")
        }
    }

    private fun resetChecklist(context: Context) {
        try {
            val widgetData = HomeWidgetPlugin.getData(context) ?: return
            val jsonStr = widgetData.getString("note_widget_items", "[]") ?: "[]"
            val jsonArray = JSONArray(jsonStr)

            for (i in 0 until jsonArray.length()) {
                val item = jsonArray.getJSONObject(i)
                item.put("isChecked", false)
                jsonArray.put(i, item)
            }

            widgetData.edit().putString("note_widget_items", jsonArray.toString()).apply()
            widgetData.edit().putBoolean("note_widget_dirty", true).apply()
            Log.d("NoteChecklistWidget", "Reset all items to unchecked")
        } catch (e: Exception) {
            Log.e("NoteChecklistWidget", "Error resetting checklist: $e")
        }
    }
}
