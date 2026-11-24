import 'package:flutter/material.dart';
import 'home_style.dart';
import 'models.dart';
import 'purchases.dart';
import 'pillflow_style.dart';
import 'store.dart';

/// Thống kê, lịch uống theo tháng và chi tiết liều theo ngày.
class HistoryScreen extends StatefulWidget {
  final ThuocStore store;
  final bool calendarOnly;
  final DateTime? detailDay;
  final Widget? cabinet;

  const HistoryScreen({
    super.key,
    required this.store,
    this.calendarOnly = false,
    this.detailDay,
    this.cabinet,
  });

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
    final today = DateUtils.dateOnly(DateTime.now());
    if (widget.detailDay case final day?) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: _daySection(store, day),
      );
    }
    if (widget.calendarOnly) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
        children: [
          const HomeSectionLabel('LỊCH UỐNG THEO THÁNG'),
          _calendarCard(store),
          if (_selectedDay case final day?)
            ..._daySection(store, day)
          else if (_month.year == today.year && _month.month == today.month)
            ..._daySection(store, today),
        ],
      );
    }
    final now = DateTime.now();
    final monday =
        DateTime(today.year, today.month, today.day - today.weekday + 1);
    final previousMonday = DateTime(monday.year, monday.month, monday.day - 7);
    final current = _weekTotals(store, monday, now);
    final previous = _weekTotals(store, previousMonday, monday);
    final percent =
        current.total == 0 ? 0 : (100 * current.taken / current.total).round();
    final previousPercent = previous.total == 0
        ? 0
        : (100 * previous.taken / previous.total).round();
    final delta = percent - previousPercent;
    final medStats = store.medicineAdherenceStats();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Báo cáo sức khỏe',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                  const Text('Thống kê & Tủ thuốc',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            if (current.total > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      (percent >= 80 ? pillEmerald : pillAmber).withAlpha(38),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(percent >= 80 ? 'Tốt $percent%' : '$percent%',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: _kpi(
              'Tuân thủ tuần này',
              '$percent%',
              current.total == 0
                  ? 'Chưa có liều đến giờ'
                  : previous.total == 0
                      ? 'Chưa có dữ liệu tuần trước'
                      : '${delta >= 0 ? '+' : '−'}${delta.abs()} điểm % so với tuần trước',
              scheme.surfaceAccent,
            )),
            const SizedBox(width: 10),
            Expanded(
                child: _kpi(
              'Uống đúng giờ',
              '${current.onTime}/${current.total}',
              '${current.taken - current.onTime} lần uống trễ',
              scheme.onSurface,
            )),
          ],
        ),
        const SizedBox(height: 16),
        _weeklyChart(store, today),
        const SizedBox(height: 16),
        if (widget.cabinet != null) ...[
          widget.cabinet!,
          const SizedBox(height: 16),
        ],

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
                        PillShapeIcon(stat.medicine.displayShape,
                            color: Color(stat.medicine.color)),
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
                                ? pillEmerald
                                : pct >= 50
                                    ? pillAmber
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
                            ? pillEmerald
                            : pct >= 50
                                ? pillAmber
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
        _calendarCard(store),
        if (_selectedDay case final day?) ..._daySection(store, day),
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

  ({int total, int onTime, int taken}) _weekTotals(
    ThuocStore store,
    DateTime start,
    DateTime cutoff,
  ) {
    var total = 0;
    var onTime = 0;
    var taken = 0;
    for (var i = 0; i < 7; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      if (day.isAfter(cutoff)) break;
      for (final slot in store.slotsForDay(day)) {
        final status = store.statusOf(slot);
        if (!slot.dateTime.isBefore(cutoff) && !pillTaken(status)) continue;
        total++;
        if (status == 'taken') onTime++;
        if (pillTaken(status)) taken++;
      }
    }
    return (total: total, onTime: onTime, taken: taken);
  }

  Widget _kpi(String title, String value, String detail, Color ink) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 11, color: scheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: muted),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 24, color: ink, fontWeight: FontWeight.w800)),
            Text(detail, style: muted),
          ],
        ),
      ),
    );
  }

  Widget _weeklyChart(ThuocStore store, DateTime today) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(today.year, today.month, today.day - 6);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                    child: Text('Lịch sử 7 ngày qua',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold))),
                Text(
                    '${first.day}/${first.month} – ${today.day}/${today.month}',
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                      child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                    child: _chartBar(
                        store,
                        DateTime(first.year, first.month, first.day + i),
                        i == 6),
                  )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartBar(ThuocStore store, DateTime day, bool isToday) {
    final scheme = Theme.of(context).colorScheme;
    final slots = store.slotsForDay(day);
    final onTime =
        slots.where((slot) => store.statusOf(slot) == 'taken').length;
    final rate = slots.isEmpty ? 0.0 : onTime / slots.length;
    final color = rate == 1
        ? scheme.surfaceAccent
        : rate >= .5
            ? pillSky
            : pillAmber;
    return Column(
      children: [
        Text(slots.isEmpty ? '–' : '${(rate * 100).round()}%',
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Container(
          height: 80,
          width: double.infinity,
          padding: const EdgeInsets.all(2),
          alignment: Alignment.bottomCenter,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: double.infinity,
            height: slots.isEmpty ? 0 : (rate * 76).clamp(6.0, 76.0),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 4),
        Text(pillWeekday(day),
            style: TextStyle(
              fontSize: 10,
              color: isToday ? scheme.surfaceAccent : scheme.onSurfaceVariant,
              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
            )),
      ],
    );
  }

  List<Widget> _daySection(ThuocStore store, DateTime day) => [
        const SizedBox(height: 16),
        HomeSectionLabel('Chi tiết ngày ${formatDateVn(day)}'),
        ..._dayDetails(store, day),
      ];

  void _changeMonth(int offset) => setState(() {
        _month = DateTime(_month.year, _month.month + offset);
        _selectedDay = null;
      });

  Widget _calendarCard(ThuocStore store) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Tháng trước',
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text('Tháng ${_month.month}/${_month.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Tháng sau',
                onPressed: () => _changeMonth(1),
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
              const _LegendDot(color: pillEmerald, label: 'Đủ đúng giờ'),
              const _LegendDot(color: pillAmber, label: 'Có trễ'),
              const _LegendDot(color: pillSlate, label: 'Thiếu'),
              _LegendDot(color: scheme.outlineVariant, label: 'Không có thuốc'),
            ],
          ),
        ]),
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
      final isToday = DateUtils.isSameDay(date, today);
      final recorded =
          !date.isAfter(DateUtils.dateOnly(today)) && slots.isNotEmpty;
      final completed =
          slots.where((slot) => pillTaken(store.statusOf(slot))).length;
      final onTime =
          slots.where((slot) => store.statusOf(slot) == 'taken').length;
      final dot = !recorded
          ? scheme.outlineVariant
          : onTime == slots.length
              ? pillEmerald
              : completed == slots.length
                  ? pillAmber
                  : pillSlate;
      final selected = DateUtils.isSameDay(_selectedDay, date);
      cells.add(
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _selectedDay = date),
            child: Ink(
              decoration: BoxDecoration(
                color: selected || isToday ? scheme.primaryContainer : null,
                borderRadius: BorderRadius.circular(12),
                border:
                    selected ? Border.all(color: scheme.surfaceAccent) : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$day',
                      style: TextStyle(
                          fontSize: 12,
                          color: selected || isToday
                              ? scheme.surfaceAccent
                              : scheme.onSurface,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Icon(Icons.circle, color: dot, size: 5),
                ],
              ),
            ),
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
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PillShapeIcon(slot.medicine.displayShape,
                  color: Color(slot.medicine.color)),
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
