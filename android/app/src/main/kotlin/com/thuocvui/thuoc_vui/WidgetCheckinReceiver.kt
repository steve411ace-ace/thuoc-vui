package com.thuocvui.thuoc_vui

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Receiver riêng cho nút "Đã uống" trên widget (từ 1.2.6).
 *
 * Trước đây nút gửi broadcast về chính AppWidgetProvider. Trên một số máy
 * Samsung, sau lần bấm đầu, PendingIntent cũ bị launcher giữ lại làm lần
 * bấm sau không tới nữa ("bấm được 1 lần rồi chết"). Receiver riêng +
 * FLAG_CANCEL_CURRENT ở provider sẽ tạo PendingIntent mới mỗi lần cập
 * nhật widget, tránh tình trạng đó.
 */
class WidgetCheckinReceiver : BroadcastReceiver() {
  companion object {
    const val ACTION_CHECKIN = "com.thuocvui.thuoc_vui.ACTION_WIDGET_CHECKIN"
  }

  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != ACTION_CHECKIN) return
    try {
      val provider = ThuocVuiWidgetProvider()
      provider.checkinNextDose(context)
      provider.refreshWidget(context)
    } catch (_: Exception) {
    }
  }
}
