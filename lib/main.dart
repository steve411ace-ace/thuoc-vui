import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'add_medicine.dart';
import 'history.dart';
import 'home_color_picker.dart';
import 'home_style.dart';
import 'models.dart';
import 'pillflow_style.dart';
import 'purchases.dart';
import 'store.dart';
import 'strings.dart';
import 'widget_service.dart';

const _appVersion = '1.2.50';
const _appBuild = '53';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HomeWidget.registerInteractivityCallback(widgetInteractivityCallback);
  final store = ThuocStore();
  await store.init();
  runApp(ThuocVuiApp(store: store));
}

class ThuocVuiApp extends StatelessWidget {
  final ThuocStore store;
  const ThuocVuiApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final settings = store.settings;
        return MaterialApp(
          title: 'Thuốc Vui',
          debugShowCheckedModeBanner: false,
          theme: settings.palette.themeWithCustomColor(settings.customColor),
          darkTheme: settings.palette.darkThemeWithCustomColor(
            settings.customColor,
          ),
          themeMode: settings.appThemeMode,
          home: HomeScreen(store: store),
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  final ThuocStore store;
  const HomeScreen({super.key, required this.store});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  DateTime? _selectedHomeDay;
  final _pendingSlots = <String>{};
  final _pendingRefills = <String>{};
  final _dismissedReminders = <String>{};
  final _snoozedReminders = <String, DateTime>{};
  Timer? _reminderTimer;
  Timer? _toastTimer;
  String? _toastMessage;

  // Tủ thuốc search & filter
  final _cabinetSearchController = TextEditingController();
  String _cabinetQuery = '';
  String _cabinetFilter = 'all'; // all, active, low

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cabinetSearchController.dispose();
    _reminderTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.reload();
    }
  }

  Future<void> _openAdd([Medicine? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (pageContext) => AddMedicineScreen(
          existing: existing,
          onSave: (med) async {
            if (existing == null) {
              await widget.store.addMedicine(med);
            } else {
              await widget.store.updateMedicine(med);
            }
            if (pageContext.mounted &&
                ModalRoute.of(pageContext)?.isCurrent == true) {
              Navigator.pop(pageContext);
            }
          },
          onDelete: existing == null
              ? null
              : () async {
                  await widget.store.deleteMedicine(existing.id);
                  if (pageContext.mounted &&
                      ModalRoute.of(pageContext)?.isCurrent == true) {
                    Navigator.pop(pageContext);
                  }
                },
        ),
      ),
    );
  }

  Future<void> _askSkip(DoseSlot slot) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Bỏ qua lần uống này?', 'Skip this dose?')),
        children: [
          for (final r in ['Quên', 'Hết thuốc', 'Khó chịu', 'Khác'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(skipReasonLabel(r),
                    style: const TextStyle(fontSize: 16)),
              ),
            ),
        ],
      ),
    );
    if (reason != null) {
      await widget.store.markSkipped(slot, reason);
    }
  }

  Future<void> _handleRefill(Medicine med) async {
    if (!_pendingRefills.add(med.id)) return;
    try {
      final over = await widget.store.replenishMedicine(med, 10);
      if (!mounted) return;
      _toast(over > 0
          ? tr('Đã bổ sung 10 viên cho ${med.name} (đã trừ $over viên uống trước).',
              'Added 10 pills for ${med.name} ($over pills taken earlier were deducted).')
          : tr('Đã bổ sung 10 viên cho ${med.name}.',
              'Added 10 pills for ${med.name}.'));
      final recordPurchase = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Ghi lần mua này không?', 'Record this purchase?')),
          content: Text(tr(
              'Bạn vừa bổ sung 10 viên ${med.name}. Có muốn ghi vào lịch sử mua thuốc không?',
              'You just added 10 pills of ${med.name}. Add it to your purchase history?')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Để sau', 'Later')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Ghi lần mua', 'Record purchase')),
            ),
          ],
        ),
      );
      if (recordPurchase == true && mounted) {
        await showPurchaseForm(context, widget.store, medicineId: med.id);
      }
    } finally {
      _pendingRefills.remove(med.id);
    }
  }

  Widget _homeTab() {
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final selected = _selectedHomeDay;
    final viewingDay = selected != null &&
            !selected.isAfter(today) &&
            today.difference(selected).inDays <= 6
        ? selected
        : today;
    final isViewingToday = DateUtils.isSameDay(viewingDay, today);
    final slots = store.slotsForDay(viewingDay);
    final todaySlots = isViewingToday ? slots : store.slotsForDay(today);
    final taken = slots.where((slot) => pillTaken(store.statusOf(slot))).length;
    DoseSlot? next;
    for (final slot in slots) {
      if (store.statusOf(slot) != null) continue;
      if ((store.remainingPills(slot.medicine) ?? 1) > 0) {
        next = slot;
        break;
      }
    }
    DoseSlot? reminder;
    var refreshAt = DateTime(today.year, today.month, today.day + 1);
    for (final slot in todaySlots) {
      if (store.statusOf(slot) != null) continue;
      if (_dismissedReminders.contains(slot.key)) continue;
      final remindAt = _snoozedReminders[slot.key] ?? slot.dateTime;
      if (remindAt.isAfter(now)) {
        if (remindAt.isBefore(refreshAt)) refreshAt = remindAt;
      } else {
        reminder ??= slot;
      }
    }
    _reminderTimer?.cancel();
    _reminderTimer = Timer(refreshAt.difference(now), () {
      if (mounted && _tab == 0) setState(() {});
    });
    final total = slots.length;
    final progress = total == 0 ? 0.0 : taken / total;
    final hour = now.hour;
    final greeting = hour < 11
        ? tr('Chào buổi sáng!', 'Good morning!')
        : hour < 14
            ? tr('Chào buổi trưa!', 'Good midday!')
            : hour < 18
                ? tr('Chào buổi chiều!', 'Good afternoon!')
                : tr('Chào buổi tối!', 'Good evening!');
    final weekday = weekdayFull(viewingDay.weekday);
    final left = total - taken;
    final hint = isViewingToday
        ? (next != null
            ? tr('Tiếp theo: ${next.time} · ${next.medicine.name}',
                'Next: ${next.time} · ${next.medicine.name}')
            : total == 0
                ? tr('Chưa có lịch uống thuốc', 'No medication scheduled')
                : taken == total
                    ? tr('Tuyệt vời! Bạn đã hoàn thành hôm nay 🎉',
                        'Great! You are all done for today 🎉')
                    : tr('Còn $left liều chưa uống',
                        '$left ${enPlural(left, 'dose', 'doses')} not taken yet'))
        : (total == 0
            ? tr('Chưa có lịch uống thuốc', 'No medication scheduled')
            : taken == total
                ? tr('Tuyệt vời! Bạn đã uống đủ ngày này 🎉',
                    'Great! All doses taken on this day 🎉')
                : tr('Còn $left liều chưa uống',
                    '$left ${enPlural(left, 'dose', 'doses')} not taken'));

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$weekday, ${monthDayLabel(viewingDay)}',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                    Text(greeting,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: pillAmber.withAlpha(38),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  child: Text(
                      '🔥 ${tr('${store.currentStreak()} ngày', '${store.currentStreak()}-day streak')}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: scheme.brightness == Brightness.dark
                              ? pillAmber
                              : const Color(0xFF92400E))),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, gradient: pillGradient(scheme)),
                child: const Text('TV',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: tr('Cài đặt', 'Settings'),
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (reminder != null) ...[
            _doseReminderBanner(reminder),
            const SizedBox(height: 16),
          ],
          _weekSelectorStrip(scheme, today, viewingDay),
          const SizedBox(height: 16),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: pillGradient(scheme),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x260F766E),
                    blurRadius: 16,
                    offset: Offset(0, 6)),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -32,
                  top: -32,
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: const BoxDecoration(
                      color: Color(0x1AFFFFFF),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 76,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned.fill(
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(end: progress),
                                duration: const Duration(milliseconds: 450),
                                builder: (context, value, _) => Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 8,
                                    strokeCap: StrokeCap.round,
                                    value: value,
                                    color: Colors.white,
                                    backgroundColor: const Color(0x38FFFFFF),
                                  ),
                                ),
                              ),
                            ),
                            Text('${(progress * 100).round()}%',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                isViewingToday
                                    ? tr('Tiến độ hôm nay', "Today's progress")
                                    : tr(
                                        'Tiến độ ${monthDayLabel(viewingDay)}',
                                        'Progress · ${monthDayLabel(viewingDay)}'),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            Text(
                                tr('$taken/$total liều đã uống',
                                    '$taken/$total ${enPlural(total, 'dose', 'doses')} taken'),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Icon(Icons.circle,
                                    size: 6,
                                    color: total > 0 && taken == total
                                        ? const Color(0xFF6EE7B7)
                                        : pillAmber),
                                const SizedBox(width: 6),
                                Expanded(
                                    child: Text(hint,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          for (final (label, from, until) in [
            (tr('Sáng', 'Morning'), 0, 11),
            (tr('Trưa', 'Afternoon'), 11, 17),
            (tr('Tối', 'Evening'), 17, 24),
          ])
            ..._doseGroup(
                label,
                slots
                    .where((slot) =>
                        slot.dateTime.hour >= from &&
                        slot.dateTime.hour < until)
                    .toList(),
                next),
          if (slots.isEmpty && isViewingToday)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FilledButton.icon(
                onPressed: () => _openAdd(),
                icon: const Icon(Icons.add),
                label: Text(tr('Thêm thuốc mới', 'Add medicine')),
              ),
            ),
          _lowStockAlertBanner(store, scheme),
          _summaryBanner(scheme, taken, total, next,
              viewingDay: viewingDay, isToday: isViewingToday),
        ],
      ),
    );
  }

  Widget _doseReminderBanner(DoseSlot slot) {
    final scheme = Theme.of(context).colorScheme;
    final store = widget.store;
    final med = slot.medicine;
    final locked = (store.remainingPills(med) ?? 1) <= 0;
    final busy = _pendingSlots.contains(slot.key);

    return PillGlass(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0F766E), pillTeal, pillSky],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const PillShapeGlyph('capsule', color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('PILLFLOW · BÂY GIỜ', 'PILLFLOW · NOW'),
                        style: TextStyle(
                          color: scheme.brightness == Brightness.dark
                              ? pillDarkTeal
                              : const Color(0xFF0F766E),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr('Đến giờ uống ${med.name}', 'Time to take ${med.name}'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${slot.time} · ${med.dose} · ${med.formLabel} · ${med.mealTiming}',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (locked)
                        Text(
                          tr('Hết thuốc', 'Out of stock'),
                          style: TextStyle(color: scheme.error, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr('Đóng thông báo', 'Dismiss'),
                  onPressed: busy
                      ? null
                      : () => setState(() => _dismissedReminders.add(slot.key)),
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.surfaceContainerHighest,
                      foregroundColor: scheme.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: busy ? null : () => _snoozeReminder(slot),
                    child: Text(
                      tr('Nhắc lại 15p', 'Snooze 15m'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF047857),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: locked || busy
                        ? null
                        : () {
                            if (store.statusOf(slot) != null) return;
                            _toggleDose(slot);
                          },
                    child: Text(
                      tr('✓ Đánh dấu đã uống', '✓ Mark as taken'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _snoozeReminder(DoseSlot slot) async {
    if (!_pendingSlots.add(slot.key)) return;
    setState(() {});
    try {
      await widget.store.scheduleSnooze(slot.key, 15);
      if (!mounted) return;
      _snoozedReminders[slot.key] = DateTime.now().add(
        const Duration(minutes: 15),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr('Đã hoãn nhắc sau 15 phút!', 'Snoozed for 15 minutes!'))),
      );
    } finally {
      _pendingSlots.remove(slot.key);
      if (mounted) setState(() {});
    }
  }

  Widget _weekSelectorStrip(
          ColorScheme scheme, DateTime today, DateTime viewingDay) =>
      Row(
        children: [
          for (var i = 6; i >= 0; i--) ...[
            if (i < 6) const SizedBox(width: 4),
            Expanded(
              child: Builder(builder: (_) {
                final day = DateTime(today.year, today.month, today.day - i);
                return _dayButton(
                  scheme,
                  day,
                  isToday: i == 0,
                  isSelected: DateUtils.isSameDay(day, viewingDay),
                );
              }),
            ),
          ],
        ],
      );

  Widget _dayButton(
    ColorScheme scheme,
    DateTime day, {
    required bool isToday,
    required bool isSelected,
  }) {
    final store = widget.store;
    final slots = store.slotsForDay(day);
    final taken = slots.where((slot) => pillTaken(store.statusOf(slot))).length;
    final decoration = pillPanel(scheme, radius: 16);
    return Semantics(
      button: true,
      selected: isSelected,
      label: tr('${formatDateLocal(day)}, $taken/${slots.length} liều đã uống',
          '${formatDateLocal(day)}, $taken/${slots.length} doses taken'),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: isSelected
              ? BoxDecoration(
                  gradient: pillGradient(scheme),
                  borderRadius: decoration.borderRadius)
              : isToday
                  ? decoration.copyWith(
                      border: Border.all(
                        color: scheme.surfaceAccent.withAlpha(140),
                        width: 1.5,
                      ),
                    )
                  : decoration,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() {
              _selectedHomeDay = isToday ? null : day;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(pillWeekday(day),
                      style: TextStyle(
                          fontSize: 10,
                          color: isSelected
                              ? Colors.white70
                              : scheme.onSurfaceVariant)),
                  Text('${day.day}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color:
                              isSelected ? Colors.white : scheme.onSurface)),
                  const SizedBox(height: 4),
                  Icon(Icons.circle,
                      size: 6,
                      color: isSelected
                          ? Colors.white
                          : pillAdherenceDot(taken, slots.length)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _doseGroup(String label, List<DoseSlot> slots, DoseSlot? next) {
    if (slots.isEmpty) return [];
    final scheme = Theme.of(context).colorScheme;
    final taken =
        slots.where((slot) => pillTaken(widget.store.statusOf(slot))).length;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold)),
            Text(tr('$taken/${slots.length} xong', '$taken/${slots.length} done'),
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
          ],
        ),
      ),
      for (final slot in slots) _slotCard(slot, next?.key == slot.key),
      const SizedBox(height: 6),
    ];
  }

  bool _lowStock(Medicine med) => (widget.store.daysSupply(med) ?? 999) <= 7;

  Widget _lowStockAlertBanner(ThuocStore store, ColorScheme scheme) {
    final low =
        store.medicines.where((med) => med.refillWarning && _lowStock(med));
    if (low.isEmpty) return const SizedBox.shrink();
    final med = low.first;
    final remaining = store.remainingPills(med) ?? 0;
    final perDose = med.pillsPerDose > 0 ? med.pillsPerDose : 1;
    final ink = scheme.brightness == Brightness.dark
        ? const Color(0xFFFDBA74)
        : const Color(0xFF9A3412);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: pillOrange.withAlpha(28),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    remaining == 0
                        ? tr('Hết thuốc: ${med.name}', 'Out of stock: ${med.name}')
                        : tr('Sắp hết: ${med.name}', 'Running low: ${med.name}'),
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: ink, fontSize: 13)),
                Text(
                    remaining == 0
                        ? tr('Đã hết liều trong tủ thuốc', 'No doses left in your cabinet')
                        : tr('Chỉ còn ${remaining ~/ perDose} liều trong tủ thuốc',
                            'Only ${remaining ~/ perDose} ${enPlural(remaining ~/ perDose, 'dose', 'doses')} left in your cabinet'),
                    style: TextStyle(fontSize: 11, color: ink)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _handleRefill(med),
            style: TextButton.styleFrom(foregroundColor: ink),
            child: Text(tr('Bổ sung', 'Refill')),
          ),
        ],
      ),
    );
  }

  Widget _slotCard(DoseSlot slot, bool isNext) {
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final med = slot.medicine;
    final status = store.statusOf(slot);
    final taken = pillTaken(status);
    final remaining = store.remainingPills(med);
    final locked = status == null && (remaining ?? 1) <= 0;
    final busy = _pendingSlots.contains(slot.key);
    final accent = Color(med.color);
    final now = DateTime.now();
    final lateMin = now.difference(slot.dateTime).inMinutes;
    final snooze = store.settings.remindIntervalMinutes > 0
        ? store.settings.remindIntervalMinutes
        : 15;
    final detail = switch (status) {
      'late' => tr('Đã uống trễ', 'Taken late'),
      'skipped' => tr('Đã bỏ qua', 'Skipped'),
      null when locked => tr('Hết thuốc', 'Out of stock'),
      null when lateMin > 0 =>
        tr('Trễ ${_formatLate(lateMin)}', 'Late by ${_formatLate(lateMin)}'),
      _ => null,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
            color: isNext
                ? scheme.surfaceAccent.withAlpha(155)
                : scheme.outlineVariant,
            width: isNext ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: locked || busy ? null : () => _toggleDose(slot),
                child: Row(
                  children: [
                    PillShapeIcon(med.displayShape, color: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(med.name,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: taken
                                      ? scheme.onSurfaceVariant
                                      : scheme.onSurface,
                                  decoration: taken
                                      ? TextDecoration.lineThrough
                                      : null)),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                  text: slot.time,
                                  style: TextStyle(
                                      color: taken ? null : accent,
                                      fontWeight: FontWeight.w600)),
                              TextSpan(
                                  text: ' · ${med.dose} · ${med.mealTiming}'),
                            ]),
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                          if (med.note.isNotEmpty)
                            Text(med.note,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant)),
                          if (detail != null)
                            Text(detail,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: locked
                                        ? scheme.error
                                        : scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
                tooltip: status != null
                    ? tr('Hoàn tác', 'Undo')
                    : locked
                        ? tr('Hết thuốc', 'Out of stock')
                        : tr('Đã uống', 'Taken'),
                onPressed: locked || busy ? null : () => _toggleDose(slot),
                icon: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: taken ? pillEmerald : null,
                    border: Border.all(
                        color: taken ? pillEmerald : scheme.outlineVariant,
                        width: 2),
                  ),
                  child: taken
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : locked
                          ? Icon(Icons.lock_outline,
                              size: 16, color: scheme.onSurfaceVariant)
                          : null,
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: tr('Tùy chọn liều uống', 'Dose options'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 140),
              enabled: !busy,
              iconSize: 18,
              icon: const Icon(Icons.more_vert),
              onSelected: (action) async {
                switch (action) {
                  case 'undo':
                    await _toggleDose(slot);
                  case 'refill':
                    await _handleRefill(med);
                  case 'skip':
                    await _askSkip(slot);
                  case 'snooze':
                    await store.scheduleSnooze(slot.key, snooze);
                    if (mounted) {
                      _toast(tr('Đã hoãn nhắc sau $snooze phút!',
                          'Snoozed for $snooze minutes!'));
                    }
                }
              },
              itemBuilder: (_) => [
                if (status != null)
                  PopupMenuItem(value: 'undo', child: Text(tr('Hoàn tác', 'Undo')))
                else ...[
                  if (locked)
                    PopupMenuItem(
                        value: 'refill', child: Text(tr('Bổ sung', 'Refill')))
                  else
                    PopupMenuItem(
                        value: 'snooze',
                        child: Text(tr('Hoãn ${snooze}p', 'Snooze ${snooze}m'))),
                  PopupMenuItem(
                      value: 'skip',
                      child: Text(tr('Bỏ qua lần này', 'Skip this dose'))),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _toast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  Future<void> _toggleDose(DoseSlot slot) async {
    final store = widget.store;
    final undo = store.statusOf(slot) != null;
    if (!undo && (store.remainingPills(slot.medicine) ?? 1) <= 0) return;
    if (!_pendingSlots.add(slot.key)) return;
    setState(() {});
    try {
      if (undo) {
        await store.undoTaken(slot);
        if (mounted) {
          _toast(tr('Đã hoàn tác, liều quay lại chưa uống.',
              'Undone, the dose is back to not taken.'));
        }
        return;
      }
      final before = store.earnedBadgeIds();
      final status = await store.markTaken(slot);
      if (!mounted) return;
      final message = status == 'late'
          ? tr('Đã ghi nhận uống trễ ${slot.medicine.name}',
              'Logged ${slot.medicine.name} as taken late')
          : tr('Đã ghi nhận uống ${slot.medicine.name} ✓',
              'Logged ${slot.medicine.name} as taken ✓');
      final earned = store.earnedBadgeIds().difference(before);
      if (earned.isEmpty) {
        _toast(message);
      } else {
        final badge = allBadges.firstWhere((badge) => badge.id == earned.first);
        _toast(
            '$message\n${tr('Mở khóa danh hiệu', 'Badge unlocked')}: ${badge.emoji} ${badge.title}!');
      }
    } finally {
      _pendingSlots.remove(slot.key);
      if (mounted) setState(() {});
    }
  }

  Widget _summaryBanner(
    ColorScheme scheme,
    int taken,
    int total,
    DoseSlot? nextSlot, {
    required DateTime viewingDay,
    required bool isToday,
  }) {
    String summary;
    final hour = DateTime.now().hour;
    final timeGreeting = hour < 12
        ? tr('Sáng nay', 'This morning')
        : (hour < 17 ? tr('Chiều nay', 'This afternoon') : tr('Tối nay', 'This evening'));
    final dayLabel = '${weekdayFull(viewingDay.weekday)}, ${monthDayLabel(viewingDay)}';
    final left = total - taken;

    if (total == 0) {
      summary = tr('Không có lịch uống thuốc trong ngày này.',
          'No medication scheduled for this day.');
    } else if (!isToday) {
      summary = taken == total
          ? tr('$dayLabel bạn đã uống đủ $taken/$total liều. Tuyệt vời!',
              'On $dayLabel you took all $taken/$total doses. Great job!')
          : tr('$dayLabel bạn đã uống $taken/$total liều (còn $left liều chưa uống).',
              'On $dayLabel you took $taken/$total doses ($left not taken).');
    } else if (taken == total) {
      summary = tr('$timeGreeting bạn đã uống đủ $taken/$total liều. Tuyệt vời!',
          '$timeGreeting you took all $taken/$total doses. Great job!');
    } else if (nextSlot != null) {
      summary = tr(
          '$timeGreeting bạn đã uống $taken/$total liều. Còn $left liều lúc ${nextSlot.time} — ${nextSlot.medicine.name}.',
          '$timeGreeting you took $taken/$total doses. $left ${enPlural(left, 'dose', 'doses')} left, next at ${nextSlot.time} — ${nextSlot.medicine.name}.');
    } else {
      summary = tr('$timeGreeting bạn đã uống $taken/$total liều thuốc.',
          '$timeGreeting you took $taken/$total doses.');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceAccent.withAlpha(14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.surfaceAccent.withAlpha(35)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: scheme.surfaceAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              summary,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cabinetTab() => SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
          children: [_cabinetSection()],
        ),
      );

  Widget _cabinetSection({bool compact = false}) {
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final activeCount =
        store.medicines.where((med) => med.activeOn(now)).length;
    final lowCount = store.medicines.where(_lowStock).length;
    final query = _cabinetQuery.trim().toLowerCase();
    final filtered = store.medicines.where((med) {
      if (compact) return true;
      if (![med.name, med.dose, med.note]
          .any((text) => text.toLowerCase().contains(query))) {
        return false;
      }
      return switch (_cabinetFilter) {
        'active' => med.activeOn(now),
        'low' => _lowStock(med),
        _ => true,
      };
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(tr('TỦ THUỐC THÔNG MINH', 'SMART MEDICINE CABINET'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: .7))),
            Text(
                tr('$activeCount loại đang dùng', '$activeCount in use'),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.surfaceAccent)),
          ],
        ),
        const SizedBox(height: 10),
        if (!compact) ...[
          TextField(
            controller: _cabinetSearchController,
            onChanged: (value) => setState(() => _cabinetQuery = value),
            decoration: InputDecoration(
              hintText: tr('Tìm kiếm thuốc...', 'Search medicine...'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _cabinetQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: tr('Xóa tìm kiếm', 'Clear search'),
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _cabinetSearchController.clear();
                        setState(() => _cabinetQuery = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _filterChip(
                  tr('Tất cả (${store.medicines.length})',
                      'All (${store.medicines.length})'),
                  'all',
                  scheme),
              _filterChip(tr('Đang dùng ($activeCount)', 'In use ($activeCount)'),
                  'active', scheme),
              _filterChip(
                  tr('Sắp hết ($lowCount)', 'Running low ($lowCount)'), 'low', scheme),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(query.isNotEmpty && !compact
                  ? tr('Không tìm thấy thuốc phù hợp.', 'No matching medicine found.')
                  : !compact && _cabinetFilter == 'low'
                      ? tr('Không có thuốc nào sắp hết.', 'No medicine is running low.')
                      : tr('Tủ thuốc đang trống.', 'Your cabinet is empty.')),
            ),
          ),
        for (final med in filtered)
          _medicineCabinetCard(med, scheme, compact: compact),
        if (!compact)
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tr('Thêm thuốc mới', 'Add medicine')),
            onPressed: () => _openAdd(),
          ),
      ],
    );
  }

  Widget _filterChip(String label, String value, ColorScheme scheme) =>
      ChoiceChip(
        label: Text(label),
        selected: _cabinetFilter == value,
        selectedColor: scheme.primaryContainer,
        onSelected: (_) => setState(() => _cabinetFilter = value),
      );

  Widget _medicineCabinetCard(Medicine med, ColorScheme scheme,
      {required bool compact}) {
    final store = widget.store;
    final remaining = store.remainingPills(med);
    final days = store.daysSupply(med);
    final low = _lowStock(med);
    final barColor = low ? pillOrange : Color(med.color);
    final warningInk = scheme.brightness == Brightness.dark
        ? const Color(0xFFFDBA74)
        : const Color(0xFF9A3412);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(med.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold))),
                if (remaining != null) ...[
                  const SizedBox(width: 8),
                  Text(
                      tr('Còn $remaining/${med.totalPills} viên',
                          '$remaining/${med.totalPills} pills left'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: low ? warningInk : scheme.onSurfaceVariant)),
                ],
                if (low) ...[
                  const SizedBox(width: 6),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: warningInk,
                      backgroundColor: pillOrange.withAlpha(30),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _handleRefill(med),
                    child: Text(tr('+ Nạp', '+ Refill'),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (remaining != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (remaining / med.totalPills).clamp(0.0, 1.0),
                  minHeight: 6,
                  color: barColor,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              )
            else
              Text(tr('Chưa theo dõi số lượng', 'Quantity not tracked'),
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            if (!compact) ...[
              const SizedBox(height: 8),
              Text('${med.dose} · ${med.times.join(', ')} · ${med.mealTiming}',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              if (days != null)
                Text(
                    tr('Đủ $days ngày',
                        'Enough for $days ${enPlural(days, 'day', 'days')}'),
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              if (med.note.isNotEmpty)
                Text(med.note,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              Wrap(
                spacing: 4,
                children: [
                  if (remaining != null && !low)
                    TextButton(
                        onPressed: () => _handleRefill(med),
                        child: Text(tr('Bổ sung +10', 'Refill +10'))),
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(tr('Sửa', 'Edit')),
                    onPressed: () => _openAdd(med),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(tr('Xóa', 'Delete')),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(tr('Xóa thuốc này?', 'Delete this medicine?')),
                          content: Text(tr(
                              'Xóa "${med.name}" khỏi tủ thuốc? Lịch nhắc và lịch sử cũng sẽ bị xóa.',
                              'Delete "${med.name}" from your cabinet? Its reminders and history will also be deleted.')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(tr('Hủy', 'Cancel'))),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: Text(tr('Xóa', 'Delete'))),
                          ],
                        ),
                      );
                      if (ok == true) await store.deleteMedicine(med.id);
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _settingsTab(BuildContext context) {
    final store = widget.store;
    final settings = store.settings;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    const appModes = [ThemeMode.light, ThemeMode.dark, ThemeMode.system];

    Future<void> pickQuiet(bool isStart) async {
      final parts =
          (isStart ? settings.quietStart : settings.quietEnd).split(':');
      final picked = await showTimePicker(
        context: context,
        initialTime:
            TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      );
      if (picked == null) return;
      final value =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      final next = settings.copyWith(
        quietStart: isStart ? value : settings.quietStart,
        quietEnd: isStart ? settings.quietEnd : value,
      );
      await store.updateSettings(next);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
      children: [
        // 0. Ngôn ngữ / Language
        HomeSectionLabel(tr('NGÔN NGỮ', 'LANGUAGE')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                for (final lang in AppLang.values)
                  _LanguageOption(
                    lang: lang,
                    selected: settings.language == lang,
                    onTap: () => store.updateLanguage(lang),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 1. Nhóm "Hiển thị & âm thanh"
        HomeSectionLabel(tr('HIỂN THỊ & ÂM THANH', 'DISPLAY & SOUND')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Chế độ', 'Mode')),
                const SizedBox(height: 6),
                _ThemeModeControl(
                  labels: [
                    tr('Sáng', 'Light'),
                    tr('Tối', 'Dark'),
                    tr('Theo điện thoại', 'System')
                  ],
                  systemIndex: 2,
                  selectedIndex: appModes.indexOf(settings.appThemeMode),
                  onSelected: (index) => store.updateAppTheme(appModes[index]),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Âm thanh nhắc', 'Reminder sound')),
                  value: settings.sound,
                  onChanged: (v) async {
                    await store.updateSettings(settings.copyWith(sound: v));
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Rung khi nhắc', 'Vibrate on reminder')),
                  value: settings.vibration,
                  onChanged: (v) async {
                    await store.updateSettings(settings.copyWith(vibration: v));
                  },
                ),
                const Divider(height: 20),
                Text(tr('Bảng màu giao diện', 'Color palette')),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth < 270 ? 4 : 5;
                    return Wrap(
                      runSpacing: 6,
                      children: [
                        for (final palette in HomePalette.values)
                          SizedBox(
                            width: constraints.maxWidth / columns,
                            child: HomePaletteSwatch(
                              palette: palette,
                              color: palette.accent(settings.customColor),
                              selected: settings.palette == palette,
                              onTap: () async {
                                if (palette == HomePalette.custom) {
                                  final color = await showDialog<Color>(
                                    context: context,
                                    builder: (_) => HomeColorPicker(
                                      initialColor: store.settings.customColor,
                                    ),
                                  );
                                  if (color == null) return;
                                  await store.updateAppearance(palette,
                                      customColor: color);
                                } else {
                                  await store.updateAppearance(palette);
                                }
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. Nhóm "Thời gian hoãn nhắc mặc định" (5 / 10 / 15 / 30 phút)
        HomeSectionLabel(tr('THỜI GIAN HOÃN NHẮC MẶC ĐỊNH', 'DEFAULT SNOOZE TIME')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Thời gian nhắc lại khi bấm nút "Hoãn" trên thẻ liều thuốc hoặc thông báo:',
                      'Reminder delay when you tap "Snooze" on a dose card or notification:'),
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [5, 10, 15, 30].map((mins) {
                    final selected = settings.remindIntervalMinutes == mins;
                    return ChoiceChip(
                      label: Text(tr('$mins phút', '$mins min')),
                      selected: selected,
                      selectedColor: scheme.surfaceAccent.withAlpha(30),
                      onSelected: (_) async {
                        await store.updateSettings(
                            settings.copyWith(remindIntervalMinutes: mins));
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 3. Độ mờ widget
        HomeSectionLabel(tr('ĐỘ MỜ WIDGET', 'WIDGET OPACITY')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Nền widget trong suốt dần khi kéo xuống. 100% là đặc như hiện tại, 0% là nền biến mất hoàn toàn.',
                      'The widget background gets more transparent as you drag down. 100% is solid as it is now, 0% makes the background disappear completely.'),
                  style: TextStyle(color: muted),
                ),
                Row(
                  children: [
                    Text(tr('Mờ hơn', 'Clearer')),
                    Expanded(
                      child: Slider(
                        value: (settings.widgetOpacity / 100).clamp(0.0, 1.0),
                        min: 0.0,
                        max: 1.0,
                        divisions: 10,
                        label: '${settings.widgetOpacity}%',
                        onChanged: (v) async {
                          await store.updateSettings(settings.copyWith(
                              widgetOpacity: (v * 100).round()));
                        },
                      ),
                    ),
                    Text('${settings.widgetOpacity}%',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(tr('Giao diện widget', 'Widget theme')),
                const SizedBox(height: 6),
                _ThemeModeControl(
                  labels: [
                    tr('Theo điện thoại', 'System'),
                    tr('Sáng', 'Light'),
                    tr('Tối', 'Dark')
                  ],
                  systemIndex: 0,
                  selectedIndex: settings.widgetThemeMode.index,
                  onSelected: (index) =>
                      store.updateWidgetTheme(WidgetThemeMode.values[index]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 4. Giờ yên lặng
        HomeSectionLabel(tr('GIỜ YÊN LẶNG', 'QUIET HOURS')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _SettingsField(
                  label: tr('Giờ yên lặng bắt đầu', 'Quiet hours start'),
                  value: settings.quietStart,
                  onTap: () => pickQuiet(true),
                ),
                const SizedBox(height: 11),
                _SettingsField(
                  label: tr('Giờ yên lặng kết thúc', 'Quiet hours end'),
                  value: settings.quietEnd,
                  onTap: () => pickQuiet(false),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Trong giờ yên lặng, app không lên lịch nhắc mới. Các lần uống vẫn hiện trên lịch hôm nay.',
                      'During quiet hours the app does not schedule new reminders. Doses still appear on today\'s schedule.'),
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 5. Thông báo & Báo thức
        HomeSectionLabel(tr('THÔNG BÁO', 'NOTIFICATIONS')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Lịch nhắc dùng báo thức hệ thống. Nếu đã từ chối quyền vĩnh viễn, bật thủ công tại Cài đặt máy > Ứng dụng > Thuốc Vui > Thông báo.',
                      'Reminders use system alarms. If you permanently denied the permission, enable it manually in Phone Settings > Apps > Thuốc Vui > Notifications.'),
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_outlined),
                    label: Text(tr('Xin quyền thông báo', 'Request notification permission')),
                    onPressed: () async {
                      final granted =
                          await store.requestNotificationPermission();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(granted
                              ? tr('Đã có quyền thông báo, lịch nhắc đã lên lại!',
                                  'Notification permission granted, reminders are scheduled again!')
                              : tr('Chưa có quyền thông báo. Hãy bật tay trong Cài đặt máy > Ứng dụng > Thuốc Vui.',
                                  'Notification permission is not granted. Enable it manually in Phone Settings > Apps > Thuốc Vui.')),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.alarm_outlined),
                    label: Text(tr('Cho phép báo thức chính xác', 'Allow exact alarms')),
                    onPressed: () async {
                      final canExact = await store.canScheduleExact();
                      if (canExact) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(tr(
                                  'Máy đã cho phép báo thức chính xác rồi, nhắc sẽ đúng giờ.',
                                  'Exact alarms are already allowed, reminders will be on time.'))),
                        );
                        return;
                      }
                      await store.requestExactAlarmPermission();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(tr(
                                'Đã mở màn hình Báo thức & nhắc nhở. Bật "Cho phép đặt báo thức và nhắc nhở" cho Thuốc Vui nhé!',
                                'Opened the Alarms & reminders screen. Turn on "Allow setting alarms and reminders" for Thuốc Vui!'))),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.battery_charging_full_outlined),
                    label: Text(tr('Tắt tối ưu pin cho Thuốc Vui', 'Disable battery optimization for Thuốc Vui')),
                    onPressed: () async {
                      final opened =
                          await store.requestIgnoreBatteryOptimizations();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(opened
                                ? tr('Đã mở màn hình miễn tối ưu pin. Bấm "Cho phép" để Thuốc Vui không bị máy cho ngủ.',
                                    'Opened the battery optimization screen. Tap "Allow" so Thuốc Vui is not put to sleep.')
                                : tr('Không mở được màn hình pin. Vào Cài đặt máy > Ứng dụng > Thuốc Vui > Pin > Không giới hạn.',
                                    'Could not open the battery screen. Go to Phone Settings > Apps > Thuốc Vui > Battery > Unrestricted.'))),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _SettingsField(
                label: tr('Số lần báo lại nếu chưa uống', 'Repeat reminders if not taken'),
                value: settings.remindTimes == 0
                    ? tr('Tắt', 'Off')
                    : tr('${settings.remindTimes} lần', '${settings.remindTimes}x'),
                onTap: () async {
                  final picked = await showDialog<int>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: Text(tr('Số lần báo lại nếu chưa uống', 'Repeat reminders if not taken')),
                      children: [
                        for (final n in [0, 1, 2, 3, 5])
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(ctx, n),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(n == 0 ? tr('Tắt', 'Off') : tr('$n lần', '${n}x'),
                                  style: const TextStyle(fontSize: 16)),
                            ),
                          ),
                      ],
                    ),
                  );
                  if (picked != null) {
                    await store
                        .updateSettings(settings.copyWith(remindTimes: picked));
                  }
                },
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr('Lưu ý: app chỉ nhắc giờ uống và ghi nhận đã uống, không thay thế chỉ định của bác sĩ. Khởi động lại điện thoại xong, mở app một lần để lịch nhắc hoạt động lại.',
              'Note: the app only reminds you when to take medicine and logs doses; it does not replace your doctor\'s instructions. After restarting your phone, open the app once so reminders work again.'),
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(tr('Thuốc Vui • Phiên bản $_appVersion+$_appBuild', 'Thuốc Vui • Version $_appVersion+$_appBuild'),
              style: TextStyle(color: muted, fontSize: 13)),
        ),
      ],
    );
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(tr('Cài đặt', 'Settings')), centerTitle: true),
        body: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => _settingsTab(context),
        ),
      ),
    ));
  }

  Widget _navigation(ColorScheme scheme) {
    final labels = [
      tr('Hôm nay', 'Today'),
      tr('Lịch', 'Calendar'),
      tr('Thêm thuốc mới', 'Add medicine'),
      tr('Thống kê', 'Stats'),
      tr('Tủ thuốc', 'Cabinet')
    ];
    const icons = [
      Icons.home_outlined,
      Icons.calendar_month_outlined,
      Icons.add,
      Icons.bar_chart_rounded,
      Icons.inventory_2_outlined
    ];
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x22101B2B),
                  blurRadius: 18,
                  offset: Offset(0, 6)),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              PillGlass(
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      for (var index = 0; index < labels.length; index++)
                        Expanded(
                          child: index == 2
                              ? const SizedBox.shrink()
                              : Semantics(
                                  selected: _tab == index,
                                  button: true,
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() => _tab = index);
                                        if (index == 0) widget.store.reload();
                                      },
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                              index == 0 && _tab == 0
                                                  ? Icons.home_rounded
                                                  : icons[index],
                                              size: 21,
                                              color: _tab == index
                                                  ? scheme.surfaceAccent
                                                  : scheme.onSurfaceVariant),
                                          const SizedBox(height: 3),
                                          Text(labels[index],
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: _tab == index
                                                      ? scheme.surfaceAccent
                                                      : scheme.onSurfaceVariant,
                                                  fontWeight: _tab == index
                                                      ? FontWeight.bold
                                                      : FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                top: 2,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: pillGradient(scheme),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x400F766E),
                            blurRadius: 8,
                            offset: Offset(0, 3)),
                      ],
                    ),
                    child: IconButton(
                      tooltip: labels[2],
                      onPressed: () => _openAdd(),
                      icon: Icon(icons[2], color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          if (!widget.store.loaded) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          final scheme = Theme.of(context).colorScheme;
          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: switch (_tab) {
                    0 => _homeTab(),
                    1 => SafeArea(
                        bottom: false,
                        child: HistoryScreen(
                          key: const ValueKey('calendar'),
                          store: widget.store,
                          calendarOnly: true,
                        ),
                      ),
                    3 => SafeArea(
                        bottom: false,
                        child: HistoryScreen(
                          key: const ValueKey('stats'),
                          store: widget.store,
                          cabinet: _cabinetSection(compact: true),
                        ),
                      ),
                    _ => _cabinetTab(),
                  },
                ),
                if (_toastMessage case final message?)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 84 + MediaQuery.paddingOf(context).bottom,
                    child: IgnorePointer(
                      child: Semantics(
                        liveRegion: true,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Text(message,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                    left: 0, right: 0, bottom: 0, child: _navigation(scheme)),
              ],
            ),
          );
        },
      );
}

Color _settingsTrackColor(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
        ? const Color(0xFF1B2735)
        : const Color(0xFFEEF2F5);

class _ThemeModeControl extends StatelessWidget {
  const _ThemeModeControl({
    required this.labels,
    required this.systemIndex,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int systemIndex;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _settingsTrackColor(scheme),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (var index = 0; index < labels.length; index++) ...[
              if (index > 0) const SizedBox(width: 3),
              Expanded(
                flex: index == systemIndex ? 3 : 2,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: index == selectedIndex
                        ? scheme.surfaceAccent
                        : scheme.onSurfaceVariant,
                    backgroundColor: index == selectedIndex
                        ? scheme.surface
                        : Colors.transparent,
                    elevation: index == selectedIndex ? 1 : 0,
                    shadowColor: const Color(0x20153A23),
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                    minimumSize: const Size(0, 42),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: index == selectedIndex
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  onPressed: () => onSelected(index),
                  child: Semantics(
                    selected: index == selectedIndex,
                    child: Text(labels[index], textAlign: TextAlign.center),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: _settingsTrackColor(scheme),
              foregroundColor: scheme.onSurface,
              side: BorderSide(color: theme.dividerColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              minimumSize: const Size(0, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onTap,
            child: Row(
              children: [
                Expanded(child: Text(value)),
                Icon(Icons.keyboard_arrow_down, color: scheme.surfaceAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Số phút trễ thành "35 phút" / "1 giờ 25 phút" / "2 giờ".
String _formatLate(int minutes) {
  if (minutes < 60) return tr('$minutes phút', '$minutes min');
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0
      ? tr('$h giờ', '$h h')
      : tr('$h giờ $m phút', '$h h $m min');
}

/// Một dòng chọn ngôn ngữ trong Cài đặt: cờ + tên + dấu chọn.
class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.lang,
    required this.selected,
    required this.onTap,
  });

  final AppLang lang;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: lang.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              FlagIcon(lang: lang, width: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  lang.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? scheme.surfaceAccent : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
