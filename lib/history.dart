import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';

/// Màn hình Lịch sử: lưới tháng + thống kê 30 ngày.
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
    final store = widget.store;
    final adherence = store.adherence30Days();
    final streak = store.currentStreak();
    final mostMissed = store.mostMissedMedicine();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Lịch sử & thống kê', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _statCard('Tỷ lệ uống đúng\n30 ngày qua', '${(adherence * 100).round()}%')),
            const SizedBox(width: 12),
            Expanded(child: _statCard('Chuỗi ngày\nliên tục', '$streak ngày')),
          ],
        ),
        const SizedBox(height: 12),
        _statCard(
          'Thuốc hay bị bỏ qua nhất',
          mostMissed ?? 'Chưa có lần bỏ qua nào. Tuyệt vời!',
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1, 1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Tháng ${_month.month}/${_month.year}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            IconButton(
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1, 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        _monthGrid(store),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: Color(0xFF95E77E), label: 'Đủ'),
            SizedBox(width: 14),
            _LegendDot(color: Color(0xFFFFB020), label: 'Thiếu'),
            SizedBox(width: 14),
            _LegendDot(color: Color(0xFFE0E0E0), label: 'Không có thuốc'),
          ],
        ),
        if (_selectedDay != null) ...[
          const SizedBox(height: 20),
          Text(
            'Ngày ${formatDateVn(_selectedDay!)}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._dayDetails(store, _selectedDay!),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _monthGrid(ThuocStore store) {
    final firstDay = _month;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final startWeekday = firstDay.weekday; // 1 = Thứ 2
    final cells = <Widget>[];
    for (final label in ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']) {
      cells.add(Center(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54))));
    }
    for (var i = 1; i < startWeekday; i++) {
      cells.add(const SizedBox());
    }
    final today = DateTime.now();
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final slots = store.slotsForDay(date);
      Color bg;
      if (slots.isEmpty) {
        bg = const Color(0xFFE0E0E0);
      } else if (date.isAfter(DateTime(today.year, today.month, today.day))) {
        bg = Colors.white;
      } else {
        final taken = slots.where((s) => store.logs[s.key]?.status == 'taken').length;
        if (taken == slots.length) {
          bg = const Color(0xFF95E77E);
        } else if (taken > 0) {
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
              border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
            ),
            alignment: Alignment.center,
            child: Text('$day', style: const TextStyle(fontWeight: FontWeight.w600)),
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
      final status = store.logs[slot.key]?.status;
      final label = status == 'taken'
          ? 'Đã uống'
          : status == 'skipped'
              ? 'Đã bỏ qua'
              : 'Chưa uống';
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          leading: Text(slot.medicine.formEmoji, style: const TextStyle(fontSize: 26)),
          title: Text('${slot.medicine.name} — ${slot.medicine.dose}'),
          subtitle: Text('Lúc ${slot.time}'),
          trailing: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    }).toList();
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
