import 'package:flutter/material.dart';

import 'home_style.dart';
import 'models.dart';
import 'store.dart';
import 'strings.dart';

String formatPurchaseMoney(int amount) => '${amount.toString().replaceAllMapped(
      RegExp(r'\d(?=(\d{3})+$)'),
      (match) => '${match[0]}.',
    )} ${tr('đ', 'VND')}';

String _purchaseDateKey(DateTime date) => todayKey(date).padLeft(10, '0');

String _formatPurchaseDate(String date) {
  final parsed = DateTime.tryParse(date);
  return parsed == null
      ? date.split('-').reversed.join('/')
      : formatDateLocal(parsed);
}

String _boxesLabel(int n) => '$n ${tr('vỉ', enPlural(n, 'box', 'boxes'))}';

String firstPurchaseLabel(ThuocStore store) {
  final first = store.firstPurchaseDate;
  return first == null
      ? tr('Chưa có lần mua nào', 'No purchases yet')
      : tr('Mua đầu tiên: ${_formatPurchaseDate(first)}',
          'First purchase: ${_formatPurchaseDate(first)}');
}

String get _deletedMedicineLabel => tr('Thuốc đã xóa', 'Deleted medicine');

class PurchaseHistoryScreen extends StatelessWidget {
  final ThuocStore store;

  const PurchaseHistoryScreen({super.key, required this.store});

  Future<void> _confirmDelete(
    BuildContext context,
    PurchaseRecord purchase,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Xóa lần mua này?', 'Delete this purchase?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Hủy', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Xóa', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) await store.deletePurchase(purchase.id);
  }

  static const _valueStyle = TextStyle(fontWeight: FontWeight.bold);

  Widget _card(Widget child) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: child,
      );

  Widget _summaryValue(BuildContext context, String label, String value) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: muted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        Text(value, style: _valueStyle.copyWith(fontSize: 18)),
      ],
    );
  }

  String _cardMoney(int amount) =>
      formatPurchaseMoney(amount).replaceFirst(' ', '\u00A0');

  Widget _periodCard(
    String label,
    ({int boxes, int cost}) stats,
  ) {
    return _card(
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  Text('${_boxesLabel(stats.boxes)} •'),
                  Text(_cardMoney(stats.cost), style: _valueStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final purchases = [...store.purchases]..sort((a, b) {
            final byDate = b.date.compareTo(a.date);
            return byDate == 0 ? b.id.compareTo(a.id) : byDate;
          });
        final medicineNames = {
          for (final medicine in store.medicines) medicine.id: medicine.name,
        };
        final firstPurchase = store.firstPurchaseDate;
        final months = store.purchasesByMonth();
        final years = store.purchasesByYear();
        final monthKeys = months.keys.toList()..sort((a, b) => b.compareTo(a));
        final yearKeys = years.keys.toList()..sort((a, b) => b.compareTo(a));

        return Scaffold(
          appBar: AppBar(
            title: HomeAppBarTitle(
              tr('Mua thuốc', 'Medicine purchases'),
              tr('Chi phí và các lần mua', 'Costs and purchases'),
            ),
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: tr('Ghi lần mua', 'Add purchase'),
            onPressed: () => showPurchaseForm(context, store),
            child: const Icon(Icons.add),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              HomeSectionLabel(tr('Tổng quan', 'Overview')),
              _card(
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _summaryValue(
                        context,
                        tr('Mua đầu tiên', 'First purchase'),
                        firstPurchase == null
                            ? tr('Chưa có lần mua nào', 'No purchases yet')
                            : _formatPurchaseDate(firstPurchase),
                      ),
                      _summaryValue(
                        context,
                        tr('Tổng số vỉ', 'Total boxes'),
                        store.totalPurchasedBoxes.toString(),
                      ),
                      _summaryValue(
                        context,
                        tr('Tổng tiền', 'Total cost'),
                        _cardMoney(store.totalPurchaseCost),
                      ),
                    ],
                  ),
                ),
              ),
              if (monthKeys.isNotEmpty) HomeSectionLabel(tr('Theo tháng', 'By month')),
              for (final month in monthKeys)
                _periodCard(
                  tr('Tháng ${month.split('-').reversed.join('/')}',
                      'Month ${month.split('-').reversed.join('/')}'),
                  months[month]!,
                ),
              if (yearKeys.isNotEmpty) HomeSectionLabel(tr('Theo năm', 'By year')),
              for (final year in yearKeys)
                _periodCard(tr('Năm $year', 'Year $year'), years[year]!),
              if (purchases.isNotEmpty) HomeSectionLabel(tr('Các lần mua', 'Purchases')),
              for (final purchase in purchases)
                _card(
                  ListTile(
                    leading: const HomeTileIcon(Icons.shopping_bag_outlined),
                    contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    title: Text(
                      medicineNames[purchase.medicineId] ??
                          _deletedMedicineLabel,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_formatPurchaseDate(purchase.date)),
                        Text(
                          '${_boxesLabel(purchase.boxes)} × ${_cardMoney(purchase.pricePerBox)}',
                        ),
                        Text(_cardMoney(purchase.total), style: _valueStyle),
                      ],
                    ),
                    onTap: () =>
                        showPurchaseForm(context, store, purchase: purchase),
                    trailing: IconButton(
                      tooltip: tr('Xóa lần mua', 'Delete purchase'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(context, purchase),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

int _suggestedPriceFor(List<PurchaseRecord> purchases, String medicineId) {
  PurchaseRecord? latest;
  DateTime? latestDate;
  for (final record in purchases) {
    if (record.medicineId != medicineId) continue;
    final parsedDate = DateTime.tryParse(record.date);
    if (latest == null) {
      latest = record;
      latestDate = parsedDate;
      continue;
    }
    final cmp = parsedDate != null && latestDate != null
        ? parsedDate.compareTo(latestDate)
        : record.date.compareTo(latest.date);
    if (cmp > 0 || (cmp == 0 && record.id.compareTo(latest.id) > 0)) {
      latest = record;
      latestDate = parsedDate;
    }
  }
  return latest?.pricePerBox ?? 0;
}

Future<void> showPurchaseForm(
  BuildContext context,
  ThuocStore store, {
  PurchaseRecord? purchase,
  String? medicineId,
}) async {
  final medicines = {
    for (final medicine in store.medicines) medicine.id: medicine.name,
  };
  if (purchase != null) {
    medicines.putIfAbsent(purchase.medicineId, () => _deletedMedicineLabel);
  }
  if (medicines.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(tr('Hãy thêm thuốc trước khi ghi lần mua.',
            'Add a medicine before recording a purchase.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Đóng', 'Close')),
          ),
        ],
      ),
    );
    return;
  }

  final result = await showDialog<PurchaseRecord>(
    context: context,
    builder: (context) => _PurchaseFormDialog(
      store: store,
      medicines: medicines,
      purchase: purchase,
      medicineId: medicineId,
    ),
  );
  if (result == null) return;
  if (purchase == null) {
    await store.addPurchase(result);
  } else {
    await store.updatePurchase(result);
  }
}

class _PurchaseFormDialog extends StatefulWidget {
  final ThuocStore store;
  final Map<String, String> medicines;
  final PurchaseRecord? purchase;
  final String? medicineId;

  const _PurchaseFormDialog({
    required this.store,
    required this.medicines,
    required this.purchase,
    required this.medicineId,
  });

  @override
  State<_PurchaseFormDialog> createState() => _PurchaseFormDialogState();
}

class _PurchaseFormDialogState extends State<_PurchaseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final DateTime _today;
  late String _selectedMedicine;
  late DateTime _date;
  late int _boxes;
  late int _price;
  late int _pills;
  late final TextEditingController _priceController;
  var _priceEdited = false;

  @override
  void initState() {
    super.initState();
    final purchase = widget.purchase;
    _selectedMedicine = purchase?.medicineId ??
        (widget.medicines.containsKey(widget.medicineId)
            ? widget.medicineId!
            : widget.medicines.keys.first);
    _today = DateUtils.dateOnly(DateTime.now());
    _date = purchase == null ? _today : DateTime.parse(purchase.date);
    _boxes = purchase?.boxes ?? 1;
    _price = purchase?.pricePerBox ??
        _suggestedPriceFor(widget.store.purchases, _selectedMedicine);
    _pills = purchase?.pillsPerBox ?? 10;
    _priceController = TextEditingController(text: _price.toString());
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchase = widget.purchase;
    return AlertDialog(
      title: Text(purchase == null
          ? tr('Ghi lần mua', 'Add purchase')
          : tr('Sửa lần mua', 'Edit purchase')),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_formatPurchaseDate(_purchaseDateKey(_date))),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(1),
                  lastDate: _date.isAfter(_today) ? _date : _today,
                );
                if (picked != null && context.mounted) {
                  setState(() => _date = picked);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedMedicine,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Thuốc', 'Medicine')),
              items: [
                for (final medicine in widget.medicines.entries)
                  DropdownMenuItem(
                    value: medicine.key,
                    child:
                        Text(medicine.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedMedicine = value;
                  if (purchase == null && !_priceEdited) {
                    final suggested =
                        _suggestedPriceFor(widget.store.purchases, value);
                    _price = suggested;
                    _priceController.text = suggested.toString();
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            _numberField(
                tr('Số vỉ', 'Number of boxes'), _boxes.toString(), 1, (value) => _boxes = value),
            const SizedBox(height: 12),
            _numberField(
              tr('Đơn giá mỗi vỉ (đ)', 'Price per box (VND)'),
              null,
              0,
              (value) => _price = value,
              controller: _priceController,
              onChanged: (_) => _priceEdited = true,
            ),
            const SizedBox(height: 12),
            _numberField(
              tr('Số viên mỗi vỉ', 'Pills per box'),
              _pills.toString(),
              1,
              (value) => _pills = value,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Hủy', 'Cancel')),
        ),
        FilledButton(
          onPressed: () {
            final form = _formKey.currentState!;
            if (!form.validate()) return;
            form.save();
            Navigator.pop(
              context,
              PurchaseRecord(
                id: purchase?.id ??
                    DateTime.now().microsecondsSinceEpoch.toString(),
                medicineId: _selectedMedicine,
                date: _purchaseDateKey(_date),
                boxes: _boxes,
                pricePerBox: _price,
                pillsPerBox: _pills,
              ),
            );
          },
          child: Text(tr('Lưu', 'Save')),
        ),
      ],
    );
  }
}

Widget _numberField(
  String label,
  String? initialValue,
  int min,
  ValueChanged<int> onSaved, {
  TextEditingController? controller,
  ValueChanged<String>? onChanged,
}) {
  return TextFormField(
    controller: controller,
    initialValue: controller == null ? initialValue : null,
    decoration: InputDecoration(labelText: label),
    keyboardType: TextInputType.number,
    onChanged: onChanged,
    validator: (value) {
      final number = int.tryParse(value?.trim() ?? '', radix: 10);
      return number == null || number < min ? tr('Nhập số nguyên ≥ $min', 'Enter an integer ≥ $min') : null;
    },
    onSaved: (value) => onSaved(int.parse(value!.trim(), radix: 10)),
  );
}
