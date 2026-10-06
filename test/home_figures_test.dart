import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/design_tokens.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/l10n/tr.dart';
import 'package:storev2/models/customer.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/models/sale_model.dart';
import 'package:storev2/screens/dashboard_screen.dart';
import 'package:storev2/screens/sales_list_screen.dart';
import 'package:storev2/screens/utang_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/shift_service.dart';
import 'package:storev2/services/utang_service.dart';

/// Sales with a chosen revenue against a chosen previous period.
class _Sales extends SalesService {
  _Sales({this.revenue = 500, this.previous = 0, this.cash = 0});

  final double revenue;
  final double previous;
  final double cash;

  @override
  Future<List<Sale>> getRecentSales({int limit = 10}) async => [];

  @override
  Future<PeriodStats> getPeriodStats(int days) async => PeriodStats(
        revenue: revenue,
        previousRevenue: previous,
        transactions: 5,
        itemsSold: 9,
        dailyRevenue: List<double>.generate(days, (i) => 10.0 + i),
      );

  @override
  Future<double> cashSalesSince(DateTime since) async => cash;
}

/// [n] recent sales, newest first, numbered #0001 up.
class _WithRecent extends _Sales {
  _WithRecent(this.n);
  final int n;

  @override
  Future<List<Sale>> getRecentSales({int limit = 10}) async => [
        for (var i = 1; i <= n && i <= limit; i++)
          Sale(
            id: i,
            reference: 'S20261004-${i.toString().padLeft(4, '0')}',
            createdAt: DateTime.now().toIso8601String(),
            subtotal: 10,
            total: 10,
            paymentMethod: 'Cash',
            itemCount: 1,
          ),
      ];
}

class _Products extends ProductService {
  _Products(this.items);
  final List<Product> items;

  @override
  Future<List<Product>> getAllProducts() async => items;
}

class _Utang extends UtangService {
  _Utang(this.customers);
  final List<Customer> customers;

  @override
  Future<List<Customer>> getCustomers() async => customers;
}

/// Sales since a close [daysAgo] days back, for the Close day card.
class _Shift extends ShiftService {
  _Shift(this.openedAt);
  final DateTime openedAt;

  @override
  Future<({double total, int count, DateTime openedAt})> currentShiftSales() async =>
      (total: 4250.0, count: 38, openedAt: openedAt);

  @override
  Future<({double float, double cashSales, double utangCash, double expected})> drawerNow() async =>
      (float: 1000.0, cashSales: 0.0, utangCash: 0.0, expected: 1000.0);
}

Product _p(String name, {int stock = 50, int minStock = 5, double price = 10}) => Product(
      id: name.hashCode,
      name: name,
      stock: stock,
      minStock: minStock,
      category: 'Snacks',
      createdAt: '2026-09-01',
      price: price,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsService.instance.resetForTests();
    await SettingsService.instance.load();
  });

  Future<void> pump(
    WidgetTester tester, {
    SalesService? sales,
    List<Product>? products,
    List<Customer> customers = const [],
    ShiftService? shifts,
  }) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: DashboardScreen(
        salesService: sales ?? _Sales(),
        productService: _Products(products ?? [_p('Kopiko')]),
        utangService: _Utang(customers),
        shiftService: shifts,
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('the comparison badge', () {
    testWidgets('is not shown with nothing to compare against', (tester) async {
      await pump(tester, sales: _Sales(revenue: 500, previous: 0));
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('says what it compares with', (tester) async {
      await pump(tester, sales: _Sales(revenue: 112, previous: 100));
      expect(find.text('+12% vs yesterday'), findsOneWidget);

      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(find.text('+12% vs previous 7 days'), findsOneWidget);
    });
  });

  group('the period', () {
    testWidgets('is named for what it counts', (tester) async {
      await pump(tester);
      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(find.text('SALES · LAST 7 DAYS'), findsOneWidget);
      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      expect(find.text('SALES · LAST 30 DAYS'), findsOneWidget);
    });

    testWidgets('30 days charts 30 days, dated at the ends', (tester) async {
      await pump(tester);
      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      final first = DateTime.now().subtract(const Duration(days: 29));
      expect(find.text(trDay(first)), findsOneWidget);
    });

    testWidgets('Today says its chart is the last 7 days', (tester) async {
      await pump(tester);
      expect(find.text('Last 7 days'), findsOneWidget);
    });
  });

  group('the tiles', () {
    testWidgets('show the drawer, credit and stock value rather than repeat the sales card',
        (tester) async {
      await pump(
        tester,
        sales: _Sales(cash: 250),
        products: [_p('Kopiko', stock: 10, price: 12), _p('Zesto', stock: 5, price: 20)],
        customers: [
          Customer(name: 'Aling Nena', createdAt: '2026-09-01', balance: 150),
          Customer(name: 'Mang Jose', createdAt: '2026-09-01', balance: 0),
        ],
      );

      final drawer = SettingsService.instance.openingFloat + 250;
      expect(find.text('Expected in drawer'), findsOneWidget);
      expect(find.text(formatPeso(drawer)), findsOneWidget);
      expect(find.text('Owed to you'), findsOneWidget);
      expect(find.text(formatPeso(150)), findsOneWidget);
      expect(find.text(formatPeso(220)), findsOneWidget); // 10 × 12 + 5 × 20
      expect(find.text('Items sold'), findsNothing);
    });

    testWidgets('Transactions in the sales card opens the list of sales', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Transactions'));
      await tester.pumpAndSettle();
      expect(find.byType(SalesListScreen), findsOneWidget);
    });
  });

  group('needs attention', () {
    testWidgets('follows Restock\'s order and offers the rest', (tester) async {
      await pump(tester, products: [
        _p('Half', stock: 5, minStock: 5), // 50% of healthy
        _p('Nearly', stock: 1, minStock: 5), // 10%
        _p('Out slow', stock: 0, minStock: 3),
        _p('Out fast', stock: 0, minStock: 20),
        _p('Low a', stock: 2, minStock: 5),
        _p('Low b', stock: 3, minStock: 5),
        _p('Low c', stock: 4, minStock: 5),
      ]);

      expect(find.text('See all 7'), findsOneWidget);
      double y(String n) => tester.getTopLeft(find.text(n)).dy;
      expect(y('Out fast'), lessThan(y('Out slow')));
      expect(y('Out slow'), lessThan(y('Nearly')));
      // Only five on Home; the least urgent waits in Restock.
      expect(find.text('Half'), findsNothing);
    });

    testWidgets('has no See all when everything is already shown', (tester) async {
      await pump(tester, products: [_p('Nearly', stock: 1)]);
      expect(find.textContaining('See all'), findsNothing);
    });
  });

  testWidgets('+ Stock on Home offers the same suggestion Restock does', (tester) async {
    await pump(tester, products: [_p('Nearly', stock: 1, minStock: 5)]);
    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();
    // Twice the minimum, less what is left: 10 - 1.
    expect(find.text('Suggested +9'), findsOneWidget);
  });

  testWidgets('the Close day card names the day it counts from', (tester) async {
    final opened = DateTime.now().subtract(const Duration(days: 2));
    await pump(tester, shifts: _Shift(opened));
    expect(find.textContaining('since ${trDay(opened)}, '), findsOneWidget);
  });

  group('the phone layout', () {
    testWidgets('Close day sits under the sales card, and no Start a new sale card', (tester) async {
      await pump(tester, sales: _WithRecent(5), shifts: _Shift(DateTime.now()));
      final closeDay = tester.getTopLeft(find.text('Close day')).dy;
      expect(closeDay, lessThan(tester.getTopLeft(find.text('Recent sales')).dy));
      expect(closeDay, lessThan(tester.getTopLeft(find.text('Expected in drawer')).dy));
      // The raised Sell button in the bar does that.
      expect(find.text('Start a new sale'), findsNothing);
    });

    testWidgets('shows three recent sales, and See all opens the list', (tester) async {
      await pump(tester, sales: _WithRecent(5));
      expect(find.text('#0001'), findsOneWidget);
      expect(find.text('#0003'), findsOneWidget);
      expect(find.text('#0004'), findsNothing);
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.byType(SalesListScreen), findsOneWidget);
    });

    testWidgets('greets whoever is at the till, under the store\'s own name', (tester) async {
      await SettingsService.instance.setStoreName('Tindahan ni Aling Nena');
      await pump(tester);
      expect(find.text('Tindahan ni Aling Nena'), findsOneWidget);
      expect(find.textContaining(', ${SettingsService.instance.cashier}'), findsOneWidget);
      expect(find.text('Store Overview'), findsNothing);
    });
  });

  testWidgets('the overdue alert opens Credit on Overdue', (tester) async {
    final overdue = Customer(
      name: 'Aling Nena',
      createdAt: '2026-08-01',
      balance: 300,
      oldestChargeAt: DateTime.now().subtract(const Duration(days: 45)),
    );
    await pump(tester, customers: [overdue]);
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 customer overdue'));
    await tester.pumpAndSettle();
    expect(tester.widget<UtangScreen>(find.byType(UtangScreen)).overdueOnly, isTrue);
  });
}
