package com.remindbuddy.remindbuddy

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.util.Log
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

data class ChecklistItemData(
    val text: String,
    val isChecked: Boolean
)

class NoteChecklistWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return NoteChecklistRemoteViewsFactory(applicationContext, intent)
    }
}

class NoteChecklistRemoteViewsFactory(
    private val context: Context,
    private val intent: Intent
) : RemoteViewsService.RemoteViewsFactory {

    private val items = mutableListOf<ChecklistItemData>()

    override fun onCreate() {
        loadData()
    }

    override fun onDataSetChanged() {
        loadData()
    }

    private fun loadData() {
        items.clear()
        try {
            val widgetData = HomeWidgetPlugin.getData(context)
            val itemsJson = widgetData.getString("note_widget_items", "[]") ?: "[]"
            val jsonArray = JSONArray(itemsJson)
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                val text = obj.optString("text", "")
                val isChecked = obj.optBoolean("isChecked", false)
                items.add(ChecklistItemData(text, isChecked))
            }
        } catch (e: Exception) {
            Log.e("NoteChecklistService", "Error parsing checklist items: $e")
        }
    }

    override fun onDestroy() {
        items.clear()
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position < 0 || position >= items.size) {
            return RemoteViews(context.packageName, R.layout.note_checklist_item)
        }

        val item = items[position]
        val views = RemoteViews(context.packageName, R.layout.note_checklist_item)

        if (item.isChecked) {
            views.setImageViewResource(R.id.widget_item_checkbox, R.drawable.ic_check_circle_filled)
            val span = SpannableString(item.text)
            span.setSpan(StrikethroughSpan(), 0, span.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            views.setTextViewText(R.id.widget_item_text, span)
            views.setTextColor(R.id.widget_item_text, Color.parseColor("#94A3B8"))
        } else {
            views.setImageViewResource(R.id.widget_item_checkbox, R.drawable.ic_circle_outline)
            views.setTextViewText(R.id.widget_item_text, item.text)
            views.setTextColor(R.id.widget_item_text, Color.parseColor("#F1F5F9"))
        }

        // Fill-in intent for item tap to toggle
        val fillInIntent = Intent().apply {
            putExtra(NoteChecklistWidgetProvider.EXTRA_ITEM_INDEX, position)
        }
        views.setOnClickFillInIntent(R.id.widget_item_container, fillInIntent)

        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}
