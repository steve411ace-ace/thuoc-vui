import 'package:flutter/material.dart';
import 'models.dart';

const List<int> _palette = [
  0xFF2BB3A3,
  0xFFFF6B9D,
  0xFFFFB020,
  0xFF6BCBFF,
  0xFF95E77E,
  0xFF9B7EDE,
  0xFFFF7A45,
];

const List<String> _weekdayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

class AddMedicineScreen extends StatefulWidget {
  final Medicine? existing;
  final void Function(Medicine med) onSave;
  final VoidCallback? onDelete;

  const AddMedicineScreen({super.key, this.existing, required this.onSave, this.onDelete});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _name = TextEditingController();
  final _dose = TextEditingController();
  final _note = TextEditingController();
  String _form = 'vien';
  int _color = _palette[0];
  List<String> _times = ['08:00'];
  List<int> _weekdays = [1, 2, 3, 4, 5, 6, 7];
  DateTime _start = DateTime.now();
  DateTime? _end;
  String _meal = 'khong';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _dose.text = e.dose;
      _note.text = e.note;
      _form = e.form;
      _color = e.color;
      _times = List.of(e.times);
      _weekdays = List.of(e.weekdays);
      _start = DateTime.parse(e.startDate);
      _end = e.endDate != null && e.endDate!.isNotEmpty ? DateTime.parse(e.endDate!) : null;
      _meal = e.mealNote;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _note.dispose();
    super.dispose();
  }

  String _dateKey(DateTime d) => todayKey(d);

  Future<void> _pickTime(int index) async {
    final parts = _times[index].split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
    );
    if (picked == null) return;
    setState(() {
      _times[index] =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _pickDate(bool isEnd) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isEnd ? (_end ?? DateTime.now()) : _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isEnd) {
        _end = picked;
      } else {
        _start = picked;
      }
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn chưa nhập tên thuốc.')),
      );
      return;
    }
    if (_times.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cần ít nhất một giờ uống trong ngày.')),
      );
      return;
    }
    if (_weekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chọn ít nhất một ngày trong tuần.')),
      );
      return;
    }
    final sortedTimes = List.of(_times)..sort();
    final med = Medicine(
      id: widget.existing?.id ?? stableHash('${DateTime.now().millisecondsSinceEpoch}$name').toString(),
      name: name,
      dose: _dose.text.trim().isEmpty ? '1 viên' : _dose.text.trim(),
      form: _form,
      color: _color,
      times: sortedTimes,
      weekdays: List.of(_weekdays)..sort(),
      startDate: _dateKey(_start),
      endDate: _end == null ? null : _dateKey(_end!),
      mealNote: _meal,
      note: _note.text.trim(),
    );
    widget.onSave(med);
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        selected: selected,
        selectedColor: color ?? const Color(0xFFFFD93D),
        onSelected: (_) => onTap(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Sửa thuốc' : 'Thêm thuốc mới'),
        backgroundColor: const Color(0xFFFFD93D),
        foregroundColor: const Color(0xFF333333),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle('Tên thuốc'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              hintText: 'Ví dụ: Vitamin C, Thuốc huyết áp...',
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          _sectionTitle('Liều dùng'),
          TextField(
            controller: _dose,
            decoration: const InputDecoration(
              hintText: 'Ví dụ: 1 viên, 5 ml, 2 viên...',
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          _sectionTitle('Dạng thuốc'),
          Wrap(
            children: [
              _chip(label: '💊 Viên', selected: _form == 'vien', onTap: () => setState(() => _form = 'vien')),
              _chip(label: '💧 Nước', selected: _form == 'nuoc', onTap: () => setState(() => _form = 'nuoc')),
              _chip(label: '💉 Tiêm', selected: _form == 'tiem', onTap: () => setState(() => _form = 'tiem')),
              _chip(label: '🌬️ Xịt', selected: _form == 'xit', onTap: () => setState(() => _form = 'xit')),
              _chip(label: '📦 Khác', selected: _form == 'khac', onTap: () => setState(() => _form = 'khac')),
            ],
          ),
          _sectionTitle('Màu của thuốc'),
          Wrap(
            children: _palette.map((c) {
              final selected = c == _color;
              return GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  margin: const EdgeInsets.only(right: 10, bottom: 8),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: selected ? Border.all(color: Colors.black, width: 3) : null,
                  ),
                  child: selected ? const Icon(Icons.check, color: Colors.white) : null,
                ),
              );
            }).toList(),
          ),
          _sectionTitle('Giờ uống trong ngày'),
          ..._times.asMap().entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(e.key),
                      icon: const Icon(Icons.access_time),
                      label: Text('Uống lúc ${e.value}', style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                  if (_times.length > 1)
                    IconButton(
                      onPressed: () => setState(() => _times.removeAt(e.key)),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                ],
              ),
            );
          }),
          TextButton.icon(
            onPressed: () => setState(() => _times.add('20:00')),
            icon: const Icon(Icons.add),
            label: const Text('Thêm giờ uống'),
          ),
          _sectionTitle('Uống vào ngày nào'),
          Wrap(
            children: List.generate(7, (i) {
              final weekday = i + 1;
              return _chip(
                label: _weekdayLabels[i],
                selected: _weekdays.contains(weekday),
                onTap: () => setState(() {
                  if (_weekdays.contains(weekday)) {
                    _weekdays.remove(weekday);
                  } else {
                    _weekdays.add(weekday);
                  }
                }),
              );
            }),
          ),
          _sectionTitle('Thời gian uống'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(false),
                  child: Text('Từ: ${formatDateVn(_start)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(true),
                  child: Text(_end == null ? 'Đến: dài hạn' : 'Đến: ${formatDateVn(_end!)}'),
                ),
              ),
            ],
          ),
          if (_end != null)
            TextButton(
              onPressed: () => setState(() => _end = null),
              child: const Text('Đổi thành uống dài hạn'),
            ),
          _sectionTitle('Uống trước hay sau ăn?'),
          Wrap(
            children: [
              _chip(label: 'Trước ăn', selected: _meal == 'truoc_an', onTap: () => setState(() => _meal = 'truoc_an')),
              _chip(label: 'Sau ăn', selected: _meal == 'sau_an', onTap: () => setState(() => _meal = 'sau_an')),
              _chip(label: 'Không dặn', selected: _meal == 'khong', onTap: () => setState(() => _meal = 'khong')),
            ],
          ),
          _sectionTitle('Ghi chú'),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Ví dụ: uống với nước ấm, không uống cùng sữa...',
              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2BB3A3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(isEdit ? 'Lưu thay đổi' : 'Thêm thuốc', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ),
          if (isEdit && widget.onDelete != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Xóa thuốc này?'),
                      content: const Text('Lịch nhắc và lịch sử của thuốc này cũng sẽ bị xóa.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (ok == true) widget.onDelete!();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Xóa thuốc này'),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
