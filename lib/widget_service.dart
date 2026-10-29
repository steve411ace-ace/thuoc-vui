import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Callback chạy nền khi bấm nút trên widget màn hình chính.
/// Không dùng ThuocStore ở đây để tránh khởi tạo notification plugin trong isolate nền:
/// đọc thẳng file SharedPreferences mà app chính đang dùng, ghi check-in realtime rồi
/// cập nhật lại dữ liệu widget.
@pragma('vm:entry-point')
Future<void> widgetInteractivityCallback(Uri? uri) async {
  if (uri == null || uri.host != 'checkin') return;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('thuoc_vui_v1');
    if (raw == null || raw.isEmpty) return;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final medicines = (data['medicines'] as List<dynamic>)
        .map((e) => Medicine.fromJson(e as Map<String, dynamic>))
        .toList();
    final logMap = data['logs'] as Map<String, dynamic>? ?? {};
    final logs = logMap.map((k, v) => MapEntry(k, DoseLog.fromJson(v as Map<String, dynamic>)));

    final today = DateTime.now();
    final slots = <DoseSlot>[];
    for (final med in medicines) {
      if (!med.activeOn(today)) continue;
      for (final time in med.times) {
        slots.add(DoseSlot(medicine: med, time: time, day: today));
      }
    }
    slots.sort((a, b) => a.time.compareTo(b.time));
    DoseSlot? next;
    for (final s in slots) {
      final st = logs[s.key]?.status;
      if (st != 'taken' && st != 'late') {
        next = s;
        break;
      }
    }
    if (next == null) return;
    final now = DateTime.now();
    final status = now.isAfter(next.dateTime.add(const Duration(minutes: 30))) ? 'late' : 'taken';
    logs[next.key] = DoseLog(status: status, at: now.toIso8601String());
    await prefs.setString(
      'thuoc_vui_v1',
      jsonEncode({
        'medicines': medicines.map((m) => m.toJson()).toList(),
        'logs': logs.map((k, v) => MapEntry(k, v.toJson())),
        'settings': data['settings'],
      }),
    );

    final completed = slots.where((s) {
      final st = logs[s.key]?.status;
      return st == 'taken' || st == 'late';
    }).length;
    final onTime = slots.where((s) => logs[s.key]?.status == 'taken').length;
    DoseSlot? following;
    for (final s in slots) {
      final st = logs[s.key]?.status;
      if (st != 'taken' && st != 'late') {
        following = s;
        break;
      }
    }
    await HomeWidget.saveWidgetData<String>(
        'progress', 'Hôm nay: $completed/${slots.length} lần • đúng giờ $onTime lần');
    await HomeWidget.saveWidgetData<String>(
        'next_text',
        following == null
            ? '🎉 Đã xong hôm nay!'
            : '${following.medicine.formEmoji} ${following.medicine.name} — ${following.medicine.dose}');
    await HomeWidget.saveWidgetData<String>(
        'next_time', following == null ? '' : 'Lúc ${following.time} • ${following.medicine.mealLabel}');
    await HomeWidget.saveWidgetData<String>('all_done', following == null ? '1' : '0');
    await HomeWidget.updateWidget(
        name: 'ThuocVuiWidgetProvider', androidName: 'ThuocVuiWidgetProvider');
  } catch (_) {}
}
