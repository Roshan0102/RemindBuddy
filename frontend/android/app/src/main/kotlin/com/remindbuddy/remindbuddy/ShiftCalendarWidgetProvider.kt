package com.remindbuddy.remindbuddy

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

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
        val widgetData = HomeWidgetPlugin.getData(context)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.shift_calendar_widget_layout).apply {
                // Dynamically format current month name (e.g. "September 2026") - NEVER use "This Month"!
                val currentMonth = SimpleDateFormat("MMMM yyyy", Locale.getDefault()).format(Date())
                val monthTitle = widgetData?.getString("shift_calendar_month", null) ?: currentMonth
                setTextViewText(R.id.widget_shift_calendar_month, monthTitle)

                // Always generate and display the calendar bitmap
                var bitmap: Bitmap? = null
                val imagePath = widgetData?.getString("shift_calendar_image_path", null)
                if (!imagePath.isNullOrEmpty()) {
                    val imgFile = File(imagePath)
                    if (imgFile.exists()) {
                        try {
                            val options = BitmapFactory.Options().apply {
                                inPreferredConfig = Bitmap.Config.RGB_565
                            }
                            bitmap = BitmapFactory.decodeFile(imagePath, options)
                        } catch (_: Exception) {
                            bitmap = null
                        }
                    }
                }

                // If image is missing or cannot be decoded, immediately draw native canvas bitmap
                if (bitmap == null) {
                    try {
                        bitmap = drawCalendarBitmap(context, widgetData)
                    } catch (_: Exception) {
                        bitmap = null
                    }
                }

                if (bitmap != null) {
                    setImageViewBitmap(R.id.widget_shift_calendar_image, bitmap)
                    setViewVisibility(R.id.widget_shift_calendar_image, View.VISIBLE)
                }
                setViewVisibility(R.id.widget_shift_calendar_empty, View.GONE)

                // Launch RemindBuddy directly on shifts screen on click
                val pendingIntent = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("remindbuddy://feature/shifts")
                )
                setOnClickPendingIntent(R.id.widget_shift_calendar_root, pendingIntent)
            }

            try {
                appWidgetManager.updateAppWidget(appWidgetId, views)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun drawCalendarBitmap(context: Context, widgetData: SharedPreferences?): Bitmap {
        val size = 420
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565)
        val canvas = Canvas(bitmap)

        // 1. Background Card
        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0F141C")
        }
        val bgRect = RectF(0f, 0f, size.toFloat(), size.toFloat())
        canvas.drawRoundRect(bgRect, 20f, 20f, bgPaint)

        // Card Border
        val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#1E293B")
            style = Paint.Style.STROKE
            strokeWidth = 2f
        }
        canvas.drawRoundRect(bgRect, 20f, 20f, borderPaint)

        // 2. Weekday headers
        val weekdays = arrayOf("Su", "Mo", "Tu", "We", "Th", "Fr", "Sa")
        val marginX = 14f
        val gridWidth = size - (2 * marginX)
        val colWidth = gridWidth / 7f

        val weekdayPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#64748B")
            textSize = 15f
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }

        val weekdayY = 24f
        for (i in 0 until 7) {
            val cx = marginX + (i * colWidth) + (colWidth / 2f)
            canvas.drawText(weekdays[i], cx, weekdayY, weekdayPaint)
        }

        // 3. Days Grid Setup
        val cal = Calendar.getInstance()
        val year = cal.get(Calendar.YEAR)
        val month = cal.get(Calendar.MONTH) // 0-indexed
        val todayDay = cal.get(Calendar.DAY_OF_MONTH)

        val tempCal = Calendar.getInstance().apply {
            set(Calendar.YEAR, year)
            set(Calendar.MONTH, month)
            set(Calendar.DAY_OF_MONTH, 1)
        }
        val firstDayOfWeek = tempCal.get(Calendar.DAY_OF_WEEK) - 1 // 0 for Sunday
        val maxDays = tempCal.getActualMaximum(Calendar.DAY_OF_MONTH)

        // Parse shifts JSON if present
        var shiftsJson: JSONObject? = null
        val rawJson = widgetData?.getString("shift_calendar_shifts_json", null)
        if (!rawJson.isNullOrEmpty()) {
            try {
                shiftsJson = JSONObject(rawJson)
            } catch (_: Exception) {}
        }

        val gridTop = 36f
        val gridBottom = 384f
        val gridHeight = gridBottom - gridTop
        val spacing = 4f
        val cellW = (gridWidth - (6 * spacing)) / 7f
        val numRows = Math.ceil((firstDayOfWeek + maxDays) / 7.0).toInt().coerceAtLeast(5)
        val cellH = (gridHeight - ((numRows - 1) * spacing)) / numRows.toFloat()

        val cellBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#1E2638")
        }
        val cellStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1f
            color = Color.parseColor("#263248")
        }
        val todayStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2.5f
            color = Color.parseColor("#38BDF8")
        }
        val dayNumPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            textSize = 14f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val badgeTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            textSize = 10f
            color = Color.WHITE
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }

        for (day in 1..maxDays) {
            val slotIndex = (day - 1) + firstDayOfWeek
            val col = slotIndex % 7
            val row = slotIndex / 7

            val cellLeft = marginX + (col * (cellW + spacing))
            val cellTop = gridTop + (row * (cellH + spacing))
            val cellRect = RectF(cellLeft, cellTop, cellLeft + cellW, cellTop + cellH)

            val isToday = (day == todayDay)

            // Cell Background
            canvas.drawRoundRect(cellRect, 6f, 6f, cellBgPaint)
            // Cell Border
            if (isToday) {
                canvas.drawRoundRect(cellRect, 6f, 6f, todayStrokePaint)
            } else {
                canvas.drawRoundRect(cellRect, 6f, 6f, cellStrokePaint)
            }

            // Day Number
            dayNumPaint.color = if (isToday) Color.parseColor("#38BDF8") else Color.parseColor("#E2E8F0")
            val numY = cellTop + 15f
            canvas.drawText(day.toString(), cellRect.centerX(), numY, dayNumPaint)

            // Shift Badge
            val dateKey = String.format(Locale.US, "%04d-%02d-%02d", year, month + 1, day)
            val shiftType = shiftsJson?.optString(dateKey, null)

            if (!shiftType.isNullOrEmpty()) {
                val lower = shiftType.lowercase(Locale.US)
                val (badgeColor, badgeLabel) = when {
                    lower.contains("morning") || lower == "m" -> Pair(Color.parseColor("#F59E0B"), "M")
                    lower.contains("afternoon") || lower.contains("evening") || lower == "a" -> Pair(Color.parseColor("#06B6D4"), "A")
                    lower.contains("night") || lower == "n" -> Pair(Color.parseColor("#8B5CF6"), "N")
                    lower.contains("off") || lower.contains("leave") || lower == "wo" -> Pair(Color.parseColor("#10B981"), "OFF")
                    lower.contains("general") || lower == "g" -> Pair(Color.parseColor("#3B82F6"), "G")
                    else -> Pair(Color.parseColor("#6366F1"), shiftType.take(1).uppercase(Locale.US))
                }

                val badgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = badgeColor
                }
                val badgeH = 15f
                val badgeW = cellW - 6f
                val badgeLeft = cellLeft + 3f
                val badgeTop = cellTop + cellH - badgeH - 3f
                val badgeRect = RectF(badgeLeft, badgeTop, badgeLeft + badgeW, badgeTop + badgeH)

                canvas.drawRoundRect(badgeRect, 4f, 4f, badgePaint)
                canvas.drawText(badgeLabel, badgeRect.centerX(), badgeTop + 11.5f, badgeTextPaint)
            }
        }

        // 4. Legend at bottom
        val legendPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 11f
            color = Color.parseColor("#94A3B8")
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val legendY = 407f
        val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG)

        val items = listOf(
            Pair("#F59E0B", "M: Morn"),
            Pair("#06B6D4", "A: Aft"),
            Pair("#8B5CF6", "N: Night"),
            Pair("#10B981", "OFF")
        )

        val itemSpacing = gridWidth / items.size.toFloat()
        for (i in items.indices) {
            val item = items[i]
            val startX = marginX + (i * itemSpacing) + 6f
            dotPaint.color = Color.parseColor(item.first)
            canvas.drawCircle(startX, legendY - 3.5f, 4f, dotPaint)
            canvas.drawText(item.second, startX + 8f, legendY, legendPaint)
        }

        return bitmap
    }
}
