import 'package:flutter/material.dart';
import 'home_style.dart';
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

enum FrequencyMode { daily, alternate, weekly }

class AddMedicineScreen extends StatefulWidget {
  final Medicine? existing;
  final void Function(Medicine med) onSave;
  final VoidCallback? onDelete;

  const AddMedicineScreen(
      {super.key, this.existing, required this.onSave, this.onDelete});

  @override
  State<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends State<AddMedicineScreen> {
  final _name = TextEditingController();
  final _dose = TextEditingController();
  final _note = TextEditingController();
  final _totalPills = TextEditingController();
  final _startPill = TextEditingController();
  final _pillsPerDose = TextEditingController();
  String _form = 'vien';
  int _color = _palette[0];
  List<String> _times = ['08:00'];
  List<int> _weekdays = [1, 2, 3, 4, 5, 6, 7];
  FrequencyMode _frequency = FrequencyMode.daily;
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
      if (_weekdays.length == 7) {
        _frequency = FrequencyMode.daily;
      } else if (_weekdays.length == 4 &&
          _weekdays.contains(1) &&
          _weekdays.contains(3) &&
          _weekdays.contains(5) &&
          _weekdays.contains(7)) {
        _frequency = FrequencyMode.alternate;
      } else {
        _frequency = FrequencyMode.weekly;
      }
      _start = DateTime.parse(e.startDate);
      _end = e.endDate != null && e.endDate!.isNotEmpty
          ? DateTime.parse(e.endDate!)
          : null;
      _meal = e.mealNote;
      if (e.totalPills > 0) _totalPills.text = e.totalPills.toString();
      if (e.startPill > 1) _startPill.text = e.startPill.toString();
      if (e.pillsPerDose > 1) _pillsPerDose.text = e.pillsPerDose.toString();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _note.dispose();
    _totalPills.dispose();
    _startPill.dispose();
    _pillsPerDose.dispose();
    super.dispose();
  }

  String _dateKey(DateTime d) => todayKey(d);

  Future<void> _pickTime(int index) async {
    final parts = _times[index].split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
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
      id: widget.existing?.id ??
          stableHash('${DateTime.now().millisecondsSinceEpoch}$name')
              .toString(),
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
      totalPills: int.tryParse(_totalPills.text.trim()) ?? 0,
      startPill: int.tryParse(_startPill.text.trim()) ?? 1,
      pillsPerDose: int.tryParse(_pillsPerDose.text.trim()) ?? 1,
      stockFrom: widget.existing?.stockFrom ?? '',
    );
    widget.onSave(med);
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: HomeSectionLabel(text),
      );

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        selected: selected,
        selectedColor:
            Theme.of(context).colorScheme.surfaceAccent.withAlpha(26),
        onSelected: (_) => onTap(),
      ),
    );
  }

  void _onFrequencyChanged(FrequencyMode mode) {
    setState(() {
      _frequency = mode;
      switch (mode) {
        case FrequencyMode.daily:
          _weekdays = [1, 2, 3, 4, 5, 6, 7];
          break;
        case FrequencyMode.alternate:
          _weekdays = [1, 3, 5, 7];
          break;
        case FrequencyMode.weekly:
          if (_weekdays.length == 7) {
            _weekdays = [1, 3, 5];
          }
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        flexibleSpace: const HomeHeaderBackground(),
        title: HomeAppBarTitle(
          isEdit ? 'Sửa thuốc' : 'Thêm thuốc mới',
          'Thông tin thuốc và lịch uống',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('Tên thuốc *'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              hintText: 'Ví dụ: Vitamin D3 + K2, Amlodipine...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          _sectionTitle('Liều dùng'),
          TextField(
            controller: _dose,
            decoration: const InputDecoration(
              hintText: 'Ví dụ: 1 viên nang mềm, 5 ml, 2 viên...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          _sectionTitle('Giờ uống trong ngày *'),
          ..._times.asMap().entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(e.key),
                      icon: const Icon(Icons.access_time),
                      label: Text('Uống lúc ${e.value}',
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                  if (_times.length > 1)
                    IconButton(
                      onPressed: () => setState(() => _times.removeAt(e.key)),
                      icon: Icon(Icons.delete_outline, color: scheme.error),
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
          _sectionTitle('Tần suất uống'),
          Wrap(
            children: [
              _chip(
                label: 'Hàng ngày',
                selected: _frequency == FrequencyMode.daily,
                onTap: () => _onFrequencyChanged(FrequencyMode.daily),
              ),
              _chip(
                label: 'Cách ngày',
                selected: _frequency == FrequencyMode.alternate,
                onTap: () => _onFrequencyChanged(FrequencyMode.alternate),
              ),
              _chip(
                label: 'Hàng tuần',
                selected: _frequency == FrequencyMode.weekly,
                onTap: () => _onFrequencyChanged(FrequencyMode.weekly),
              ),
            ],
          ),
          if (_frequency == FrequencyMode.weekly) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'Chọn các ngày trong tuần:',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            Wrap(
              children: List.generate(7, (i) {
                final weekday = i + 1;
                return _chip(
                  label: _weekdayLabels[i],
                  selected: _weekdays.contains(weekday),
                  onTap: () => setState(() {
                    if (_weekdays.contains(weekday)) {
                      if (_weekdays.length > 1) _weekdays.remove(weekday);
                    } else {
                      _weekdays.add(weekday);
                    }
                  }),
                );
              }),
            ),
          ],
          _sectionTitle('Số liều hiện có trong tủ thuốc (tùy chọn)'),
          TextField(
            controller: _totalPills,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Số viên / liều trong hộp, ví dụ: 30',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _startPill,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText:
                  'Ngày bắt đầu là viên thứ mấy, ví dụ: 1 (đang uống dở thì nhập 10)',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pillsPerDose,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Số viên mỗi lần uống, ví dụ: 1',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          _sectionTitle('Dạng thuốc'),
          Wrap(
            children: [
              _chip(
                  label: '💊 Viên',
                  selected: _form == 'vien',
                  onTap: () => setState(() => _form = 'vien')),
              _chip(
                  label: '💧 Nước',
                  selected: _form == 'nuoc',
                  onTap: () => setState(() => _form = 'nuoc')),
              _chip(
                  label: '💉 Tiêm',
                  selected: _form == 'tiem',
                  onTap: () => setState(() => _form = 'tiem')),
              _chip(
                  label: '🌬️ Xịt',
                  selected: _form == 'xit',
                  onTap: () => setState(() => _form = 'xit')),
              _chip(
                  label: '📦 Khác',
                  selected: _form == 'khac',
                  onTap: () => setState(() => _form = 'khac')),
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
                    border: selected
                        ? Border.all(
                            color: Theme.of(context).colorScheme.surfaceAccent,
                            width: 3)
                        : null,
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
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
                  child: Text(_end == null
                      ? 'Đến: dài hạn'
                      : 'Đến: ${formatDateVn(_end!)}'),
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
              _chip(
                  label: 'Trước ăn',
                  selected: _meal == 'truoc_an',
                  onTap: () => setState(() => _meal = 'truoc_an')),
              _chip(
                  label: 'Sau ăn',
                  selected: _meal == 'sau_an',
                  onTap: () => setState(() => _meal = 'sau_an')),
              _chip(
                  label: 'Không dặn',
                  selected: _meal == 'khong',
                  onTap: () => setState(() => _meal = 'khong')),
            ],
          ),
          _sectionTitle('Ghi chú'),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Ví dụ: Sau ăn sáng 15 phút, uống với nước ấm...',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          const SizedBox(height: 28),

          // Nút Lưu thuốc và Hủy theo MediFlow
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Hủy',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      isEdit ? 'Lưu thay đổi' : 'Lưu thuốc',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (isEdit && widget.onDelete != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Xóa thuốc này?'),
                      content: const Text(
                          'Lịch nhắc và lịch sử của thuốc này cũng sẽ bị xóa.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Hủy')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text('Xóa',
                                style: TextStyle(
                                    color: Theme.of(ctx).colorScheme.error))),
                      ],
                    ),
                  );
                  if (ok == true) widget.onDelete!();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.error,
                  side: BorderSide(color: scheme.error),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
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
