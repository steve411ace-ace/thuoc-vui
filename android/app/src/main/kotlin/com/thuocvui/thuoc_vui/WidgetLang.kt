package com.thuocvui.thuoc_vui

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

/**
 * Chọn ngôn ngữ (vi/en) cho các chuỗi do Kotlin tự tạo (widget, thông báo).
 * Ngôn ngữ nằm trong JSON chính của app: settings.language = "vi" | "en"
 * (thiếu hoặc lỗi => "vi").
 */
object WidgetLang {
  /** true nếu settings.language == "en" trong dữ liệu FlutterSharedPreferences. */
  fun isEn(prefs: SharedPreferences): Boolean {
    return try {
      val raw = ThuocVuiPrefs.read(prefs)?.second
      if (raw.isNullOrEmpty()) {
        false
      } else {
        val settings = JSONObject(raw).optJSONObject("settings")
        settings != null && settings.optString("language") == "en"
      }
    } catch (_: Exception) {
      false
    }
  }

  fun isEn(context: Context): Boolean {
    return try {
      isEn(context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE))
    } catch (_: Exception) {
      false
    }
  }

  fun tr(vi: String, en: String, isEn: Boolean): String = if (isEn) en else vi

  fun doses(n: Int): String = if (n == 1) "1 dose" else "$n doses"

  fun pills(n: Int): String = if (n == 1) "1 pill" else "$n pills"

  fun days(n: Int): String = if (n == 1) "1 day" else "$n days"
}
