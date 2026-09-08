import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/reports_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  final sales = SalesService();
  final products = ProductService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    await DatabaseHelper.instance.clearAllData();
  });

  Future<Product> addProduct({double price = 50, int stock = 500}) async {
    final id = await products.insertProduct(Product(
      name: 'SkyFlakes',
      stock: stock,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    return Product(
      id: id,
      name: 'SkyFlakes',
      stock: stock,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ReportsScreen(key: UniqueKey())));
    await tester.pumpAndSettle();
  }

  /// A sale, then a refund larger than everything else the period took —
  /// which is what happens when an old, expensive sale is voided today.
  Future<void> seedRefundBiggerThanRevenue() async {
    final cheap = await addProduct(price: 9);
    await sales.recordSale(
        lines: [CartLine(product: cheap, qty: 2)], paymentMethod: 'Cash');

    final db = await DatabaseHelper.instance.database;
    final saleId = await db.insert('sales', {
      'reference': 'S20260101-0001',
      // Backdated well outside the window, so its revenue is not counted.
      'created_at':
          DateTime.now().subtract(const Duration(days: 200)).toIso8601String(),
      'subtotal': 999999.0,
      'total': 999999.0,
      'payment_method': 'Cash',
      'cash_received': 999999.0,
      'change_amount': 0,
      'item_count': 1,
    });
    await db.insert('refunds', {
      'sale_id': saleId,
      'sale_reference': 'S20260101-0001',
      'created_at': DateTime.now().toIso8601String(),
      'amount': 999999.0,
      'reason': 'Damaged',
      'method': 'Cash',
      'is_void': 1,
      'restocked': 1,
    });
  }

  group('the returns card', () {
    testWidgets('does not print a nonsense percentage', (tester) async {
      await seedRefundBiggerThanRevenue();
      await pump(tester);

      // Regression: this read "5555550.0% of revenue", which is arithmetically
      // right and useless to a shopkeeper.
      expect(find.textContaining('% of revenue'), findsNothing);
      expect(
        find.text('More than this range took in — some are returns of earlier sales'),
        findsOneWidget,
      );
    });

    testWidgets('an ordinary refund still shows its share', (tester) async {
      final p = await addProduct(price: 100);
      final sale = await sales.recordSale(
          lines: [CartLine(product: p, qty: 10)], paymentMethod: 'Cash');
      await sales.recordRefund(
        sale: sale,
        lines: {p.id!: 1},
        reason: 'Damaged',
        method: 'Cash',
        restock: true,
        isVoid: false,
      );

      await pump(tester);
      expect(find.text('10.0% of revenue'), findsOneWidget);
    });

    testWidgets('refunds with no sales in range say so', (tester) async {
      final db = await DatabaseHelper.instance.database;
      final saleId = await db.insert('sales', {
        'reference': 'S20260101-0002',
        'created_at':
            DateTime.now().subtract(const Duration(days: 200)).toIso8601String(),
        'subtotal': 500.0,
        'total': 500.0,
        'payment_method': 'Cash',
        'cash_received': 500.0,
        'change_amount': 0,
        'item_count': 1,
      });
      await db.insert('refunds', {
        'sale_id': saleId,
        'sale_reference': 'S20260101-0002',
        'created_at': DateTime.now().toIso8601String(),
        'amount': 500.0,
        'reason': 'Damaged',
        'method': 'Cash',
        'is_void': 1,
        'restocked': 1,
      });

      await pump(tester);
      // Dividing by zero revenue is the other way this used to go wrong.
      expect(
        find.text('Refunds only in this range — the sales were from earlier'),
        findsOneWidget,
      );
    });
  });

  group('large figures', () {
    testWidgets('a six-digit refund total is not truncated', (tester) async {
      await seedRefundBiggerThanRevenue();
      await pump(tester);

      // Ellipsis would render "-₱999,99…"; shrinking keeps the whole number.
      expect(find.text('-₱999,999.00'), findsWidgets);
      expect(find.textContaining('…'), findsNothing);
    });

    testWidgets('the three figures do not run into each other', (tester) async {
      await seedRefundBiggerThanRevenue();
      await pump(tester);

      // Each column shrinks its own figure to fit, which is not the same as
      // leaving room between them: without a gap this rendered as
      // "-P999,999.001", the refund total and the count read as one number.
      // Measured against the next column's label rather than its value: a
      // bare "1" appears in several places and the finder picked the wrong one.
      final refunded = tester.getRect(find.text('-₱999,999.00').first);
      final nextColumn = tester.getRect(find.text('Recorded'));
      expect(refunded.right, lessThan(nextColumn.left),
          reason: 'the refunded figure must end before the next column starts');
    });

    testWidgets('a large sale renders without overflowing', (tester) async {
      final p = await addProduct(price: 999999);
      await sales.recordSale(
          lines: [CartLine(product: p, qty: 2)], paymentMethod: 'Cash');

      // An overflow throws in a test, so simply arriving here is the assertion.
      await pump(tester);
      expect(find.text('Reports'), findsOneWidget);
    });
  });
}
