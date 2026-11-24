import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thuoc_vui/main.dart';
import 'package:thuoc_vui/store.dart';
import 'package:thuoc_vui/strings.dart';

void main() {
  tearDown(() {
    Lang.current = AppLang.vi;
  });

  test('AppSettings defaults to Vietnamese and persists language code', () {
    expect(AppSettings().language, AppLang.vi);
    expect(AppSettings.fromJson(null).language, AppLang.vi);
    expect(AppSettings.fromJson({'language': 'unknown'}).language, AppLang.vi);

    final en = AppSettings(language: AppLang.en);
    expect(en.toJson()['language'], 'en');
    expect(AppSettings.fromJson(en.toJson()).language, AppLang.en);
  });

  testWidgets('Switching language in Settings updates UI, storage, and widget immediately',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final widgetData = <String, Object?>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('home_widget'),
        (call) async {
      if (call.method == 'saveWidgetData') {
        final args = call.arguments as Map;
        widgetData[args['id'] as String] = args['data'];
      }
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('home_widget'), null));

    final store = ThuocStore()..loaded = true;
    await tester.pumpWidget(ThuocVuiApp(store: store));
    await tester.tap(find.byTooltip('Cài đặt'));
    await tester.pumpAndSettle();

    expect(find.text('NGÔN NGỮ'), findsOneWidget);
    expect(find.text('Chế độ'), findsOneWidget);
    expect(find.byType(FlagIcon), findsNWidgets(2));

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(store.settings.language, AppLang.en);
    expect(Lang.current, AppLang.en);
    expect(find.text('LANGUAGE'), findsOneWidget);
    expect(find.text('DISPLAY & SOUND'), findsOneWidget);
    expect(find.text('Mode'), findsOneWidget);
    expect(widgetData['progress'], 'No medicines today');

    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('thuoc_vui_v1')!) as Map;
    expect(saved['settings']['language'], 'en');

    // Reloading a fresh store keeps English.
    Lang.current = AppLang.vi;
    final reloaded = ThuocStore();
    await reloaded.reload();
    expect(reloaded.settings.language, AppLang.en);
    expect(Lang.current, AppLang.en);

    // Switch back to Vietnamese.
    await tester.tap(find.text('Tiếng Việt'));
    await tester.pumpAndSettle();
    expect(store.settings.language, AppLang.vi);
    expect(find.text('NGÔN NGỮ'), findsOneWidget);
    expect(widgetData['progress'], 'Chưa có thuốc hôm nay');
  });
}
