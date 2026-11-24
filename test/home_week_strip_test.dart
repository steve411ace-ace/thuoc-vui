import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thuoc_vui/main.dart';
import 'package:thuoc_vui/models.dart';
import 'package:thuoc_vui/store.dart';
import 'package:thuoc_vui/strings.dart';

void main() {
  tearDown(() {
    Lang.current = AppLang.vi;
  });

  testWidgets('Tapping a day in week strip switches Home inline without modal',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final med = Medicine(
      id: 'm1',
      name: 'Vitamin C',
      dose: '1 viên',
      form: 'vien',
      color: 0xFF0F766E,
      times: ['08:00'],
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      startDate: todayKey(yesterday),
      mealNote: 'sau_an',
      note: '',
    );
    final store = ThuocStore()
      ..loaded = true
      ..medicines = [med]
      ..logs = {
        '${med.id}|${todayKey(yesterday)}|08:00': DoseLog(
          status: 'taken',
          at: DateTime(yesterday.year, yesterday.month, yesterday.day, 8, 5)
              .toIso8601String(),
        ),
      };

    await tester.pumpWidget(ThuocVuiApp(store: store));
    await tester.pumpAndSettle();

    // Initially viewing today: 0/1 taken
    expect(find.text('Tiến độ hôm nay'), findsOneWidget);
    expect(find.text('0/1 liều đã uống'), findsOneWidget);

    // Tap yesterday in the week strip
    await tester.tap(find.text('${yesterday.day}'));
    await tester.pumpAndSettle();

    // No modal bottom sheet opened; Home switched inline to yesterday (1/1 taken)
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Tiến độ ${monthDayLabel(yesterday)}'), findsOneWidget);
    expect(find.text('1/1 liều đã uống'), findsOneWidget);

    // Tap today in the week strip -> back to today
    await tester.tap(find.text('${today.day}'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Tiến độ hôm nay'), findsOneWidget);
    expect(find.text('0/1 liều đã uống'), findsOneWidget);
  });
}
