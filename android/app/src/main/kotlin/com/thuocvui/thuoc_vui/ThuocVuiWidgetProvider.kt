package com.thuocvui.thuoc_vui

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import android.widget.Toast
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

class ThuocVuiWidgetProvider : HomeWidgetProvider() {
  companion object {
    const val ACTION_CHECKIN = "com.thuocvui.thuoc_vui.ACTION_CHECKIN"

    private const val PILL_TEAL = 0xFF0D9488.toInt()
    private const val PILL_TEAL_DARK = 0xFF0F766E.toInt()
    private const val PILL_DARK_TEAL = 0xFF2DD4BF.toInt()
    private const val PILL_SKY = 0xFF0EA5E9.toInt()
    private const val PILL_ORANGE = 0xFFF97316.toInt()
    private const val PILL_AMBER = 0xFFFBBF24.toInt()
    private const val PILL_OVERDUE_DOT = 0xFFFDBA74.toInt()
    private const val PILL_EMERALD_SOFT = 0xFF6EE7B7.toInt()

    private const val COLOR_TEXT_LIGHT = 0xFF0F172A.toInt()
    private const val COLOR_TEXT_DARK = 0xFFF1F5F9.toInt()
    private const val COLOR_MUTED_LIGHT = 0xFF64748B.toInt()
    private const val COLOR_MUTED_DARK = 0xFF94A3B8.toInt()
    private const val COLOR_SLATE_300 = 0xFFCBD5E1.toInt()
    private const val COLOR_OUT_TAG_LIGHT = 0xFFEA580C.toInt()
    private const val COLOR_OUT_TAG_DARK = 0xFFFB923C.toInt()
  }

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    // 1.2.30: dữ liệu widget được đóng dấu ngày (widget_date) ở
    // Dart updateHomeWidget() và ở các hàm Kotlin ghi widget. Qua
    // nửa đêm mà dấu ngày cũ thì tính lại từ log rồi mới vẽ, vì
    // chu kỳ vẽ 30 phút trước đây chỉ vẽ lại chuỗi cũ nên widget
    // giữ nguyên trạng thái hôm qua cho tới khi mở app. Hàm cập
    // nhật đã tự gọi refreshWidget nên vẽ lại ở lần onUpdate sau.
    val todayStr = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
    if (widgetData.getString("widget_date", null) != todayStr) {
      val refreshed = try { updateWidgetFromCurrentLogs(context) } catch (_: Exception) { false }
      if (refreshed) return
    }
    val langEn = WidgetLang.isEn(context)
    appWidgetIds.forEach { widgetId ->
      val minHeightDp = appWidgetManager.getAppWidgetOptions(widgetId)
          .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
      val isTall = minHeightDp >= 210
      val views = RemoteViews(context.packageName, R.layout.thuoc_vui_widget).apply {
        val themeMode = widgetData.getString("widget_theme", "system")
        val isDark = themeMode == "dark" || (themeMode == "system" &&
            (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES)

        // Màu chủ đạo từ HomePalette + Custom (widget_accent) đồng bộ công thức
        // pillGradient() trong lib/pillflow_style.dart và HomePalette._theme().
        val rawAccent = try {
          Color.parseColor(widgetData.getString("widget_accent", null) ?: "#0F766E")
        } catch (_: IllegalArgumentException) {
          PILL_TEAL_DARK
        }
        val isDefaultTeal = rawAccent == PILL_TEAL_DARK ||
            rawAccent == PILL_TEAL ||
            rawAccent == PILL_DARK_TEAL
        val resolvedAccent = if (isDefaultTeal) {
          if (isDark) PILL_DARK_TEAL else PILL_TEAL
        } else {
          rawAccent
        }
        val heroColors = computeHeroGradientColors(rawAccent, isDefaultTeal)
        val accentLuminance = luminanceOf(resolvedAccent)
        val darkOnAccent = if (isDefaultTeal && !isDark) false else accentLuminance > 0.179
        val onAccent = if (darkOnAccent) COLOR_TEXT_LIGHT else Color.WHITE
        val lightButtonOutline = accentLuminance > 0.8 && !isDark
        val shapeAccent = when {
          !isDark && accentLuminance > 0.8 -> COLOR_TEXT_LIGHT
          isDark && accentLuminance < 0.04 -> COLOR_SLATE_300
          else -> resolvedAccent
        }

        // Độ mờ widget (1.2.18, mở rộng 0-100% ở 1.2.26): Dart lưu
        // widget_opacity (%) vào HomeWidgetPreferences, mặc định 100.
        // Drawable có đủ các mức 0/10/.../100 nên làm tròn về mức 10%
        // gần nhất; thẻ Hero & thẻ lần uống tiếp theo giữ nền đặc để
        // chữ luôn rõ trên mọi hình nền.
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

        val mainText = if (isDark) COLOR_TEXT_DARK else COLOR_TEXT_LIGHT
        val mutedText = if (isDark) COLOR_MUTED_DARK else COLOR_MUTED_LIGHT

        val openIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        setOnClickPendingIntent(R.id.widget_container, openIntent)

        // Hero Bento Gradient Card (gộp tên app + đồng hồ TextClock ở dòng đầu)
        // + vòng tròn tiến độ 42dp chỉ hiện % (không mặt Pip).
        val pct = (widgetData.getString("progress_pct", null)?.toIntOrNull() ?: 0).coerceIn(0, 100)
        val allDone = widgetData.getString("all_done", null) == "1"
        setImageViewBitmap(R.id.widget_hero_bg, heroBackgroundBitmap(heroColors))
        setImageViewBitmap(R.id.widget_progress_ring, progressRingBitmap(context, pct))
        setTextViewText(R.id.widget_ring_pct, "$pct%")
        setTextViewText(
            R.id.widget_hero_kicker,
            WidgetLang.tr("Tiến độ hôm nay", "Today's progress", langEn),
        )
        setTextViewText(R.id.widget_progress, widgetData.getString("progress", null) ?: "Thuốc Vui")

        val pipMessage = widgetData.getString("pip_message", null) ?: WidgetLang.tr("😊 Pip đang nhắc bạn uống thuốc đúng giờ nhé!", "😊 Pip is reminding you to take your medicine on time!", langEn)
        val hasMoodPrefix = pipMessage.startsWith("🥳 ") ||
            pipMessage.startsWith("😟 ") ||
            pipMessage.startsWith("😊 ")
        val statusDotColor = when {
          pipMessage.startsWith("🥳 ") -> PILL_EMERALD_SOFT
          pipMessage.startsWith("😟 ") -> PILL_OVERDUE_DOT
          pipMessage.startsWith("😊 ") -> PILL_AMBER
          allDone -> PILL_EMERALD_SOFT
          else -> PILL_AMBER
        }
        setInt(R.id.widget_status_dot, "setColorFilter", statusDotColor)
        setInt(R.id.widget_pip, "setMaxLines", if (isTall) 4 else 3)
        val rawPip = if (hasMoodPrefix) pipMessage.substringAfter(' ') else pipMessage
        setTextViewText(R.id.widget_pip, rawPip.replace(" 🛒 ", "\n🛒 "))

        if (allDone) {
          setViewVisibility(R.id.widget_next_card, View.GONE)
          setViewVisibility(R.id.widget_checkin_row, View.GONE)
          setViewVisibility(R.id.widget_done_card, View.VISIBLE)
          setInt(
              R.id.widget_done_card,
              "setBackgroundResource",
              if (isDark) R.drawable.done_card_dark else R.drawable.done_card_light,
          )
          setTextViewText(
              R.id.widget_done,
              WidgetLang.tr("🎉 Đã xong hôm nay!", "🎉 All done for today!", langEn),
          )
          setTextColor(R.id.widget_done, mainText)
          bindDoneItems(
              this,
              widgetData.getString("done_detail", null) ?: "",
              isDark,
              mainText,
              mutedText,
              maxItems = if (isTall) 3 else 1,
              langEn = langEn,
          )
        } else {
          setViewVisibility(R.id.widget_done_card, View.GONE)
          setViewVisibility(R.id.widget_next_card, View.VISIBLE)
          setViewVisibility(R.id.widget_checkin_row, View.VISIBLE)

          val isOutOfStock = widgetData.getString("next_out_of_stock", null) == "1"
          setInt(
              R.id.widget_next_card,
              "setBackgroundResource",
              if (isOutOfStock) {
                if (isDark) R.drawable.next_card_out_dark else R.drawable.next_card_out_light
              } else {
                if (isDark) R.drawable.next_card_dark else R.drawable.next_card_light
              },
          )

          // Ô icon viên thuốc 42dp (đổi sang cam san hô #F97316 khi hết thuốc 0 viên).
          val boxColor = if (isOutOfStock) PILL_ORANGE else shapeAccent
          val boxAlpha = if (isOutOfStock) 0.14f else if (isDark) 0.20f else 0.14f
          setInt(R.id.widget_shape_box_bg, "setColorFilter", boxColor)
          setFloat(R.id.widget_shape_box_bg, "setAlpha", boxAlpha)
          setInt(R.id.widget_shape_icon, "setColorFilter", boxColor)

          if (isOutOfStock) {
            setTextViewText(R.id.widget_next_tag, WidgetLang.tr("HẾT THUỐC · 0 VIÊN", "OUT OF STOCK · 0 LEFT", langEn))
            setTextColor(
                R.id.widget_next_tag,
                if (isDark) COLOR_OUT_TAG_DARK else COLOR_OUT_TAG_LIGHT,
            )
            setInt(R.id.widget_next_tag, "setBackgroundResource", R.drawable.widget_out_tag_bg)
            val padH = dpToPx(context, 7f)
            val padV = dpToPx(context, 2f)
            setViewPadding(R.id.widget_next_tag, padH, padV, padH, padV)
          } else {
            setTextViewText(R.id.widget_next_tag, WidgetLang.tr("LẦN UỐNG TIẾP THEO", "NEXT DOSE", langEn))
            setTextColor(R.id.widget_next_tag, mutedText)
            setInt(R.id.widget_next_tag, "setBackgroundResource", 0)
            setViewPadding(R.id.widget_next_tag, 0, 0, 0, 0)
          }

          val nextText = widgetData.getString("next_text", null) ?: WidgetLang.tr("Mở app để xem lịch hôm nay", "Open the app to see today's schedule", langEn)
          val nextTime = widgetData.getString("next_time", null) ?: ""
          setTextViewText(R.id.widget_next, nextText)
          setTextColor(R.id.widget_next, mainText)
          setInt(R.id.widget_next_time, "setMaxLines", if (isTall) 2 else 1)
          setTextViewText(R.id.widget_next_time, nextTime)
          setTextColor(R.id.widget_next_time, mutedText)
          setViewVisibility(R.id.widget_next_time, if (nextTime.isEmpty()) View.GONE else View.VISIBLE)

          // Nút check-in bo Bento 16dp: icon tích (hoặc khóa khi hết thuốc) + "Đã uống lần này".
          setInt(R.id.widget_checkin_background, "setColorFilter", resolvedAccent)
          setViewVisibility(
              R.id.widget_checkin_border,
              if (lightButtonOutline) View.VISIBLE else View.GONE,
          )
          setImageViewResource(
              R.id.widget_checkin_icon,
              if (isOutOfStock) R.drawable.widget_ic_lock else R.drawable.widget_ic_check,
          )
          setInt(R.id.widget_checkin_icon, "setColorFilter", onAccent)
          setTextViewText(
              R.id.widget_checkin_label,
              WidgetLang.tr("Đã uống lần này", "Mark as taken", langEn),
          )
          setTextColor(R.id.widget_checkin_label, onAccent)

          // 1.2.33: hết thuốc thì khóa + làm mờ nút check-in (alpha 0.4),
          // mở lại khi mua hộp mới (luôn set cả 2 chiều vì RemoteViews giữ
          // trạng thái cũ). Vẫn gắn PendingIntent để khi người dùng bấm vào
          // nút đã khóa, checkinNextDose() chặn ghi log và hiện Toast
          // "Hết thuốc rồi, mua hộp mới nhé!".
          val checkinAlpha = if (isOutOfStock) 0.4f else 1.0f
          setFloat(R.id.widget_checkin, "setAlpha", checkinAlpha)
          setFloat(R.id.widget_checkin_background, "setAlpha", checkinAlpha)
          setFloat(R.id.widget_checkin_border, "setAlpha", checkinAlpha)

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

  override fun onAppWidgetOptionsChanged(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      newOptions: Bundle,
  ) {
    super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
    onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), prefs)
  }

  private fun bindDoneItems(
      views: RemoteViews,
      doneDetail: String,
      isDark: Boolean,
      mainText: Int,
      mutedText: Int,
      maxItems: Int,
      langEn: Boolean,
  ) {
    val rawLines = doneDetail
        .split("\n")
        .map { it.trim() }
        .filter { it.isNotEmpty() }
    val pairs = mutableListOf<Pair<String, String>>()
    var overflowLine = ""
    var idx = 0
    while (idx < rawLines.size) {
      val line = rawLines[idx]
      if (line.startsWith("…") || pairs.size >= 3) {
        overflowLine = rawLines.subList(idx, rawLines.size).joinToString("\n")
        break
      }
      val nextLine = if (idx + 1 < rawLines.size && !rawLines[idx + 1].startsWith("…")) {
        idx += 2
        rawLines[idx - 1]
      } else {
        idx += 1
        ""
      }
      pairs.add(Pair(line, nextLine))
    }

    val visibleCount = pairs.size.coerceAtMost(maxItems.coerceIn(1, 3))
    val hiddenPairs = (pairs.size - visibleCount).coerceAtLeast(0)
    val moreText = when {
      hiddenPairs > 0 && overflowLine.isNotEmpty() -> overflowLine
      hiddenPairs > 0 -> if (langEn) "… and $hiddenPairs more" else "… và $hiddenPairs lần nữa"
      else -> overflowLine
    }

    val itemBg = if (isDark) R.drawable.done_item_dark else R.drawable.done_item_light
    val itemSpecs = arrayOf(
        Triple(R.id.widget_done_item_1, R.id.widget_done_1_line1, R.id.widget_done_1_line2),
        Triple(R.id.widget_done_item_2, R.id.widget_done_2_line1, R.id.widget_done_2_line2),
        Triple(R.id.widget_done_item_3, R.id.widget_done_3_line1, R.id.widget_done_3_line2),
    )
    for (i in itemSpecs.indices) {
      val (boxId, line1Id, line2Id) = itemSpecs[i]
      if (i < visibleCount) {
        val (line1, line2) = pairs[i]
        views.setViewVisibility(boxId, View.VISIBLE)
        views.setInt(boxId, "setBackgroundResource", itemBg)
        views.setTextViewText(line1Id, line1)
        views.setTextColor(line1Id, mainText)
        if (line2.isNotEmpty()) {
          views.setViewVisibility(line2Id, View.VISIBLE)
          views.setTextViewText(line2Id, line2)
          views.setTextColor(line2Id, mutedText)
        } else {
          views.setViewVisibility(line2Id, View.GONE)
        }
      } else {
        views.setViewVisibility(boxId, View.GONE)
      }
    }

    if (moreText.isNotEmpty()) {
      views.setViewVisibility(R.id.widget_done_more, View.VISIBLE)
      views.setTextViewText(R.id.widget_done_more, moreText)
      views.setTextColor(R.id.widget_done_more, mutedText)
    } else {
      views.setViewVisibility(R.id.widget_done_more, View.GONE)
    }
  }

  private fun dpToPx(context: Context, dp: Float): Int =
      (dp * context.resources.displayMetrics.density).roundToInt()

  private fun linearChannel(channel: Int): Double {
    val value = channel / 255.0
    return if (value <= 0.04045) value / 12.92
    else Math.pow((value + 0.055) / 1.055, 2.4)
  }

  private fun luminanceOf(color: Int): Double =
      0.2126 * linearChannel(Color.red(color)) +
          0.7152 * linearChannel(Color.green(color)) +
          0.0722 * linearChannel(Color.blue(color))

  private fun alphaBlendBlack(color: Int, blackAlpha: Int): Int {
    val keep = (255 - blackAlpha.coerceIn(0, 255)) / 255.0
    return Color.rgb(
        (Color.red(color) * keep).roundToInt().coerceIn(0, 255),
        (Color.green(color) * keep).roundToInt().coerceIn(0, 255),
        (Color.blue(color) * keep).roundToInt().coerceIn(0, 255),
    )
  }

  private fun lerpColor(colorA: Int, colorB: Int, t: Float): Int {
    val r = (Color.red(colorA) + (Color.red(colorB) - Color.red(colorA)) * t).roundToInt().coerceIn(0, 255)
    val g = (Color.green(colorA) + (Color.green(colorB) - Color.green(colorA)) * t).roundToInt().coerceIn(0, 255)
    val b = (Color.blue(colorA) + (Color.blue(colorB) - Color.blue(colorA)) * t).roundToInt().coerceIn(0, 255)
    return Color.rgb(r, g, b)
  }

  /** Khớp công thức pillGradient() trong lib/pillflow_style.dart. */
  private fun computeHeroGradientColors(rawAccent: Int, isDefaultTeal: Boolean): IntArray {
    if (isDefaultTeal) {
      return intArrayOf(PILL_TEAL_DARK, PILL_TEAL, PILL_SKY)
    }
    val brandLum = luminanceOf(rawAccent)
    val middle = if (brandLum > 0.45) alphaBlendBlack(rawAccent, 110) else rawAccent
    val c1 = alphaBlendBlack(middle, 66) // Colors.black26
    val c3 = lerpColor(middle, PILL_SKY, 0.4f)
    return intArrayOf(c1, middle, c3)
  }

  /** Nền thẻ Hero Bento bo 20dp: gradient 135° theo pillGradient() + vòng sáng trang trí góc phải trên. */
  private fun heroBackgroundBitmap(heroColors: IntArray): Bitmap {
    val width = 360
    val height = 116
    val radius = 22f
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val rect = RectF(0f, 0f, width.toFloat(), height.toFloat())
    val clipPath = Path().apply {
      addRoundRect(rect, radius, radius, Path.Direction.CW)
    }
    canvas.save()
    canvas.clipPath(clipPath)
    val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      shader = LinearGradient(
          0f,
          0f,
          width.toFloat(),
          height.toFloat(),
          heroColors,
          floatArrayOf(0f, 0.5f, 1f),
          Shader.TileMode.CLAMP,
      )
    }
    canvas.drawRect(rect, bgPaint)
    val orbPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = 0x1CFFFFFF // rgba(255, 255, 255, 0.11)
    }
    canvas.drawCircle(width - 26f, 22f, 52f, orbPaint)
    canvas.restore()
    return bitmap
  }

  /** Vòng tròn tiến độ 56dp viền trắng bo tròn đầu (chỉ vẽ vòng; % hiển thị bằng TextView Be Vietnam Pro ở giữa). */
  private fun progressRingBitmap(context: Context, percent: Int): Bitmap {
    val density = context.resources.displayMetrics.density
    val size = (56f * density).roundToInt().coerceIn(112, 196)
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val cx = size / 2f
    val cy = size / 2f
    val strokeWidth = size * (7.5f / 80f)
    val radius = size * (32f / 80f)
    val oval = RectF(cx - radius, cy - radius, cx + radius, cy + radius)

    val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.STROKE
      this.strokeWidth = strokeWidth
      color = 0x3DFFFFFF // rgba(255, 255, 255, 0.24)
    }
    canvas.drawCircle(cx, cy, radius, trackPaint)

    val clamped = percent.coerceIn(0, 100)
    if (clamped > 0) {
      val progressPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        this.strokeWidth = strokeWidth
        color = Color.WHITE
        strokeCap = Paint.Cap.ROUND
      }
      val sweep = 360f * (clamped / 100f)
      canvas.drawArc(oval, -90f, sweep, false, progressPaint)
    }
    return bitmap
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

  private fun mealLabel(mealNote: String, langEn: Boolean = false): String = when (mealNote) {
    "truoc_an" -> WidgetLang.tr("Uống trước ăn", "Take before meals", langEn)
    "sau_an" -> WidgetLang.tr("Uống sau ăn", "Take after meals", langEn)
    "trong_bua" -> WidgetLang.tr("Uống trong bữa", "Take with meals", langEn)
    "truoc_ngu" -> WidgetLang.tr("Uống trước khi ngủ", "Take before bed", langEn)
    else -> WidgetLang.tr("Không dặn trước/sau ăn", "No meal instruction", langEn)
  }

  /** So sánh thời điểm tới giây: cắt phần lẻ giây của chuỗi ISO vì
   * Dart ghi 6 chữ số lẻ, Kotlin ghi 3 chữ số lẻ, so chuỗi thô sẽ
   * lệch ở phần lẻ giây. Dùng cho mốc mua hộp mới (1.2.30). */
  private fun atSecond(s: String): String = if (s.length >= 19) s.substring(0, 19) else s

  // Số viên còn lại của 1 thuốc (1.2.33, cùng công thức với Dart
  // remainingPills và khối done_detail bên dưới): null nếu không theo
  // dõi (totalPills <= 0); mốc mua hộp mới stockFromAt loại các lần
  // uống trước lúc mua (so tới giây).
  private fun remainingFor(med: JSONObject, logs: JSONObject): Int? {
    val total = med.optInt("totalPills", 0)
    if (total <= 0) return null
    val perDose = med.optInt("pillsPerDose", 1).let { if (it > 0) it else 1 }
    val startPill = med.optInt("startPill", 1).let { if (it > 0) it else 1 }
    val stockFrom = med.optString("stockFrom", "").let { if (it.isNotEmpty()) it else med.optString("startDate", "") }
    val stockFromAt = med.optString("stockFromAt", "")
    var takenCount = 0
    val keys = logs.keys()
    while (keys.hasNext()) {
      val k = keys.next()
      if (!k.startsWith("${med.optString("id")}|")) continue
      val parts = k.split("|")
      if (parts.size != 3) continue
      val logObj2 = logs.optJSONObject(k)
      if (stockFromAt.isNotEmpty()) {
        if (atSecond(logObj2?.optString("at", "") ?: "") < atSecond(stockFromAt)) continue
      } else {
        if (parts[1] < stockFrom) continue
      }
      val ls = logObj2?.optString("status")
      if (ls == "taken" || ls == "late") takenCount++
    }
    val rem = total - (startPill - 1) - takenCount * perDose
    return if (rem < 0) 0 else rem
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
    // 1.2.33: hết thuốc (còn 0 viên) thì không ghi lần uống nữa — chặn
    // tận gốc cho mọi đường bấm nút widget, kể cả khi giao diện chưa
    // kịp làm mờ nút.
    if (remainingFor(next.med, logs) == 0) {
      Toast.makeText(context, WidgetLang.tr("Hết thuốc rồi, mua hộp mới nhé!", "Out of stock — time to buy a new box!", WidgetLang.isEn(flutterPrefs)), Toast.LENGTH_SHORT).show()
      return null
    }

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
    val langEn = WidgetLang.isEn(flutterPrefs)
    val pipMessage = when {
      slots.isEmpty() -> if (langEn) "😊 Add a medicine so Pip can remind you!" else "😊 Thêm thuốc để Pip nhắc bạn nhé!"
      onTime == slots.size -> if (langEn) "🥳 All doses taken on time today — awesome!" else "🥳 Hôm nay uống đủ và đúng giờ hết rồi, tuyệt vời!"
      completed == slots.size -> if (langEn) "😊 All doses done today, ${completed - onTime} late — try to be on time next time!" else "😊 Hôm nay uống đủ hết rồi, có ${completed - onTime} lần trễ, lần sau cố đúng giờ nhé!"
      overdue -> if (langEn) "😟 A dose is overdue and not checked in — take it now?" else "😟 Ơ, có lần uống quá giờ chưa thấy bạn bấm, uống bù nhé?"
      skipped > 0 -> if (langEn) "😟 You skipped ${WidgetLang.doses(skipped)} today — try again tomorrow?" else "😟 Hôm nay bạn bỏ qua $skipped lần, mai cố nhé?"
      else -> if (langEn) "😊 ${WidgetLang.doses(slots.size - completed)} left today — you've got this!" else "😊 Hôm nay còn ${slots.size - completed} lần nữa là xong, cố lên nhé!"
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
      val takenStr = if (langEn) { if (st == "late") "Taken late at $atStr" else "Taken on time at $atStr" } else { if (st == "late") "Đã uống trễ lúc $atStr" else "Đã uống đúng giờ lúc $atStr" }
      val med = s.med
      var remStr = ""
      val total = med.optInt("totalPills", 0)
      if (total > 0) {
        val perDose = med.optInt("pillsPerDose", 1).let { if (it > 0) it else 1 }
        val startPill = med.optInt("startPill", 1).let { if (it > 0) it else 1 }
        val stockFrom = med.optString("stockFrom", "").let { if (it.isNotEmpty()) it else med.optString("startDate", "") }
        val stockFromAt = med.optString("stockFromAt", "")
        var takenCount = 0
        val keys = logs.keys()
        while (keys.hasNext()) {
          val k = keys.next()
          if (!k.startsWith("${med.optString("id")}|")) continue
          val parts = k.split("|")
          if (parts.size != 3) continue
          val logObj2 = logs.optJSONObject(k)
          if (stockFromAt.isNotEmpty()) {
            // 1.2.30: chỉ tính lần uống từ sau thời điểm mua hộp mới.
            if (atSecond(logObj2?.optString("at", "") ?: "") < atSecond(stockFromAt)) continue
          } else {
            if (parts[1] < stockFrom) continue
          }
          val ls = logObj2?.optString("status")
          if (ls == "taken" || ls == "late") takenCount++
        }
        var rem = total - (startPill - 1) - takenCount * perDose
        if (rem < 0) rem = 0
        val perDay = (med.optJSONArray("times")?.length() ?: 0) * perDose
        val daysStr = if (perDay > 0) { if (langEn) " (enough for ${WidgetLang.days(rem / perDay)})" else " (đủ ${rem / perDay} ngày)" } else ""
        remStr = if (langEn) " • ${WidgetLang.pills(rem)} left$daysStr" else " • Còn $rem viên$daysStr"
      }
      doneLines.add("${formEmoji(med.optString("form"))} ${med.optString("name")} — ${med.optString("dose")} • ${WidgetLang.tr("Lúc", "At", langEn)} ${s.time} • ${mealLabel(med.optString("mealNote"), langEn)}\n$takenStr$remStr")
    }
    if (completedSlots.size > 3) doneLines.add(if (langEn) "… and ${completedSlots.size - 3} more" else "… và ${completedSlots.size - 3} lần nữa")
    widgetPrefs.putString("done_detail", doneLines.joinToString("\n"))
    widgetPrefs.putString("pip_message", pipMessage)
    widgetPrefs.putString(
        "progress",
        if (langEn) {
          if (slots.isEmpty()) "No medicines today"
          else "Today: $completed/${slots.size} doses • $onTime on time"
        } else {
          if (slots.isEmpty()) "Chưa có thuốc hôm nay"
          else "Hôm nay: $completed/${slots.size} lần • đúng giờ $onTime lần"
        })
    if (following == null) {
      widgetPrefs.putString("next_text", if (langEn) { if (slots.isEmpty()) "Add a medicine so Pip can remind you!" else "🎉 All done for today!" } else { if (slots.isEmpty()) "Thêm thuốc để Pip nhắc bạn nhé!" else "🎉 Đã xong hôm nay!" })
      widgetPrefs.putString("next_time", "")
    } else {
      val nextRem = remainingFor(following.med, logs)
      val nextRemStr = if (nextRem != null) { if (langEn) " • ${WidgetLang.pills(nextRem)} left" else " • Còn $nextRem viên" } else ""
      widgetPrefs.putString("next_text", "${formEmoji(following.med.optString("form"))} ${following.med.optString("name")} — ${following.med.optString("dose")}")
      widgetPrefs.putString("next_time", "${WidgetLang.tr("Lúc", "At", langEn)} ${following.time} • ${mealLabel(following.med.optString("mealNote"), langEn)}$nextRemStr")
    }
    widgetPrefs.putString("progress_pct", if (slots.isEmpty()) "0" else ((completed * 100) / slots.size).toString())
    widgetPrefs.putString("all_done", if (following == null && slots.isNotEmpty()) "1" else "0")
    // 1.2.33: cờ hết thuốc cho nút widget (xem onUpdate) — "1" khi lần
    // tiếp theo đã hết thuốc, "0" trong các trường hợp còn lại.
    widgetPrefs.putString("next_out_of_stock", if (following != null && remainingFor(following.med, logs) == 0) "1" else "0")
    widgetPrefs.putString("widget_date", todayStr)
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
  /** Trả về true nếu đã ghi dữ liệu mới và gọi refreshWidget (để
   * onUpdate biết mà không vẽ lại dữ liệu cũ trong cùng lượt). */
  fun updateWidgetFromCurrentLogs(context: Context): Boolean {
    val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    val raw = ThuocVuiPrefs.read(flutterPrefs)?.second ?: return false
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
    val langEn = WidgetLang.isEn(flutterPrefs)
    val pipMessage = when {
      slots.isEmpty() -> if (langEn) "😊 Add a medicine so Pip can remind you!" else "😊 Thêm thuốc để Pip nhắc bạn nhé!"
      onTime == slots.size -> if (langEn) "🥳 All doses taken on time today — awesome!" else "🥳 Hôm nay uống đủ và đúng giờ hết rồi, tuyệt vời!"
      completed == slots.size -> if (langEn) "😊 All doses done today, ${completed - onTime} late — try to be on time next time!" else "😊 Hôm nay uống đủ hết rồi, có ${completed - onTime} lần trễ, lần sau cố đúng giờ nhé!"
      overdue -> if (langEn) "😟 A dose is overdue and not checked in — take it now?" else "😟 Ơ, có lần uống quá giờ chưa thấy bạn bấm, uống bù nhé?"
      skipped > 0 -> if (langEn) "😟 You skipped ${WidgetLang.doses(skipped)} today — try again tomorrow?" else "😟 Hôm nay bạn bỏ qua $skipped lần, mai cố nhé?"
      else -> if (langEn) "😊 ${WidgetLang.doses(slots.size - completed)} left today — you've got this!" else "😊 Hôm nay còn ${slots.size - completed} lần nữa là xong, cố lên nhé!"
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
      val takenStr = if (langEn) { if (st == "late") "Taken late at $atStr" else "Taken on time at $atStr" } else { if (st == "late") "Đã uống trễ lúc $atStr" else "Đã uống đúng giờ lúc $atStr" }
      val med = s.med
      var remStr = ""
      val total = med.optInt("totalPills", 0)
      if (total > 0) {
        val perDose = med.optInt("pillsPerDose", 1).let { if (it > 0) it else 1 }
        val startPill = med.optInt("startPill", 1).let { if (it > 0) it else 1 }
        val stockFrom = med.optString("stockFrom", "").let { if (it.isNotEmpty()) it else med.optString("startDate", "") }
        val stockFromAt = med.optString("stockFromAt", "")
        var takenCount = 0
        val keys = logs.keys()
        while (keys.hasNext()) {
          val k = keys.next()
          if (!k.startsWith("${med.optString("id")}|")) continue
          val parts = k.split("|")
          if (parts.size != 3) continue
          val logObj2 = logs.optJSONObject(k)
          if (stockFromAt.isNotEmpty()) {
            // 1.2.30: chỉ tính lần uống từ sau thời điểm mua hộp mới.
            if (atSecond(logObj2?.optString("at", "") ?: "") < atSecond(stockFromAt)) continue
          } else {
            if (parts[1] < stockFrom) continue
          }
          val ls = logObj2?.optString("status")
          if (ls == "taken" || ls == "late") takenCount++
        }
        var rem = total - (startPill - 1) - takenCount * perDose
        if (rem < 0) rem = 0
        val perDay = (med.optJSONArray("times")?.length() ?: 0) * perDose
        val daysStr = if (perDay > 0) { if (langEn) " (enough for ${WidgetLang.days(rem / perDay)})" else " (đủ ${rem / perDay} ngày)" } else ""
        remStr = if (langEn) " • ${WidgetLang.pills(rem)} left$daysStr" else " • Còn $rem viên$daysStr"
      }
      doneLines.add("${formEmoji(med.optString("form"))} ${med.optString("name")} — ${med.optString("dose")} • ${WidgetLang.tr("Lúc", "At", langEn)} ${s.time} • ${mealLabel(med.optString("mealNote"), langEn)}\n$takenStr$remStr")
    }
    if (completedSlots.size > 3) doneLines.add(if (langEn) "… and ${completedSlots.size - 3} more" else "… và ${completedSlots.size - 3} lần nữa")
    widgetPrefs.putString("done_detail", doneLines.joinToString("\n"))
    widgetPrefs.putString("pip_message", pipMessage)
    widgetPrefs.putString(
        "progress",
        if (langEn) {
          if (slots.isEmpty()) "No medicines today"
          else "Today: $completed/${slots.size} doses • $onTime on time"
        } else {
          if (slots.isEmpty()) "Chưa có thuốc hôm nay"
          else "Hôm nay: $completed/${slots.size} lần • đúng giờ $onTime lần"
        })
    if (following == null) {
      widgetPrefs.putString("next_text", if (langEn) { if (slots.isEmpty()) "Add a medicine so Pip can remind you!" else "🎉 All done for today!" } else { if (slots.isEmpty()) "Thêm thuốc để Pip nhắc bạn nhé!" else "🎉 Đã xong hôm nay!" })
      widgetPrefs.putString("next_time", "")
    } else {
      val nextRem = remainingFor(following.med, logs)
      val nextRemStr = if (nextRem != null) { if (langEn) " • ${WidgetLang.pills(nextRem)} left" else " • Còn $nextRem viên" } else ""
      widgetPrefs.putString("next_text", "${formEmoji(following.med.optString("form"))} ${following.med.optString("name")} — ${following.med.optString("dose")}")
      widgetPrefs.putString("next_time", "${WidgetLang.tr("Lúc", "At", langEn)} ${following.time} • ${mealLabel(following.med.optString("mealNote"), langEn)}$nextRemStr")
    }
    widgetPrefs.putString("progress_pct", if (slots.isEmpty()) "0" else ((completed * 100) / slots.size).toString())
    widgetPrefs.putString("all_done", if (following == null && slots.isNotEmpty()) "1" else "0")
    // 1.2.33: cờ hết thuốc cho nút widget (xem onUpdate) — "1" khi lần
    // tiếp theo đã hết thuốc, "0" trong các trường hợp còn lại.
    widgetPrefs.putString("next_out_of_stock", if (following != null && remainingFor(following.med, logs) == 0) "1" else "0")
    widgetPrefs.putString("widget_date", todayStr)
    widgetPrefs.apply()
    refreshWidget(context)
    return true
  }
}
