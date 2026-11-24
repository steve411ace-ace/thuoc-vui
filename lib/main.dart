import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'add_medicine.dart';
import 'history.dart';
import 'home_color_picker.dart';
import 'home_style.dart';
import 'models.dart';
import 'pip.dart';
import 'purchases.dart';
import 'store.dart';
import 'widget_service.dart';

const _appVersion = '1.2.48';
const _appBuild = '51';

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
  bool _showConfetti = false;
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());

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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.store.reload();
    }
  }

  List<String> get _greetings {
    final hour = DateTime.now().hour;
    if (hour < 11) {
      return [
        'Chào buổi sáng! Uống thuốc rồi mới khỏe cả ngày nè!',
        'Sáng rồi! Pip nhắc bạn uống thuốc buổi sáng nhé!',
        'Buổi sáng tràn đầy năng lượng, uống thuốc đúng giờ nhé! ☀️',
      ];
    }
    if (hour < 14) {
      return [
        'Giờ uống thuốc trưa rồi, đừng quên nhé!',
        'Trưa rồi, uống thuốc xong nghỉ ngơi nhé!',
        'Trưa nay Pip nhắc nhẹ: uống thuốc rồi nghỉ trưa thôi!',
      ];
    }
    if (hour < 18) {
      return [
        'Chiều rồi! Còn mấy lần uống nữa là xong hôm nay!',
        'Pip đây! Nhớ uống thuốc chiều nhé!',
        'Chiều rồi, Pip cổ vũ bạn nốt mấy lần nữa là xong!',
      ];
    }
    return [
      'Uống thuốc tối xong là yên tâm đi ngủ ngon!',
      'Tối rồi, uống thuốc xong là hoàn thành ngày hôm nay!',
      'Tối nay uống thuốc xong là ngủ ngon nhé! 🌙',
    ];
  }

  String get _greeting {
    final list = _greetings;
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
    return list[dayOfYear % list.length];
  }

  Future<void> _openAdd([Medicine? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddMedicineScreen(
          existing: existing,
          onSave: (med) async {
            if (existing == null) {
              await widget.store.addMedicine(med);
            } else {
              await widget.store.updateMedicine(med);
            }
            if (mounted) Navigator.pop(context);
          },
          onDelete: existing == null
              ? null
              : () async {
                  await widget.store.deleteMedicine(existing.id);
                  if (mounted) Navigator.pop(context);
                },
        ),
      ),
    );
  }

  Future<void> _askSkip(DoseSlot slot) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Bỏ qua lần uống này?'),
        children: [
          for (final r in ['Quên', 'Hết thuốc', 'Khó chịu', 'Khác'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(r, style: const TextStyle(fontSize: 16)),
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
    final over = await widget.store.replenishMedicine(med, 10);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(over > 0
            ? 'Đã bổ sung 10 viên cho ${med.name} (đã trừ $over viên uống trước).'
            : 'Đã bổ sung 10 viên cho ${med.name}.'),
      ),
    );
    final recordPurchase = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ghi lần mua này không?'),
        content: Text(
            'Bạn vừa bổ sung 10 viên ${med.name}. Có muốn ghi vào lịch sử mua thuốc không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ghi lần mua'),
          ),
        ],
      ),
    );
    if (recordPurchase == true && mounted) {
      await showPurchaseForm(context, widget.store, medicineId: med.id);
    }
  }

  // -------------------------------------------------------------
  // TAB 0: HÔM NAY (MEDIFLOW)
  // -------------------------------------------------------------
  Widget _homeTab() {
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final isViewingToday = DateUtils.isSameDay(_selectedDay, today);
    final slots = store.slotsForDay(_selectedDay);
    final taken = slots
        .where(
            (s) => store.statusOf(s) == 'taken' || store.statusOf(s) == 'late')
        .length;
    final onTime = slots.where((s) => store.statusOf(s) == 'taken').length;
    final overdue = isViewingToday &&
        slots.any((s) =>
            store.statusOf(s) == null && s.dateTime.isBefore(DateTime.now()));
    final allDone = slots.isNotEmpty && taken == slots.length;
    final allOnTime = slots.isNotEmpty && onTime == slots.length;
    final streak = store.currentStreak();

    DoseSlot? nextSlot;
    if (isViewingToday) {
      for (final s in slots) {
        if (store.statusOf(s) == null) {
          nextSlot = s;
          break;
        }
      }
    }

    final PipMood pipMood;
    if (allOnTime) {
      pipMood = PipMood.celebrate;
    } else if (overdue) {
      pipMood = PipMood.worried;
    } else {
      pipMood = PipMood.happy;
    }

    // Nhóm liều theo buổi: BUỔI SÁNG / BUỔI TRƯA / BUỔI TỐI
    final morningSlots = <DoseSlot>[];
    final noonSlots = <DoseSlot>[];
    final eveningSlots = <DoseSlot>[];
    for (final s in slots) {
      final hour = int.tryParse(s.time.split(':')[0]) ?? 0;
      if (hour < 12) {
        morningSlots.add(s);
      } else if (hour < 17) {
        noonSlots.add(s);
      } else {
        eveningSlots.add(s);
      }
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
          children: [
            // 1. Thanh chọn ngày cả tuần ở đầu trang (T7-T6 / T2-CN)
            _weekSelectorStrip(scheme, today),

            if (!isViewingToday) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceAccent.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event, size: 18, color: scheme.surfaceAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Đang xem ngày ${formatDateVn(_selectedDay)}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scheme.surfaceAccent),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => setState(() => _selectedDay = today),
                      child: const Text('Về hôm nay'),
                    ),
                  ],
                ),
              ),
            ],

            // 2. Thẻ tổng quan ở đầu trang: streak, liều tiếp theo, vòng tròn tiến độ %
            _overviewCard(scheme, taken, slots.length, streak, nextSlot,
                allDone, pipMood, isViewingToday),
            const SizedBox(height: 12),

            // 3. Cảnh báo sắp hết thuốc ngay trên trang chính kèm nút "Bổ sung"
            _lowStockAlertBanner(store, scheme),

            // 4. Lịch uống trong ngày chia nhóm theo buổi
            if (slots.isEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 48, color: scheme.surfaceAccent.withAlpha(120)),
                      const SizedBox(height: 12),
                      Text(
                        isViewingToday
                            ? 'Chưa có lịch uống thuốc hôm nay.'
                            : 'Không có thuốc nào cần uống ngày này.',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isViewingToday
                            ? 'Bấm nút "Thêm thuốc" để bắt đầu theo dõi.'
                            : 'Lịch nhắc sẽ tự động hiển thị theo các ngày bạn cài đặt.',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              if (morningSlots.isNotEmpty) ...[
                const SizedBox(height: 8),
                const HomeSectionLabel('BUỔI SÁNG'),
                ...morningSlots.map((s) => _slotCard(s, isViewingToday)),
              ],
              if (noonSlots.isNotEmpty) ...[
                const SizedBox(height: 8),
                const HomeSectionLabel('BUỔI TRƯA'),
                ...noonSlots.map((s) => _slotCard(s, isViewingToday)),
              ],
              if (eveningSlots.isNotEmpty) ...[
                const SizedBox(height: 8),
                const HomeSectionLabel('BUỔI TỐI'),
                ...eveningSlots.map((s) => _slotCard(s, isViewingToday)),
              ],
            ],

            // 5. Dòng tóm tắt cuối trang
            const SizedBox(height: 16),
            _summaryBanner(scheme, taken, slots.length, nextSlot, isViewingToday),
            const SizedBox(height: 72),
          ],
        ),
        if (_showConfetti)
          ConfettiOverlay(onDone: () => setState(() => _showConfetti = false)),
      ],
    );
  }

  /// Thanh chọn 7 ngày trong tuần
  Widget _weekSelectorStrip(ColorScheme scheme, DateTime today) {
    final monday = _selectedDay.subtract(Duration(days: _selectedDay.weekday - 1));
    const weekdayNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: List.generate(7, (i) {
            final day = monday.add(Duration(days: i));
            final isSelected = DateUtils.isSameDay(day, _selectedDay);
            final isToday = DateUtils.isSameDay(day, today);

            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedDay = day),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? scheme.surfaceAccent
                        : (isToday
                            ? scheme.surfaceAccent.withAlpha(24)
                            : Colors.transparent),
                    borderRadius: BorderRadius.circular(14),
                    border: isToday && !isSelected
                        ? Border.all(color: scheme.surfaceAccent, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        weekdayNames[i],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isToday || isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (isToday
                                  ? scheme.surfaceAccent
                                  : scheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected || isToday
                              ? FontWeight.bold
                              : FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : (isToday
                                  ? scheme.surfaceAccent
                                  : scheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  /// Thẻ tổng quan đầu trang: streak, liều tiếp theo, vòng tròn tiến độ %
  Widget _overviewCard(
    ColorScheme scheme,
    int taken,
    int total,
    int streak,
    DoseSlot? nextSlot,
    bool allDone,
    PipMood pipMood,
    bool isViewingToday,
  ) {
    final nextDoseText = nextSlot != null
        ? 'Tiếp theo lúc ${nextSlot.time} — ${nextSlot.medicine.name} · ${nextSlot.medicine.dose}'
        : (allDone
            ? 'Đã hoàn thành tất cả liều hôm nay! 🎉'
            : (total == 0
                ? 'Không có liều thuốc nào cần uống'
                : 'Đã hoàn thành các liều đã đến giờ'));

    return Card(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.surface,
              Color.alphaBlend(scheme.surfaceAccent.withAlpha(16), scheme.surface),
            ],
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Vòng tròn tiến độ % liều đã uống
                _progressCircle(taken, total, scheme),
                const SizedBox(width: 14),
                // Thông tin chuỗi ngày + liều tiếp theo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF7A45).withAlpha(24),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🔥 ', style: TextStyle(fontSize: 11)),
                                Text(
                                  'Chuỗi $streak ngày liên tiếp',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFD64D18),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isViewingToday
                            ? nextDoseText
                            : 'Lịch ngày: $taken/$total liều hoàn thành',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Bong bóng lời nhắn của Pip
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PipWidget(size: 46, mood: pipMood),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceAccent.withAlpha(18),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
                      border: Border.all(
                        color: scheme.surfaceAccent.withAlpha(35),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _greeting,
                      style: TextStyle(
                        fontFamily: 'Be Vietnam Pro',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                        height: 1.35,
                      ),
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

  /// Vòng tròn tiến độ %
  Widget _progressCircle(int completed, int total, ColorScheme scheme) {
    final pct = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;
    final pctInt = (pct * 100).round();
    return SizedBox(
      width: 66,
      height: 66,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: pct,
            strokeWidth: 6,
            backgroundColor: scheme.surfaceAccent.withAlpha(30),
            valueColor: AlwaysStoppedAnimation<Color>(scheme.surfaceAccent),
            strokeCap: StrokeCap.round,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$pctInt%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  height: 1.1,
                ),
              ),
              Text(
                '$completed/$total liều',
                style: TextStyle(
                  fontSize: 9.5,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Cảnh báo sắp hết thuốc trên trang chính
  Widget _lowStockAlertBanner(ThuocStore store, ColorScheme scheme) {
    final lowMeds = store.medicines.where((m) {
      final rem = store.remainingPills(m);
      return rem != null && rem <= 6;
    }).toList();

    if (lowMeds.isEmpty) return const SizedBox.shrink();

    final med = lowMeds.first;
    final rem = store.remainingPills(med) ?? 0;
    final isOut = rem <= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.brightness == Brightness.dark
          ? (isOut ? const Color(0xFF381A1E) : const Color(0xFF362810))
          : (isOut ? const Color(0xFFFFECEF) : const Color(0xFFFFF7E6)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(
              isOut ? Icons.error_outline : Icons.warning_amber_rounded,
              color: isOut ? const Color(0xFFD32F2F) : const Color(0xFFE65100),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOut ? 'Hết thuốc: ${med.name}' : 'Sắp hết: ${med.name}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                      color: isOut
                          ? const Color(0xFFD32F2F)
                          : const Color(0xFFE65100),
                    ),
                  ),
                  Text(
                    isOut
                        ? 'Đã hết liều trong tủ thuốc'
                        : 'Chỉ còn $rem liều trong tủ thuốc',
                    style: TextStyle(fontSize: 12, color: scheme.onSurface),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 36),
              ),
              onPressed: () => _handleRefill(med),
              child: const Text('Bổ sung',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  /// Thẻ liều thuốc từng lần uống
  Widget _slotCard(DoseSlot slot, bool isViewingToday) {
    final store = widget.store;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    final status = store.statusOf(slot);
    final remaining = store.remainingPills(slot.medicine);
    final outOfStock = (remaining ?? 1) <= 0;
    final now = DateTime.now();
    final isOverdue = isViewingToday &&
        status == null &&
        slot.dateTime.isBefore(now);
    final log = store.logs[slot.key];

    final isTaken = status == 'taken' || status == 'late';
    final isSkipped = status == 'skipped';

    // Tính thời gian còn lại hoặc quá giờ
    String timeBadge;
    Color timeBadgeColor = scheme.surfaceAccent;
    if (isTaken) {
      final at = log != null && log.at.isNotEmpty ? DateTime.tryParse(log.at) : null;
      final atText = at != null
          ? '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'
          : '';
      if (status == 'late') {
        final lateMin = at?.difference(slot.dateTime).inMinutes ?? 0;
        timeBadge = 'Đã uống trễ lúc $atText${lateMin > 0 ? ' (trễ $lateMin phút)' : ''}';
        timeBadgeColor = const Color(0xFFE5A000);
      } else {
        timeBadge = 'Đã uống lúc $atText';
        timeBadgeColor = const Color(0xFF2E7D32);
      }
    } else if (isSkipped) {
      timeBadge = 'Đã bỏ qua${log != null && log.reason.isNotEmpty ? ' (${log.reason})' : ''}';
      timeBadgeColor = muted;
    } else if (isOverdue) {
      final lateMin = now.difference(slot.dateTime).inMinutes;
      timeBadge = 'Quá giờ • Trễ ${_formatLate(lateMin)}';
      timeBadgeColor = const Color(0xFFE5A000);
    } else {
      // Chưa đến giờ
      if (isViewingToday && now.isBefore(slot.dateTime)) {
        final diff = slot.dateTime.difference(now);
        final hours = diff.inHours;
        final mins = diff.inMinutes % 60;
        final diffText =
            hours > 0 ? '$hours giờ $mins phút' : '$mins phút';
        timeBadge = 'Chưa đến giờ • Còn $diffText';
      } else {
        timeBadge = 'Hẹn lúc ${slot.time}';
      }
      timeBadgeColor = scheme.surfaceAccent;
    }

    final stripe = doseStatusColor(isOverdue ? 'late' : status) ??
        (isTaken ? const Color(0xFF2E7D32) : scheme.surfaceAccent);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: stripe, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HomeTileIcon.emoji(slot.medicine.formEmoji),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${slot.medicine.name} — ${slot.medicine.dose}',
                              style: theme.listTileTheme.titleTextStyle,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.surfaceAccent.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              slot.time,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: scheme.surfaceAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${slot.medicine.mealLabel}'
                        '${slot.medicine.note.isNotEmpty ? ' • ${slot.medicine.note}' : ''}',
                        style: theme.listTileTheme.subtitleTextStyle,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: timeBadgeColor.withAlpha(20),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              timeBadge,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: timeBadgeColor,
                              ),
                            ),
                          ),
                          if (remaining != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              'Còn $remaining liều',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: remaining <= 3
                                    ? scheme.error
                                    : muted,
                                fontWeight: remaining <= 3
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            // Nút thao tác
            if (isTaken || isSkipped) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.undo, size: 17),
                  label: const Text('Hoàn tác'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: muted,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () async {
                    await store.undoTaken(slot);
                    if (!mounted) return;
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Đã hoàn tác, liều quay lại chưa uống.')),
                    );
                  },
                ),
              ),
            ] else ...[
              if (outOfStock) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hết thuốc rồi, bổ sung trước nhé!',
                        style: TextStyle(color: scheme.error, fontSize: 12),
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Bổ sung'),
                      onPressed: () => _handleRefill(slot.medicine),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Đã uống',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        onPressed: () async {
                          final beforeBadges = store.earnedBadgeIds();
                          final result = await store.markTaken(slot);
                          if (!mounted) return;
                          if (result == 'late') {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Đã ghi uống trễ, lần sau cố đúng giờ nhé! ⏰')),
                            );
                          } else {
                            setState(() => _showConfetti = true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Giỏi quá! Bạn đã uống đúng giờ! 🌟')),
                            );
                          }
                          final newBadges = store
                              .earnedBadgeIds()
                              .difference(beforeBadges);
                          if (newBadges.isNotEmpty && mounted) {
                            final badge = allBadges
                                .firstWhere((b) => b.id == newBadges.first);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Mở khóa danh hiệu mới: ${badge.emoji} ${badge.title}!')),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        onPressed: () async {
                          final snoozeMin =
                              store.settings.remindIntervalMinutes > 0
                                  ? store.settings.remindIntervalMinutes
                                  : 15;
                          await store.scheduleSnooze(slot.key, snoozeMin);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Đã hoãn nhắc sau $snoozeMin phút!')),
                          );
                        },
                        child: Text(
                          'Hoãn ${store.settings.remindIntervalMinutes > 0 ? store.settings.remindIntervalMinutes : 15}p',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Bỏ qua lần này',
                      icon: const Icon(Icons.close),
                      color: muted,
                      onPressed: () => _askSkip(slot),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Dòng tóm tắt cuối trang MediFlow
  Widget _summaryBanner(ColorScheme scheme, int taken, int total,
      DoseSlot? nextSlot, bool isViewingToday) {
    String summary;
    final hour = DateTime.now().hour;
    final timeGreeting = hour < 12 ? 'Sáng nay' : (hour < 17 ? 'Chiều nay' : 'Tối nay');

    if (total == 0) {
      summary = 'Không có lịch uống thuốc trong ngày này.';
    } else if (taken == total) {
      summary =
          '$timeGreeting bạn đã uống đủ $taken/$total liều. Tuyệt vời!';
    } else if (nextSlot != null) {
      summary =
          '$timeGreeting bạn đã uống $taken/$total liều. Còn ${total - taken} liều lúc ${nextSlot.time} — ${nextSlot.medicine.name}.';
    } else {
      summary =
          '$timeGreeting bạn đã uống $taken/$total liều thuốc.';
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

  // -------------------------------------------------------------
  // TAB 1: TỦ THUỐC (MEDIFLOW)
  // -------------------------------------------------------------
  Widget _cabinetTab() {
    final store = widget.store;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    final allCount = store.medicines.length;
    final activeCount =
        store.medicines.where((m) => m.activeOn(now)).length;
    final lowCount = store.medicines
        .where((m) => (store.remainingPills(m) ?? 999) <= 6)
        .length;

    // Lọc theo text search + filter
    final query = _cabinetQuery.trim().toLowerCase();
    final filtered = store.medicines.where((m) {
      if (query.isNotEmpty) {
        final matchName = m.name.toLowerCase().contains(query);
        final matchDose = m.dose.toLowerCase().contains(query);
        final matchNote = m.note.toLowerCase().contains(query);
        if (!matchName && !matchDose && !matchNote) return false;
      }
      if (_cabinetFilter == 'active') {
        return m.activeOn(now);
      } else if (_cabinetFilter == 'low') {
        return (store.remainingPills(m) ?? 999) <= 6;
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
      children: [
        // 1. Ô tìm kiếm thuốc
        TextField(
          controller: _cabinetSearchController,
          onChanged: (v) => setState(() => _cabinetQuery = v),
          decoration: InputDecoration(
            hintText: 'Tìm kiếm thuốc...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _cabinetQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _cabinetSearchController.clear();
                      setState(() => _cabinetQuery = '');
                    },
                  )
                : null,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 2. Bộ lọc: Tất cả / Đang dùng / Sắp hết
        Row(
          children: [
            _filterChip('Tất cả ($allCount)', 'all', scheme),
            const SizedBox(width: 8),
            _filterChip('Đang dùng ($activeCount)', 'active', scheme),
            const SizedBox(width: 8),
            _filterChip('Sắp hết ($lowCount)', 'low', scheme),
          ],
        ),
        const SizedBox(height: 16),

        // 3. Danh sách thẻ thuốc
        if (filtered.isEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 48, color: scheme.onSurfaceVariant.withAlpha(120)),
                  const SizedBox(height: 12),
                  Text(
                    _cabinetQuery.isNotEmpty
                        ? 'Không tìm thấy thuốc phù hợp.'
                        : (_cabinetFilter == 'low'
                            ? 'Không có thuốc nào sắp hết. Rất tốt!'
                            : 'Tủ thuốc đang trống.'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm thuốc mới'),
                    onPressed: () => _openAdd(),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          ...filtered.map((med) => _medicineCabinetCard(med, scheme)),
        ],

        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Thêm thuốc mới',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            onPressed: () => _openAdd(),
          ),
        ),
        const SizedBox(height: 60),
      ],
    );
  }

  Widget _filterChip(String label, String value, ColorScheme scheme) {
    final selected = _cabinetFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: scheme.surfaceAccent.withAlpha(30),
      onSelected: (_) => setState(() => _cabinetFilter = value),
    );
  }

  Widget _medicineCabinetCard(Medicine med, ColorScheme scheme) {
    final store = widget.store;
    final remaining = store.remainingPills(med);
    final total = med.totalPills;
    final days = store.daysSupply(med);

    double pct = 1.0;
    Color barColor = const Color(0xFF2E7D32);
    if (total > 0 && remaining != null) {
      pct = (remaining / total).clamp(0.0, 1.0);
      if (remaining <= 0) {
        barColor = scheme.error;
      } else if (pct <= 0.2 || (days != null && days <= 3)) {
        barColor = const Color(0xFFFF7A45);
      } else if (pct <= 0.5) {
        barColor = const Color(0xFFE5A000);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                HomeTileIcon.emoji(med.formEmoji),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              med.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Color(med.color),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${med.dose} • ${med.times.join(', ')} • ${med.mealLabel}',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                      if (med.note.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          med.note,
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Thanh % tồn kho thuốc
            if (total > 0 && remaining != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    remaining <= 0
                        ? 'Hết thuốc (0/$total liều)'
                        : 'Còn $remaining/$total liều${days != null ? ' (đủ $days ngày)' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: remaining <= 3 ? scheme.error : scheme.onSurface,
                    ),
                  ),
                  Text(
                    '${(pct * 100).round()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: barColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 8,
                  backgroundColor: scheme.surfaceAccent.withAlpha(24),
                  color: barColor,
                ),
              ),
            ] else ...[
              Text(
                'Chưa theo dõi số lượng (Dài hạn)',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const Divider(height: 20),

            // Nút thao tác: Bổ sung +10, Sửa, Xóa
            Row(
              children: [
                if (total > 0) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Bổ sung +10'),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    onPressed: () => _handleRefill(med),
                  ),
                  const Spacer(),
                ],
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Sửa'),
                  onPressed: () => _openAdd(med),
                ),
                TextButton.icon(
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: scheme.error),
                  label: Text('Xóa', style: TextStyle(color: scheme.error)),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Xóa thuốc này?'),
                        content: Text('Xóa "${med.name}" khỏi tủ thuốc? Lịch nhắc và lịch sử cũng sẽ bị xóa.'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Hủy')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text('Xóa',
                                  style: TextStyle(color: scheme.error))),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await store.deleteMedicine(med.id);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // TAB 3: CÀI ĐẶT
  // -------------------------------------------------------------
  Widget _settingsTab() {
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
        // 1. Nhóm "Hiển thị & âm thanh"
        const HomeSectionLabel('HIỂN THỊ & ÂM THANH'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chế độ'),
                const SizedBox(height: 6),
                _ThemeModeControl(
                  labels: const ['Sáng', 'Tối', 'Theo điện thoại'],
                  systemIndex: 2,
                  selectedIndex: appModes.indexOf(settings.appThemeMode),
                  onSelected: (index) => store.updateAppTheme(appModes[index]),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Âm thanh nhắc'),
                  value: settings.sound,
                  onChanged: (v) async {
                    await store.updateSettings(settings.copyWith(sound: v));
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rung khi nhắc'),
                  value: settings.vibration,
                  onChanged: (v) async {
                    await store.updateSettings(settings.copyWith(vibration: v));
                  },
                ),
                const Divider(height: 20),
                const Text('Bảng màu giao diện'),
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
        const HomeSectionLabel('THỜI GIAN HOÃN NHẮC MẶC ĐỊNH'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Thời gian nhắc lại khi bấm nút "Hoãn" trên thẻ liều thuốc hoặc thông báo:',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [5, 10, 15, 30].map((mins) {
                    final selected = settings.remindIntervalMinutes == mins;
                    return ChoiceChip(
                      label: Text('$mins phút'),
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
        const HomeSectionLabel('ĐỘ MỜ WIDGET'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nền widget trong suốt dần khi kéo xuống. 100% là đặc như hiện tại, 0% là nền biến mất hoàn toàn.',
                  style: TextStyle(color: muted),
                ),
                Row(
                  children: [
                    const Text('Mờ hơn'),
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
                const Text('Giao diện widget'),
                const SizedBox(height: 6),
                _ThemeModeControl(
                  labels: const ['Theo điện thoại', 'Sáng', 'Tối'],
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
        const HomeSectionLabel('GIỜ YÊN LẶNG'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _SettingsField(
                  label: 'Giờ yên lặng bắt đầu',
                  value: settings.quietStart,
                  onTap: () => pickQuiet(true),
                ),
                const SizedBox(height: 11),
                _SettingsField(
                  label: 'Giờ yên lặng kết thúc',
                  value: settings.quietEnd,
                  onTap: () => pickQuiet(false),
                ),
                const SizedBox(height: 8),
                Text(
                  'Trong giờ yên lặng, app không lên lịch nhắc mới. Các lần uống vẫn hiện trên lịch hôm nay.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 5. Thông báo & Báo thức
        const HomeSectionLabel('THÔNG BÁO'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Lịch nhắc dùng báo thức hệ thống. Nếu đã từ chối quyền vĩnh viễn, bật thủ công tại Cài đặt máy > Ứng dụng > Thuốc Vui > Thông báo.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('Xin quyền thông báo'),
                    onPressed: () async {
                      final granted =
                          await store.requestNotificationPermission();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(granted
                              ? 'Đã có quyền thông báo, lịch nhắc đã lên lại!'
                              : 'Chưa có quyền thông báo. Hãy bật tay trong Cài đặt máy > Ứng dụng > Thuốc Vui.'),
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
                    label: const Text('Cho phép báo thức chính xác'),
                    onPressed: () async {
                      final canExact = await store.canScheduleExact();
                      if (canExact) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Máy đã cho phép báo thức chính xác rồi, nhắc sẽ đúng giờ.')),
                        );
                        return;
                      }
                      await store.requestExactAlarmPermission();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Đã mở màn hình Báo thức & nhắc nhở. Bật "Cho phép đặt báo thức và nhắc nhở" cho Thuốc Vui nhé!')),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.battery_charging_full_outlined),
                    label: const Text('Tắt tối ưu pin cho Thuốc Vui'),
                    onPressed: () async {
                      final opened =
                          await store.requestIgnoreBatteryOptimizations();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(opened
                                ? 'Đã mở màn hình miễn tối ưu pin. Bấm "Cho phép" để Thuốc Vui không bị máy cho ngủ.'
                                : 'Không mở được màn hình pin. Vào Cài đặt máy > Ứng dụng > Thuốc Vui > Pin > Không giới hạn.')),
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
                label: 'Số lần báo lại nếu chưa uống',
                value: settings.remindTimes == 0
                    ? 'Tắt'
                    : '${settings.remindTimes} lần',
                onTap: () async {
                  final picked = await showDialog<int>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: const Text('Số lần báo lại nếu chưa uống'),
                      children: [
                        for (final n in [0, 1, 2, 3, 5])
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(ctx, n),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(n == 0 ? 'Tắt' : '$n lần',
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
          'Lưu ý: app chỉ nhắc giờ uống và ghi nhận đã uống, không thay thế chỉ định của bác sĩ. Khởi động lại điện thoại xong, mở app một lần để lịch nhắc hoạt động lại.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text('Thuốc Vui • Phiên bản $_appVersion+$_appBuild',
              style: TextStyle(color: muted, fontSize: 13)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, child) {
        if (!widget.store.loaded) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 82,
            titleSpacing: 22,
            flexibleSpace: const HomeHeaderBackground(),
            actions: [
              Builder(builder: (context) {
                final ink = Theme.of(context).colorScheme.onPrimary;
                return Container(
                  margin: const EdgeInsets.only(right: 20),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: ink.withAlpha(16),
                    border: Border.all(color: ink.withAlpha(40)),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(_appVersion,
                      style: TextStyle(fontSize: 11, color: ink)),
                );
              }),
            ],
            title: HomeAppBarTitle(
              'Thuốc Vui',
              ['Hôm nay', 'Tủ thuốc', 'Thống kê', 'Cài đặt'][_tab],
              icon: Icons.medication_outlined,
            ),
            centerTitle: false,
          ),
          body: _tab == 0
              ? _homeTab()
              : _tab == 1
                  ? _cabinetTab()
                  : _tab == 2
                      ? HistoryScreen(store: widget.store)
                      : Theme(
                          data: Theme.of(context).copyWith(
                            cardTheme: Theme.of(context).cardTheme.copyWith(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  shadowColor: const Color(0x16173E2C),
                                ),
                          ),
                          child: _settingsTab(),
                        ),
          floatingActionButton: _tab == 0
              ? FloatingActionButton.extended(
                  onPressed: () => _openAdd(),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm thuốc',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                )
              : null,
          bottomNavigationBar: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: NavigationBar(
              height: 68,
              backgroundColor: Theme.of(context).colorScheme.surface,
              indicatorColor:
                  Theme.of(context).colorScheme.surfaceAccent.withAlpha(26),
              indicatorShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11)),
              selectedIndex: _tab,
              onDestinationSelected: (i) {
                setState(() => _tab = i);
                if (i == 0) widget.store.reload();
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.today_outlined),
                  selectedIcon: Icon(Icons.today),
                  label: 'Hôm nay',
                ),
                NavigationDestination(
                  icon: Icon(Icons.medical_services_outlined),
                  selectedIcon: Icon(Icons.medical_services),
                  label: 'Tủ thuốc',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: 'Thống kê',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Cài đặt',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Color _settingsTrackColor(ColorScheme scheme) =>
    scheme.brightness == Brightness.dark
        ? const Color(0xFF253D36)
        : const Color(0xFFF0F4F1);

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
  if (minutes < 60) return '$minutes phút';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h giờ' : '$h giờ $m phút';
}
