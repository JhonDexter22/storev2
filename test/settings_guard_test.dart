import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/store_settings_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: StoreSettingsScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester, String title) async {
    await tester.scrollUntilVisible(find.text(title), 200);
    // Built is not the same as on screen: bring the row fully into view.
    await tester.ensureVisible(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  // Each replaces the whole store; a cashier used to be one dialog from it.
  group('store-wide changes ask for the manager first', () {
    testWidgets('clear all data', (tester) async {
      await pump(tester);
      await tapRow(tester, 'Clear all data');

      expect(find.text('Manager PIN'), findsOneWidget);
      expect(find.text('Clear all data?'), findsNothing);
    });

    // Cash count reads it when it counts: lowering it hid a short drawer.
    testWidgets('opening cash', (tester) async {
      await pump(tester);
      await tapRow(tester, 'Opening cash');
      expect(find.text('Manager PIN'), findsOneWidget);
    });

    testWidgets('restore from a backup', (tester) async {
      await pump(tester);
      await tapRow(tester, 'Restore from a backup');

      expect(find.text('Manager PIN'), findsOneWidget);
    });
  });

  group('default minimum stock', () {
    Finder field() => find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));

    testWidgets('says it is for new products', (tester) async {
      await pump(tester);
      await tester.scrollUntilVisible(find.textContaining('for new products'), 200);
      expect(find.textContaining('for new products'), findsOneWidget);
    });

    testWidgets('takes digits only, and says so when empty', (tester) async {
      await pump(tester);
      await tapRow(tester, 'Default minimum stock');
      await tester.enterText(field(), '-5');
      await tester.pump();
      expect(tester.widget<TextField>(field()).controller!.text, '5');

      await tester.enterText(field(), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number'), findsOneWidget);
    });

    testWidgets('can be applied to every product', (tester) async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('products');
      for (final n in ['Kopiko', 'Zesto']) {
        await ProductService().insertProduct(Product(
          name: n, stock: 20, minStock: 3, category: 'Drinks',
          createdAt: DateTime.now().toIso8601String(), price: 10));
      }
      await pump(tester);
      await tapRow(tester, 'Default minimum stock');
      await tester.enterText(field(), '8');
      await tester.tap(find.text('Also apply to every product'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final mins = (await ProductService().getAllProducts()).map((p) => p.minStock).toSet();
      expect(mins, {8});
      expect(SettingsService.instance.defaultMinStock, 8);
    });
  });

  testWidgets('a blank store name says so instead of closing', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a store name'), findsOneWidget);
  });

  testWidgets('the store card no longer names the cashier', (tester) async {
    await pump(tester);
    final settings = SettingsService.instance;
    expect(find.text(settings.terminal), findsOneWidget);
    expect(find.textContaining('Cashier'), findsNothing);
  });
}
