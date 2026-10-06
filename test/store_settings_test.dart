import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/design_tokens.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/screens/store_settings_screen.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsService.instance.resetForTests();
    await SettingsService.instance.load();
  });

  // Tall enough that every row is built, so their order can be read off.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: StoreSettingsScreen()));
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

  testWidgets('printing has its own group, the printer before the switch that needs it', (tester) async {
    await pump(tester);
    expect(find.text('RECEIPTS'), findsOneWidget);
    expect(y(tester, 'Receipt printer'), lessThan(y(tester, 'Print receipt')));
    // The money settings and the scanner's beep sit together under their own heading.
    expect(find.text('AT THE TILL'), findsOneWidget);
    for (final row in ['Payment types', 'Opening cash', 'Credit limit', 'Scan sound']) {
      expect(y(tester, row), greaterThan(y(tester, 'AT THE TILL')), reason: row);
      expect(y(tester, row), lessThan(y(tester, 'INVENTORY')), reason: row);
    }
  });

  testWidgets('Export comes before the reminder switch', (tester) async {
    await pump(tester);
    expect(y(tester, 'Export a backup'), lessThan(y(tester, 'Restore from a backup')));
    expect(y(tester, 'Restore from a backup'), lessThan(y(tester, 'Remind me to back up')));
  });

  testWidgets('a store never backed up says so in amber', (tester) async {
    await pump(tester);
    final label = tester.widget<Text>(find.text('Last export: never'));
    expect(label.style!.color, AppColors.warningText);
  });

  testWidgets('a backup from today is plain grey', (tester) async {
    await SettingsService.instance.markBackedUp();
    await pump(tester);
    final label = tester.widget<Text>(find.textContaining('Last export: '));
    expect(label.style!.color, isNot(AppColors.warningText));
  });
}
