import 'package:flutter/material.dart';
import 'home_style.dart';
import 'models.dart';
import 'pillflow_style.dart';

const _palette = {
  0xFF0D9488: 'Xanh teal',
  0xFF0EA5E9: 'Xanh da trời',
  0xFFF97316: 'Cam',
  0xFF8B5CF6: 'Tím',
  0xFFEC4899: 'Hồng',
};

const _meals = {
  'truoc_an': 'Trước ăn',
  'trong_bua': 'Trong bữa',
  'sau_an': 'Sau ăn',
  'truoc_ngu': 'Trước khi ngủ',
  'khong': 'Không dặn',
};

const List<String> _weekdayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

enum FrequencyMode { daily, alternate, weekly }

class AddMedicineScreen extends StatefulWidget {
  final Medicine? existing;
  final Future<void> Function(Medicine med) onSave;
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
  String _shape = 'capsule';
  int _color = 0xFF0D9488;
  bool _refillWarning = true;
  bool _saving = false;
  List<String> _times = ['08:00'];
  List<int> _weekdays = [1, 2, 3, 4, 5, 6, 7];
  FrequencyMode _frequency = FrequencyMode.daily;
  DateTime _start = DateTime.now();
  DateTime? _end;
  String _meal = 'sau_an';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _dose.text = e.dose;
      _note.text = e.note;
      _form = e.form;
      _shape = e.displayShape;
      _refillWarning = e.refillWarning;
      _color = e.color;
      if (e.times.isNotEmpty) _times = List.of(e.times);
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
    if (picked == null || !mounted) return;
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
    if (picked == null || !mounted) return;
    setState(() {
      if (isEnd) {
        _end = picked;
      } else {
        _start = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
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
    final sortedTimes = _times.toSet().toList()..sort();
    final med = Medicine(
      id: widget.existing?.id ??
          stableHash('${DateTime.now().millisecondsSinceEpoch}$name')
              .toString(),
      name: name,
      dose: _doseLabel,
      form: _form,
      shape: _shape,
      refillWarning: _refillWarning,
      color: _color,
      times: sortedTimes,
      weekdays: List.of(_weekdays)..sort(),
      startDate: _dateKey(_start),
      endDate: _end == null ? null : _dateKey(_end!),
      mealNote: _meal,
      note: _note.text.trim(),
      totalPills: int.tryParse(_totalPills.text.trim()) ?? 0,
      startPill: int.tryParse(_startPill.text.trim()) ?? 1,
      pillsPerDose: _doseCount,
      stockFrom: widget.existing?.stockFrom ?? '',
      stockFromAt: widget.existing?.stockFromAt ?? '',
    );
    setState(() => _saving = true);
    try {
      await widget.onSave(med);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
        label: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color:
                    selected ? Theme.of(context).colorScheme.onPrimary : null)),
        selected: selected,
        selectedColor: Theme.of(context).colorScheme.primary,
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

  String get _doseLabel {
    final custom = _dose.text.trim();
    return custom.isEmpty ? '$_doseCount viên' : custom;
  }

  int get _doseCount {
    final count = int.tryParse(_pillsPerDose.text.trim()) ?? 1;
    return count < 1 ? 1 : count;
  }

  void _stepDose(int change) {
    final next = _doseCount + change;
    if (next < 1) return;
    setState(() {
      if (_dose.text.trim() == '$_doseCount viên') _dose.clear();
      _pillsPerDose.text = '$next';
    });
  }

  Widget _preview(ColorScheme scheme) => DecoratedBox(
        decoration: pillPanel(scheme, radius: 24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              PillShapeIcon(_shape, color: Color(_color), size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('XEM TRƯỚC THẺ THUỐC',
                        style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .7)),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        hintText: 'Nhập tên thuốc…',
                        isDense: true,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 5),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                    Text(
                        '$_doseLabel · ${_meals[_meal]} · ${_times.join(', ')}',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _shapePicker(ColorScheme scheme) => Row(
        children: [
          for (final (shape, label, form) in const [
            ('capsule', 'Viên nang', 'vien'),
            ('tablet', 'Viên nén', 'vien'),
            ('drop', 'Siro/Giọt', 'nuoc'),
            ('pack', 'Gói bột', 'khac'),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Semantics(
                  button: true,
                  selected: _shape == shape,
                  child: Material(
                    color: Colors.transparent,
                    child: Ink(
                      decoration: _shape == shape
                          ? BoxDecoration(
                              gradient: pillGradient(scheme),
                              borderRadius: BorderRadius.circular(16))
                          : pillPanel(scheme, radius: 16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setState(() {
                          _shape = shape;
                          _form = form;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            children: [
                              PillShapeGlyph(shape,
                                  color: _shape == shape
                                      ? Colors.white
                                      : scheme.onSurfaceVariant),
                              const SizedBox(height: 4),
                              Text(label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: _shape == shape
                                          ? Colors.white
                                          : scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _colorPicker(ColorScheme scheme) {
    final colors = Map.of(_palette);
    if (!colors.containsKey(_color)) colors[_color] = 'Màu hiện tại';
    return Wrap(
      spacing: 2,
      children: [
        for (final entry in colors.entries)
          Semantics(
            selected: entry.key == _color,
            child: IconButton(
              tooltip: entry.value,
              onPressed: () => setState(() => _color = entry.key),
              icon: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Color(entry.key),
                  shape: BoxShape.circle,
                  border: entry.key == _color
                      ? Border.all(color: scheme.surface, width: 2)
                      : null,
                  boxShadow: entry.key == _color
                      ? [
                          BoxShadow(color: Color(entry.key), spreadRadius: 1.5),
                        ]
                      : null,
                ),
                child: entry.key == _color
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  Widget _timingCards(ColorScheme scheme) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: pillPanel(scheme),
              padding: const EdgeInsets.fromLTRB(9, 12, 9, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Liều mỗi lần',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  Row(
                    children: [
                      _stepButton(Icons.remove, 'Giảm liều',
                          _doseCount > 1 ? () => _stepDose(-1) : null),
                      Expanded(
                          child: Text('$_doseCount viên',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold))),
                      _stepButton(Icons.add, 'Tăng liều', () => _stepDose(1),
                          primary: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              decoration: pillPanel(scheme),
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Giờ uống',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  PopupMenuButton<String>(
                    tooltip: 'Chọn giờ uống',
                    onSelected: (value) {
                      if (value == 'custom') {
                        _pickTime(0);
                      } else {
                        setState(() => _times[0] = value);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: '07:30', child: Text('07:30 · Sáng')),
                      PopupMenuItem(
                          value: '12:30', child: Text('12:30 · Trưa')),
                      PopupMenuItem(
                          value: '18:30', child: Text('18:30 · Chiều')),
                      PopupMenuItem(value: '21:00', child: Text('21:00 · Tối')),
                      PopupMenuItem(
                          value: 'custom', child: Text('Chọn giờ khác…')),
                    ],
                    child: SizedBox(
                      height: 40,
                      child: Row(
                        children: [
                          Expanded(
                              child: Text(_times.first,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13))),
                          const Icon(Icons.keyboard_arrow_down, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _stepButton(IconData icon, String label, VoidCallback? onPressed,
      {bool primary = false}) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
      icon: Container(
        width: 27,
        height: 27,
        decoration: BoxDecoration(
          color: primary ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon,
            size: 17,
            color: onPressed == null
                ? scheme.onSurfaceVariant
                : primary
                    ? scheme.onPrimary
                    : scheme.onSurface),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: DecoratedBox(
              decoration: pillPanel(scheme, radius: 22),
              child: const BackButton(),
            ),
          ),
        ),
        title: Text(isEdit ? 'Sửa thuốc' : 'Thêm lịch uống thuốc',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
      bottomNavigationBar: PillGlass(
        radius: 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: pillGradient(scheme),
                borderRadius: BorderRadius.circular(16),
              ),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _saving ? null : _save,
                child: Text(isEdit ? 'Lưu thay đổi' : '+ Thêm vào lịch hôm nay',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          _preview(scheme),
          _sectionTitle('Dạng thuốc'),
          _shapePicker(scheme),
          if (_form == 'tiem' || _form == 'xit')
            Text('Đang dùng: ${widget.existing!.formLabel}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          _sectionTitle('Màu nhận diện'),
          _colorPicker(scheme),
          const SizedBox(height: 12),
          _timingCards(scheme),
          _sectionTitle('Thời điểm dùng'),
          Wrap(
            children: [
              for (final entry in _meals.entries)
                _chip(
                    label: entry.value,
                    selected: _meal == entry.key,
                    onTap: () => setState(() => _meal = entry.key)),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text('Cảnh báo sắp hết thuốc'),
              subtitle: const Text(
                  'Hiện nhắc mua thêm trên Hôm nay khi còn tối đa 7 ngày'),
              value: _refillWarning,
              onChanged: (value) => setState(() => _refillWarning = value),
            ),
          ),
          _sectionTitle('Liều dùng chi tiết (tùy chọn)'),
          TextField(
            controller: _dose,
            onChanged: (_) => setState(() {}),
            decoration:
                const InputDecoration(hintText: 'Ví dụ: 5 ml, 1 viên nang mềm'),
          ),
          _sectionTitle('Giờ uống bổ sung'),
          ..._times.asMap().entries.skip(1).map((e) {
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
            onPressed: () async {
              final index = _times.length;
              setState(() => _times.add('20:00'));
              await _pickTime(index);
            },
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
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Số viên mỗi lần uống, ví dụ: 1',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
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
