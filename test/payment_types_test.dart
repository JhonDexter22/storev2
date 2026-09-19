import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/payment_type.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/checkout_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  final settings = SettingsService.instance;
  final products = ProductService();
  final sales = SalesService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
    await DatabaseHelper.instance.clearAllData();
  });

  PaymentType typeNamed(String name) =>
      settings.allPaymentTypes.firstWhere((t) => t.name == name);

  Future<Product> addProduct({double price = 50}) async {
    final id = await products.insertProduct(Product(
      name: 'SkyFlakes',
      stock: 100,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    return Product(
      id: id,
      name: 'SkyFlakes',
      stock: 100,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    );
  }

  Future<void> pumpCheckout(WidgetTester tester, Product p) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: CheckoutScreen(lines: [CartLine(product: p, qty: 1)]),
    ));
    await tester.pumpAndSettle();
  }

  group('configuration', () {
    test('a fresh install offers exactly what was hardcoded before', () {
      expect(settings.paymentTypes.map((t) => t.name),
          ['Cash', 'GCash', 'Card', 'Utang']);
    });

    test('switching one off removes it from the offered list', () async {
      await settings.setPaymentTypeEnabled(typeNamed('Card'), false);
      expect(settings.paymentTypes.map((t) => t.name),
          ['Cash', 'GCash', 'Utang']);
      // Still listed in settings, so it can be turned back on.
      expect(settings.allPaymentTypes.map((t) => t.name), contains('Card'));
    });

    test('cash cannot be switched off', () async {
      final cash = typeNamed('Cash');
      expect(cash.canBeDisabled, isFalse);

      await settings.setPaymentTypeEnabled(cash, false);
      // A till that cannot take cash is not a till.
      expect(settings.paymentTypes.map((t) => t.name), contains('Cash'));
      expect(settings.isPaymentTypeEnabled(cash), isTrue);
    });

    test('a custom type is added and offered', () async {
      expect(await settings.addPaymentType('Maya'), isTrue);
      expect(settings.paymentTypes.map((t) => t.name), contains('Maya'));
      expect(settings.paymentTypes.last.kind, PaymentKind.plain);
    });

    test('a duplicate name is refused, whatever its case', () async {
      await settings.addPaymentType('Maya');
      expect(await settings.addPaymentType('maya'), isFalse);
      expect(await settings.addPaymentType('GCash'), isFalse);
      expect(await settings.addPaymentType('   '), isFalse);
      expect(settings.paymentTypes.where((t) => t.name == 'Maya'), hasLength(1));
    });

    test('a custom type can be deleted; a built-in one cannot', () async {
      await settings.addPaymentType('Maya');
      await settings.removePaymentType(typeNamed('Maya'));
      expect(settings.allPaymentTypes.map((t) => t.name), isNot(contains('Maya')));

      await settings.removePaymentType(typeNamed('Card'));
      expect(settings.allPaymentTypes.map((t) => t.name), contains('Card'));
    });

    test('re-adding a removed name comes back switched on', () async {
      await settings.addPaymentType('Maya');
      await settings.setPaymentTypeEnabled(typeNamed('Maya'), false);
      await settings.removePaymentType(typeNamed('Maya'));

      await settings.addPaymentType('Maya');
      expect(settings.paymentTypes.map((t) => t.name), contains('Maya'));
    });
  });

  group('checkout', () {
    testWidgets('offers only what is switched on', (tester) async {
      await settings.setPaymentTypeEnabled(typeNamed('Card'), false);
      final p = await addProduct();
      await pumpCheckout(tester, p);

      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('GCash'), findsOneWidget);
      expect(find.text('Utang'), findsOneWidget);
      // A store that never takes a card should not have a Card button in the
      // one place that has to be fast.
      expect(find.text('Card'), findsNothing);
    });

    testWidgets('a custom type is selectable and records its own name',
        (tester) async {
      await settings.addPaymentType('Maya');
      final p = await addProduct(price: 50);
      await pumpCheckout(tester, p);

      expect(find.text('Maya'), findsOneWidget);
      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Complete sale'));
      await tester.pumpAndSettle();

      final sale = (await sales.getRecentSales()).single;
      expect(sale.paymentMethod, 'Maya');
    });

    testWidgets('a custom type takes no cash and gives no change',
        (tester) async {
      await settings.addPaymentType('Maya');
      final p = await addProduct(price: 50);
      await pumpCheckout(tester, p);

      await tester.tap(find.text('Maya'));
      await tester.pumpAndSettle();
      // Only Cash tenders; everything else is just a name on the sale.
      expect(find.text('Cash received'), findsNothing);

      await tester.tap(find.textContaining('Complete sale'));
      await tester.pumpAndSettle();
      final sale = (await sales.getRecentSales()).single;
      expect(sale.changeAmount, 0);
    });

    testWidgets('cash still tenders and works out change', (tester) async {
      final p = await addProduct(price: 50);
      await pumpCheckout(tester, p);

      expect(find.text('Cash received'), findsOneWidget);
      await tester.tap(find.text('₱500'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Complete sale'));
      await tester.pumpAndSettle();

      final sale = (await sales.getRecentSales()).single;
      expect(sale.cashReceived, closeTo(500, 0.001));
      expect(sale.changeAmount, closeTo(450, 0.001));
    });
  });

  group('history is not rewritten', () {
    test('a sale keeps its method after that type is switched off', () async {
      final p = await addProduct(price: 50);
      await sales.recordSale(
          lines: [CartLine(product: p, qty: 1)], paymentMethod: 'Card');

      await settings.setPaymentTypeEnabled(typeNamed('Card'), false);

      // Disabling changes what is offered, never what was recorded — the
      // books have to survive a settings change.
      final sale = (await sales.getRecentSales()).single;
      expect(sale.paymentMethod, 'Card');
      final mix = await sales.paymentMix(1);
      expect(mix.single.label, 'Card');
    });

    test('a deleted custom type still appears in past sales', () async {
      await settings.addPaymentType('Maya');
      final p = await addProduct(price: 50);
      await sales.recordSale(
          lines: [CartLine(product: p, qty: 1)], paymentMethod: 'Maya');

      await settings.removePaymentType(typeNamed('Maya'));

      expect((await sales.getRecentSales()).single.paymentMethod, 'Maya');
    });
  });
}
