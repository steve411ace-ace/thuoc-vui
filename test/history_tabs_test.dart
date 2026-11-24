import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thuoc_vui/history.dart';
import 'package:thuoc_vui/store.dart';
import 'package:thuoc_vui/strings.dart';

void main() {
  tearDown(() {
    Lang.current = AppLang.vi;
  });

  testWidgets('Calendar tab keeps monthly calendar and day detail',
      (tester) async {
    final store = ThuocStore()..loaded = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryScreen(store: store, calendarOnly: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LỊCH UỐNG THEO THÁNG'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Chi tiết ngày'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Chi tiết ngày'), findsOneWidget);
  });

  testWidgets('Statistics tab omits monthly calendar and keeps KPI, badges, purchases',
      (tester) async {
    final store = ThuocStore()..loaded = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryScreen(store: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tuân thủ tuần này'), findsOneWidget);
    expect(find.text('LỊCH UỐNG THEO THÁNG'), findsNothing);

    await tester.scrollUntilVisible(find.text('Lịch sử mua thuốc'), 300);
    expect(find.text('Danh hiệu đúng giờ'), findsOneWidget);
    expect(find.text('Lịch sử mua thuốc'), findsOneWidget);
    expect(find.text('LỊCH UỐNG THEO THÁNG'), findsNothing);
    expect(find.textContaining('Chi tiết ngày'), findsNothing);
  });
}
