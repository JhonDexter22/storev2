import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/design_tokens.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/l10n/tr.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/reports_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/utang_service.dart';
import 'package:storev2/widgets/sales_chart.dart';

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
  });

  Future<void> sell(String name, double price) async {
    final id = await products.insertProduct(Product(
      name: name,
      stock: 10,
      minStock: 1,
      category: 'Snacks',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    final p = (await products.getAllProducts()).firstWhere((x) => x.id == id);
    await sales.recordSale(lines: [CartLine(product: p, qty: 1)], paymentMethod: 'Cash');
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty range says so instead of a zero headline', (tester) async {
    await pump(tester);
    expect(find.text('No sales yet today'), findsOneWidget);
    expect(find.text('REVENUE'), findsNothing);
  });

  testWidgets('no comparison badge on a first day', (tester) async {
    await sell('Kopiko', 12);
    await pump(tester);
    expect(find.text('REVENUE'), findsOneWidget);
    // (The payment mix shows "100%" for Cash; the badge is what must not.)
    expect(find.textContaining('vs yesterday'), findsNothing);
    expect(find.textContaining('+100%'), findsNothing);
  });

  testWidgets('30 days charts 30 days, with the same chart Home uses', (tester) async {
    await sell('Kopiko', 12);
    await pump(tester);
    expect(find.byType(SalesBarChart), findsOneWidget);

    await tester.tap(find.text('30 days'));
    await tester.pumpAndSettle();
    final first = DateTime.now().subtract(const Duration(days: 29));
    expect(find.text(trDay(first)), findsOneWidget);
  });

  testWidgets('changing the range keeps the report on screen', (tester) async {
    await sell('Kopiko', 12);
    await pump(tester);
    await tester.tap(find.text('7 days'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Top products'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('offers Share, not a full-store Export', (tester) async {
    await pump(tester);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Export'), findsNothing);
  });

  test('credit flows count a tab return against the book', () async {
    final utang = UtangService();
    final customer = await utang.addCustomer('Aling Nena');
    await sell('Kopiko', 300);
    final sale = (await sales.getRecentSales(limit: 1)).single;
    await utang.charge(customerId: customer, amount: 300, saleId: sale.id);
    final db = await DatabaseHelper.instance.database;
    await db.insert('utang_entries', {
      'customer_id': customer,
      'sale_id': sale.id,
      'created_at': DateTime.now().toIso8601String(),
      'amount': -300.0,
      'kind': 'return',
    });

    final flows = await utang.getFlows(1);
    expect(flows.charged, 300);
    expect(flows.returned, 300);
    expect(flows.net, 0, reason: 'charged and returned the same day: the book did not grow');
  });

  test('sales are grouped by the hour they were rung up', () async {
    for (var i = 0; i < 3; i++) {
      await sell('Item $i', 10);
    }
    final db = await DatabaseHelper.instance.database;
    final ids = (await db.query('sales', columns: ['id'], orderBy: 'id')).map((r) => r['id']).toList();
    final today = DateTime.now();
    DateTime at(int h, int m) => DateTime(today.year, today.month, today.day, h, m);
    await db.update('sales', {'created_at': at(9, 15).toIso8601String()}, where: 'id = ?', whereArgs: [ids[0]]);
    await db.update('sales', {'created_at': at(17, 5).toIso8601String()}, where: 'id = ?', whereArgs: [ids[1]]);
    await db.update('sales', {'created_at': at(17, 50).toIso8601String()}, where: 'id = ?', whereArgs: [ids[2]]);

    final hours = await sales.salesByHour(1);
    expect(hours.length, 24);
    expect(hours[9].count, 1);
    expect(hours[17].count, 2);
    expect(hours[17].revenue, 20);
    expect(hours[12].count, 0);
  });

  test('not selling: stock that sat still, most money first', () async {
    await sell('Kopiko', 12); // sold
    for (final (name, stock, price) in [('Corned beef', 12, 45.0), ('Candle', 3, 5.0), ('Empty', 0, 99.0)]) {
      await products.insertProduct(Product(
        name: name,
        stock: stock,
        minStock: 1,
        category: 'Canned goods',
        createdAt: DateTime.now().toIso8601String(),
        price: price,
      ));
    }
    final idle = await sales.notSelling(7);
    expect(idle.items.map((p) => p.name), ['Corned beef', 'Candle'],
        reason: 'nothing on the shelf is not "not selling"');
    expect(idle.total, 2);
  });

  testWidgets('Not selling waits for a range longer than today', (tester) async {
    await sell('Kopiko', 12);
    await products.insertProduct(Product(
      name: 'Corned beef', stock: 12, minStock: 1, category: 'Canned goods',
      createdAt: DateTime.now().toIso8601String(), price: 45));
    await pump(tester);
    expect(find.text('Not selling'), findsNothing);
    expect(find.text('Busiest hours'), findsOneWidget);

    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(find.text('Not selling'), findsOneWidget);
    expect(find.text('Corned beef'), findsOneWidget);
  });

  test('the shared summary reads as a message', () {
    final text = reportSummaryText(
      store: 'Jhed',
      range: 'Last 7 days',
      date: DateTime(2026, 10, 2),
      stats: PeriodStats(
        revenue: 12480,
        previousRevenue: 0,
        transactions: 182,
        itemsSold: 400,
        dailyRevenue: const [],
      ),
      refunds: 0,
      top: [
        BreakdownRow(label: 'Kopiko', value: 1240),
        BreakdownRow(label: 'Pancit canton', value: 980),
        BreakdownRow(label: 'Zesto', value: 500),
        BreakdownRow(label: 'Fourth', value: 100),
      ],
      payment: [
        BreakdownRow(label: 'Cash', value: 9100),
        BreakdownRow(label: 'GCash', value: 2300),
      ],
      owed: 4250,
    );
    final lines = text.split('\n');
    expect(lines[0], 'Jhed · Last 7 days · ${trDay(DateTime(2026, 10, 2))}');
    expect(lines[1], 'Sales ${formatPeso(12480)} (182 sales)');
    expect(lines[2], startsWith('Top: Kopiko ${formatPeso(1240)}'));
    expect(lines[2], isNot(contains('Fourth')), reason: 'three is enough for a message');
    expect(lines[3], 'Cash ${formatPeso(9100)} · GCash ${formatPeso(2300)}');
    expect(lines[4], 'Owed to you ${formatPeso(4250)}');
    expect(text, isNot(contains('Returns')), reason: 'no returns line when there were none');
  });
}
