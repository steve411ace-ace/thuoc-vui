package com.thuocvui.thuoc_vui

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Receiver riêng cho nút "Đã uống" trên widget (từ 1.2.6).
 *
 * Trước đây nút gửi broadcast về chính AppWidgetProvider. Trên một số máy
 * Samsung, sau lần bấm đầu, PendingIntent cũ bị launcher giữ lại làm lần
 * bấm sau không tới nữa ("bấm được 1 lần rồi chết"). Receiver riêng +
 * FLAG_CANCEL_CURRENT ở provider sẽ tạo PendingIntent mới mỗi lần cập
 * nhật widget, tránh tình trạng đó. Receiver cũng ghi lại lần bấm cuối
 * vào HomeWidgetPreferences để chẩn đoán trong Cài đặt của app.
 */
class WidgetCheckinReceiver : BroadcastReceiver() {
  companion object {
    const val ACTION_CHECKIN = "com.thuocvui.thuoc_vui.ACTION_WIDGET_CHECKIN"
  }

  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != ACTION_CHECKIN) return
    val widgetPrefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
    val timeStr = SimpleDateFormat("HH:mm:ss", Locale.US).format(Calendar.getInstance().time)
    try {
      val provider = ThuocVuiWidgetProvider()
      val result = provider.checkinNextDose(context)
      val tapInfo = if (result == null) {
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val hasData = ThuocVuiPrefs.read(flutterPrefs) != null
        if (hasData) {
          "$timeStr - đã bấm nhưng không có lần nào để uống (đã xong hết hoặc thuốc không active hôm nay)"
        } else {
          "$timeStr - đã bấm nhưng không đọc được dữ liệu"
        }
      } else {
        "$timeStr - đã uống $result"
      }
      widgetPrefs.edit().putString("last_widget_tap", tapInfo).apply()
      provider.refreshWidget(context)
    } catch (e: Exception) {
      try {
        widgetPrefs.edit().putString("last_widget_tap", "$timeStr - lỗi: ${e.message}").apply()
      } catch (_: Exception) {
      }
    }
  }
}
