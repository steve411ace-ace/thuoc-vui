import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
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
  // Báo lại tự động khi chưa check-in: mỗi remindIntervalMinutes phút,
  // tối đa remindTimes lần sau lần nhắc chính (0 = tắt báo lại).
  int remindIntervalMinutes;
  int remindTimes;

  AppSettings({
    this.sound = true,
    this.vibration = true,
    this.quietStart = '22:00',
    this.quietEnd = '07:00',
    this.remindIntervalMinutes = 10,
    this.remindTimes = 3,
  });

  AppSettings copyWith({
    bool? sound,
    bool? vibration,
    String? quietStart,
    String? quietEnd,
    int? remindIntervalMinutes,
    int? remindTimes,
  }) =>
      AppSettings(
        sound: sound ?? this.sound,
        vibration: vibration ?? this.vibration,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
        remindIntervalMinutes: remindIntervalMinutes ?? this.remindIntervalMinutes,
        remindTimes: remindTimes ?? this.remindTimes,
      );

  Map<String, dynamic> toJson() => {
        'sound': sound,
        'vibration': vibration,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
        'remindIntervalMinutes': remindIntervalMinutes,
        'remindTimes': remindTimes,
      };

  factory AppSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return AppSettings();
    return AppSettings(
      sound: j['sound'] as bool? ?? true,
      vibration: j['vibration'] as bool? ?? true,
      quietStart: j['quietStart'] as String? ?? '22:00',
      quietEnd: j['quietEnd'] as String? ?? '07:00',
      remindIntervalMinutes: (j['remindIntervalMinutes'] as num?)?.toInt() ?? 10,
      remindTimes: (j['remindTimes'] as num?)?.toInt() ?? 3,
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
    await updateHomeWidget();
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
      // Di chuyển dữ liệu cũ: log 'taken' nhưng check-in realtime trễ quá 30 phút
      // so với giờ hẹn thì chuyển thành 'late'.
      for (final entry in logs.entries.toList()) {
        if (entry.value.status != 'taken') continue;
        final slot = _slotFromKey(entry.key);
        final at = DateTime.tryParse(entry.value.at);
        if (slot != null && at != null && at.isAfter(slot.dateTime.add(const Duration(minutes: 30)))) {
          logs[entry.key] = DoseLog(status: 'late', at: entry.value.at, reason: entry.value.reason);
        }
      }
      settings = AppSettings.fromJson(data['settings'] as Map<String, dynamic>?);
    } catch (_) {
      medicines = [];
      logs = {};
      settings = AppSettings();
    }
  }

  /// Nạp lại dữ liệu từ máy khi app mở lại (resumed). Cần thiết vì
  /// check-in từ widget (Kotlin) ghi trực tiếp vào SharedPreferences,
  /// còn Dart đang giữ bản cũ trong bộ nhớ: nếu không nạp lại mà Dart
  /// ghi đè thì sẽ xóa mất check-in từ widget.
  Future<void> reload() async {
    await _load();
    notifyListeners();
    try {
      await updateHomeWidget();
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'medicines': medicines.map((m) => m.toJson()).toList(),
      'logs': logs.map((k, v) => MapEntry(k, v.toJson())),
      'settings': settings.toJson(),
    };
    await prefs.setString(_storageKey, jsonEncode(data));
    try { await updateHomeWidget(); } catch (_) {}
  }

  /// Chuỗi sao lưu để copy ra ngoài app (dán vào Ghi chú/email giữ lại).
  /// Đây chính là dữ liệu đang lưu trong máy, dùng để khôi phục sau khi
  /// gỡ và cài lại app, vì gỡ app sẽ xóa dữ liệu trong máy.
  String exportBackup() {
    final data = {
      'medicines': medicines.map((m) => m.toJson()).toList(),
      'logs': logs.map((k, v) => MapEntry(k, v.toJson())),
      'settings': settings.toJson(),
    };
    return jsonEncode(data);
  }

  /// Khôi phục từ chuỗi sao lưu. Trả về false nếu chuỗi không đúng định dạng.
  Future<bool> importBackup(String raw) async {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final meds = (data['medicines'] as List<dynamic>)
          .map((e) => Medicine.fromJson(e as Map<String, dynamic>))
          .toList();
      final logMap = data['logs'] as Map<String, dynamic>? ?? {};
      final newLogs = logMap.map((k, v) => MapEntry(k, DoseLog.fromJson(v as Map<String, dynamic>)));
      medicines = meds;
      logs = newLogs;
      settings = AppSettings.fromJson(data['settings'] as Map<String, dynamic>?);
      await _save();
      await rescheduleAll();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
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
      const androidInit = AndroidInitializationSettings('ic_stat_pip');
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

  /// Kiểm tra quyền thông báo hiện tại (dùng trong tab Cài đặt).
  Future<bool> notificationsEnabled() async {
    try {
      final android = notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Xin lại quyền thông báo (bấm từ Cài đặt). Nếu người dùng đã từ chối
  /// vĩnh viễn thì Android không hiện hộp thoại nữa, hàm trả về false và
  /// app sẽ hướng dẫn bật tay trong Cài đặt hệ thống.
  Future<bool> requestNotificationPermission() async {
    try {
      final android = notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      if (granted) {
        notificationsReady = true;
        await rescheduleAll();
      }
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra + xin quyền báo thức chính xác (Android 12+ cần quyền này thì
  /// nhắc đúng giờ mới chính xác; chưa có thì app vẫn nhắc nhưng có thể lệch).
  Future<bool> canScheduleExact() async {
    try {
      final android = notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestExactAlarmPermission() async {
    try {
      final android = notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestExactAlarmsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Trạng thái quyền báo thức chính xác + miễn tối ưu pin, để chẩn đoán
  /// "gửi ngay thì hiện, đến giờ thì không": lịch theo giờ cần cả hai.
  Future<String> alarmPermissionStatus() async {
    final exact = await canScheduleExact();
    bool ignoringBattery = false;
    try {
      const channel = MethodChannel('thuoc_vui/reminders');
      ignoringBattery = await channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } catch (_) {}
    return 'Báo thức chính xác: ${exact ? 'ĐÃ BẬT' : 'CHƯA BẬT'}\n'
        'Miễn tối ưu pin: ${ignoringBattery ? 'ĐÃ BẬT' : 'CHƯA BẬT'}\n\n'
        'Cả hai đều cần BẬT thì lịch theo giờ mới chạy đúng giờ trên Samsung. '
        'Nếu báo thức chính xác CHƯA BẬT, bấm "Cho phép báo thức chính xác" rồi bật trong Cài đặt máy. '
        'Nếu miễn tối ưu pin CHƯA BẬT, bấm "Tắt tối ưu pin cho Thuốc Vui".';
  }

  /// Nhắc thử bằng báo thức native sau 1 phút (không qua plugin).
  /// Nếu sau 1 phút không thấy thì máy đang chặn báo thức
  /// (pin / báo thức chính xác).
  Future<void> sendNativeScheduledTestNotification() async {
    try {
      const channel = MethodChannel('thuoc_vui/reminders');
      await channel.invokeMethod('scheduleNativeTest');
    } catch (_) {}
  }

  /// Lần bấm nút trên thông báo cuối, do receiver native ghi lại, để
  /// chẩn đoán "bấm Đã uống / Nhắc lại sau không có tác dụng": nếu bấm
  /// rồi mà giá trị này không đổi thì lệnh bấm không tới receiver; nếu
  /// đổi mà app không cập nhật thì lỗi nằm ở phần ghi log / nạp lại.
  Future<String> lastNotificationActionSummary() async {
    try {
      final value = await HomeWidget.getWidgetData<String>('last_notification_action', defaultValue: '');
      if (value == null || value.isEmpty) return 'Chưa ghi nhận lần bấm nút thông báo nào.';
      return value;
    } catch (_) {
      return 'Không đọc được lần bấm thông báo.';
    }
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      const channel = MethodChannel('thuoc_vui/reminders');
      return await channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Lần bấm widget cuối, do receiver native ghi lại, để chẩn đoán
  /// "bấm nút widget không có gì": nếu bấm rồi mà giá trị này không đổi
  /// thì lệnh bấm không tới receiver; nếu đổi mà không check-in thì
  /// lỗi nằm ở phần ghi log.
  Future<String> lastWidgetTapSummary() async {
    try {
      final value = await HomeWidget.getWidgetData<String>('last_widget_tap', defaultValue: '');
      if (value == null || value.isEmpty) return 'Chưa ghi nhận lần bấm widget nào.';
      return value;
    } catch (_) {
      return 'Không đọc được lần bấm widget.';
    }
  }

  /// Giờ hẹn của một slot, suy từ key dạng medId|yyyy-MM-dd|HH:mm.
  DoseSlot? _slotFromKey(String key) {
    final parts = key.split('|');
    if (parts.length != 3) return null;
    final meds = medicines.where((m) => m.id == parts[0]).toList();
    if (meds.isEmpty) return null;
    final dateParts = parts[1].split('-');
    if (dateParts.length != 3) return null;
    final day = DateTime(int.parse(dateParts[0]), int.parse(dateParts[1]), int.parse(dateParts[2]));
    return DoseSlot(medicine: meds.first, time: parts[2], day: day);
  }

  /// Ghi check-in realtime: trễ quá 30 phút so với giờ hẹn thì là 'late'.
  String _statusForCheckIn(DoseSlot slot, DateTime at) {
    return at.isAfter(slot.dateTime.add(const Duration(minutes: 30))) ? 'late' : 'taken';
  }

  Future<void> _markLogTaken(String key) async {
    // Đã uống/trễ/bỏ qua rồi thì bỏ qua, tránh lần nhắc lại bấm nhầm
    // ghi đè trạng thái cũ (ví dụ đã uống đúng giờ thành trễ).
    final existing = logs[key]?.status;
    if (existing == 'taken' || existing == 'late' || existing == 'skipped') return;
    final slot = _slotFromKey(key);
    final now = DateTime.now();
    final status = slot == null ? 'taken' : _statusForCheckIn(slot, now);
    logs[key] = DoseLog(status: status, at: now.toIso8601String());
    await _save();
    notifyListeners();
    await rescheduleAll();
  }

  Future<void> _onNotificationResponse(NotificationResponse response) async {
    final action = response.actionId;
    final payload = response.payload ?? '';
    // Bấm vào thân noti (không có actionId) chỉ mở app, không ghi gì.
    if (action == null || action.isEmpty) return;
    if (action == 'snooze') {
      String? key;
      if (payload.startsWith('taken2|')) {
        final rest = payload.substring('taken2|'.length).split('|');
        if (rest.length == 2) key = '${rest[0]}|${todayKey(DateTime.now())}|${rest[1]}';
      } else if (payload.startsWith('taken|')) {
        key = payload.substring('taken|'.length);
      }
      if (key != null) await scheduleSnooze(key);
      return;
    }
    if (action != 'taken') return;
    if (payload.startsWith('taken2|')) {
      final rest = payload.substring('taken2|'.length).split('|');
      if (rest.length == 2) {
        await _markLogTaken('${rest[0]}|${todayKey(DateTime.now())}|${rest[1]}');
      }
      return;
    }
    if (payload.startsWith('taken|')) {
      await _markLogTaken(payload.substring('taken|'.length));
    }
  }

  /// Lên lịch nhắc hàng tuần cho mọi thuốc, mọi ngày, mọi giờ.
  /// Mỗi lần đổi thuốc là hủy hết rồi lên lịch lại cho chắc chắn.
  /// Ngoài lần nhắc chính, mỗi lần uống còn có thêm remindTimes lần nhắc
  /// lại hàng tuần, mỗi lần cách nhau remindIntervalMinutes phút, để
  /// nhắc lại khi người dùng chưa bấm đã uống.
  Future<void> rescheduleAll() async {
    if (!notificationsReady) return;
    try {
      // QUAN TRỌNG (1.2.9): cancelAll của plugin PHẢI tách riêng.
      // Kho lưu lịch plugin trên máy anh đã hỏng (loadScheduledNotifications
      // ném "Missing type parameter", xem ảnh chẩn đoán 00:19), nên
      // cancelAll cũng ném theo. Nếu để nó chung try với phần dưới thì
      // ngoại lệ sẽ chặn luôn scheduleNativeAlarms(), tức là lần nhắc
      // chính native sẽ KHÔNG BAO GIỜ được lên lịch, dù code native
      // đã đúng. Hủy plugin thất bại thì cứ bỏ qua, lịch native vẫn
      // phải được lên.
      try {
        await notifications.cancelAll();
      } catch (_) {}
      // Lần nhắc chính KHÔNG dùng lịch plugin nữa (1.2.8): lịch plugin
      // zonedSchedule không bao giờ tới giờ trên máy anh, kể cả nhắc thử
      // sau 1 phút, dù gửi ngay vẫn hiện. Thay vào đó, lần nhắc chính
      // cũng dùng báo thức native qua ReReminderReceiver, giống báo lại:
      // lúc báo tới, receiver đọc log hôm nay trước, đã uống/trễ/bỏ qua
      // rồi thì không hiện, chưa bấm thì hiện với nút Đã uống / Nhắc lại
      // sau, và tự đặt lại cho tuần sau. Xem scheduleNativeAlarms().
      final mainAlarms = <Map<String, dynamic>>[];
      for (final med in medicines) {
        for (final weekday in med.weekdays) {
          for (final time in med.times) {
            if (settings.inQuietHours(time)) continue;
            final scheduled = _nextWeekdayTime(weekday, time);
            final body = '${med.formEmoji} ${med.name} — ${med.dose}'
                '${med.note.isNotEmpty ? '\n${med.note}' : ''}';
            mainAlarms.add({
              'id': stableHash('main|${med.id}|$weekday|$time') % 2000000000,
              'triggerMillis': scheduled.millisecondsSinceEpoch,
              'title': 'Đến giờ uống thuốc rồi!',
              'body': body,
              'medId': med.id,
              'slotTime': time,
              'intervalMinutes': settings.remindIntervalMinutes,
              'sound': settings.sound,
              'vibration': settings.vibration,
            });
            // Báo lại KHÔNG dùng lịch plugin ở đây nữa. Lý do: lịch plugin
            // hiện thông báo vô điều kiện khi tới giờ, nên bấm đã uống trên
            // widget (ghi log trực tiếp bằng Kotlin, không qua Dart) sẽ
            // không hủy được lần báo lại đó. Thay vào đó, Dart gửi danh
            // sách báo lại sang native (MethodChannel) để ReReminderReceiver
            // đặt báo thức riêng: lúc báo thức tới, receiver đọc log hôm
            // nay trước, đã uống/trễ/bỏ qua rồi thì không hiện thông báo
            // nữa, bất kể lần uống đó được bấm ở app, widget hay thông báo.
            // Xem scheduleNativeAlarms() ở cuối rescheduleAll.
          }
        }
      }
      await scheduleNativeAlarms(mainAlarms);
    } catch (_) {}
  }

  /// Gửi danh sách báo lại sang native để ReReminderReceiver đặt báo thức.
  /// Mỗi lần uống có remindTimes lần báo lại, mỗi lần cách nhau
  /// remindIntervalMinutes phút. Nếu giờ báo lại rơi vào giờ yên lặng thì
  /// bỏ qua lần đó. Native sẽ tự đặt lại cho tuần sau mỗi khi báo thức tới,
  /// nên báo lại chạy hàng tuần mà không cần mở app.
  Future<void> scheduleNativeAlarms(List<Map<String, dynamic>> mainAlarms) async {
    try {
      const channel = MethodChannel('thuoc_vui/reminders');
      final alarms = <Map<String, dynamic>>[];
      if (settings.remindTimes > 0 && settings.remindIntervalMinutes > 0) {
        for (final med in medicines) {
          for (final weekday in med.weekdays) {
            for (final time in med.times) {
              if (settings.inQuietHours(time)) continue;
              final baseParts = time.split(':');
              final baseMinutes = int.parse(baseParts[0]) * 60 + int.parse(baseParts[1]);
              for (var i = 1; i <= settings.remindTimes; i++) {
                final total = baseMinutes + settings.remindIntervalMinutes * i;
                final daysOver = total ~/ 1440;
                final remindMinutes = total % 1440;
                final remindWeekday = ((weekday - 1 + daysOver) % 7) + 1;
                final remindHhmm =
                    '${(remindMinutes ~/ 60).toString().padLeft(2, '0')}:${(remindMinutes % 60).toString().padLeft(2, '0')}';
                if (settings.inQuietHours(remindHhmm)) continue;
                final trigger = _nextWeekdayTime(remindWeekday, remindHhmm);
                alarms.add({
                  'id': stableHash('remind|${med.id}|$weekday|$time|$i') % 2000000000,
                  'triggerMillis': trigger.millisecondsSinceEpoch,
                  'title': 'Nhắc lại lần $i: đến giờ uống thuốc!',
                  'body': '${med.formEmoji} ${med.name} — ${med.dose}\nChưa thấy bạn bấm đã uống, nhắc lại lần $i.',
                  'medId': med.id,
                  'slotTime': time,
                  'intervalMinutes': settings.remindIntervalMinutes,
                  'sound': settings.sound,
                  'vibration': settings.vibration,
                });
              }
            }
          }
        }
      }
      final allAlarms = <Map<String, dynamic>>[...mainAlarms, ...alarms];
      await channel.invokeMethod('scheduleReReminders', {'alarms': allAlarms});
    } catch (_) {
      // Native chưa sẵn sàng thì lần nhắc chính (plugin) vẫn chạy,
      // chỉ thiếu báo lại; lần reschedule sau sẽ thử lại.
    }
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
      final at = tz.TZDateTime.now(tz.local)
          .add(Duration(minutes: settings.remindIntervalMinutes > 0 ? settings.remindIntervalMinutes : 10));
      await notifications.zonedSchedule(
        stableHash('snooze|$slotKey') % 2000000000,
        'Nhắc lại: đến giờ uống thuốc!',
        '${med.first.formEmoji} ${med.first.name} — ${med.first.dose}',
        at,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Nhắc uống thuốc',
          icon: 'ic_stat_pip',
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

  /// Trả về 'taken' (đúng giờ) hoặc 'late' (trễ quá 30 phút, tính theo giờ realtime).
  Future<String> markTaken(DoseSlot slot) async {
    final now = DateTime.now();
    final status = _statusForCheckIn(slot, now);
    logs[slot.key] = DoseLog(status: status, at: now.toIso8601String());
    await _save();
    notifyListeners();
    // Lên lịch lại để hủy các lần nhắc lại còn lại trong ngày của lần này.
    await rescheduleAll();
    return status;
  }

  Future<void> markSkipped(DoseSlot slot, String reason) async {
    logs[slot.key] = DoseLog(
      status: 'skipped',
      at: DateTime.now().toIso8601String(),
      reason: reason,
    );
    await _save();
    notifyListeners();
    await rescheduleAll();
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
    // Android: kênh thông báo đã tạo rồi thì đổi âm thanh/rung trong
    // NotificationDetails sẽ không có tác dụng (hệ thống giữ kênh cũ).
    // Vì vậy khi âm thanh/rung đổi thì xóa kênh cũ trước, lần nhắc sau
    // sẽ tạo lại kênh với cấu hình mới. Đây là lý do cấu hình trên đầu
    // Cài đặt trước đây trông như không có tác dụng.
    final soundChanged = next.sound != settings.sound || next.vibration != settings.vibration;
    settings = next;
    await _save();
    notifyListeners();
    if (soundChanged) {
      try {
        final android = notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.deleteNotificationChannel(_channelId);
      } catch (_) {}
    }
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
      final allTaken = slots.every((s) => logs[s.key]?.status == 'taken' || logs[s.key]?.status == 'late');
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
        if (logs[slot.key]?.status == 'taken' || logs[slot.key]?.status == 'late') taken++;
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

  bool _isCompleted(DoseSlot s) =>
      logs[s.key]?.status == 'taken' || logs[s.key]?.status == 'late';
  bool _isOnTime(DoseSlot s) => logs[s.key]?.status == 'taken';

  /// Chuỗi ngày liên tiếp uống đủ VÀ đúng giờ (không trễ, không bỏ qua).
  int onTimeStreak() {
    var streak = 0;
    var day = DateTime.now().subtract(const Duration(days: 1));
    for (var i = 0; i < 365; i++) {
      final slots = slotsForDay(day);
      if (slots.isEmpty) {
        day = day.subtract(const Duration(days: 1));
        continue;
      }
      if (!slots.every(_isOnTime)) break;
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int totalOnTime() => logs.values.where((l) => l.status == 'taken').length;

  bool _isPerfectDay(DateTime day) {
    final slots = slotsForDay(day);
    return slots.isNotEmpty && slots.every(_isOnTime);
  }

  Set<String> earnedBadgeIds() {
    final earned = <String>{};
    final onTime = totalOnTime();
    final streak = onTimeStreak();
    if (onTime >= 1) earned.add('first_ontime');
    var day = DateTime.now();
    for (var i = 0; i < 365; i++) {
      if (_isPerfectDay(day)) { earned.add('perfect_day'); break; }
      day = day.subtract(const Duration(days: 1));
    }
    if (streak >= 3) earned.add('streak_3');
    if (streak >= 7) earned.add('streak_7');
    if (streak >= 30) earned.add('streak_30');
    if (onTime >= 50) earned.add('ontime_50');
    if (onTime >= 100) earned.add('ontime_100');
    return earned;
  }

  /// Đẩy dữ liệu hôm nay lên widget màn hình chính.
  Future<void> updateHomeWidget() async {
    try {
      final today = DateTime.now();
      final slots = slotsForDay(today);
      final completed = slots.where(_isCompleted).length;
      final onTime = slots.where(_isOnTime).length;
      DoseSlot? next;
      for (final s in slots) {
        if (!_isCompleted(s)) { next = s; break; }
      }
      // Trạng thái Pip lên widget: cùng logic mặt + thông tin như trong app.
      final skipped = slots.where((s) => logs[s.key]?.status == 'skipped').length;
      final overdue = slots.any((s) => logs[s.key]?.status == null && s.dateTime.isBefore(DateTime.now()));
      final streak = onTimeStreak();
      final String pipMessage;
      if (slots.isEmpty) {
        pipMessage = '😊 Thêm thuốc để Pip nhắc bạn nhé!';
      } else if (onTime == slots.length) {
        pipMessage = streak >= 2
            ? '🥳 Hôm nay uống đủ và đúng giờ hết rồi! Chuỗi: $streak ngày 🔥'
            : '🥳 Hôm nay uống đủ và đúng giờ hết rồi, tuyệt vời!';
      } else if (completed == slots.length) {
        pipMessage = '😊 Hôm nay uống đủ hết rồi, có ${completed - onTime} lần trễ, lần sau cố đúng giờ nhé!';
      } else if (overdue) {
        pipMessage = '😟 Ơ, có lần uống quá giờ chưa thấy bạn bấm, uống bù nhé?';
      } else if (skipped > 0) {
        pipMessage = '😟 Hôm nay bạn bỏ qua $skipped lần, mai cố nhé?';
      } else {
        pipMessage = streak >= 2
            ? '😊 Hôm nay còn ${slots.length - completed} lần nữa là xong! Chuỗi: $streak ngày 🔥'
            : '😊 Hôm nay còn ${slots.length - completed} lần nữa là xong, cố lên nhé!';
      }
      await HomeWidget.saveWidgetData<String>('pip_message', pipMessage);
      await HomeWidget.saveWidgetData<String>('progress', slots.isEmpty ? 'Chưa có thuốc hôm nay' : 'Hôm nay: $completed/${slots.length} lần • đúng giờ $onTime lần');
      await HomeWidget.saveWidgetData<String>('next_text', next == null ? (slots.isEmpty ? 'Thêm thuốc để Pip nhắc bạn nhé!' : '🎉 Đã xong hôm nay!') : '${next.medicine.formEmoji} ${next.medicine.name} — ${next.medicine.dose}');
      await HomeWidget.saveWidgetData<String>('next_time', next == null ? '' : 'Lúc ${next.time} • ${next.medicine.mealLabel}');
      await HomeWidget.saveWidgetData<String>('all_done', next == null && slots.isNotEmpty ? '1' : '0');
      await HomeWidget.updateWidget(name: 'ThuocVuiWidgetProvider', androidName: 'ThuocVuiWidgetProvider');
    } catch (_) {}
  }
}
