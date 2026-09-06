import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/discount.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/checkout_screen.dart';
import 'package:storev2/screens/returns_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/widgets/discount_sheet.dart';

void main() {
  final sales = SalesService();
  final products = ProductService();

  setUpAll(() {
    sqfliteFfiInit();
    // No-isolate, so a query finishes on the microtask queue the tester
    // already drains — see tablet_layout_test for the full reasoning.
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    final db = await DatabaseHelper.instance.database;
    for (final t in ['refund_items', 'refunds', 'sale_items', 'sales', 'products']) {
      await db.delete(t);
    }
  });

  Future<Product> addProduct({String name = 'SkyFlakes', double price = 50}) async {
    final id = await products.insertProduct(Product(
      name: name,
      stock: 100,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    return Product(
      id: id,
      name: name,
      stock: 100,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    );
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  group('checkout', () {
    testWidgets('applying a preset updates every figure on the screen',
        (tester) async {
      final p = await addProduct(price: 50);
      await pump(tester, CheckoutScreen(lines: [CartLine(product: p, qty: 2)]));

      expect(find.text('Add a discount'), findsOneWidget);
      expect(find.textContaining('Complete sale'), findsOneWidget);

      await tester.tap(find.text('Add a discount'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Senior citizen'));
      await tester.pumpAndSettle();

      // Subtotal, the discount line and the amount due all have to move
      // together, and so does the button the cashier actually presses.
      expect(find.text('Subtotal'), findsOneWidget);
      // Twice over: the line total and the subtotal row, which agree.
      expect(find.text('₱100.00'), findsNWidgets(2));
      expect(find.text('Senior citizen · 20%'), findsOneWidget);
      expect(find.text('−₱20.00'), findsOneWidget);
      expect(find.text('₱80.00'), findsOneWidget);
      expect(find.text('Complete sale · ₱80.00'), findsOneWidget);
    });

    testWidgets('removing it puts the full price back', (tester) async {
      final p = await addProduct(price: 50);
      await pump(tester, CheckoutScreen(lines: [CartLine(product: p, qty: 2)]));

      await tester.tap(find.text('Add a discount'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suki'));
      await tester.pumpAndSettle();
      expect(find.text('Complete sale · ₱95.00'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Add a discount'), findsOneWidget);
      expect(find.text('Subtotal'), findsNothing);
      expect(find.text('Complete sale · ₱100.00'), findsOneWidget);
    });

    testWidgets('a discount with no reason is refused', (tester) async {
      final p = await addProduct(price: 50);
      await pump(tester, CheckoutScreen(lines: [CartLine(product: p, qty: 2)]));

      await tester.tap(find.text('Add a discount'));
      await tester.pumpAndSettle();
      // Scoped to the sheet: the checkout behind it has a cash field of its
      // own, and an unscoped finder types into that instead.
      await tester.enterText(
        find
            .descendant(
                of: find.byType(DiscountSheet), matching: find.byType(TextField))
            .first,
        '10',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply discount'));
      await tester.pumpAndSettle();

      // Without a reason a discount is just money leaving the till.
      expect(find.text('Say what the discount is for.'), findsOneWidget);
      expect(find.byType(DiscountSheet), findsOneWidget,
          reason: 'the sheet stays open so the reason can be typed');
    });
  });

  group('the receipt', () {
    testWidgets('itemises a discount so the customer can show it',
        (tester) async {
      final p = await addProduct(price: 50);
      await pump(tester, CheckoutScreen(lines: [CartLine(product: p, qty: 2)]));

      await tester.tap(find.text('Add a discount'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Senior citizen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Complete sale'));
      await tester.pumpAndSettle();

      // The receipt view is what a customer is handed, so the discount has to
      // be on it, not just folded into a smaller total.
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Senior citizen · 20%'), findsOneWidget);
      expect(find.text('-₱20.00'), findsOneWidget);
      expect(find.text('₱80.00'), findsWidgets);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('an undiscounted sale shows no discount rows', (tester) async {
      final p = await addProduct(price: 50);
      await pump(tester, CheckoutScreen(lines: [CartLine(product: p, qty: 2)]));

      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Complete sale'));
      await tester.pumpAndSettle();

      expect(find.text('Payment successful'), findsOneWidget);
      expect(find.text('Subtotal'), findsNothing);
    });
  });

  group('returns', () {
    testWidgets('quotes what the customer paid, not the shelf price',
        (tester) async {
      final p = await addProduct(price: 50);
      await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
        discount: const Discount(
            kind: DiscountKind.percent, value: 20, reason: 'Senior citizen'),
      );

      await pump(tester, const ReturnsScreen());
      await tester.tap(find.text('Return items').first);
      await tester.pumpAndSettle();

      // Regression: this row quoted the undiscounted ₱50.00 while the refund
      // would have paid ₱40.00 — the screen and the money disagreeing.
      expect(find.textContaining('₱40.00'), findsWidgets);
      expect(find.textContaining('₱50.00'), findsNothing);
    });

    testWidgets('an undiscounted sale still quotes the full price',
        (tester) async {
      final p = await addProduct(price: 50);
      await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
      );

      await pump(tester, const ReturnsScreen());
      await tester.tap(find.text('Return items').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('₱50.00'), findsWidgets);
    });
  });
}
