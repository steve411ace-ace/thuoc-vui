import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

const String _storageKey = 'thuoc_vui_v1';
const String _channelId = 'thuoc_vui_reminder';

class AppSettings {
  bool sound;
  bool vibration;
  String quietStart; // HH:mm
  String quietEnd; // HH:mm

  AppSettings({
    this.sound = true,
    this.vibration = true,
    this.quietStart = '22:00',
    this.quietEnd = '07:00',
  });

  Map<String, dynamic> toJson() => {
        'sound': sound,
        'vibration': vibration,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
      };

  factory AppSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return AppSettings();
    return AppSettings(
      sound: j['sound'] as bool? ?? true,
      vibration: j['vibration'] as bool? ?? true,
      quietStart: j['quietStart'] as String? ?? '22:00',
      quietEnd: j['quietEnd'] as String? ?? '07:00',
    );
  }

  bool inQuietHours(String hhmm) {
    // Khoảng yên lặng có thể qua đêm (22:00 -> 07:00).
    if (quietStart == quietEnd) return false;
    if (quietStart.compareTo(quietEnd) < 0) {
      return hhmm.compareTo(quietStart) >= 0 && hhmm.compareTo(quietEnd) < 0;
    }
    return hhmm.compareTo(quietStart) >= 0 || hhmm.compareTo(quietEnd) < 0;
  }
}

class ThuocStore extends ChangeNotifier {
  final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();
  bool notificationsReady = false;

  List<Medicine> medicines = [];
  Map<String, DoseLog> logs = {};
  AppSettings settings = AppSettings();
  bool loaded = false;

  Future<void> init() async {
    await _load();
    await _initNotifications();
    loaded = true;
    notifyListeners();
    await rescheduleAll();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      medicines = [];
      logs = {};
      settings = AppSettings();
      return;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      medicines = (data['medicines'] as List<dynamic>)
          .map((e) => Medicine.fromJson(e as Map<String, dynamic>))
          .toList();
      final logMap = data['logs'] as Map<String, dynamic>? ?? {};
      logs = logMap.map((k, v) => MapEntry(k, DoseLog.fromJson(v as Map<String, dynamic>)));
      settings = AppSettings.fromJson(data['settings'] as Map<String, dynamic>?);
    } catch (_) {
      medicines = [];
      logs = {};
      settings = AppSettings();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'medicines': medicines.map((m) => m.toJson()).toList(),
      'logs': logs.map((k, v) => MapEntry(k, v.toJson())),
      'settings': settings.toJson(),
    };
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  Future<void> _initNotifications() async {
    try {
      tz.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
      }
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      final android = notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      notificationsReady = true;
    } catch (_) {
      notificationsReady = false;
    }
  }

  Future<void> _onNotificationResponse(NotificationResponse response) async {
    final payload = response.payload ?? '';
    if (payload.startsWith('taken2|')) {
      // Nhắc hàng tuần lặp lại nên payload không mang ngày cố định:
      // bấm "Đã uống" thì ghi cho lần uống của chính ngày hôm nay.
      final rest = payload.substring('taken2|'.length).split('|');
      if (rest.length == 2) {
        final today = todayKey(DateTime.now());
        final key = '${rest[0]}|$today|${rest[1]}';
        logs[key] = DoseLog(status: 'taken', at: DateTime.now().toIso8601String());
        await _save();
        notifyListeners();
      }
      return;
    }
    if (payload.startsWith('taken|')) {
      final key = payload.substring('taken|'.length);
      final log = DoseLog(status: 'taken', at: DateTime.now().toIso8601String());
      logs[key] = log;
      await _save();
      notifyListeners();
    } else if (payload.startsWith('snooze|')) {
      final key = payload.substring('snooze|'.length);
      await scheduleSnooze(key);
    }
  }

  /// Lên lịch nhắc hàng tuần cho mọi thuốc, mọi ngày, mọi giờ.
  /// Mỗi lần đổi thuốc là hủy hết rồi lên lịch lại cho chắc chắn.
  Future<void> rescheduleAll() async {
    if (!notificationsReady) return;
    try {
      await notifications.cancelAll();
      for (final med in medicines) {
        for (final weekday in med.weekdays) {
          for (final time in med.times) {
            if (settings.inQuietHours(time)) continue;
            final id = stableHash('${med.id}|$weekday|$time') % 2000000000;
            final scheduled = _nextWeekdayTime(weekday, time);
            final details = NotificationDetails(
              android: AndroidNotificationDetails(
                _channelId,
                'Nhắc uống thuốc',
                channelDescription: 'Nhắc uống thuốc đúng giờ mỗi ngày',
                importance: Importance.max,
                priority: Priority.high,
                playSound: settings.sound,
                enableVibration: settings.vibration,
                actions: const [
                  AndroidNotificationAction('taken', 'Đã uống'),
                  AndroidNotificationAction('snooze', 'Nhắc lại sau'),
                ],
              ),
            );
            final body = '${med.formEmoji} ${med.name} — ${med.dose}'
                '${med.note.isNotEmpty ? '\n${med.note}' : ''}';
            try {
              await notifications.zonedSchedule(
                id,
                'Đến giờ uống thuốc rồi!',
                body,
                scheduled,
                details,
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                uiLocalNotificationDateInterpretation:
                    UILocalNotificationDateInterpretation.absoluteTime,
                matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
                payload: 'taken2|${med.id}|$time',
              );
            } catch (_) {
              // Máy chưa cấp quyền báo thức chính xác thì dùng lịch không chính xác.
              try {
                await notifications.zonedSchedule(
                  id,
                  'Đến giờ uống thuốc rồi!',
                  body,
                  scheduled,
                  details,
                  androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
                  uiLocalNotificationDateInterpretation:
                      UILocalNotificationDateInterpretation.absoluteTime,
                  matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
                  payload: 'taken2|${med.id}|$time',
                );
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  tz.TZDateTime _nextWeekdayTime(int weekday, String hhmm) {
    final parts = hhmm.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    var scheduled = tz.TZDateTime(
      tz.local,
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      hour,
      minute,
    );
    while (scheduled.weekday != weekday || scheduled.isBefore(tz.TZDateTime.now(tz.local))) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  Future<void> scheduleSnooze(String slotKey) async {
    if (!notificationsReady) return;
    try {
      final parts = slotKey.split('|');
      if (parts.length != 3) return;
      final med = medicines.where((m) => m.id == parts[0]).toList();
      if (med.isEmpty) return;
      final at = tz.TZDateTime.now(tz.local).add(const Duration(minutes: 10));
      await notifications.zonedSchedule(
        stableHash('snooze|$slotKey') % 2000000000,
        'Nhắc lại: đến giờ uống thuốc!',
        '${med.first.formEmoji} ${med.first.name} — ${med.first.dose}',
        at,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Nhắc uống thuốc',
            channelDescription: 'Nhắc uống thuốc đúng giờ mỗi ngày',
            importance: Importance.max,
            priority: Priority.high,
            playSound: settings.sound,
            enableVibration: settings.vibration,
            actions: const [
              AndroidNotificationAction('taken', 'Đã uống'),
              AndroidNotificationAction('snooze', 'Nhắc lại sau'),
            ],
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'taken|$slotKey',
      );
    } catch (_) {}
  }

  List<DoseSlot> slotsForDay(DateTime day) {
    final out = <DoseSlot>[];
    for (final med in medicines) {
      if (!med.activeOn(day)) continue;
      for (final time in med.times) {
        out.add(DoseSlot(medicine: med, time: time, day: day));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  String? statusOf(DoseSlot slot) => logs[slot.key]?.status;

  Future<void> markTaken(DoseSlot slot) async {
    logs[slot.key] = DoseLog(status: 'taken', at: DateTime.now().toIso8601String());
    await _save();
    notifyListeners();
  }

  Future<void> markSkipped(DoseSlot slot, String reason) async {
    logs[slot.key] = DoseLog(
      status: 'skipped',
      at: DateTime.now().toIso8601String(),
      reason: reason,
    );
    await _save();
    notifyListeners();
  }

  Future<void> addMedicine(Medicine med) async {
    medicines.add(med);
    await _save();
    notifyListeners();
    await rescheduleAll();
  }

  Future<void> updateMedicine(Medicine med) async {
    final i = medicines.indexWhere((m) => m.id == med.id);
    if (i == -1) return;
    medicines[i] = med;
    await _save();
    notifyListeners();
    await rescheduleAll();
  }

  Future<void> deleteMedicine(String id) async {
    medicines.removeWhere((m) => m.id == id);
    logs.removeWhere((k, _) => k.startsWith('$id|'));
    await _save();
    notifyListeners();
    await rescheduleAll();
  }

  Future<void> updateSettings(AppSettings next) async {
    settings = next;
    await _save();
    notifyListeners();
    await rescheduleAll();
  }

  Future<void> clearAll() async {
    medicines = [];
    logs = {};
    await _save();
    notifyListeners();
    await rescheduleAll();
  }

  /// Chuỗi ngày liên tục uống đủ (tính ngược từ hôm qua, hôm nay chưa xong thì không phá chuỗi).
  int currentStreak() {
    var streak = 0;
    var day = DateTime.now().subtract(const Duration(days: 1));
    for (var i = 0; i < 365; i++) {
      final slots = slotsForDay(day);
      if (slots.isEmpty) {
        day = day.subtract(const Duration(days: 1));
        continue;
      }
      final allTaken = slots.every((s) => logs[s.key]?.status == 'taken');
      if (!allTaken) break;
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Tỷ lệ uống đúng trong 30 ngày qua (chỉ tính các lần đã qua giờ).
  double adherence30Days() {
    var taken = 0;
    var total = 0;
    final now = DateTime.now();
    for (var i = 0; i < 30; i++) {
      final day = now.subtract(Duration(days: i));
      for (final slot in slotsForDay(day)) {
        if (slot.dateTime.isAfter(now)) continue;
        total++;
        if (logs[slot.key]?.status == 'taken') taken++;
      }
    }
    if (total == 0) return 0;
    return taken / total;
  }

  /// Thuốc hay bị bỏ qua nhất trong 30 ngày qua (trả về tên hoặc null).
  String? mostMissedMedicine() {
    final counts = <String, int>{};
    final now = DateTime.now();
    for (var i = 0; i < 30; i++) {
      final day = now.subtract(Duration(days: i));
      for (final slot in slotsForDay(day)) {
        if (slot.dateTime.isAfter(now)) continue;
        if (logs[slot.key]?.status == 'skipped') {
          counts[slot.medicine.name] = (counts[slot.medicine.name] ?? 0) + 1;
        }
      }
    }
    if (counts.isEmpty) return null;
    var best = counts.entries.first;
    for (final e in counts.entries) {
      if (e.value > best.value) best = e;
    }
    return '${best.key} (${best.value} lần)';
  }
}
