package com.thuocvui.thuoc_vui

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

class ThuocVuiWidgetProvider : HomeWidgetProvider() {
  companion object {
    const val ACTION_CHECKIN = "com.thuocvui.thuoc_vui.ACTION_CHECKIN"
  }

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
        setTextViewText(R.id.widget_pip, widgetData.getString("pip_message", null) ?: "😊 Pip đang nhắc bạn uống thuốc đúng giờ nhé!")
        setTextViewText(R.id.widget_progress, widgetData.getString("progress", null) ?: "Thuốc Vui")
        setTextViewText(R.id.widget_next, widgetData.getString("next_text", null) ?: "Mở app để xem lịch hôm nay")
        setTextViewText(R.id.widget_next_time, widgetData.getString("next_time", null) ?: "")
        val allDone = widgetData.getString("all_done", null) == "1"
        if (allDone) {
          setViewVisibility(R.id.widget_checkin, View.GONE)
          setViewVisibility(R.id.widget_done, View.VISIBLE)
          // Trước đây cả widget_next ("🎉 Đã xong hôm nay!" từ dữ liệu
          // next_text) và widget_done đều hiện cùng lúc nên bị trùng 2 dòng.
          // Khi đã xong thì chỉ hiện widget_done, ẩn 2 dòng next đi.
          setViewVisibility(R.id.widget_next, View.GONE)
          setViewVisibility(R.id.widget_next_time, View.GONE)
        } else {
          setViewVisibility(R.id.widget_checkin, View.VISIBLE)
          setViewVisibility(R.id.widget_done, View.GONE)
          setViewVisibility(R.id.widget_next, View.VISIBLE)
          setViewVisibility(R.id.widget_next_time, View.VISIBLE)
          // Bấm trực tiếp trên widget: gửi broadcast về chính provider này,
          // provider tự ghi check-in bằng Kotlin (không qua Dart background
          // engine / JobIntentService của plugin, vốn hay bị Samsung và
          // Android 12+ trì hoãn hoặc chặn, nên bấm mà không thấy gì).
          val checkinIntent = Intent(context, ThuocVuiWidgetProvider::class.java).apply {
            action = ACTION_CHECKIN
          }
          val flags = PendingIntent.FLAG_UPDATE_CURRENT or
              if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
          val pending = PendingIntent.getBroadcast(context, widgetId, checkinIntent, flags)
          setOnClickPendingIntent(R.id.widget_checkin, pending)
        }
      }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == ACTION_CHECKIN) {
      try {
        checkinNextDose(context)
      } catch (_: Exception) {
        // Không làm gì thêm: widget vẫn hiện, người dùng bấm lại hoặc mở app.
      }
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(ComponentName(context, ThuocVuiWidgetProvider::class.java))
      if (ids.isNotEmpty()) {
        onUpdate(context, manager, ids, context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE))
      }
      return
    }
    super.onReceive(context, intent)
  }

  private fun formEmoji(form: String): String = when (form) {
    "nuoc" -> "\uD83D\uDCA7"
    "tiem" -> "\uD83D\uDC89"
    "xit" -> "\uD83C\uDF2C\uFE0F"
    else -> "\uD83D\uDC8A"
  }

  private fun mealLabel(mealNote: String): String = when (mealNote) {
    "truoc_an" -> "Uống trước ăn"
    "sau_an" -> "Uống sau ăn"
    else -> "Không dặn trước/sau ăn"
  }

  private fun checkinNextDose(context: Context) {
    val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    var raw: String? = flutterPrefs.getString("thuoc_vui_v1", null)
    if (raw == null) {
      // Một số bản shared_preferences cũ lưu key có tiền tố flutter.
      for ((key, value) in flutterPrefs.all) {
        if (key.endsWith("thuoc_vui_v1") && value is String) {
          raw = value
          break
        }
      }
    }
    if (raw.isNullOrEmpty()) return
    val data = JSONObject(raw)
    val medicines = data.optJSONArray("medicines") ?: JSONArray()
    val logs = data.optJSONObject("logs") ?: JSONObject()

    val now = Calendar.getInstance()
    val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now.time)
    // Calendar: Chủ nhật=1 ... Thứ 7=7; Dart weekday: Thứ 2=1 ... Chủ nhật=7.
    val dartWeekday = if (now.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY) 7
        else now.get(Calendar.DAY_OF_WEEK) - 1
    val dateFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    data class Slot(val med: JSONObject, val time: String, val key: String, val dateTime: Calendar)
    val slots = mutableListOf<Slot>()
    for (i in 0 until medicines.length()) {
      val med = medicines.getJSONObject(i)
      val start = try { dateFmt.parse(med.optString("startDate")) } catch (_: Exception) { null }
      if (start != null && now.time.before(start) && SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now.time) != med.optString("startDate")) {
        // So sánh theo ngày, không theo giờ.
        val startCal = Calendar.getInstance().apply { time = start }
        if (now.get(Calendar.YEAR) < startCal.get(Calendar.YEAR) ||
            (now.get(Calendar.YEAR) == startCal.get(Calendar.YEAR) && now.get(Calendar.DAY_OF_YEAR) < startCal.get(Calendar.DAY_OF_YEAR))) {
          continue
        }
      }
      val endStr = med.optString("endDate", "")
      if (endStr.isNotEmpty()) {
        val end = try { dateFmt.parse(endStr) } catch (_: Exception) { null }
        if (end != null) {
          val endCal = Calendar.getInstance().apply { time = end }
          if (now.get(Calendar.YEAR) > endCal.get(Calendar.YEAR) ||
              (now.get(Calendar.YEAR) == endCal.get(Calendar.YEAR) && now.get(Calendar.DAY_OF_YEAR) > endCal.get(Calendar.DAY_OF_YEAR))) {
            continue
          }
        }
      }
      val weekdays = med.optJSONArray("weekdays") ?: JSONArray()
      var active = false
      for (j in 0 until weekdays.length()) {
        if (weekdays.optInt(j) == dartWeekday) { active = true; break }
      }
      if (!active) continue
      val times = med.optJSONArray("times") ?: JSONArray()
      for (j in 0 until times.length()) {
        val time = times.optString(j)
        val parts = time.split(":")
        if (parts.size != 2) continue
        // Không dùng ?: continue trong apply (Kotlin 1.8 coi đó là tính năng
        // thử nghiệm): tính giờ/phút trước, rồi mới tạo Calendar.
        val hour = parts[0].toIntOrNull() ?: continue
        val minute = parts[1].toIntOrNull() ?: continue
        val slotCal = Calendar.getInstance().apply {
          set(Calendar.HOUR_OF_DAY, hour)
          set(Calendar.MINUTE, minute)
          set(Calendar.SECOND, 0)
          set(Calendar.MILLISECOND, 0)
        }
        slots.add(Slot(med, time, "${med.optString("id")}|$todayStr|$time", slotCal))
      }
    }
    slots.sortBy { it.time }
    var next: Slot? = null
    for (s in slots) {
      val st = logs.optJSONObject(s.key)?.optString("status")
      if (st != "taken" && st != "late") { next = s; break }
    }
    if (next == null) return

    val lateThreshold = (next.dateTime.clone() as Calendar).apply { add(Calendar.MINUTE, 30) }
    val status = if (now.after(lateThreshold)) "late" else "taken"
    val atFmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US)
    val logObj = JSONObject().apply {
      put("status", status)
      put("at", atFmt.format(Date()))
      put("reason", "")
    }
    logs.put(next.key, logObj)
    data.put("logs", logs)
    flutterPrefs.edit().putString("thuoc_vui_v1", data.toString()).apply()

    // Cập nhật dữ liệu widget giống hệt Dart updateHomeWidget().
    var completed = 0
    var onTime = 0
    var following: Slot? = null
    for (s in slots) {
      val st = logs.optJSONObject(s.key)?.optString("status")
      if (st == "taken" || st == "late") completed++
      if (st == "taken") onTime++
      if (following == null && st != "taken" && st != "late") following = s
    }
    val widgetPrefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE).edit()
    // Trạng thái Pip lên widget (giống trong app, trừ chuỗi đúng giờ dài ngày:
    // tính chuỗi cần lịch sử nhiều ngày nên Kotlin chỉ làm trường hợp cơ bản,
    // mở app sẽ được Dart updateHomeWidget() làm đầy đủ lại).
    var skipped = 0
    var overdue = false
    for (s in slots) {
      val st = logs.optJSONObject(s.key)?.optString("status")
      if (st == "skipped") skipped++
      if (st != "taken" && st != "late" && st != "skipped" && s.dateTime.before(now)) overdue = true
    }
    val pipMessage = when {
      slots.isEmpty() -> "😊 Thêm thuốc để Pip nhắc bạn nhé!"
      onTime == slots.size -> "🥳 Hôm nay uống đủ và đúng giờ hết rồi, tuyệt vời!"
      completed == slots.size -> "😊 Hôm nay uống đủ hết rồi, có ${completed - onTime} lần trễ, lần sau cố đúng giờ nhé!"
      overdue -> "😟 Ơ, có lần uống quá giờ chưa thấy bạn bấm, uống bù nhé?"
      skipped > 0 -> "😟 Hôm nay bạn bỏ qua $skipped lần, mai cố nhé?"
      else -> "😊 Hôm nay còn ${slots.size - completed} lần nữa là xong, cố lên nhé!"
    }
    widgetPrefs.putString("pip_message", pipMessage)
    widgetPrefs.putString(
        "progress",
        if (slots.isEmpty()) "Chưa có thuốc hôm nay"
        else "Hôm nay: $completed/${slots.size} lần • đúng giờ $onTime lần")
    if (following == null) {
      widgetPrefs.putString("next_text", if (slots.isEmpty()) "Thêm thuốc để Pip nhắc bạn nhé!" else "🎉 Đã xong hôm nay!")
      widgetPrefs.putString("next_time", "")
    } else {
      widgetPrefs.putString("next_text", "${formEmoji(following.med.optString("form"))} ${following.med.optString("name")} — ${following.med.optString("dose")}")
      widgetPrefs.putString("next_time", "Lúc ${following.time} • ${mealLabel(following.med.optString("mealNote"))}")
    }
    widgetPrefs.putString("all_done", if (following == null && slots.isNotEmpty()) "1" else "0")
    widgetPrefs.apply()
  }
}
