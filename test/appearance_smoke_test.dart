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
      expect(settings.appThemeMode, ThemeMode.system);
      expect(settings.toJson().containsKey('themeMode'), isFalse);
    }
    expect(AppSettings.fromJson({'appThemeMode': 'invalid'}).appThemeMode,
        ThemeMode.system);
    for (final palette in HomePalette.values) {
      final theme = palette.themeWithCustomColor(Colors.pink);
      expect(theme.brightness, Brightness.light);
      expect(theme.cardTheme.elevation, 0);
      expect(theme.scaffoldBackgroundColor, Color(palette.background));
      final darkTheme = palette.darkThemeWithCustomColor(Colors.pink);
      expect(darkTheme.brightness, Brightness.dark);
      expect(
        darkTheme.colorScheme.primary,
        palette == HomePalette.light
            ? const Color(0xFF2DD4BF)
            : theme.colorScheme.primary,
      );
      expect(darkTheme.scaffoldBackgroundColor, const Color(0xFF0B1117));
      expect(darkTheme.cardTheme.color, const Color(0xFF131C26));
    }
  });

  testWidgets('App theme segments save and apply appearance independently',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const widgetChannel = MethodChannel('home_widget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final widgetCalls = <MethodCall>[];
    messenger.setMockMethodCallHandler(widgetChannel, (call) async {
      widgetCalls.add(call);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(widgetChannel, null));
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    final store = ThuocStore()..loaded = true;
    await tester.pumpWidget(ThuocVuiApp(store: store));
    await tester.tap(find.byTooltip('Cài đặt'));
    await tester.pumpAndSettle();

    final appCard =
        find.ancestor(of: find.text('Chế độ'), matching: find.byType(Card));
    final systemChip = find.descendant(
      of: appCard,
      matching: find.widgetWithText(TextButton, 'Theo điện thoại'),
    );
    expect(_isSelected(tester, systemChip), isTrue);
    expect(Theme.of(tester.element(systemChip)).brightness, Brightness.dark);
    final prefs = await SharedPreferences.getInstance();

    for (final (label, mode, brightness) in [
      ('Sáng', ThemeMode.light, Brightness.light),
      ('Tối', ThemeMode.dark, Brightness.dark),
      ('Theo điện thoại', ThemeMode.system, Brightness.dark),
    ]) {
      final chip = find.descendant(
        of: appCard,
        matching: find.widgetWithText(TextButton, label),
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(_isSelected(tester, chip), isTrue);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, mode);
      expect(Theme.of(tester.element(chip)).brightness, brightness);
      final saved = jsonDecode(prefs.getString('thuoc_vui_v1')!) as Map;
      expect(saved['settings']['appThemeMode'], mode.name);
      final restored = AppSettings.fromJson(
          Map<String, dynamic>.from(saved['settings'] as Map));
      expect(restored.appThemeMode, mode);
      expect(restored.widgetThemeMode, WidgetThemeMode.system);
      expect(widgetCalls, isEmpty);
    }

    dispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(systemChip)).brightness, Brightness.light);
  });

  testWidgets('Palette and Custom color update the app, storage and widget',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final widgetData = <String, Object?>{};
    final widgetUpdates = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'),
            (call) async {
      if (call.method == 'saveWidgetData') {
        final args = call.arguments as Map;
        widgetData[args['id'] as String] = args['data'];
      } else if (call.method == 'updateWidget') {
        widgetUpdates.add(widgetData['widget_theme']);
      }
      return true;
    });

    final store = ThuocStore()..loaded = true;
    await tester.pumpWidget(ThuocVuiApp(store: store));
    await tester.tap(find.byTooltip('Cài đặt'));
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

    final widgetHeading = find.text('Giao diện widget');
    await tester.scrollUntilVisible(widgetHeading, 200);
    final widgetCard =
        find.ancestor(of: widgetHeading, matching: find.byType(Card));
    final systemChip = find.descendant(
      of: widgetCard,
      matching: find.widgetWithText(TextButton, 'Theo điện thoại'),
    );
    await tester.ensureVisible(systemChip);
    expect(_isSelected(tester, systemChip), isTrue);
    expect(widgetData['widget_theme'], 'system');
    for (final (label, mode) in [
      ('Sáng', WidgetThemeMode.light),
      ('Tối', WidgetThemeMode.dark),
      ('Theo điện thoại', WidgetThemeMode.system),
    ]) {
      final chip = find.descendant(
        of: widgetCard,
        matching: find.widgetWithText(TextButton, label),
      );
      await tester.ensureVisible(chip);
      final previousUpdates = widgetUpdates.length;
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(_isSelected(tester, chip), isTrue);
      expect(store.settings.widgetThemeMode, mode);
      final saved = jsonDecode(prefs.getString('thuoc_vui_v1')!) as Map;
      expect(saved['settings']['widgetThemeMode'], mode.name);
      expect(widgetData['widget_theme'], mode.name);
      expect(widgetUpdates.skip(previousUpdates), [mode.name]);
      expect(widgetData['widget_accent'], '#9A492B');
      expect(
          tester
              .widget<MaterialApp>(find.byType(MaterialApp))
              .theme!
              .brightness,
          Brightness.light);
    }

    await tester.scrollUntilVisible(find.textContaining('1.2.49+52'), 400);
    await tester.ensureVisible(find.textContaining('1.2.49+52'));
    expect(find.textContaining('1.2.49+52'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

bool? _isSelected(WidgetTester tester, Finder button) {
  final child = tester.widget<TextButton>(button).child as Semantics;
  return child.properties.selected;
}
