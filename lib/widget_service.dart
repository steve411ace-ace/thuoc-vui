import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'store.dart';
import 'strings.dart';

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

    final settings = AppSettings.fromJson(data['settings'] as Map<String, dynamic>?);
    Lang.current = settings.language;

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
    final skipped = slots.where((s) => logs[s.key]?.status == 'skipped').length;
    final overdue = slots.any((s) => logs[s.key]?.status == null && s.dateTime.isBefore(DateTime.now()));
    final String pipMessage;
    if (completed == slots.length && onTime == slots.length) {
      pipMessage = tr(
        '🥳 Hôm nay uống đủ và đúng giờ hết rồi, tuyệt vời!',
        '🥳 All doses taken on time today — awesome!',
      );
    } else if (completed == slots.length) {
      final lateCount = completed - onTime;
      pipMessage = tr(
        '😊 Hôm nay uống đủ hết rồi, có $lateCount lần trễ, lần sau cố đúng giờ nhé!',
        '😊 All doses done today, $lateCount late — try to be on time next time!',
      );
    } else if (overdue) {
      pipMessage = tr(
        '😟 Ơ, có lần uống quá giờ chưa thấy bạn bấm, uống bù nhé?',
        '😟 A dose is overdue and not checked in — take it now?',
      );
    } else if (skipped > 0) {
      pipMessage = tr(
        '😟 Hôm nay bạn bỏ qua $skipped lần, mai cố nhé?',
        '😟 You skipped $skipped ${enPlural(skipped, 'dose', 'doses')} today — try again tomorrow?',
      );
    } else {
      final left = slots.length - completed;
      pipMessage = tr(
        '😊 Hôm nay còn $left lần nữa là xong, cố lên nhé!',
        '😊 $left ${enPlural(left, 'dose', 'doses')} left today — you\'ve got this!',
      );
    }
    await HomeWidget.saveWidgetData<String>('pip_message', pipMessage);
    await HomeWidget.saveWidgetData<String>(
        'progress',
        tr(
          'Hôm nay: $completed/${slots.length} lần • đúng giờ $onTime lần',
          'Today: $completed/${slots.length} doses • $onTime on time',
        ));
    await HomeWidget.saveWidgetData<String>(
        'next_text',
        following == null
            ? tr('🎉 Đã xong hôm nay!', '🎉 All done for today!')
            : '${following.medicine.formEmoji} ${following.medicine.name} — ${following.medicine.dose}');
    await HomeWidget.saveWidgetData<String>(
        'next_time',
        following == null
            ? ''
            : '${tr('Lúc', 'At')} ${following.time} • ${following.medicine.mealLabel}');
    await HomeWidget.saveWidgetData<String>('all_done', following == null ? '1' : '0');
    await settings.saveWidgetAppearance();
    await HomeWidget.updateWidget(
        name: 'ThuocVuiWidgetProvider', androidName: 'ThuocVuiWidgetProvider');
  } catch (_) {}
}
