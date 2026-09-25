import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/main.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/utang_service.dart';

/// Walks every tab and every More-hub destination on a phone and a tablet
/// with a realistic store seeded (stock in every state, sales, a customer on
/// tab) and fails on any exception, including layout overflows. A cheap net
/// for the class of bug where a screen nobody opened in the last change
/// stops rendering.
void main() {
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

  Future<void> smoke(WidgetTester tester, Size size) async {
    final svc = ProductService();
    final products = <Product>[];
    for (final (n, stock) in [('SkyFlakes', 40), ('Kopiko', 2), ('Coke', 0), ('Piattos', 12), ('Eggs', 30), ('Bear Brand', 9)]) {
      final id = await svc.insertProduct(Product(
          name: n, price: 10, stock: stock, minStock: 5, category: n == 'Eggs' ? 'Fresh' : 'Snacks',
          createdAt: DateTime.now().toIso8601String()));
      products.add((await svc.getAllProducts()).firstWhere((p) => p.id == id));
    }
    final sales = SalesService();
    for (var i = 0; i < 8; i++) {
      final p = products[i % products.length];
      if (p.stock <= 0) continue;
      await sales.recordSale(lines: [CartLine(product: p, qty: 1)], paymentMethod: i.isEven ? 'Cash' : 'GCash', cashReceived: 50);
    }
    final utang = UtangService();
    final c = await utang.addCustomer('Aling Nena', phone: '09171234567');
    await utang.charge(customerId: c, amount: 120);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const RestockApp());
    await tester.pump();
    await tester.pumpAndSettle();

    Future<void> tab(String label) async {
      await tester.tap(find.text(label).first);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'tab $label');
    }

    await tab('Home');
    await tab('Sell');
    await tab('Restock');
    await tab('Products');
    await tab('More');

    // Every hub destination opens and comes back.
    for (final item in ['Reports', 'Cash count', 'Shift history', 'Returns & voids', 'Utang', 'Settings']) {
      await tester.ensureVisible(find.text(item).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'open $item');
      final back = find.byIcon(Icons.arrow_back_ios_new_rounded);
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back.first);
      } else {
        await tester.pageBack();
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'close $item');
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'switch cashier');
  }

  testWidgets('phone: every tab and hub screen renders', (tester) => smoke(tester, const Size(390, 812)));
  testWidgets('tablet: every tab and hub screen renders', (tester) => smoke(tester, const Size(1180, 800)));
}
