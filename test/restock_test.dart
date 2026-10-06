import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/l10n/tr.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/restock_screen.dart';
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

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: RestockScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> openSheetFor(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  group('the add-stock sheet', () {
    testWidgets('+12 means 12, not 12 on top of the suggestion', (tester) async {
      await seed('Kopiko', stock: 0);
      await pump(tester);
      await openSheetFor(tester, 'Kopiko');

      await tester.tap(find.text('+12'));
      await tester.pump();
      expect(find.text('Add 12'), findsOneWidget);
    });

    testWidgets('the suggestion is one tap, and sets rather than adds', (tester) async {
      await seed('Kopiko', stock: 0); // suggested: twice the minimum, 20
      await pump(tester);
      await openSheetFor(tester, 'Kopiko');

      await tester.tap(find.text('Suggested +20'));
      await tester.pump();
      await tester.tap(find.text('Suggested +20'));
      await tester.pump();
      expect(find.text('Add 20'), findsOneWidget);
    });
  });

  testWidgets('a restock can be undone', (tester) async {
    final id = await seed('Kopiko', stock: 0);
    await pump(tester);
    await openSheetFor(tester, 'Kopiko');
    await tester.tap(find.text('+24'));
    await tester.pump();
    await tester.tap(find.text('Add 24'));
    await tester.pumpAndSettle();

    expect(await stockOf(id), 24);
    expect(find.text('Added 24 · Kopiko now 24'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await stockOf(id), 0);
  });

  testWidgets('out of stock is a compact row, not a card with its own button',
      (tester) async {
    for (var i = 0; i < 6; i++) {
      await seed('Out $i', stock: 0);
    }
    await seed('Nearly gone', stock: 2);
    await pump(tester);

    expect(find.text('Restock now'), findsNothing);
    // Six out-of-stock rows no longer push running-low off the first screen.
    expect(find.text('Nearly gone').hitTestable(), findsOneWidget);
  });

  testWidgets('the nearest to empty comes first', (tester) async {
    await seed('Half left', stock: 10); // 50% of the healthy level
    await seed('Almost out', stock: 1); // 5%
    await seed('Getting low', stock: 6); // 30%
    await pump(tester);

    final top = [
      tester.getTopLeft(find.text('Almost out')).dy,
      tester.getTopLeft(find.text('Getting low')).dy,
      tester.getTopLeft(find.text('Half left')).dy,
    ];
    expect(top, orderedEquals([...top]..sort()));
  });

  testWidgets('the third tile is the shopping list, not a sum of units', (tester) async {
    await seed('Kopiko', stock: 0);
    await seed('Zesto', stock: 2);
    await pump(tester);
    expect(find.text('Shopping list'), findsOneWidget);
    expect(find.text('Units to order'), findsNothing);
  });

  test('the shared list goes by category, out of stock first', () {
    Product p(String name, String category, int stock, {int min = 10}) => Product(
        name: name, stock: stock, minStock: min, category: category, createdAt: '', price: 10);
    final text = restockListText(
      store: 'Jhed',
      date: DateTime(2026, 10, 2),
      items: [
        p('Pancit canton', 'Noodles', 3),
        p('Cola', 'Drinks', 4),
        p('Kopiko', 'Drinks', 0),
      ],
      suggested: (x) => x.minStock * 2 - x.stock,
    );
    expect(
      text,
      [
        'Jhed · Restock list · ${trDay(DateTime(2026, 10, 2))}',
        '',
        'DRINKS',
        'Kopiko — 20 (out)',
        'Cola — 16',
        '',
        'NOODLES',
        'Pancit canton — 17',
      ].join('\n'),
    );
  });
}
