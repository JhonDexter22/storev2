import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/design_tokens.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/models/sale_model.dart';
import 'package:storev2/screens/returns_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/shift_service.dart';
import 'package:storev2/services/utang_service.dart';

void main() {
  final products = ProductService();
  final sales = SalesService();
  final utang = UtangService();

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
  });

  Future<Sale> sell(String name, {double price = 100, String method = 'Cash'}) async {
    final id = await products.insertProduct(Product(
      name: name,
      stock: 10,
      minStock: 1,
      category: 'Snacks',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    final p = (await products.getAllProducts()).firstWhere((x) => x.id == id);
    return sales.recordSale(lines: [CartLine(product: p, qty: 1)], paymentMethod: method);
  }

  /// A sale put on Aling Nena's tab, the way checkout does it.
  Future<({Sale sale, int customer})> sellOnTab(double price) async {
    final customer = await utang.addCustomer('Aling Nena');
    final sale = await sell('Kopiko', price: price, method: 'Utang');
    await utang.charge(customerId: customer, amount: price, saleId: sale.id, note: sale.reference);
    return (sale: sale, customer: customer);
  }

  Future<double> balanceOf(int id) async =>
      (await utang.getCustomers()).firstWhere((c) => c.id == id).balance;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ReturnsScreen()));
    await tester.pumpAndSettle();
  }

  group('a sale that went on a tab', () {
    test('comes off the tab when returned, and no cash leaves the drawer', () async {
      final tab = await sellOnTab(300);
      final items = await sales.getSaleItems(tab.sale.id!);

      final refund = await sales.recordRefund(
        sale: tab.sale,
        lines: {items.single.productId: 1},
        reason: 'Damaged',
        method: 'Cash', // what the screen used to default to
        restock: true,
        isVoid: true,
      );

      expect(refund.method, 'Utang');
      expect(await balanceOf(tab.customer), 0);
      final drawer = await ShiftService().drawerNow();
      expect(drawer.cashSales, 0, reason: 'nothing was paid in, so nothing goes out');
    });

    test('a return does not count as money collected', () async {
      final tab = await sellOnTab(300);
      final items = await sales.getSaleItems(tab.sale.id!);
      await sales.recordRefund(
        sale: tab.sale,
        lines: {items.single.productId: 1},
        reason: 'Damaged',
        method: 'Utang',
        restock: true,
        isVoid: true,
      );
      expect((await utang.collectedToday()).amount, 0);
    });

    testWidgets('offers only "Take off their tab"', (tester) async {
      await sellOnTab(300);
      await pump(tester);
      await tester.tap(find.text('Kopiko'));
      await tester.pumpAndSettle();
      expect(find.text('Take off their tab'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
    });
  });

  testWidgets('the refund defaults to how the sale was paid', (tester) async {
    await sell('Kopiko', method: 'GCash');
    await pump(tester);
    await tester.tap(find.text('Kopiko'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Void all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review refund'));
    await tester.pumpAndSettle();
    expect(find.textContaining('refunded by GCash'), findsOneWidget);
  });

  testWidgets('a cash refund asks for the manager', (tester) async {
    await sell('Kopiko');
    await pump(tester);
    await tester.tap(find.text('Kopiko'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Void all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Void sale'));
    await tester.pumpAndSettle();

    expect(find.text('Manager PIN'), findsOneWidget);
    expect(find.text('Sale voided'), findsNothing);
  });

  group('finding the sale', () {
    testWidgets('by item name', (tester) async {
      await sell('Kopiko');
      await sell('Zesto');
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'zest');
      await tester.pumpAndSettle();
      expect(find.text('Zesto'), findsOneWidget);
      expect(find.text('Kopiko'), findsNothing);
    });

    testWidgets('older than the first twenty', (tester) async {
      for (var i = 0; i < 25; i++) {
        await sell('Item $i');
      }
      await pump(tester);
      expect(find.text('Item 0'), findsNothing);
      final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text('Show older'), 400, scrollable: list);
      await tester.tap(find.text('Show older'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Item 0'), 400, scrollable: list);
      expect(find.text('Item 0'), findsOneWidget);
    });
  });

  testWidgets('a returned sale says so, and no card carries a Void button', (tester) async {
    final sale = await sell('Kopiko');
    final items = await sales.getSaleItems(sale.id!);
    await sales.recordRefund(
      sale: sale,
      lines: {items.single.productId: 1},
      reason: 'Damaged',
      method: 'GCash',
      restock: true,
      isVoid: true,
    );
    await pump(tester);
    expect(find.text('Returned'), findsOneWidget);
    expect(find.text('Void whole sale'), findsNothing);
  });

  group('saying which sale', () {
    testWidgets('the list puts each sale under its day', (tester) async {
      final old = await sell('Kopiko');
      await sell('SkyFlakes');
      final db = await DatabaseHelper.instance.database;
      await db.update('sales', {'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String()},
          where: 'id = ?', whereArgs: [old.id]);
      await pump(tester);

      // Newest first: today's sale, then yesterday's under its own heading.
      final today = tester.getTopLeft(find.text('TODAY')).dy;
      final yesterday = tester.getTopLeft(find.text('YESTERDAY')).dy;
      expect(today, lessThan(tester.getTopLeft(find.text('SkyFlakes')).dy));
      expect(yesterday, greaterThan(tester.getTopLeft(find.text('SkyFlakes')).dy));
      expect(yesterday, lessThan(tester.getTopLeft(find.text('Kopiko')).dy));
    });

    test('sales come newest first by time, whatever their receipt number', () async {
      await sell('Kopiko');
      final later = await sell('SkyFlakes');
      // A clock put right after the fact: the higher receipt number is older.
      final db = await DatabaseHelper.instance.database;
      await db.update('sales', {'created_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String()},
          where: 'id = ?', whereArgs: [later.id]);
      final found = await sales.findSales();
      expect(found.map((s) => s.items.single.name), ['Kopiko', 'SkyFlakes']);
    });

    testWidgets('the return page says when and how it was paid', (tester) async {
      await sell('Kopiko', method: 'GCash');
      await pump(tester);
      await tester.tap(find.text('Kopiko'));
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp(r'^Today · .* · GCash · #')), findsOneWidget);
    });

    testWidgets('until something is picked, the button says so and ₱0.00 is not red', (tester) async {
      await sell('Kopiko');
      await pump(tester);
      await tester.tap(find.text('Kopiko'));
      await tester.pumpAndSettle();

      expect(find.text('Pick what came back'), findsOneWidget);
      expect(tester.widget<Text>(find.text('₱0.00')).style!.color, isNot(AppColors.dangerText));

      await tester.tap(find.text('Void all'));
      await tester.pumpAndSettle();
      expect(find.text('Review refund'), findsOneWidget);
    });
  });
}
