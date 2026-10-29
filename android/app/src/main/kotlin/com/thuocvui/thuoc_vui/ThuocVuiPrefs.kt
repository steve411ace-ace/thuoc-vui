package com.thuocvui.thuoc_vui

import android.content.SharedPreferences

/**
 * Đọc/ghi dữ liệu Thuốc Vui trong FlutterSharedPreferences.
 *
 * BUG đã tìm ra ở 1.2.6 (22:43, chẩn đoán "không có lần nào để uống"):
 * shared_preferences_android lưu key với tiền tố "flutter.", tức là
 * "flutter.thuoc_vui_v1", không phải "thuoc_vui_v1". Code Kotlin trước đây
 * đọc bằng vòng lặp endsWith (lúc được key này, lúc được key kia) rồi
 * luôn ghi lại vào key không tiền tố "thuoc_vui_v1", tạo ra 2 bản dữ liệu
 * lệch nhau: Dart chỉ đọc key "flutter.", Kotlin lúc đọc bản này lúc đọc
 * bản kia. Hậu quả: bấm widget lần đầu có vẻ được, lần sau thì báo
 * "không có lần nào để uống" dù trong app vẫn còn lần chưa uống, và khi
 * mở app, Dart ghi đè lại dữ liệu cũ lên key "flutter.", xóa mất
 * check-in từ widget.
 *
 * Quy tắc từ nay: luôn ưu tiên key "flutter.thuoc_vui_v1" (bản của Dart),
 * chỉ dùng key không tiền tố khi chưa có key flutter. Khi ghi vào key
 * flutter thì xóa luôn key không tiền tố để chữa lệch cho những máy đã
 * bị tạo 2 bản.
 */
object ThuocVuiPrefs {
  const val KEY_FLUTTER = "flutter.thuoc_vui_v1"
  const val KEY_PLAIN = "thuoc_vui_v1"

  /** Trả về (key, dữ liệu) hoặc null nếu không có dữ liệu nào. */
  fun read(prefs: SharedPreferences): Pair<String, String>? {
    val flutterValue = prefs.getString(KEY_FLUTTER, null)
    if (!flutterValue.isNullOrEmpty()) {
      return Pair(KEY_FLUTTER, flutterValue)
    }
    val plainValue = prefs.getString(KEY_PLAIN, null)
    if (!plainValue.isNullOrEmpty()) {
      return Pair(KEY_PLAIN, plainValue)
    }
    // Phòng hờ: key lạ nào đó kết thúc bằng thuoc_vui_v1.
    for ((key, value) in prefs.all) {
      if (key.endsWith("thuoc_vui_v1") && value is String && value.isNotEmpty()) {
        return Pair(key, value)
      }
    }
    return null
  }

  /** Ghi vào đúng key đã đọc, và chữa lệch bằng cách xóa key còn lại. */
  fun write(prefs: SharedPreferences, key: String, data: String) {
    val editor = prefs.edit()
    editor.putString(key, data)
    if (key == KEY_FLUTTER) {
      editor.remove(KEY_PLAIN)
    } else if (key == KEY_PLAIN) {
      // Nếu chưa có key flutter thì ghi luôn sang key flutter để Dart
      // đọc được, rồi xóa key không tiền tố.
      editor.putString(KEY_FLUTTER, data)
      editor.remove(KEY_PLAIN)
    }
    editor.apply()
  }
}
