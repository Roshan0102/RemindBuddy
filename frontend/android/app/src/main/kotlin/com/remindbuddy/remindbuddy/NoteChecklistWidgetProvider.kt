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
        const val ACTION_WIDGET_PINNED_CALLBACK = "com.remindbuddy.remindbuddy.ACTION_WIDGET_PINNED_CALLBACK"
        const val EXTRA_ITEM_INDEX = "com.remindbuddy.remindbuddy.EXTRA_ITEM_INDEX"
        const val EXTRA_NOTE_ID = "extra_note_id"
        const val EXTRA_NOTE_TITLE = "extra_note_title"
        const val EXTRA_NOTE_ITEMS = "extra_note_items"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val thisWidget = ComponentName(context, NoteChecklistWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)

        when (intent.action) {
            ACTION_WIDGET_PINNED_CALLBACK -> {
                val newWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
                val noteId = intent.getStringExtra(EXTRA_NOTE_ID) ?: ""
                val title = intent.getStringExtra(EXTRA_NOTE_TITLE) ?: "Office Checklist"
                val items = intent.getStringExtra(EXTRA_NOTE_ITEMS) ?: "[]"

                if (newWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    val widgetData = HomeWidgetPlugin.getData(context)
                    widgetData?.edit()?.apply {
                        putString("note_widget_id_$newWidgetId", noteId)
                        putString("note_widget_title_$newWidgetId", title)
                        putString("note_widget_items_$newWidgetId", items)
                        putBoolean("note_widget_dirty_$newWidgetId", false)
                        apply()
                    }
                    onUpdate(context, appWidgetManager, intArrayOf(newWidgetId))
                    Log.d("NoteChecklistWidget", "Pinned callback configured widget $newWidgetId for note $noteId")
                }
            }
            ACTION_TOGGLE_CHECKLIST_ITEM -> {
                val itemIndex = intent.getIntExtra(EXTRA_ITEM_INDEX, -1)
                val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
                if (itemIndex >= 0) {
                    toggleItem(context, appWidgetId, itemIndex)
                    if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_checklist_list)
                    } else if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
                        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_checklist_list)
                    }
                }
            }
            ACTION_RESET_CHECKLIST -> {
                val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
                resetChecklist(context, appWidgetId)
                if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_checklist_list)
                } else if (appWidgetIds != null && appWidgetIds.isNotEmpty()) {
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

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        try {
            val widgetData = HomeWidgetPlugin.getData(context) ?: return
            val editor = widgetData.edit()
            for (id in appWidgetIds) {
                editor.remove("note_widget_id_$id")
                editor.remove("note_widget_title_$id")
                editor.remove("note_widget_items_$id")
                editor.remove("note_widget_dirty_$id")
            }
            editor.apply()
        } catch (e: Exception) {
            Log.e("NoteChecklistWidget", "Error cleaning up deleted widgets: $e")
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)

        for (appWidgetId in appWidgetIds) {
            val title = widgetData?.getString("note_widget_title_$appWidgetId", null)
                ?: widgetData?.getString("note_widget_title", null)
                ?: "Office Checklist"
            val noteId = widgetData?.getString("note_widget_id_$appWidgetId", null)
                ?: widgetData?.getString("note_widget_id", null)
                ?: ""

            val views = RemoteViews(context.packageName, R.layout.note_checklist_widget_layout).apply {
                setTextViewText(R.id.widget_note_title, title)
                setEmptyView(R.id.widget_checklist_list, R.id.widget_checklist_empty)

                // 1. Bind RemoteViewsService to ListView with widget-specific intent URI
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
                    2000 + appWidgetId,
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
                    3000 + appWidgetId,
                    resetIntent,
                    resetFlags
                )
                setOnClickPendingIntent(R.id.widget_note_reset_btn, resetPendingIntent)

                // 4. Header Click (Open specific note in app)
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

    private fun toggleItem(context: Context, appWidgetId: Int, index: Int) {
        try {
            val widgetData = HomeWidgetPlugin.getData(context) ?: return
            val key = if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID && widgetData.contains("note_widget_items_$appWidgetId")) {
                "note_widget_items_$appWidgetId"
            } else {
                "note_widget_items"
            }
            val jsonStr = widgetData.getString(key, "[]") ?: "[]"
            val jsonArray = JSONArray(jsonStr)

            if (index in 0 until jsonArray.length()) {
                val item = jsonArray.getJSONObject(index)
                val current = item.optBoolean("isChecked", false)
                item.put("isChecked", !current)
                jsonArray.put(index, item)

                val editor = widgetData.edit().putString(key, jsonArray.toString())
                if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                    editor.putBoolean("note_widget_dirty_$appWidgetId", true)
                }
                editor.putBoolean("note_widget_dirty", true)
                editor.apply()
                Log.d("NoteChecklistWidget", "Toggled item $index in $key to ${!current}")
            }
        } catch (e: Exception) {
            Log.e("NoteChecklistWidget", "Error toggling item: $e")
        }
    }

    private fun resetChecklist(context: Context, appWidgetId: Int) {
        try {
            val widgetData = HomeWidgetPlugin.getData(context) ?: return
            val key = if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID && widgetData.contains("note_widget_items_$appWidgetId")) {
                "note_widget_items_$appWidgetId"
            } else {
                "note_widget_items"
            }
            val jsonStr = widgetData.getString(key, "[]") ?: "[]"
            val jsonArray = JSONArray(jsonStr)

            for (i in 0 until jsonArray.length()) {
                val item = jsonArray.getJSONObject(i)
                item.put("isChecked", false)
                jsonArray.put(i, item)
            }

            val editor = widgetData.edit().putString(key, jsonArray.toString())
            if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
                editor.putBoolean("note_widget_dirty_$appWidgetId", true)
            }
            editor.putBoolean("note_widget_dirty", true)
            editor.apply()
            Log.d("NoteChecklistWidget", "Reset checklist for $key")
        } catch (e: Exception) {
            Log.e("NoteChecklistWidget", "Error resetting checklist: $e")
        }
    }
}
