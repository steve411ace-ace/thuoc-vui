import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thuoc_vui/models.dart';
import 'package:thuoc_vui/purchases.dart';
import 'package:thuoc_vui/store.dart';

void main() {
  testWidgets('Purchase history fits a 390×844 screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = ThuocStore()
      ..medicines = [
        Medicine(
          id: 'medicine',
          name: 'Thuốc uống hằng ngày',
          dose: '1 viên',
          form: 'vien',
          color: 0xFF009688,
          times: const ['08:00'],
          weekdays: const [1, 2, 3, 4, 5, 6, 7],
          startDate: '2025-12-31',
          mealNote: 'khong',
          note: '',
          pillsPerDose: 1,
        ),
      ]
      ..purchases = const [
        PurchaseRecord(
          id: 'purchase',
          medicineId: 'medicine',
          date: '2025-12-31',
          boxes: 33,
          pricePerBox: 210000,
          pillsPerBox: 10,
        ),
      ];
    addTearDown(store.dispose);

    expect(store.purchasesByMonth()['2025-12'], (boxes: 1, cost: 210000));
    expect(store.purchasesByMonth()['2026-01'], (boxes: 3, cost: 630000));
    expect(store.purchasesByYear(), {
      '2025': (boxes: 1, cost: 210000),
      '2026': (boxes: 32, cost: 6720000),
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Be Vietnam Pro'),
        home: PurchaseHistoryScreen(store: store),
      ),
    );
    expect(tester.takeException(), isNull);

    final purchase = find.text('Thuốc uống hằng ngày');
    await tester.scrollUntilVisible(purchase, 200);
    await tester.pumpAndSettle();

    expect(purchase, findsOneWidget);
    expect(find.text('33 vỉ × 210.000\u00A0đ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
