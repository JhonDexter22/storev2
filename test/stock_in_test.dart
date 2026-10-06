import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/restock_screen.dart';
import 'package:storev2/screens/stock_in_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  final products = ProductService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    final db = await DatabaseHelper.instance.database;
    await db.delete('products');
  });

  // Minimum 10: suggestions land at twice that.
  Future<int> seed(String name, {required int stock, int minStock = 10}) =>
      products.insertProduct(Product(
        name: name,
        stock: stock,
        minStock: minStock,
        category: 'Snacks',
        createdAt: DateTime.now().toIso8601String(),
        price: 10,
      ));

  Future<int> stockOf(int id) async =>
      (await products.getAllProducts()).firstWhere((p) => p.id == id).stock;

  Future<void> pumpRestock(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: RestockScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> openStockIn(WidgetTester tester) async {
    await pumpRestock(tester);
    await tester.tap(find.text('Stock in'));
    await tester.pumpAndSettle();
  }

  Finder boxFor(String name) => find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(Row)).first,
        matching: find.byType(TextField),
      );

  test('a batch adds to every product at once, and takes it back', () async {
    final a = await seed('Kopiko', stock: 3);
    final b = await seed('Piattos', stock: 0);
    await products.addStockBatch({a: 12, b: 24});
    expect(await stockOf(a), 15);
    expect(await stockOf(b), 24);
    await products.addStockBatch({a: -12, b: -24});
    expect(await stockOf(a), 3);
    expect(await stockOf(b), 0);
  });

  group('Restock', () {
    testWidgets('says how many to buy, not "+7"', (tester) async {
      await seed('Kopiko', stock: 3);
      await pumpRestock(tester);
      expect(find.text('Buy 17'), findsOneWidget);
      expect(find.text('+17'), findsNothing);
    });

    testWidgets('the add-stock button says what is missing', (tester) async {
      await seed('Kopiko', stock: 3);
      await pumpRestock(tester);
      await tester.tap(find.text('Kopiko'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount'), findsOneWidget);
      await tester.tap(find.text('+5'));
      await tester.pump();
      expect(find.text('Add 5'), findsOneWidget);
    });
  });

  group('Stock in', () {
    testWidgets('opens with the restock list, boxes empty, suggestions greyed', (tester) async {
      await seed('Kopiko', stock: 3);
      await seed('Piattos', stock: 0);
      await seed('SkyFlakes', stock: 50);
      await openStockIn(tester);

      expect(find.text('Kopiko'), findsOneWidget);
      expect(find.text('Piattos'), findsOneWidget);
      expect(find.text('SkyFlakes'), findsNothing);
      final kopiko = tester.widget<TextField>(boxFor('Kopiko'));
      expect(kopiko.controller!.text, isEmpty);
      expect(kopiko.decoration!.hintText, '17');
      expect(find.text('Enter an amount'), findsOneWidget);
    });

    testWidgets('saves only the rows filled in, with one Undo for the lot', (tester) async {
      final kopiko = await seed('Kopiko', stock: 3);
      final piattos = await seed('Piattos', stock: 0);
      await openStockIn(tester);

      await tester.enterText(boxFor('Kopiko'), '24');
      await tester.pump();
      expect(find.text('Add 24 to 1 product'), findsOneWidget);
      await tester.tap(find.text('Add 24 to 1 product'));
      await tester.pumpAndSettle();

      expect(await stockOf(kopiko), 27);
      expect(await stockOf(piattos), 0); // not bought, not touched
      expect(find.text('Added 24 to 1 product'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await stockOf(kopiko), 3);
    });

    testWidgets('"Fill in suggested" fills every empty box', (tester) async {
      final kopiko = await seed('Kopiko', stock: 3);
      final piattos = await seed('Piattos', stock: 0);
      await openStockIn(tester);

      await tester.tap(find.text('Fill in suggested amounts'));
      await tester.pump();
      await tester.tap(find.text('Add 37 to 2 products'));
      await tester.pumpAndSettle();
      expect(await stockOf(kopiko), 20);
      expect(await stockOf(piattos), 20);
    });

    testWidgets('anything else bought is a search away', (tester) async {
      await seed('Kopiko', stock: 3);
      final sky = await seed('SkyFlakes', stock: 50);
      await openStockIn(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Add another product'), 'sky');
      await tester.pump();
      await tester.tap(find.text('SkyFlakes'));
      await tester.pumpAndSettle();

      await tester.enterText(boxFor('SkyFlakes'), '6');
      await tester.pump();
      await tester.tap(find.text('Add 6 to 1 product'));
      await tester.pumpAndSettle();
      expect(await stockOf(sky), 56);
    });

    testWidgets('leaving with amounts typed asks first', (tester) async {
      final kopiko = await seed('Kopiko', stock: 3);
      await openStockIn(tester);
      await tester.enterText(boxFor('Kopiko'), '5');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(StockInScreen), findsNothing);
      expect(await stockOf(kopiko), 3);
    });
  });
}
