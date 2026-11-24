import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'home_style.dart';
import 'models.dart';
import 'strings.dart';

const String _storageKey = 'thuoc_vui_v1';
const String _channelId = 'thuoc_vui_reminder';

enum WidgetThemeMode { system, light, dark }

class AppSettings {
  bool sound;
  bool vibration;
  String quietStart; // HH:mm
  String quietEnd; // HH:mm
  // Báo lại tự động khi chưa check-in: mỗi remindIntervalMinutes phút,
  // tối đa remindTimes lần sau lần nhắc chính (0 = tắt báo lại).
  int remindIntervalMinutes;
  int remindTimes;
  final HomePalette palette;
  final Color customColor;
  final ThemeMode appThemeMode;
  // Độ mờ nền widget (%), 100 = đặc như cũ, 50 = trong suốt nhất cho phép.
  int widgetOpacity;
  final WidgetThemeMode widgetThemeMode;
  final AppLang language;

  AppSettings({
    this.sound = true,
    this.vibration = true,
    this.quietStart = '22:00',
    this.quietEnd = '07:00',
    this.remindIntervalMinutes = 15,
    this.remindTimes = 3,
    this.palette = HomePalette.light,
    this.customColor = HomePalette.defaultCustomColor,
    this.appThemeMode = ThemeMode.system,
    this.widgetOpacity = 100,
    this.widgetThemeMode = WidgetThemeMode.system,
    this.language = AppLang.vi,
  });

  AppSettings copyWith({
    bool? sound,
    bool? vibration,
    String? quietStart,
    String? quietEnd,
    int? remindIntervalMinutes,
    int? remindTimes,
    HomePalette? palette,
    Color? customColor,
    ThemeMode? appThemeMode,
    int? widgetOpacity,
    WidgetThemeMode? widgetThemeMode,
    AppLang? language,
  }) =>
      AppSettings(
        sound: sound ?? this.sound,
        vibration: vibration ?? this.vibration,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
        remindIntervalMinutes: remindIntervalMinutes ?? this.remindIntervalMinutes,
        remindTimes: remindTimes ?? this.remindTimes,
        palette: palette ?? this.palette,
        customColor: customColor ?? this.customColor,
        appThemeMode: appThemeMode ?? this.appThemeMode,
        widgetOpacity: widgetOpacity ?? this.widgetOpacity,
        widgetThemeMode: widgetThemeMode ?? this.widgetThemeMode,
        language: language ?? this.language,
      );

  Map<String, dynamic> toJson() => {
        'sound': sound,
        'vibration': vibration,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
        'remindIntervalMinutes': remindIntervalMinutes,
        'remindTimes': remindTimes,
        'palette': palette.name,
        'customColor': customColor.value & 0xFFFFFF,
        'appThemeMode': appThemeMode.name,
        'widgetOpacity': widgetOpacity,
        'widgetThemeMode': widgetThemeMode.name,
        'language': language.code,
      };

  factory AppSettings.fromJson(Map<String, dynamic>? j) {
    if (j == null) return AppSettings();
    return AppSettings(
      sound: j['sound'] as bool? ?? true,
      vibration: j['vibration'] as bool? ?? true,
      quietStart: j['quietStart'] as String? ?? '22:00',
      quietEnd: j['quietEnd'] as String? ?? '07:00',
      remindIntervalMinutes: (j['remindIntervalMinutes'] as num?)?.toInt() ?? 15,
      remindTimes: (j['remindTimes'] as num?)?.toInt() ?? 3,
      palette: HomePalette.fromName(j['palette']),
      customColor: j['customColor'] is int
          ? Color(0xFF000000 | ((j['customColor'] as int) & 0xFFFFFF))
          : HomePalette.defaultCustomColor,
      appThemeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == j['appThemeMode'],
        orElse: () => ThemeMode.system,
      ),
      widgetOpacity: (j['widgetOpacity'] as num?)?.toInt() ?? 100,
      widgetThemeMode: WidgetThemeMode.values.firstWhere(
        (mode) => mode.name == j['widgetThemeMode'],
        orElse: () => WidgetThemeMode.system,
      ),
      language: AppLang.fromCode(j['language']),
    );
  }

  Future<void> saveWidgetAppearance() async {
    final rgb = palette.accent(customColor).value & 0xFFFFFF;
    final hex = '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
    await HomeWidget.saveWidgetData<String>('widget_accent', hex);
    await HomeWidget.saveWidgetData<String>('widget_theme', widgetThemeMode.name);
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
  List<PurchaseRecord> purchases = [];
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
    // QUAN TRỌNG (1.2.14): SharedPreferences của Dart giữ cache trong bộ nhớ.
    // Kotlin (widget / nút thông báo) ghi trực tiếp vào file trên máy, Dart
    // không tự thấy. Trước đây reload() chỉ đọc lại từ cache nên vẫn là dữ
    // liệu cũ, và lần _save() sau đó còn ghi đè mất check-in từ Kotlin.
    // prefs.reload() bắt Dart đọc lại từ file, nên check-in từ nút thông
    // báo / widget mới hiện trong app khi mở lại hoặc chuyển tab.
    try { await prefs.reload(); } catch (_) {}
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      medicines = [];
      purchases = [];
      logs = {};
      settings = AppSettings();
      Lang.current = settings.language;
      return;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      medicines = (data['medicines'] as List<dynamic>)
          .map((e) => Medicine.fromJson(e as Map<String, dynamic>))
          .toList();
      purchases = _readPurchases(data);
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
      Lang.current = settings.language;
    } catch (_) {
      medicines = [];
      purchases = [];
      logs = {};
      settings = AppSettings();
      Lang.current = settings.language;
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

  Future<void> _save({bool refreshWidget = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'medicines': medicines.map((m) => m.toJson()).toList(),
      'purchases': purchases.map((p) => p.toJson()).toList(),
      'logs': logs.map((k, v) => MapEntry(k, v.toJson())),
      'settings': settings.toJson(),
    };
    await prefs.setString(_storageKey, jsonEncode(data));
    if (refreshWidget) {
      try { await updateHomeWidget(); } catch (_) {}
    }
  }

  List<PurchaseRecord> _readPurchases(Map<String, dynamic> data) =>
      (data['purchases'] as List<dynamic>? ?? [])
          .map((entry) => PurchaseRecord.fromJson(entry as Map<String, dynamic>))
          .toList();

  Future<void> addPurchase(PurchaseRecord purchase) async {
    purchases.add(purchase);
    await _save();
    notifyListeners();
  }

  Future<void> updatePurchase(PurchaseRecord purchase) async {
    final index = purchases.indexWhere((entry) => entry.id == purchase.id);
    if (index == -1) return;
    purchases[index] = purchase;
    await _save();
    notifyListeners();
  }

  Future<void> deletePurchase(String id) async {
    purchases.removeWhere((entry) => entry.id == id);
    await _save();
    notifyListeners();
  }

  int get totalPurchasedBoxes =>
      purchases.fold(0, (sum, purchase) => sum + purchase.boxes);

  int get totalPurchaseCost =>
      purchases.fold(0, (sum, purchase) => sum + purchase.total);

  String? get firstPurchaseDate {
    String? first;
    for (final purchase in purchases) {
      if (first == null || purchase.date.compareTo(first) < 0) {
        first = purchase.date;
      }
    }
    return first;
  }

  Map<String, ({int boxes, int cost})> purchasesByMonth() =>
      _purchasesByPeriod(7);

  Map<String, ({int boxes, int cost})> purchasesByYear() =>
      _purchasesByPeriod(4);

  Map<String, ({int boxes, int cost})> _purchasesByPeriod(int keyLength) {
    final totals = <String, ({int boxes, int cost})>{};
    final medicinesById = {
      for (final medicine in medicines) medicine.id: medicine,
    };

    void addToPeriod(String date, int boxes, int cost) {
      final period = date.substring(0, keyLength);
      final previous = totals[period];
      totals[period] = (
        boxes: (previous?.boxes ?? 0) + boxes,
        cost: (previous?.cost ?? 0) + cost,
      );
    }

    for (final purchase in purchases) {
      final medicine = medicinesById[purchase.medicineId];
      final pillsPerDose = medicine?.pillsPerDose ?? 1;
      final pillsPerDay =
          (medicine?.times.length ?? 0) * (pillsPerDose > 0 ? pillsPerDose : 1);
      final start = DateTime.tryParse(purchase.date);
      if (pillsPerDay <= 0 || purchase.boxes <= 1 || start == null) {
        addToPeriod(purchase.date, purchase.boxes, purchase.total);
        continue;
      }

      // Ngày của từng vỉ là ước tính theo lịch uống hiện tại của thuốc.
      final startDay = DateTime.utc(start.year, start.month, start.day);
      for (var i = 0; i < purchase.boxes; i++) {
        final offset = i * purchase.pillsPerBox ~/ pillsPerDay;
        final date = startDay.add(Duration(days: offset));
        addToPeriod(todayKey(date).padLeft(10, '0'), 1, purchase.pricePerBox);
      }
    }
    return totals;
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

  /// Số viên còn lại của 1 thuốc, null nếu không theo dõi (totalPills <= 0).
  /// Còn lại = tổng hộp − (viên bắt đầu − 1) − (số lần đã uống × viên mỗi lần).
  /// Chỉ đếm log taken/late từ ngày bắt đầu hộp (stockFrom, mặc định startDate).
  int? remainingPills(Medicine med) {
    if (med.totalPills <= 0) return null;
    final from = med.stockFrom.isNotEmpty ? med.stockFrom : med.startDate;
    // 1.2.30: nếu có mốc thời điểm mua hộp mới thì chỉ tính các lần
    // uống từ sau mốc đó (so tới giây, để khỏi lệch do phần lẻ giây
    // khác nhau giữa các định dạng ISO); không có mốc thì tính theo
    // ngày như cũ để tương thích hộp cũ.
    final cutoff =
        med.stockFromAt.isNotEmpty ? DateTime.tryParse(med.stockFromAt) : null;
    var taken = 0;
    for (final entry in logs.entries) {
      if (!entry.key.startsWith('${med.id}|')) continue;
      if (entry.value.status != 'taken' && entry.value.status != 'late') continue;
      final parts = entry.key.split('|');
      if (parts.length != 3) continue;
      if (cutoff != null) {
        final at = DateTime.tryParse(entry.value.at);
        if (at == null || at.isBefore(cutoff)) continue;
      } else {
        if (parts[1].compareTo(from) < 0) continue;
      }
      taken++;
    }
    final perDose = med.pillsPerDose > 0 ? med.pillsPerDose : 1;
    final start = med.startPill > 0 ? med.startPill : 1;
    final remaining = med.totalPills - (start - 1) - taken * perDose;
    return remaining < 0 ? 0 : remaining;
  }

  /// Số ngày uống còn đủ (ước tính theo số lần mỗi ngày, giả sử uống đều
  /// mỗi ngày; nếu thuốc không uống hàng ngày thì đây là ước tính thấp).
  int? daysSupply(Medicine med) {
    final remaining = remainingPills(med);
    if (remaining == null || med.times.isEmpty) return null;
    final perDose = med.pillsPerDose > 0 ? med.pillsPerDose : 1;
    final perDay = med.times.length * perDose;
    if (perDay <= 0) return null;
    return remaining ~/ perDay;
  }

  /// Câu nhắc mua thuốc cho 1 thuốc, null nếu không cần nhắc (còn nhiều
  /// hoặc không theo dõi). Dùng cho Pip và widget.
  String? buyPrompt(Medicine med) {
    final remaining = remainingPills(med);
    if (remaining == null) return null;
    if (remaining <= 0) {
      return tr(
        'Hết thuốc ${med.name} rồi! Mua hộp mới ngay nhé!',
        '${med.name} is out of stock! Buy a new box soon!',
      );
    }
    final days = daysSupply(med);
    if (days != null && days <= 3) {
      return tr(
        'Sắp hết thuốc ${med.name}, còn $remaining viên (đủ $days ngày), nhớ mua trước nhé!',
        'Low on ${med.name}: $remaining ${enPlural(remaining, 'pill', 'pills')} left ($days ${enPlural(days, 'day', 'days')}), remember to refill!',
      );
    }
    if (days != null && days > 7) return null; // Còn nhiều, khỏi nhắc mua.
    return null; // 4–7 ngày: chỉ hiện số viên, không nhắc mua.
  }

  /// Câu nhắc mua chung cho hôm nay (ưu tiên hết thuốc, rồi sắp hết).
  String? todayBuyPrompt() {
    String? low;
    for (final med in medicines) {
      final prompt = buyPrompt(med);
      if (prompt == null) continue;
      if ((remainingPills(med) ?? 1) <= 0) return prompt;
      low ??= prompt;
    }
    return low;
  }

  /// Đã mua hộp mới: tính lại từ hôm nay. Trả về số viên "vượt" đã trừ
  /// vào hộp mới (0 nếu không có).
  /// Các lần uống vượt hộp cũ (uống khi hộp cũ đã hết thuốc — viên đó
  /// thực chất lấy từ hộp mới) được trừ vào hộp mới qua viên bắt đầu:
  /// startPill = 1 + số viên vượt, nên số viên còn lại tính ra đã trừ
  /// đúng (công thức remainingPills dùng startPill nên app và widget
  /// đều đúng theo, không cần sửa bên Kotlin).
  /// Số viên vượt = số viên đã uống thuộc hộp cũ − số viên hộp cũ có
  /// (totalPills − (startPill − 1)); hộp cũ tính từ mốc mua trước
  /// (stockFromAt, hoặc theo ngày stockFrom nếu chưa có mốc).
  Future<int> buyNewBox(Medicine med) async {
    final perDose = med.pillsPerDose > 0 ? med.pillsPerDose : 1;
    final start = med.startPill > 0 ? med.startPill : 1;
    final capacity = med.totalPills - (start - 1);
    final prevCutoff =
        med.stockFromAt.isNotEmpty ? DateTime.tryParse(med.stockFromAt) : null;
    final from = med.stockFrom.isNotEmpty ? med.stockFrom : med.startDate;
    var oldTaken = 0;
    for (final entry in logs.entries) {
      if (!entry.key.startsWith('${med.id}|')) continue;
      if (entry.value.status != 'taken' && entry.value.status != 'late') continue;
      final parts = entry.key.split('|');
      if (parts.length != 3) continue;
      if (prevCutoff != null) {
        final at = DateTime.tryParse(entry.value.at);
        if (at == null || at.isBefore(prevCutoff)) continue;
      } else {
        if (parts[1].compareTo(from) < 0) continue;
      }
      oldTaken++;
    }
    final overdraft = oldTaken * perDose - capacity;
    final carry = overdraft > 0 ? overdraft : 0;
    med.stockFrom = todayKey(DateTime.now());
    med.stockFromAt = DateTime.now().toIso8601String();
    med.startPill = 1 + carry;
    await _save();
    notifyListeners();
    await updateHomeWidget();
    return carry;
  }

  /// Bổ sung thêm thuốc (+count viên). Nếu thuốc đang hết (<= 0 viên)
  /// thì gọi buyNewBox để đặt lại hộp mới và trừ viên vượt. Nếu thuốc
  /// chưa theo dõi (totalPills <= 0) thì đặt totalPills = count.
  Future<int> replenishMedicine(Medicine med, int count) async {
    if (med.totalPills <= 0) {
      med.totalPills = count;
      med.startPill = 1;
      med.stockFrom = todayKey(DateTime.now());
      med.stockFromAt = DateTime.now().toIso8601String();
      await _save();
      notifyListeners();
      await updateHomeWidget();
      return 0;
    }
    final remaining = remainingPills(med) ?? 0;
    if (remaining <= 0) {
      final over = await buyNewBox(med);
      med.totalPills = count;
      await _save();
      notifyListeners();
      await updateHomeWidget();
      return over;
    }
    med.totalPills += count;
    await _save();
    notifyListeners();
    await updateHomeWidget();
    return 0;
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      const channel = MethodChannel('thuoc_vui/reminders');
      return await channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations') ?? false;
    } catch (_) {
      return false;
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
              'title': tr('Đến giờ uống thuốc rồi!', 'Time to take your medicine!'),
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
      // 1.2.30: đặt lại báo thức nửa đêm để widget tự reset ngày mới
      // mà không cần mở app (báo thức tự đặt lại đêm sau khi tới,
      // xem ReReminderReceiver.ACTION_MIDNIGHT).
      await scheduleMidnightRefresh();
    } catch (_) {}
  }

  /// Đặt báo thức nửa đêm qua native (1.2.30). Lỗi thì bỏ qua: chu
  /// kỳ vẽ widget 30 phút + kiểm tra dấu ngày ở Kotlin vẫn tự chữa
  /// trong vòng 30 phút sau nửa đêm.
  Future<void> scheduleMidnightRefresh() async {
    try {
      const channel = MethodChannel('thuoc_vui/reminders');
      await channel.invokeMethod('scheduleMidnightRefresh');
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
                  'title': tr(
                    'Nhắc lại lần $i: đến giờ uống thuốc!',
                    'Reminder #$i: time to take your medicine!',
                  ),
                  'body': tr(
                    '${med.formEmoji} ${med.name} — ${med.dose}\nChưa thấy bạn bấm đã uống, nhắc lại lần $i.',
                    '${med.formEmoji} ${med.name} — ${med.dose}\nNot checked in yet — reminder #$i.',
                  ),
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

  Future<void> scheduleSnooze(String slotKey, [int? minutes]) async {
    if (!notificationsReady) return;
    try {
      final parts = slotKey.split('|');
      if (parts.length != 3) return;
      final med = medicines.where((m) => m.id == parts[0]).toList();
      if (med.isEmpty) return;
      final snoozeMin = minutes ??
          (settings.remindIntervalMinutes > 0
              ? settings.remindIntervalMinutes
              : 15);
      final at = tz.TZDateTime.now(tz.local).add(Duration(minutes: snoozeMin));
      await notifications.zonedSchedule(
        stableHash('snooze|$slotKey') % 2000000000,
        tr('Nhắc lại: đến giờ uống thuốc!', 'Reminder: time to take your medicine!'),
        '${med.first.formEmoji} ${med.first.name} — ${med.first.dose}',
        at,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            tr('Nhắc uống thuốc', 'Medicine reminders'),
          icon: 'ic_stat_pip',
            channelDescription: tr('Nhắc uống thuốc đúng giờ mỗi ngày', 'Daily on-time medicine reminders'),
            importance: Importance.max,
            priority: Priority.high,
            playSound: settings.sound,
            enableVibration: settings.vibration,
            actions: [
              AndroidNotificationAction('taken', tr('Đã uống', 'Taken')),
              AndroidNotificationAction('snooze', tr('Nhắc lại sau', 'Snooze')),
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

  /// Hoàn tác một lần đã uống / uống trễ (1.2.28): xóa luôn lần ghi đó
  /// để thẻ quay lại chưa uống, số viên và tiến độ tính lại từ log.
  /// Lịch nhắc được đặt lại để lần uống còn ở phía trước vẫn nhắc lại.
  Future<void> undoTaken(DoseSlot slot) async {
    logs.remove(slot.key);
    await _save();
    notifyListeners();
    await rescheduleAll();
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

  Future<void> updateAppearance(HomePalette palette, {Color? customColor}) async {
    settings = settings.copyWith(palette: palette, customColor: customColor);
    await _save();
    notifyListeners();
  }

  Future<void> updateAppTheme(ThemeMode mode) async {
    if (settings.appThemeMode == mode) return;
    settings = settings.copyWith(appThemeMode: mode);
    notifyListeners();
    await _save(refreshWidget: false);
  }

  Future<void> updateWidgetTheme(WidgetThemeMode mode) async {
    if (settings.widgetThemeMode == mode) return;
    settings = settings.copyWith(widgetThemeMode: mode);
    notifyListeners();
    await _save();
  }

  Future<void> updateLanguage(AppLang lang) async {
    if (settings.language == lang && Lang.current == lang) return;
    settings = settings.copyWith(language: lang);
    Lang.current = lang;
    notifyListeners();
    await _save();
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
    Lang.current = settings.language;
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

  /// Tỷ lệ tuân thủ tuần này (từ đầu tuần đến hiện tại).
  double adherenceThisWeek() {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final monday = todayDate.subtract(Duration(days: todayDate.weekday - 1));
    var total = 0;
    var taken = 0;
    for (var i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      if (day.isAfter(todayDate)) break;
      for (final slot in slotsForDay(day)) {
        if (slot.dateTime.isAfter(now)) continue;
        total++;
        final st = logs[slot.key]?.status;
        if (st == 'taken' || st == 'late') taken++;
      }
    }
    if (total == 0) return 1.0;
    return taken / total;
  }

  /// Tổng số liều đã uống trong tháng hiện tại.
  int takenDosesThisMonth() {
    final now = DateTime.now();
    var count = 0;
    for (final entry in logs.entries) {
      if (entry.value.status != 'taken' && entry.value.status != 'late') continue;
      final parts = entry.key.split('|');
      if (parts.length != 3) continue;
      final dateParts = parts[1].split('-');
      if (dateParts.length != 3) continue;
      final year = int.tryParse(dateParts[0]);
      final month = int.tryParse(dateParts[1]);
      if (year == now.year && month == now.month) {
        count++;
      }
    }
    return count;
  }

  /// Tỉ lệ đúng giờ 7 ngày tuần này (T2 đến CN, ngày chưa tới thì 0%).
  List<DailyAdherence> weeklyDailyAdherence() {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final monday = todayDate.subtract(Duration(days: todayDate.weekday - 1));
    final labels = [for (var d = 1; d <= 7; d++) weekdayShort(d)];
    final list = <DailyAdherence>[];
    for (var i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final isFuture = day.isAfter(todayDate);
      final slots = slotsForDay(day);
      if (isFuture || slots.isEmpty) {
        list.add(DailyAdherence(
          day: day,
          weekdayLabel: labels[i],
          rate: 0.0,
          total: slots.length,
          onTime: 0,
        ));
      } else {
        final onTime =
            slots.where((s) => logs[s.key]?.status == 'taken').length;
        list.add(DailyAdherence(
          day: day,
          weekdayLabel: labels[i],
          rate: slots.isEmpty ? 0.0 : onTime / slots.length,
          total: slots.length,
          onTime: onTime,
        ));
      }
    }
    return list;
  }

  /// Thống kê tỉ lệ đúng giờ theo từng thuốc (trong 30 ngày qua).
  List<MedicineAdherence> medicineAdherenceStats() {
    final now = DateTime.now();
    final list = <MedicineAdherence>[];
    for (final med in medicines) {
      var total = 0;
      var onTime = 0;
      for (var i = 0; i < 30; i++) {
        final day = now.subtract(Duration(days: i));
        if (!med.activeOn(day)) continue;
        for (final time in med.times) {
          final slot = DoseSlot(medicine: med, time: time, day: day);
          if (slot.dateTime.isAfter(now)) continue;
          total++;
          if (logs[slot.key]?.status == 'taken') onTime++;
        }
      }
      list.add(MedicineAdherence(
        medicine: med,
        onTimeRate: total == 0 ? 1.0 : onTime / total,
        totalDoses: total,
        onTimeDoses: onTime,
      ));
    }
    return list;
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
    return tr(
      '${best.key} (${best.value} lần)',
      '${best.key} (${best.value} ${enPlural(best.value, 'time', 'times')})',
    );
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
        pipMessage = tr(
          '😊 Thêm thuốc để Pip nhắc bạn nhé!',
          '😊 Add a medicine so Pip can remind you!',
        );
      } else if (onTime == slots.length) {
        pipMessage = streak >= 2
            ? tr(
                '🥳 Hôm nay uống đủ và đúng giờ hết rồi! Chuỗi: $streak ngày 🔥',
                '🥳 All doses taken on time today! Streak: $streak ${enPlural(streak, 'day', 'days')} 🔥',
              )
            : tr(
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
        final remainingCount = slots.length - completed;
        pipMessage = streak >= 2
            ? tr(
                '😊 Hôm nay còn $remainingCount lần nữa là xong! Chuỗi: $streak ngày 🔥',
                '😊 $remainingCount ${enPlural(remainingCount, 'dose', 'doses')} left today! Streak: $streak ${enPlural(streak, 'day', 'days')} 🔥',
              )
            : tr(
                '😊 Hôm nay còn $remainingCount lần nữa là xong, cố lên nhé!',
                '😊 $remainingCount ${enPlural(remainingCount, 'dose', 'doses')} left today — you\'ve got this!',
              );
      }
      // Nhắc mua thuốc lên widget luôn (nếu có), để người dùng thấy
      // ngay cả khi không mở app.
      final buyPrompt = todayBuyPrompt();
      await HomeWidget.saveWidgetData<String>(
          'pip_message', buyPrompt == null ? pipMessage : '$pipMessage\n🛒 $buyPrompt');
      await HomeWidget.saveWidgetData<String>(
          'progress',
          slots.isEmpty
              ? tr('Chưa có thuốc hôm nay', 'No medicines today')
              : tr(
                  'Hôm nay: $completed/${slots.length} lần • đúng giờ $onTime lần',
                  'Today: $completed/${slots.length} doses • $onTime on time',
                ));
      await HomeWidget.saveWidgetData<String>(
          'next_text',
          next == null
              ? (slots.isEmpty
                  ? tr('Thêm thuốc để Pip nhắc bạn nhé!', 'Add a medicine so Pip can remind you!')
                  : tr('🎉 Đã xong hôm nay!', '🎉 All done for today!'))
              : '${next.medicine.formEmoji} ${next.medicine.name} — ${next.medicine.dose}');
      final nextRem = next == null ? null : remainingPills(next.medicine);
      await HomeWidget.saveWidgetData<String>(
          'next_time',
          next == null
              ? ''
              : '${tr('Lúc', 'At')} ${next.time} • ${next.medicine.mealLabel}'
                  '${nextRem != null ? tr(' • Còn $nextRem viên', ' • $nextRem ${enPlural(nextRem, 'pill', 'pills')} left') : ''}');
      // 1.2.33: cờ hết thuốc cho nút widget — widget đọc cờ này để mờ
      // nút "Đã uống lần này" khi lần tiếp theo đã hết thuốc.
      await HomeWidget.saveWidgetData<String>('next_out_of_stock',
          next != null && (remainingPills(next.medicine) ?? 1) <= 0 ? '1' : '0');
      // Chi tiết lịch hôm nay sau khi đã xong (1.2.15): mỗi lần đã uống
      // một khối 2 dòng, giống thẻ Lịch uống hôm nay trong app:
      // dòng 1 thuốc + giờ dự kiến + trước/sau ăn, dòng 2 đã uống lúc
      // mấy giờ + còn bao nhiêu viên. Giới hạn 3 lần đầu để widget
      // không tràn khi một ngày có nhiều lần uống.
      final doneSlots = slots.where(_isCompleted).toList();
      final doneLines = <String>[];
      for (final s in doneSlots.take(3)) {
        final log = logs[s.key];
        final at = log != null && log.at.isNotEmpty ? DateTime.tryParse(log.at) : null;
        final atStr = at != null
            ? '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'
            : '';
        final takenStr = log?.status == 'late'
            ? tr('Đã uống trễ lúc $atStr', 'Taken late at $atStr')
            : tr('Đã uống đúng giờ lúc $atStr', 'Taken on time at $atStr');
        final rem = remainingPills(s.medicine);
        final days = daysSupply(s.medicine);
        final remStr = rem != null
            ? tr(
                ' • Còn $rem viên${days != null ? ' (đủ $days ngày)' : ''}',
                ' • $rem ${enPlural(rem, 'pill', 'pills')} left${days != null ? ' (enough for $days ${enPlural(days, 'day', 'days')})' : ''}',
              )
            : '';
        doneLines.add('${s.medicine.formEmoji} ${s.medicine.name} — ${s.medicine.dose} • ${tr('Lúc', 'At')} ${s.time} • ${s.medicine.mealLabel}\n$takenStr$remStr');
      }
      if (doneSlots.length > 3) {
        doneLines.add(tr(
          '… và ${doneSlots.length - 3} lần nữa',
          '… and ${doneSlots.length - 3} more',
        ));
      }
      await HomeWidget.saveWidgetData<String>('done_detail', doneLines.join('\n'));
      await HomeWidget.saveWidgetData<String>('all_done', next == null && slots.isNotEmpty ? '1' : '0');
      await settings.saveWidgetAppearance();
      await HomeWidget.saveWidgetData<String>('widget_opacity', settings.widgetOpacity.toString());
      await HomeWidget.saveWidgetData<String>('progress_pct', slots.isEmpty ? '0' : ((completed * 100) ~/ slots.length).toString());
      // 1.2.30: đóng dấu ngày của dữ liệu widget để Kotlin tự phát
      // hiện dữ liệu qua ngày và tính lại, thay vì vẽ lại chuỗi cũ.
      await HomeWidget.saveWidgetData<String>('widget_date', todayKey(today));
      await HomeWidget.updateWidget(name: 'ThuocVuiWidgetProvider', androidName: 'ThuocVuiWidgetProvider');
    } catch (_) {}
  }
}
