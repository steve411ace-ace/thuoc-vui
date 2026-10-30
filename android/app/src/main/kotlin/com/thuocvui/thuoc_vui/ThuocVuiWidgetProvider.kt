package com.thuocvui.thuoc_vui

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
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
        // Giao diện widget (1.2.13): app lưu lựa chọn thô vào
        // HomeWidgetPreferences key "widget_theme" ('system'/'light'/'dark').
        // 'system' = theo chế độ tối của máy, trên Samsung chính là
        // chế độ Tối của One UI (uiMode night): One UI bật tối thì
        // widget tối theo, không cần cài riêng cho widget. Chọn Sáng/Tối
        // trong app thì widget theo app, ghi đè One UI.
        val themeMode = widgetData.getString("widget_theme", null) ?: "system"
        val isDark = when (themeMode) {
          "dark" -> true
          "light" -> false
          else -> (context.resources.configuration.uiMode and
              Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        }
        // Độ mờ widget (1.2.18, mở rộng 0-100% ở 1.2.26): Dart lưu
        // widget_opacity (%) vào HomeWidgetPreferences, mặc định 100.
        // Drawable có đủ các mức 0/10/.../100 nên làm tròn về mức 10%
        // gần nhất; nền khối lần uống tiếp theo giữ đặc để chữ còn
        // đọc được khi nền mờ.
        val opacityRaw = widgetData.getString("widget_opacity", null)?.toIntOrNull() ?: 100
        val opacity = when {
          opacityRaw < 0 -> 0
          opacityRaw > 100 -> 100
          else -> ((opacityRaw + 5) / 10 * 10)
        }
        val bgRes = when {
          opacity >= 100 -> if (isDark) R.drawable.widget_background_dark else R.drawable.widget_background
          opacity >= 90 -> if (isDark) R.drawable.widget_background_dark_90 else R.drawable.widget_background_90
          opacity >= 80 -> if (isDark) R.drawable.widget_background_dark_80 else R.drawable.widget_background_80
          opacity >= 70 -> if (isDark) R.drawable.widget_background_dark_70 else R.drawable.widget_background_70
          opacity >= 60 -> if (isDark) R.drawable.widget_background_dark_60 else R.drawable.widget_background_60
          opacity >= 50 -> if (isDark) R.drawable.widget_background_dark_50 else R.drawable.widget_background_50
          opacity >= 40 -> if (isDark) R.drawable.widget_background_dark_40 else R.drawable.widget_background_40
          opacity >= 30 -> if (isDark) R.drawable.widget_background_dark_30 else R.drawable.widget_background_30
          opacity >= 20 -> if (isDark) R.drawable.widget_background_dark_20 else R.drawable.widget_background_20
          opacity >= 10 -> if (isDark) R.drawable.widget_background_dark_10 else R.drawable.widget_background_10
          else -> if (isDark) R.drawable.widget_background_dark_0 else R.drawable.widget_background_0
        }
        setInt(R.id.widget_container, "setBackgroundResource", bgRes)
        setInt(R.id.widget_next_card, "setBackgroundResource", if (isDark) R.drawable.next_card_dark else R.drawable.next_card_light)
        // Thanh tiến độ hôm nay (1.2.18): Dart/Kotlin đều lưu progress_pct.
        val pct = widgetData.getString("progress_pct", null)?.toIntOrNull() ?: 0
        setProgressBar(R.id.widget_progress_bar, 100, pct.coerceIn(0, 100), false)
        val mainText = if (isDark) Color.parseColor("#EDEDED") else Color.parseColor("#333333")
        val subText = if (isDark) Color.parseColor("#B8C4C2") else Color.parseColor("#666666")
        setTextColor(R.id.widget_title, mainText)
        setTextColor(R.id.widget_datetime, subText)
        setTextColor(R.id.widget_pip, mainText)
        setTextColor(R.id.widget_progress, mainText)
        setTextColor(R.id.widget_next, mainText)
        setTextColor(R.id.widget_next_time, subText)
        setTextColor(R.id.widget_done, mainText)
        setTextColor(R.id.widget_done_detail, subText)
        setTextViewText(R.id.widget_done_detail, widgetData.getString("done_detail", null) ?: "")
        // Nút teal + chữ trắng giữ nguyên cả sáng lẫn tối.
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
          setViewVisibility(R.id.widget_done_detail, View.VISIBLE)
          // Trước đây cả widget_next ("🎉 Đã xong hôm nay!" từ dữ liệu
          // next_text) và widget_done đều hiện cùng lúc nên bị trùng 2 dòng.
          // Khi đã xong thì chỉ hiện widget_done, ẩn 2 dòng next đi.
          setViewVisibility(R.id.widget_next_card, View.GONE)
          setViewVisibility(R.id.widget_next, View.GONE)
          setViewVisibility(R.id.widget_next_time, View.GONE)
        } else {
          setViewVisibility(R.id.widget_checkin, View.VISIBLE)
          setViewVisibility(R.id.widget_done, View.GONE)
          setViewVisibility(R.id.widget_done_detail, View.GONE)
          setViewVisibility(R.id.widget_next_card, View.VISIBLE)
          setViewVisibility(R.id.widget_next, View.VISIBLE)
          setViewVisibility(R.id.widget_next_time, View.VISIBLE)
          // Bấm trực tiếp trên widget: gửi broadcast về receiver riêng
          // WidgetCheckinReceiver, receiver tự ghi check-in bằng Kotlin
          // (không qua Dart background engine / JobIntentService của plugin,
          // vốn hay bị Samsung và Android 12+ trì hoãn hoặc chặn).
          // Dùng FLAG_CANCEL_CURRENT thay vì UPDATE_CURRENT: sau lần bấm
          // đầu, PendingIntent cũ có thể bị launcher giữ lại làm lần bấm
          // sau không tới nữa, hủy và tạo mới mỗi lần cập nhật widget sẽ
          // tránh tình trạng "bấm được 1 lần rồi chết".
          val checkinIntent = Intent(context, WidgetCheckinReceiver::class.java).apply {
            action = WidgetCheckinReceiver.ACTION_CHECKIN
          }
          val flags = PendingIntent.FLAG_CANCEL_CURRENT or
              if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
          val pending = PendingIntent.getBroadcast(context, widgetId, checkinIntent, flags)
          setOnClickPendingIntent(R.id.widget_checkin, pending)
        }
      }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }

  fun refreshWidget(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    val ids = manager.getAppWidgetIds(ComponentName(context, ThuocVuiWidgetProvider::class.java))
    if (ids.isNotEmpty()) {
      onUpdate(context, manager, ids, context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE))
    }
  }

  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == ACTION_CHECKIN) {
      // Giữ lại cho widget cũ (trước 1.2.6) vẫn bấm được cho tới khi
      // người dùng xóa và thêm lại widget mới.
      try {
        checkinNextDose(context)
      } catch (_: Exception) {
      }
      refreshWidget(context)
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

  fun checkinNextDose(context: Context): String? {
    val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    // Dùng ThuocVuiPrefs để luôn đọc/ghi đúng key "flutter.thuoc_vui_v1"
    // (xem giải thích trong ThuocVuiPrefs.kt về lỗi 2 bản dữ liệu lệch).
    val readResult = ThuocVuiPrefs.read(flutterPrefs) ?: return null
    val dataKey = readResult.first
    val raw = readResult.second
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
    if (next == null) return null

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
    ThuocVuiPrefs.write(flutterPrefs, dataKey, data.toString())

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
    // Chi tiết lịch hôm nay sau khi đã xong (1.2.15), giống Dart
    // updateHomeWidget(): mỗi lần đã uống một khối 2 dòng, tối đa 3.
    val completedSlots = slots.filter { val st = logs.optJSONObject(it.key)?.optString("status"); st == "taken" || st == "late" }
    val doneLines = mutableListOf<String>()
    for (s in completedSlots.take(3)) {
      val logObj = logs.optJSONObject(s.key) ?: continue
      val st = logObj.optString("status")
      val atRaw = logObj.optString("at")
      val atStr = if (atRaw.length >= 16) atRaw.substring(11, 16) else ""
      val takenStr = if (st == "late") "Đã uống trễ lúc $atStr" else "Đã uống đúng giờ lúc $atStr"
      val med = s.med
      var remStr = ""
      val total = med.optInt("totalPills", 0)
      if (total > 0) {
        val perDose = med.optInt("pillsPerDose", 1).let { if (it > 0) it else 1 }
        val startPill = med.optInt("startPill", 1).let { if (it > 0) it else 1 }
        val stockFrom = med.optString("stockFrom", "").let { if (it.isNotEmpty()) it else med.optString("startDate", "") }
        var takenCount = 0
        val keys = logs.keys()
        while (keys.hasNext()) {
          val k = keys.next()
          if (!k.startsWith("${med.optString("id")}|")) continue
          val parts = k.split("|")
          if (parts.size != 3) continue
          if (parts[1] < stockFrom) continue
          val ls = logs.optJSONObject(k)?.optString("status")
          if (ls == "taken" || ls == "late") takenCount++
        }
        var rem = total - (startPill - 1) - takenCount * perDose
        if (rem < 0) rem = 0
        val perDay = (med.optJSONArray("times")?.length() ?: 0) * perDose
        val daysStr = if (perDay > 0) " (đủ ${rem / perDay} ngày)" else ""
        remStr = " • Còn $rem viên$daysStr"
      }
      doneLines.add("${formEmoji(med.optString("form"))} ${med.optString("name")} — ${med.optString("dose")} • Lúc ${s.time} • ${mealLabel(med.optString("mealNote"))}\n$takenStr$remStr")
    }
    if (completedSlots.size > 3) doneLines.add("… và ${completedSlots.size - 3} lần nữa")
    widgetPrefs.putString("done_detail", doneLines.joinToString("\n"))
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
    widgetPrefs.putString("progress_pct", if (slots.isEmpty()) "0" else ((completed * 100) / slots.size).toString())
    widgetPrefs.putString("all_done", if (following == null && slots.isNotEmpty()) "1" else "0")
    widgetPrefs.apply()
    return "${next.key}|$status"
  }

  /**
   * Cập nhật dữ liệu widget từ log hiện tại trên máy, KHÔNG ghi check-in mới.
   * Dùng cho nút "Đã uống" trên thông báo (1.2.14): trước đây
   * ReReminderReceiver chỉ ghi log rồi hủy thông báo, không cập nhật
   * HomeWidgetPreferences, nên widget vẫn hiện "chưa uống" cho tới khi
   * mở app và Dart chạy updateHomeWidget(). Gọi hàm này ngay sau
   * markTaken() thì widget đổi ngay, kể cả khi không mở app.
   * Logic liệt kê slot hôm nay và câu Pip sao chép từ checkinNextDose
   * (cố ý không refactor hàm đó để không phá đường bấm widget đã
   * kiểm chứng OK ở 1.2.7).
   */
  fun updateWidgetFromCurrentLogs(context: Context) {
    val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    val raw = ThuocVuiPrefs.read(flutterPrefs)?.second ?: return
    val data = JSONObject(raw)
    val medicines = data.optJSONArray("medicines") ?: JSONArray()
    val logs = data.optJSONObject("logs") ?: JSONObject()
    val now = Calendar.getInstance()
    val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(now.time)
    val dartWeekday = if (now.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY) 7
        else now.get(Calendar.DAY_OF_WEEK) - 1
    val dateFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
    data class Slot(val med: JSONObject, val time: String, val key: String, val dateTime: Calendar)
    val slots = mutableListOf<Slot>()
    for (i in 0 until medicines.length()) {
      val med = medicines.getJSONObject(i)
      val start = try { dateFmt.parse(med.optString("startDate")) } catch (_: Exception) { null }
      if (start != null) {
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
    var completed = 0
    var onTime = 0
    var following: Slot? = null
    for (slot in slots) {
      val st = logs.optJSONObject(slot.key)?.optString("status")
      if (st == "taken" || st == "late") completed++
      if (st == "taken") onTime++
      if (following == null && st != "taken" && st != "late") following = slot
    }
    var skipped = 0
    var overdue = false
    for (slot in slots) {
      val st = logs.optJSONObject(slot.key)?.optString("status")
      if (st == "skipped") skipped++
      if (st != "taken" && st != "late" && st != "skipped" && slot.dateTime.before(now)) overdue = true
    }
    val pipMessage = when {
      slots.isEmpty() -> "😊 Thêm thuốc để Pip nhắc bạn nhé!"
      onTime == slots.size -> "🥳 Hôm nay uống đủ và đúng giờ hết rồi, tuyệt vời!"
      completed == slots.size -> "😊 Hôm nay uống đủ hết rồi, có ${completed - onTime} lần trễ, lần sau cố đúng giờ nhé!"
      overdue -> "😟 Ơ, có lần uống quá giờ chưa thấy bạn bấm, uống bù nhé?"
      skipped > 0 -> "😟 Hôm nay bạn bỏ qua $skipped lần, mai cố nhé?"
      else -> "😊 Hôm nay còn ${slots.size - completed} lần nữa là xong, cố lên nhé!"
    }
    val widgetPrefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE).edit()
    // Chi tiết lịch hôm nay sau khi đã xong (1.2.15), giống Dart
    // updateHomeWidget(): mỗi lần đã uống một khối 2 dòng, tối đa 3.
    val completedSlots = slots.filter { val st = logs.optJSONObject(it.key)?.optString("status"); st == "taken" || st == "late" }
    val doneLines = mutableListOf<String>()
    for (s in completedSlots.take(3)) {
      val logObj = logs.optJSONObject(s.key) ?: continue
      val st = logObj.optString("status")
      val atRaw = logObj.optString("at")
      val atStr = if (atRaw.length >= 16) atRaw.substring(11, 16) else ""
      val takenStr = if (st == "late") "Đã uống trễ lúc $atStr" else "Đã uống đúng giờ lúc $atStr"
      val med = s.med
      var remStr = ""
      val total = med.optInt("totalPills", 0)
      if (total > 0) {
        val perDose = med.optInt("pillsPerDose", 1).let { if (it > 0) it else 1 }
        val startPill = med.optInt("startPill", 1).let { if (it > 0) it else 1 }
        val stockFrom = med.optString("stockFrom", "").let { if (it.isNotEmpty()) it else med.optString("startDate", "") }
        var takenCount = 0
        val keys = logs.keys()
        while (keys.hasNext()) {
          val k = keys.next()
          if (!k.startsWith("${med.optString("id")}|")) continue
          val parts = k.split("|")
          if (parts.size != 3) continue
          if (parts[1] < stockFrom) continue
          val ls = logs.optJSONObject(k)?.optString("status")
          if (ls == "taken" || ls == "late") takenCount++
        }
        var rem = total - (startPill - 1) - takenCount * perDose
        if (rem < 0) rem = 0
        val perDay = (med.optJSONArray("times")?.length() ?: 0) * perDose
        val daysStr = if (perDay > 0) " (đủ ${rem / perDay} ngày)" else ""
        remStr = " • Còn $rem viên$daysStr"
      }
      doneLines.add("${formEmoji(med.optString("form"))} ${med.optString("name")} — ${med.optString("dose")} • Lúc ${s.time} • ${mealLabel(med.optString("mealNote"))}\n$takenStr$remStr")
    }
    if (completedSlots.size > 3) doneLines.add("… và ${completedSlots.size - 3} lần nữa")
    widgetPrefs.putString("done_detail", doneLines.joinToString("\n"))
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
    widgetPrefs.putString("progress_pct", if (slots.isEmpty()) "0" else ((completed * 100) / slots.size).toString())
    widgetPrefs.putString("all_done", if (following == null && slots.isNotEmpty()) "1" else "0")
    widgetPrefs.apply()
    refreshWidget(context)
  }
}
