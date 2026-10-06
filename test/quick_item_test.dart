import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/pos_screen.dart';
import 'package:storev2/services/held_sales.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  final products = ProductService();
  final sales = SalesService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsService.instance.resetForTests();
    await SettingsService.instance.load();
    await DatabaseHelper.instance.clearAllData();
    HeldSales.instance.reset();
  });

  Future<Product> seed(String name, {int stock = 20, double price = 10}) async {
    final id = await products.insertProduct(Product(
      name: name,
      stock: stock,
      minStock: 5,
      category: 'Snacks',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    return (await products.getAllProducts()).firstWhere((p) => p.id == id);
  }

  group('saving', () {
    test('a quick item is a sale line of its own, and moves no stock', () async {
      final kopiko = await seed('Kopiko', stock: 20, price: 8);
      final sale = await sales.recordSale(lines: [
        CartLine(product: kopiko, qty: 1),
        CartLine(product: Product.quick(id: -1, name: 'Yelo', price: 5), qty: 2),
      ], paymentMethod: 'Cash', cashReceived: 20);

      expect(sale.total, 18);
      final items = await sales.getSaleItems(sale.id!);
      final yelo = items.singleWhere((i) => i.name == 'Yelo');
      expect(yelo.productId, -1);
      expect(yelo.unitPrice, 5);
      expect(yelo.qty, 2);
      expect((await products.getAllProducts()).single.stock, 19);
    });

    test('is never offered as a Popular tile', () async {
      final kopiko = await seed('Kopiko');
      await sales.recordSale(lines: [
        CartLine(product: Product.quick(id: -1, name: 'Yelo', price: 5), qty: 9),
        CartLine(product: kopiko, qty: 1),
      ], paymentMethod: 'Cash');
      expect(await sales.frequentProductIds(14), [kopiko.id]);
    });

    test('two on one receipt are returned one at a time', () async {
      final sale = await sales.recordSale(lines: [
        CartLine(product: Product.quick(id: -1, name: 'Yelo', price: 5), qty: 1),
        CartLine(product: Product.quick(id: -2, name: 'Load', price: 50), qty: 1),
      ], paymentMethod: 'Cash', cashReceived: 55);

      final refund = await sales.recordRefund(
        sale: sale,
        lines: {-2: 1},
        reason: 'Wrong number',
        method: 'Cash',
        restock: true,
        isVoid: false,
      );
      expect(refund.amount, 50);

      final left = await sales.getReturnableLines(sale.id!);
      expect(left.singleWhere((l) => l.item.name == 'Yelo').returnable, 1);
      expect(left.singleWhere((l) => l.item.name == 'Load').returnable, 0);
    });
  });

  group('held sales', () {
    test('keep a quick item\'s name and price', () {
      final held = HeldSale(
        id: 'a',
        heldAt: _at,
        lines: {3: 1, -1: 2},
        quick: {-1: (name: 'Yelo', price: 5.0)},
      );
      final back = HeldSale.fromJson(held.toJson());
      expect(back.lines, {3: 1, -1: 2});
      expect(back.quick[-1], (name: 'Yelo', price: 5.0));
    });

    test('held before quick items existed still load', () {
      final back = HeldSale.fromJson({
        'id': 'a',
        'heldAt': _at.toIso8601String(),
        'lines': {'3': 1},
      });
      expect(back.lines, {3: 1});
      expect(back.quick, isEmpty);
    });
  });

  group('at the till', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: PosScreen(key: UniqueKey())));
      await tester.pumpAndSettle();
    }

    Future<void> enterPrice(WidgetTester tester, String price) async {
      await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first, price);
      await tester.pump();
    }

    testWidgets('a search that finds nothing offers to sell it by price', (tester) async {
      await seed('Kopiko', price: 8);
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'yelo');
      await tester.pump();
      await tester.tap(find.text('Sell "yelo" as a quick item'));
      await tester.pumpAndSettle();

      // The search is the name, capitalised for the receipt; the button says\n      // what is still missing.
      expect(
          find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(TextField, 'Yelo')),
          findsOneWidget);
      expect(find.text('Enter a price'), findsOneWidget);

      await enterPrice(tester, '5');
      await tester.tap(find.byIcon(Icons.add_rounded).last);
      await tester.pump();
      await tester.tap(find.text('Add 2 · ₱10.00'));
      await tester.pumpAndSettle();

      expect(find.text('2 items'), findsOneWidget);
      expect(find.text('₱10.00'), findsOneWidget);
      // Back to the full grid for the next thing.
      expect(find.text('Kopiko'), findsOneWidget);
    });

    testWidgets('the chip rings one up with no search, under a plain name', (tester) async {
      await seed('Kopiko');
      await pump(tester);

      await tester.tap(find.text('Quick item'));
      await tester.pumpAndSettle();
      await enterPrice(tester, '12.50');
      await tester.tap(find.text('Add 1 · ₱12.50'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 item'));
      await tester.pumpAndSettle();
      expect(find.text('Quick item'), findsWidgets);
      expect(find.textContaining('₱12.50'), findsWidgets);
    });

    testWidgets('a search with results ends with a quick item tile', (tester) async {
      await seed('Candy Max');
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'candy');
      await tester.pump();
      expect(find.text('Candy Max'), findsOneWidget);
      expect(find.text('Sell "candy" by price'), findsOneWidget);
    });

    testWidgets('survives being held and brought back', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Quick item'));
      await tester.pumpAndSettle();
      await enterPrice(tester, '5');
      await tester.enterText(find.widgetWithText(TextField, 'Yelo, candy, load…'), 'Yelo');
      await tester.tap(find.text('Add 1 · ₱5.00'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hold'));
      await tester.pumpAndSettle();
      expect(find.text('1 item'), findsNothing);

      await tester.tap(find.text('Held'));
      await tester.pumpAndSettle();
      expect(find.text('₱5.00'), findsOneWidget); // the held row's total
      await tester.tap(find.text('Yelo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 item'));
      await tester.pumpAndSettle();
      expect(find.text('Yelo'), findsOneWidget);
    });

    testWidgets('goes through checkout and onto the sale', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Quick item'));
      await tester.pumpAndSettle();
      await enterPrice(tester, '20');
      await tester.enterText(find.widgetWithText(TextField, 'Yelo, candy, load…'), 'Load');
      await tester.tap(find.text('Add 1 · ₱20.00'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Complete sale'));
      await tester.pumpAndSettle();
      expect(find.text('1 × Load'), findsOneWidget);

      final sale = (await sales.getRecentSales(limit: 1)).single;
      expect(sale.items.single.name, 'Load');
      expect(sale.items.single.productId, isNegative);
    });
  });
}

final _at = DateTime(2026, 10, 4, 9);
