import 'package:flutter/material.dart';
import 'home_style.dart';
import 'models.dart';
import 'purchases.dart';
import 'store.dart';

/// Màn hình Thống kê (Tab Thống kê & Lịch sử theo phong cách MediFlow).
class HistoryScreen extends StatefulWidget {
  final ThuocStore store;
  const HistoryScreen({super.key, required this.store});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = widget.store;
    final weekAdherence = store.adherenceThisWeek();
    final monthDoses = store.takenDosesThisMonth();
    final streak = store.currentStreak();
    final onTimeStreak = store.onTimeStreak();
    final now = DateTime.now();
    final medStats = store.medicineAdherenceStats();
    final weekChart = store.weeklyDailyAdherence();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
      children: [
        // 1. Thẻ tổng quan MediFlow
        const HomeSectionLabel('TỔNG QUAN TUÂN THỦ'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _statBox(
                        context,
                        'Tuân thủ tuần này',
                        '${(weekAdherence * 100).round()}%',
                        Icons.verified_outlined,
                        scheme.surfaceAccent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statBox(
                        context,
                        'Đã uống tháng ${now.month}',
                        '$monthDoses liều',
                        Icons.check_circle_outline,
                        const Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _statBox(
                        context,
                        'Chuỗi ngày uống',
                        '$streak ngày',
                        Icons.local_fire_department_outlined,
                        const Color(0xFFFF7A45),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statBox(
                        context,
                        'Chuỗi đúng giờ',
                        '$onTimeStreak ngày',
                        Icons.alarm_on_outlined,
                        const Color(0xFFE5A000),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 2. Biểu đồ cột 7 ngày
        const HomeSectionLabel('BIỂU ĐỒ 7 NGÀY TUẦN NÀY'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tỉ lệ uống đúng giờ',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Đúng giờ / tổng liều',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: weekChart.map((item) {
                      final isToday =
                          DateUtils.isSameDay(item.day, DateTime.now());
                      final isFuture = item.day
                          .isAfter(DateUtils.dateOnly(DateTime.now()));
                      final pct = (item.rate * 100).round();
                      final hasDoses = item.total > 0;
                      // Chiều cao thanh cột tối đa 80px
                      final barHeight = hasDoses && !isFuture
                          ? (item.rate * 76).clamp(8.0, 76.0)
                          : 4.0;
                      Color barColor;
                      if (isFuture || !hasDoses) {
                        barColor = scheme.surfaceContainerHighest;
                      } else if (pct >= 80) {
                        barColor = const Color(0xFF2E7D32);
                      } else if (pct >= 50) {
                        barColor = const Color(0xFFE5A000);
                      } else {
                        barColor = const Color(0xFFFF6B9D);
                      }

                      return Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              isFuture || !hasDoses ? '-' : '$pct%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isToday
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isFuture || !hasDoses
                                    ? scheme.onSurfaceVariant.withAlpha(120)
                                    : scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: barHeight,
                              width: 22,
                              decoration: BoxDecoration(
                                color: barColor,
                                borderRadius: BorderRadius.circular(6),
                                border: isToday
                                    ? Border.all(
                                        color: scheme.surfaceAccent, width: 2)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: isToday
                                  ? BoxDecoration(
                                      color:
                                          scheme.surfaceAccent.withAlpha(30),
                                      borderRadius: BorderRadius.circular(10),
                                    )
                                  : null,
                              child: Text(
                                item.weekdayLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isToday
                                      ? scheme.surfaceAccent
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // 3. Chi tiết % uống đúng giờ từng thuốc
        if (medStats.isNotEmpty) ...[
          const HomeSectionLabel('CHI TIẾT THEO THUỐC (30 NGÀY)'),
          ...medStats.map((stat) {
            final pct = (stat.onTimeRate * 100).round();
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        HomeTileIcon.emoji(stat.medicine.formEmoji),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${stat.medicine.name} — ${stat.medicine.dose}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              Text(
                                '${stat.onTimeDoses}/${stat.totalDoses} lần đúng giờ',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: pct >= 80
                                ? const Color(0xFF2E7D32)
                                : pct >= 50
                                    ? const Color(0xFFE5A000)
                                    : scheme.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: stat.onTimeRate,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceAccent.withAlpha(26),
                        color: pct >= 80
                            ? const Color(0xFF2E7D32)
                            : pct >= 50
                                ? const Color(0xFFE5A000)
                                : scheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 20),
        ],

        // 4. Danh hiệu đúng giờ
        _badgesSection(store),
        const SizedBox(height: 20),

        // 5. Lịch uống theo tháng (tính năng cốt lõi Thuốc Vui)
        const HomeSectionLabel('LỊCH UỐNG THEO THÁNG'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => setState(() =>
                        _month = DateTime(_month.year, _month.month - 1, 1)),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('Tháng ${_month.month}/${_month.year}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: () => setState(() =>
                        _month = DateTime(_month.year, _month.month + 1, 1)),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              _monthGrid(store),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  const _LegendDot(
                      color: Color(0xFF95E77E), label: 'Đủ đúng giờ'),
                  const _LegendDot(color: Color(0xFFFFB020), label: 'Có trễ'),
                  const _LegendDot(color: Color(0xFFFF9AA2), label: 'Thiếu'),
                  _LegendDot(
                      color: scheme.surfaceContainerHighest,
                      label: 'Không có thuốc'),
                ],
              ),
            ]),
          ),
        ),

        // Chi tiết ngày được chọn
        if (_selectedDay != null) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Chi tiết ngày ${formatDateVn(_selectedDay!)}',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.calendar_month_outlined,
                  color: scheme.surfaceAccent, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          ..._dayDetails(store, _selectedDay!),
        ],
        const SizedBox(height: 20),

        // 6. Mua thuốc
        const HomeSectionLabel('MUA THUỐC'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Lịch sử mua thuốc',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('${firstPurchaseLabel(store)} • '
                    'Tổng ${store.totalPurchasedBoxes} vỉ • '
                    '${formatPurchaseMoney(store.totalPurchaseCost)}'),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PurchaseHistoryScreen(store: store),
                      ),
                    ),
                    label: const Text('Xem & ghi lần mua'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _statBox(BuildContext context, String label, String value,
      IconData icon, Color iconColor) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: iconColor.withAlpha(16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _badgesSection(ThuocStore store) {
    final scheme = Theme.of(context).colorScheme;
    final earned = store.earnedBadgeIds();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Danh hiệu đúng giờ',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Chuỗi đúng giờ: ${store.onTimeStreak()} ngày • Tổng lần đúng giờ: ${store.totalOnTime()}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allBadges.map((b) {
                final got = earned.contains(b.id);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: got
                        ? scheme.surfaceAccent.withAlpha(26)
                        : scheme.surface,
                    border:
                        Border.all(color: scheme.surfaceAccent.withAlpha(55)),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    got ? '${b.emoji} ${b.title}' : '🔒 ${b.title}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: got ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthGrid(ThuocStore store) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final firstDay = _month;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final startWeekday = firstDay.weekday; // 1 = Thứ 2
    final cells = <Widget>[];
    for (final label in ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']) {
      cells.add(Center(
          child: Text(label,
              style: TextStyle(fontWeight: FontWeight.bold, color: muted))));
    }
    for (var i = 1; i < startWeekday; i++) {
      cells.add(const SizedBox());
    }
    final today = DateTime.now();
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final slots = store.slotsForDay(date);
      Color bg;
      var labelColor = scheme.onSurface;
      if (slots.isEmpty) {
        bg = scheme.surfaceContainerHighest;
      } else if (date.isAfter(DateTime(today.year, today.month, today.day))) {
        bg = scheme.surface;
      } else {
        labelColor = Colors.black87;
        final completed = slots
            .where((s) =>
                store.logs[s.key]?.status == 'taken' ||
                store.logs[s.key]?.status == 'late')
            .length;
        final onTime =
            slots.where((s) => store.logs[s.key]?.status == 'taken').length;
        if (completed == slots.length && onTime == slots.length) {
          bg = const Color(0xFF95E77E);
        } else if (completed == slots.length) {
          bg = const Color(0xFFFFB020);
        } else {
          bg = const Color(0xFFFF9AA2);
        }
      }
      final isSelected = _selectedDay != null &&
          _selectedDay!.year == date.year &&
          _selectedDay!.month == date.month &&
          _selectedDay!.day == date.day;
      cells.add(
        GestureDetector(
          onTap: () => setState(() => _selectedDay = date),
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: scheme.surfaceAccent, width: 2)
                  : null,
            ),
            alignment: Alignment.center,
            child: Text('$day',
                style:
                    TextStyle(color: labelColor, fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cells,
    );
  }

  List<Widget> _dayDetails(ThuocStore store, DateTime day) {
    final slots = store.slotsForDay(day);
    if (slots.isEmpty) {
      return [const Text('Ngày này không có thuốc nào cần uống.')];
    }
    return slots.map((slot) {
      final remaining = store.remainingPills(slot.medicine);
      final log = store.logs[slot.key];
      final status = log?.status;
      final label = status == 'taken'
          ? 'Đã uống đúng giờ'
          : status == 'late'
              ? 'Đã uống trễ'
              : status == 'skipped'
                  ? 'Đã bỏ qua'
                  : 'Chưa uống';
      String? takenAt;
      String? lateText;
      if ((status == 'taken' || status == 'late') &&
          log != null &&
          log.at.isNotEmpty) {
        final at = DateTime.tryParse(log.at);
        if (at != null) {
          takenAt =
              '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
          if (status == 'late') {
            final lateMin = at.difference(slot.dateTime).inMinutes;
            if (lateMin > 0) lateText = 'Trễ ${_formatLate(lateMin)}';
          }
        }
      }
      final scheme = Theme.of(context).colorScheme;
      final stripe = doseStatusColor(status) ?? scheme.surfaceAccent;
      final ink = doseStatusInk(scheme, status);
      final badgeBackground = scheme.brightness == Brightness.dark
          ? Color.alphaBlend(ink.withAlpha(32), scheme.surface)
          : switch (status) {
              'taken' => const Color(0xFFEAF4E8),
              'late' => const Color(0xFFFFF4D9),
              _ => const Color(0xFFEFF3F2),
            };
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: stripe, width: 4)),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeTileIcon.emoji(slot.medicine.formEmoji),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${slot.medicine.name} — ${slot.medicine.dose}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('Hẹn ${slot.time}'),
                    if (takenAt != null) Text('Uống lúc $takenAt'),
                    if (lateText != null)
                      Text(lateText, style: TextStyle(color: ink)),
                    if (remaining != null) Text('Còn lại: $remaining viên'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeBackground,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(label,
                          style: TextStyle(
                            color: ink,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}

/// 1.2.36: số phút trễ thành "35 phút" / "1 giờ 25 phút" / "2 giờ".
String _formatLate(int minutes) {
  if (minutes < 60) return '$minutes phút';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h giờ' : '$h giờ $m phút';
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
