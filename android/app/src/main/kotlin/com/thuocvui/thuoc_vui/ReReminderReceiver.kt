package com.thuocvui.thuoc_vui

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Báo lại tự động, kiểm tra log lúc báo mới hiện.
 *
 * Vì sao cần receiver riêng thay vì lịch của plugin flutter_local_notifications:
 * lịch plugin hiện thông báo vô điều kiện khi tới giờ, nên bấm đã uống trên
 * widget (ghi log trực tiếp bằng Kotlin, không qua Dart) sẽ không hủy được
 * lần báo lại đó. Receiver này đặt báo thức riêng bằng AlarmManager; khi báo
 * thức tới, nó đọc log hôm nay trong FlutterSharedPreferences trước: lần uống
 * đó đã uống/trễ/bỏ qua rồi thì không hiện thông báo nữa, bất kể lần đó được
 * bấm ở app, widget hay chính thông báo này. Chưa bấm thì mới hiện.
 * Báo thức tuần sẽ tự đặt lại cho tuần sau (+7 ngày) mỗi khi tới, nên không
 * cần mở app hàng tuần. Báo thức "Nhắc lại sau" là 1 lần, không đặt lại.
 */
class ReReminderReceiver : BroadcastReceiver() {
  companion object {
    const val ACTION_REMIND = "com.thuocvui.thuoc_vui.ACTION_REMIND"
    const val ACTION_SNOOZE_REMIND = "com.thuocvui.thuoc_vui.ACTION_SNOOZE_REMIND"
    const val ACTION_CHECKIN = "com.thuocvui.thuoc_vui.ACTION_REMIND_CHECKIN"
    const val ACTION_SCHEDULE_SNOOZE = "com.thuocvui.thuoc_vui.ACTION_SCHEDULE_SNOOZE"
    const val CHANNEL_ID = "thuoc_vui_reminder"
    private const val PREFS_NAME = "ThuocVuiReminders"
    private const val KEY_IDS = "ids"

    fun scheduleAlarm(
        context: Context,
        id: Int,
        action: String,
        triggerMillis: Long,
        title: String,
        body: String,
        medId: String,
        slotTime: String,
        intervalMinutes: Int,
        oneTime: Boolean,
        sound: Boolean = true,
        vibration: Boolean = true,
    ) {
      val intent = Intent(context, ReReminderReceiver::class.java).apply {
        this.action = action
        putExtra("id", id)
        putExtra("title", title)
        putExtra("body", body)
        putExtra("medId", medId)
        putExtra("slotTime", slotTime)
        putExtra("intervalMinutes", intervalMinutes)
        putExtra("oneTime", oneTime)
        putExtra("triggerMillis", triggerMillis)
        putExtra("sound", sound)
        putExtra("vibration", vibration)
      }
      val flags = PendingIntent.FLAG_UPDATE_CURRENT or
          if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
      val pending = PendingIntent.getBroadcast(context, id, intent, flags)
      val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
      try {
        if (Build.VERSION.SDK_INT >= 23) {
          alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMillis, pending)
        } else {
          alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerMillis, pending)
        }
      } catch (_: Exception) {
        // Máy chưa cấp quyền báo thức chính xác thì dùng lịch không chính xác.
        try {
          if (Build.VERSION.SDK_INT >= 23) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerMillis, pending)
          } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerMillis, pending)
          }
        } catch (_: Exception) {
        }
      }
      val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      val ids = prefs.getStringSet(KEY_IDS, emptySet())?.toMutableSet() ?: mutableSetOf()
      ids.add("$action|$id")
      prefs.edit().putStringSet(KEY_IDS, ids).apply()
    }

    fun cancelAlarm(context: Context, action: String, id: Int) {
      val intent = Intent(context, ReReminderReceiver::class.java).apply { this.action = action }
      val flags = PendingIntent.FLAG_UPDATE_CURRENT or
          if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
      val pending = PendingIntent.getBroadcast(context, id, intent, flags)
      val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
      try { alarmManager.cancel(pending) } catch (_: Exception) {}
    }

    fun cancelAllStored(context: Context) {
      val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      val ids = prefs.getStringSet(KEY_IDS, emptySet()) ?: emptySet()
      for (entry in ids) {
        val parts = entry.split("|")
        if (parts.size == 2) {
          val id = parts[1].toIntOrNull() ?: continue
          cancelAlarm(context, parts[0], id)
        }
      }
      prefs.edit().remove(KEY_IDS).apply()
    }
  }

  override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
      ACTION_CHECKIN -> {
        val slotKey = intent.getStringExtra("slotKey") ?: return
        val notificationId = intent.getIntExtra("notificationId", 0)
        markTaken(context, slotKey)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try { manager.cancel(notificationId) } catch (_: Exception) {}
        return
      }
      ACTION_SCHEDULE_SNOOZE -> {
        val notificationId = intent.getIntExtra("notificationId", 0)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try { manager.cancel(notificationId) } catch (_: Exception) {}
        val interval = intent.getIntExtra("intervalMinutes", 10)
        val safeInterval = if (interval > 0) interval else 10
        val trigger = System.currentTimeMillis() + safeInterval * 60L * 1000L
        // Dùng action riêng cho báo thức nhắc lại sau, để không ghi đè
        // PendingIntent của báo thức tuần (cùng id, khác action là khác nhau).
        scheduleAlarm(
            context,
            intent.getIntExtra("id", 0),
            ACTION_SNOOZE_REMIND,
            trigger,
            intent.getStringExtra("title") ?: "Nhắc lại: đến giờ uống thuốc!",
            intent.getStringExtra("body") ?: "",
            intent.getStringExtra("medId") ?: "",
            intent.getStringExtra("slotTime") ?: "",
            safeInterval,
            true,
            intent.getBooleanExtra("sound", true),
            intent.getBooleanExtra("vibration", true),
        )
        return
      }
      else -> {
        // Báo thức báo lại tới (ACTION_REMIND hoặc không có action).
        val id = intent.getIntExtra("id", 0)
        val medId = intent.getStringExtra("medId") ?: ""
        val slotTime = intent.getStringExtra("slotTime") ?: ""
        val oneTime = intent.getBooleanExtra("oneTime", false)
        val triggerMillis = intent.getLongExtra("triggerMillis", 0L)
        // Đặt lại cho tuần sau trước, kể cả khi lần này không hiện (đã uống
        // rồi), để tuần sau vẫn có báo lại mà không cần mở app.
        if (!oneTime && triggerMillis > 0L) {
          scheduleAlarm(
              context,
              id,
              ACTION_REMIND,
              triggerMillis + 7L * 24L * 60L * 60L * 1000L,
              intent.getStringExtra("title") ?: "",
              intent.getStringExtra("body") ?: "",
              medId,
              slotTime,
              intent.getIntExtra("intervalMinutes", 10),
              false,
              intent.getBooleanExtra("sound", true),
              intent.getBooleanExtra("vibration", true),
          )
        }
        if (medId.isEmpty() || slotTime.isEmpty()) return
        if (isCompletedToday(context, medId, slotTime)) return
        showNotification(context, intent, id)
      }
    }
  }

  private fun todayStr(): String {
    return SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Calendar.getInstance().time)
  }

  private fun isCompletedToday(context: Context, medId: String, slotTime: String): Boolean {
    try {
      val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
      var raw: String? = flutterPrefs.getString("thuoc_vui_v1", null)
      if (raw == null) {
        for ((key, value) in flutterPrefs.all) {
          if (key.endsWith("thuoc_vui_v1") && value is String) {
            raw = value
            break
          }
        }
      }
      if (raw.isNullOrEmpty()) return false
      val data = JSONObject(raw)
      val logs = data.optJSONObject("logs") ?: return false
      val status = logs.optJSONObject("$medId|${todayStr()}|$slotTime")?.optString("status")
      return status == "taken" || status == "late" || status == "skipped"
    } catch (_: Exception) {
      return false
    }
  }

  private fun markTaken(context: Context, slotKey: String) {
    try {
      val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
      var raw: String? = flutterPrefs.getString("thuoc_vui_v1", null)
      var rawKey: String? = "thuoc_vui_v1"
      if (raw == null) {
        for ((key, value) in flutterPrefs.all) {
          if (key.endsWith("thuoc_vui_v1") && value is String) {
            raw = value
            rawKey = key
            break
          }
        }
      }
      if (raw.isNullOrEmpty() || rawKey == null) return
      val data = JSONObject(raw)
      val logs = data.optJSONObject("logs") ?: JSONObject()
      val existing = logs.optJSONObject(slotKey)?.optString("status")
      if (existing == "taken" || existing == "late" || existing == "skipped") return
      val parts = slotKey.split("|")
      var status = "taken"
      if (parts.size == 3) {
        val timeParts = parts[2].split(":")
        if (timeParts.size == 2) {
          val hour = timeParts[0].toIntOrNull()
          val minute = timeParts[1].toIntOrNull()
          if (hour != null && minute != null) {
            val slotCal = Calendar.getInstance().apply {
              set(Calendar.HOUR_OF_DAY, hour)
              set(Calendar.MINUTE, minute)
              set(Calendar.SECOND, 0)
              set(Calendar.MILLISECOND, 0)
            }
            slotCal.add(Calendar.MINUTE, 30)
            if (Calendar.getInstance().after(slotCal)) status = "late"
          }
        }
      }
      val atFmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
      val logObj = JSONObject().apply {
        put("status", status)
        put("at", atFmt.format(Calendar.getInstance().time))
        put("reason", "")
      }
      logs.put(slotKey, logObj)
      data.put("logs", logs)
      flutterPrefs.edit().putString(rawKey, data.toString()).apply()
    } catch (_: Exception) {
    }
  }

  private fun showNotification(context: Context, intent: Intent, id: Int) {
    try {
      val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      val sound = intent.getBooleanExtra("sound", true)
      val vibration = intent.getBooleanExtra("vibration", true)
      if (Build.VERSION.SDK_INT >= 26) {
        // Xóa kênh cũ rồi tạo lại, vì kênh đã tạo thì đổi âm thanh/rung
        // sẽ không có tác dụng (hệ thống giữ kênh cũ).
        try { manager.deleteNotificationChannel(CHANNEL_ID) } catch (_: Exception) {}
        val channel = NotificationChannel(
            CHANNEL_ID, "Nhắc uống thuốc", NotificationManager.IMPORTANCE_HIGH)
        channel.description = "Nhắc uống thuốc đúng giờ mỗi ngày"
        channel.enableVibration(vibration)
        if (vibration) {
          channel.vibrationPattern = longArrayOf(0L, 500L, 250L, 500L)
        } else {
          channel.vibrationPattern = longArrayOf(0L)
        }
        if (!sound) {
          channel.setSound(null, null)
        }
        try { manager.createNotificationChannel(channel) } catch (_: Exception) {}
      }
      val medId = intent.getStringExtra("medId") ?: ""
      val slotTime = intent.getStringExtra("slotTime") ?: ""
      val slotKey = "$medId|${todayStr()}|$slotTime"
      val title = intent.getStringExtra("title") ?: "Nhắc lại: đến giờ uống thuốc!"
      val body = intent.getStringExtra("body") ?: ""
      val interval = intent.getIntExtra("intervalMinutes", 10)

      val openIntent = Intent(context, MainActivity::class.java)
      val openFlags = PendingIntent.FLAG_UPDATE_CURRENT or
          if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
      val openPending = PendingIntent.getActivity(context, id, openIntent, openFlags)

      val checkinIntent = Intent(context, ReReminderReceiver::class.java).apply {
        action = ACTION_CHECKIN
        putExtra("slotKey", slotKey)
        putExtra("notificationId", id)
      }
      val checkinPending = PendingIntent.getBroadcast(context, id, checkinIntent, openFlags)

      val snoozeIntent = Intent(context, ReReminderReceiver::class.java).apply {
        action = ACTION_SCHEDULE_SNOOZE
        putExtra("notificationId", id)
        putExtra("id", id)
        putExtra("title", title)
        putExtra("body", body)
        putExtra("medId", medId)
        putExtra("slotTime", slotTime)
        putExtra("intervalMinutes", interval)
        putExtra("sound", sound)
        putExtra("vibration", vibration)
      }
      val snoozePending = PendingIntent.getBroadcast(context, id, snoozeIntent, openFlags)

      val builder = if (Build.VERSION.SDK_INT >= 26) {
        Notification.Builder(context, CHANNEL_ID)
      } else {
        @Suppress("DEPRECATION")
        Notification.Builder(context)
      }
      builder
          .setSmallIcon(R.mipmap.ic_launcher)
          .setContentTitle(title)
          .setContentText(body)
          .setStyle(Notification.BigTextStyle().bigText(body))
          .setContentIntent(openPending)
          .setAutoCancel(true)
          .addAction(0, "Đã uống", checkinPending)
          .addAction(0, "Nhắc lại sau", snoozePending)
      manager.notify(id, builder.build())
    } catch (_: Exception) {
    }
  }
}
