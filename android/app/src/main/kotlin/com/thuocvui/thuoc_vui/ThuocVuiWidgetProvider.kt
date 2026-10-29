package com.thuocvui.thuoc_vui

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class ThuocVuiWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.thuoc_vui_widget).apply {
        val openIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        setOnClickPendingIntent(R.id.widget_container, openIntent)
        setTextViewText(R.id.widget_progress, widgetData.getString("progress", null) ?: "Thuốc Vui")
        setTextViewText(R.id.widget_next, widgetData.getString("next_text", null) ?: "Mở app để xem lịch hôm nay")
        setTextViewText(R.id.widget_next_time, widgetData.getString("next_time", null) ?: "")
        val allDone = widgetData.getString("all_done", null) == "1"
        if (allDone) {
          setViewVisibility(R.id.widget_checkin, View.GONE)
          setViewVisibility(R.id.widget_done, View.VISIBLE)
        } else {
          setViewVisibility(R.id.widget_checkin, View.VISIBLE)
          setViewVisibility(R.id.widget_done, View.GONE)
          val checkinIntent = HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("thuocvui://checkin"))
          setOnClickPendingIntent(R.id.widget_checkin, checkinIntent)
        }
      }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
