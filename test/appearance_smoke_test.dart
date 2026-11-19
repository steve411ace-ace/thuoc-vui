import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thuoc_vui/home_style.dart';
import 'package:thuoc_vui/main.dart';
import 'package:thuoc_vui/store.dart';

void main() {
  test('Legacy theme values resolve to the default light palette', () {
    for (final legacy in ['system', 'dark', 'light', 42, null]) {
      final settings = AppSettings.fromJson({'themeMode': legacy});
      expect(settings.palette, HomePalette.light);
      expect(settings.toJson().containsKey('themeMode'), isFalse);
    }
    for (final palette in HomePalette.values) {
      final theme = palette.themeWithCustomColor(Colors.pink);
      expect(theme.brightness, Brightness.light);
      expect(theme.cardTheme.elevation, 1);
      expect(theme.scaffoldBackgroundColor, Color(palette.background));
    }
  });

  testWidgets('Palette and Custom color update the app, storage and widget',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final widgetData = <String, Object?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'),
            (call) async {
      if (call.method == 'saveWidgetData') {
        final args = call.arguments as Map;
        widgetData[args['id'] as String] = args['data'];
      }
      return true;
    });

    final store = ThuocStore()..loaded = true;
    await tester.pumpWidget(ThuocVuiApp(store: store));
    await tester.tap(find.text('Cài đặt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ocean'));
    await tester.pumpAndSettle();
    expect(store.settings.palette, HomePalette.ocean);
    expect(widgetData['widget_accent'], '#175A8C');

    await tester.ensureVisible(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Warm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.colorScheme.primary, const Color(0xFF9A492B));
    expect(widgetData['widget_accent'], '#9A492B');
    final prefs = await SharedPreferences.getInstance();
    final persisted = jsonDecode(prefs.getString('thuoc_vui_v1')!) as Map;
    final restored = AppSettings.fromJson(
        Map<String, dynamic>.from(persisted['settings'] as Map));
    expect(restored.palette, HomePalette.custom);
    expect(restored.customColor, const Color(0xFF9A492B));

    await tester.scrollUntilVisible(find.textContaining('1.2.41+44'), 400);
    await tester.ensureVisible(find.textContaining('1.2.41+44'));
    expect(find.textContaining('1.2.41+44'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
