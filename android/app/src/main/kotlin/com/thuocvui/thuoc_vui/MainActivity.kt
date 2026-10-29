package com.thuocvui.thuoc_vui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
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
                  val sound = alarm["sound"] as? Boolean ?: true
                  val vibration = alarm["vibration"] as? Boolean ?: true
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
                      sound,
                      vibration,
                  )
                }
                result.success(null)
              }
              "cancelReReminders" -> {
                ReReminderReceiver.cancelAllStored(this)
                result.success(null)
              }
              "scheduleNativeTest" -> {
                // Nhắc thử native sau 1 phút, 1 lần, không đặt lại tuần sau.
                // medId/slotTime giả "test"/"00:00" để receiver không chặn
                // vì đã uống (log test không bao giờ có trạng thái).
                ReReminderReceiver.scheduleAlarm(
                    this,
                    999997,
                    ReReminderReceiver.ACTION_REMIND,
                    System.currentTimeMillis() + 60L * 1000L,
                    "Nhắc thử native sau 1 phút",
                    "Báo thức native hoạt động bình thường.",
                    "test",
                    "00:00",
                    10,
                    true,
                    true,
                    true,
                )
                result.success(null)
              }
              "isIgnoringBatteryOptimizations" -> {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(packageName))
              }
              "requestIgnoreBatteryOptimizations" -> {
                // Mở hộp xin miễn tối ưu pin của hệ thống. Samsung hay
                // đưa app vào danh sách ngủ, làm báo thức theo lịch bị
                // chặn dù thông báo gửi ngay vẫn hiện.
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                  data = Uri.parse("package:$packageName")
                }
                try {
                  startActivity(intent)
                  result.success(true)
                } catch (_: Exception) {
                  try {
                    startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    result.success(true)
                  } catch (_: Exception) {
                    result.success(false)
                  }
                }
              }
              else -> result.notImplemented()
            }
          } catch (_: Exception) {
            result.error("REMINDER_ERROR", "Không đặt được báo lại", null)
          }
        }
  }
}
