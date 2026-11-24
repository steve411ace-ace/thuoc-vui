import 'package:flutter/material.dart';
import 'home_style.dart';
import 'models.dart';
import 'pillflow_style.dart';
import 'strings.dart';

Map<int, String> get _palette => {
      0xFF0D9488: tr('Xanh teal', 'Teal'),
      0xFF0EA5E9: tr('Xanh da trời', 'Sky blue'),
      0xFFF97316: tr('Cam', 'Orange'),
      0xFF8B5CF6: tr('Tím', 'Purple'),
      0xFFEC4899: tr('Hồng', 'Pink'),
    };

Map<String, String> get _meals => {
      'truoc_an': tr('Trước ăn', 'Before meals'),
      'trong_bua': tr('Trong bữa', 'With meals'),
      'sau_an': tr('Sau ăn', 'After meals'),
      'truoc_ngu': tr('Trước khi ngủ', 'Before bed'),
      'khong': tr('Không dặn', 'No instruction'),
    };

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
        SnackBar(
            content: Text(tr('Bạn chưa nhập tên thuốc.',
                'Please enter the medicine name.'))),
      );
      return;
    }
    if (_times.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr('Cần ít nhất một giờ uống trong ngày.',
                'At least one dose time per day is required.'))),
      );
      return;
    }
    if (_weekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr('Chọn ít nhất một ngày trong tuần.',
                'Select at least one day of the week.'))),
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
    return custom.isEmpty ? _defaultDoseLabel : custom;
  }

  String get _defaultDoseLabel => tr('$_doseCount viên',
      '$_doseCount ${enPlural(_doseCount, 'pill', 'pills')}');

  int get _doseCount {
    final count = int.tryParse(_pillsPerDose.text.trim()) ?? 1;
    return count < 1 ? 1 : count;
  }

  void _stepDose(int change) {
    final next = _doseCount + change;
    if (next < 1) return;
    setState(() {
      final cur = _dose.text.trim();
      if (cur == _defaultDoseLabel || cur == '$_doseCount viên') _dose.clear();
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
                    Text(tr('XEM TRƯỚC THẺ THUỐC', 'MEDICINE CARD PREVIEW'),
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
                      decoration: InputDecoration(
                        hintText: tr('Nhập tên thuốc…', 'Enter medicine name…'),
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
          for (final (shape, label, form) in [
            ('capsule', tr('Viên nang', 'Capsule'), 'vien'),
            ('tablet', tr('Viên nén', 'Tablet'), 'vien'),
            ('drop', tr('Siro/Giọt', 'Syrup/Drops'), 'nuoc'),
            ('pack', tr('Gói bột', 'Powder pack'), 'khac'),
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
    if (!colors.containsKey(_color))
      colors[_color] = tr('Màu hiện tại', 'Current color');
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
                  Text(tr('Liều mỗi lần', 'Dose each time'),
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  Row(
                    children: [
                      _stepButton(
                          Icons.remove,
                          tr('Giảm liều', 'Decrease dose'),
                          _doseCount > 1 ? () => _stepDose(-1) : null),
                      Expanded(
                          child: Text(_defaultDoseLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold))),
                      _stepButton(Icons.add, tr('Tăng liều', 'Increase dose'),
                          () => _stepDose(1),
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
                  Text(tr('Giờ uống', 'Dose time'),
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  PopupMenuButton<String>(
                    tooltip: tr('Chọn giờ uống', 'Choose dose time'),
                    onSelected: (value) {
                      if (value == 'custom') {
                        _pickTime(0);
                      } else {
                        setState(() => _times[0] = value);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: '07:30',
                          child: Text('07:30 · ${tr('Sáng', 'Morning')}')),
                      PopupMenuItem(
                          value: '12:30',
                          child: Text('12:30 · ${tr('Trưa', 'Noon')}')),
                      PopupMenuItem(
                          value: '18:30',
                          child: Text('18:30 · ${tr('Chiều', 'Afternoon')}')),
                      PopupMenuItem(
                          value: '21:00',
                          child: Text('21:00 · ${tr('Tối', 'Evening')}')),
                      PopupMenuItem(
                          value: 'custom',
                          child:
                              Text(tr('Chọn giờ khác…', 'Pick another time…'))),
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
        title: Text(
            isEdit
                ? tr('Sửa thuốc', 'Edit medicine')
                : tr('Thêm lịch uống thuốc', 'Add medicine schedule'),
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
                child: Text(
                    isEdit
                        ? tr('Lưu thay đổi', 'Save changes')
                        : tr('+ Thêm vào lịch hôm nay',
                            '+ Add to today\'s schedule'),
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
          _sectionTitle(tr('Dạng thuốc', 'Medicine form')),
          _shapePicker(scheme),
          if (_form == 'tiem' || _form == 'xit')
            Text(
                '${tr('Đang dùng', 'Currently')}: ${widget.existing!.formLabel}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          _sectionTitle(tr('Màu nhận diện', 'Identifying color')),
          _colorPicker(scheme),
          const SizedBox(height: 12),
          _timingCards(scheme),
          _sectionTitle(tr('Thời điểm dùng', 'When to take')),
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
              title: Text(tr('Cảnh báo sắp hết thuốc', 'Low stock warning')),
              subtitle: Text(tr(
                  'Hiện nhắc mua thêm trên Hôm nay khi còn tối đa 7 ngày',
                  'Show a refill reminder on Today when 7 days or less remain')),
              value: _refillWarning,
              onChanged: (value) => setState(() => _refillWarning = value),
            ),
          ),
          _sectionTitle(
              tr('Liều dùng chi tiết (tùy chọn)', 'Dose details (optional)')),
          TextField(
            controller: _dose,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                hintText: tr('Ví dụ: 5 ml, 1 viên nang mềm',
                    'e.g. 5 ml, 1 soft capsule')),
          ),
          _sectionTitle(tr('Giờ uống bổ sung', 'Additional dose times')),
          ..._times.asMap().entries.skip(1).map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(e.key),
                      icon: const Icon(Icons.access_time),
                      label: Text(
                          tr('Uống lúc ${e.value}', 'Take at ${e.value}'),
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
            label: Text(tr('Thêm giờ uống', 'Add dose time')),
          ),
          _sectionTitle(tr('Tần suất uống', 'Frequency')),
          Wrap(
            children: [
              _chip(
                label: tr('Hàng ngày', 'Daily'),
                selected: _frequency == FrequencyMode.daily,
                onTap: () => _onFrequencyChanged(FrequencyMode.daily),
              ),
              _chip(
                label: tr('Cách ngày', 'Every other day'),
                selected: _frequency == FrequencyMode.alternate,
                onTap: () => _onFrequencyChanged(FrequencyMode.alternate),
              ),
              _chip(
                label: tr('Hàng tuần', 'Weekly'),
                selected: _frequency == FrequencyMode.weekly,
                onTap: () => _onFrequencyChanged(FrequencyMode.weekly),
              ),
            ],
          ),
          if (_frequency == FrequencyMode.weekly) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                tr('Chọn các ngày trong tuần:', 'Select days of the week:'),
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
            Wrap(
              children: List.generate(7, (i) {
                final weekday = i + 1;
                return _chip(
                  label: weekdayShort(i + 1),
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
          _sectionTitle(tr('Số liều hiện có trong tủ thuốc (tùy chọn)',
              'Doses currently in your medicine cabinet (optional)')),
          TextField(
            controller: _totalPills,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: tr('Số viên / liều trong hộp, ví dụ: 30',
                  'Number of pills / doses in the box, e.g. 30'),
              border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _startPill,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: tr(
                  'Ngày bắt đầu là viên thứ mấy, ví dụ: 1 (đang uống dở thì nhập 10)',
                  'Which pill number you start on, e.g. 1 (enter 10 if the box is already started)'),
              border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pillsPerDose,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: tr(
                  'Số viên mỗi lần uống, ví dụ: 1', 'Pills per dose, e.g. 1'),
              border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16))),
            ),
          ),
          _sectionTitle(tr('Thời gian uống', 'Duration')),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(false),
                  child:
                      Text('${tr('Từ', 'From')}: ${formatDateLocal(_start)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(true),
                  child: Text(_end == null
                      ? tr('Đến: dài hạn', 'To: ongoing')
                      : '${tr('Đến', 'To')}: ${formatDateLocal(_end!)}'),
                ),
              ),
            ],
          ),
          if (_end != null)
            TextButton(
              onPressed: () => setState(() => _end = null),
              child: Text(tr('Đổi thành uống dài hạn', 'Switch to ongoing')),
            ),
          _sectionTitle(tr('Ghi chú', 'Notes')),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: tr('Ví dụ: Sau ăn sáng 15 phút, uống với nước ấm...',
                  'e.g. 15 minutes after breakfast, take with warm water...'),
              border: const OutlineInputBorder(
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
                      title:
                          Text(tr('Xóa thuốc này?', 'Delete this medicine?')),
                      content: Text(tr(
                          'Lịch nhắc và lịch sử của thuốc này cũng sẽ bị xóa.',
                          'Its reminders and history will also be deleted.')),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(tr('Hủy', 'Cancel'))),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(tr('Xóa', 'Delete'),
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
                child: Text(tr('Xóa thuốc này', 'Delete this medicine')),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
