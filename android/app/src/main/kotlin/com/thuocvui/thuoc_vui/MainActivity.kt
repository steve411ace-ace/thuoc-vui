package com.thuocvui.thuoc_vui

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // Kênh native cho báo lại: Dart gửi danh sách báo thức, native đặt
    // AlarmManager cho ReReminderReceiver. Receiver này kiểm tra log lúc
    // báo mới hiện, nên bấm đã uống ở app, widget hay thông báo đều
    // dừng báo lại cho lần đó.
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "thuoc_vui/reminders")
        .setMethodCallHandler { call, result ->
          try {
            when (call.method) {
              "scheduleReReminders" -> {
                ReReminderReceiver.cancelAllStored(this)
                val alarms = call.argument<List<Map<String, Any>>>("alarms") ?: emptyList()
                for (alarm in alarms) {
                  val id = (alarm["id"] as? Number)?.toInt() ?: continue
                  val trigger = (alarm["triggerMillis"] as? Number)?.toLong() ?: continue
                  val title = alarm["title"] as? String ?: ""
                  val body = alarm["body"] as? String ?: ""
                  val medId = alarm["medId"] as? String ?: ""
                  val slotTime = alarm["slotTime"] as? String ?: ""
                  val interval = (alarm["intervalMinutes"] as? Number)?.toInt() ?: 10
                  ReReminderReceiver.scheduleAlarm(
                      this,
                      id,
                      ReReminderReceiver.ACTION_REMIND,
                      trigger,
                      title,
                      body,
                      medId,
                      slotTime,
                      interval,
                      false,
                  )
                }
                result.success(null)
              }
              "cancelReReminders" -> {
                ReReminderReceiver.cancelAllStored(this)
                result.success(null)
              }
              else -> result.notImplemented()
            }
          } catch (_: Exception) {
            result.error("REMINDER_ERROR", "Không đặt được báo lại", null)
          }
        }
  }
}
