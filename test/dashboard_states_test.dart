import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/models/sale_model.dart';
import 'package:storev2/screens/dashboard_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/shift_service.dart';
import 'package:storev2/services/utang_service.dart';
import 'package:storev2/services/error_log.dart';
import 'package:storev2/models/customer.dart';
import 'package:storev2/widgets/skeleton.dart';

/// Fails every read, to drive the dashboard's error path.
class _FailingProductService extends ProductService {
  @override
  Future<List<Product>> getAllProducts() async => throw StateError('db unavailable');
}

/// Succeeds, but reports a period with nothing in it.
class _EmptyProductService extends ProductService {
  @override
  Future<List<Product>> getAllProducts() async => [];
}

/// Stays pending until [release] is called, so the loading frame can be
/// inspected. Without this the fakes resolve in a microtask and the first
/// pumped frame already has data.
class _PendingProductService extends ProductService {
  final _gate = Completer<List<Product>>();
  void release() => _gate.complete(<Product>[]);

  @override
  Future<List<Product>> getAllProducts() => _gate.future;
}

class _EmptySalesService extends SalesService {
  @override
  Future<List<Sale>> getRecentSales({int limit = 10}) async => [];

  @override
  Future<PeriodStats> getPeriodStats(int days) async => PeriodStats(
        revenue: 0,
        previousRevenue: 0,
        transactions: 0,
        itemsSold: 0,
        dailyRevenue: List<double>.filled(days, 0),
      );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Each suite gets its own in-memory store; sharing one file makes
    // suites clobber each other when they run in parallel.
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('shows skeletons while loading, not a bare spinner',
      (WidgetTester tester) async {
    final pending = _PendingProductService();
    await tester.pumpWidget(wrap(DashboardScreen(
      productService: pending,
      salesService: _EmptySalesService(),
    )));
    await tester.pump();

    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Let the load finish so the test does not end with work in flight.
    pending.release();
    await tester.pumpAndSettle();
    expect(find.byType(SkeletonBox), findsNothing);
  });

  testWidgets('a failed load lands on the error state, not a hung spinner',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(DashboardScreen(
      productService: _FailingProductService(),
      salesService: _EmptySalesService(),
    )));
    await tester.pumpAndSettle();

    expect(find.text("Could not load today's sales"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Continue to POS'), findsOneWidget);
    // The reassurance matters: the shopkeeper's data is still on the device.
    expect(find.textContaining('Nothing was lost'), findsOneWidget);
    // Regression: the spinner used to run forever because nothing caught this.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a period with no sales shows the empty card, not a zero hero',
      (WidgetTester tester) async {
    await tester.pumpWidget(wrap(DashboardScreen(
      productService: _EmptyProductService(),
      salesService: _EmptySalesService(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('No sales yet today'), findsOneWidget);
    expect(find.text('Start a sale'), findsOneWidget);
    // The misleading zero hero should not be rendered at all.
    expect(find.text('₱0.00'), findsNothing);
  });

  testWidgets('Try again re-runs the load', (WidgetTester tester) async {
    final failing = _FailingProductService();
    await tester.pumpWidget(wrap(DashboardScreen(
      productService: failing,
      salesService: _EmptySalesService(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    // Still failing, so it returns to the error state rather than hanging.
    expect(find.text("Could not load today's sales"), findsOneWidget);
  });

  group('the backup reminder', () {
    testWidgets('a stocked store that has never backed up is told so',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(DashboardScreen(
        productService: _OneProductService(),
        salesService: _EmptySalesService(),
        shiftService: _NoShiftService(),
        utangService: _Utang(),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Back up your store'), findsOneWidget);
      expect(find.text('Back up now'), findsOneWidget);
    });

    testWidgets('an empty store is not nagged on its first morning',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(DashboardScreen(
        productService: _EmptyProductService(),
        salesService: _EmptySalesService(),
        shiftService: _NoShiftService(),
        utangService: _Utang(),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Back up your store'), findsNothing);
    });

    testWidgets('a backup from today silences it', (WidgetTester tester) async {
      await SettingsService.instance.markBackedUp();
      await tester.pumpWidget(wrap(DashboardScreen(
        productService: _OneProductService(),
        salesService: _EmptySalesService(),
        shiftService: _NoShiftService(),
        utangService: _Utang(),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Back up your store'), findsNothing);
    });
  });

  group('the header', () {
    Future<void> pump(
      WidgetTester tester, {
      List<Product> products = const [],
      List<Customer> customers = const [],
    }) async {
      await tester.pumpWidget(wrap(DashboardScreen(
        productService: _Products(products),
        salesService: _EmptySalesService(),
        shiftService: _NoShiftService(),
        utangService: _Utang(customers),
      )));
      await tester.pumpAndSettle();
    }

    Product product(String name, {required int stock, int min = 5}) => Product(
          id: name.hashCode,
          name: name,
          stock: stock,
          minStock: min,
          category: 'Snacks',
          createdAt: '2026-09-01',
          price: 10,
        );

    setUp(() async {
      ErrorLog.instance.resetForTests();
      // Nothing about backups in these: a fresh one silences that alert.
      await SettingsService.instance.markBackedUp();
    });

    testWidgets('the avatar shows who is signed in, not a fixed letter',
        (tester) async {
      await SettingsService.instance.setCashier('Nena Cruz');
      await pump(tester);
      expect(find.text('NC'), findsOneWidget);

      await SettingsService.instance.setCashier('Ronel');
      await tester.pump();
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('no dot when nothing needs attention', (tester) async {
      await pump(tester, products: [product('SkyFlakes', stock: 40)]);
      expect(find.byKey(const ValueKey('alert-dot')), findsNothing);

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();
      expect(find.text('All caught up — nothing needs you right now.'), findsOneWidget);
    });

    testWidgets('running low is listed but does not light the dot', (tester) async {
      await pump(tester, products: [product('SkyFlakes', stock: 2)]);
      expect(find.byKey(const ValueKey('alert-dot')), findsNothing);

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();
      expect(find.text('1 product running low'), findsOneWidget);
    });

    testWidgets('out of stock and overdue utang light it, and are listed',
        (tester) async {
      await pump(
        tester,
        products: [product('SkyFlakes', stock: 0), product('Kopiko', stock: 0)],
        customers: [
          Customer(name: 'Aling Rosa', createdAt: '2026-01-01').copyWith(
            balance: 250,
            oldestChargeAt: DateTime.now().subtract(const Duration(days: 45)),
          ),
        ],
      );
      expect(find.byKey(const ValueKey('alert-dot')), findsOneWidget);

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();
      expect(find.text('2 products out of stock'), findsOneWidget);
      expect(find.text('1 customer overdue'), findsOneWidget);
    });

    testWidgets('a new error lights it until the log is opened', (tester) async {
      ErrorLog.caught('printer gone', null, 'printing');
      await pump(tester, products: [product('SkyFlakes', stock: 40)]);
      expect(find.byKey(const ValueKey('alert-dot')), findsOneWidget);

      await SettingsService.instance.markErrorsSeen();
      await tester.pump();
      expect(find.byKey(const ValueKey('alert-dot')), findsNothing);
    });
  });
}

/// No open shift, answered at once. The real one reads the database outside
/// the test's fake clock, and can land after the widget has been torn down.
class _NoShiftService extends ShiftService {
  @override
  Future<({double total, int count, DateTime openedAt})> currentShiftSales() async =>
      (total: 0.0, count: 0, openedAt: DateTime(2026, 9, 1));
}

/// A store with one thing on the shelf — enough to have something to lose.
class _OneProductService extends ProductService {
  @override
  Future<List<Product>> getAllProducts() async => [
        Product(
          id: 1,
          name: 'SkyFlakes',
          stock: 20,
          minStock: 1,
          category: 'Biscuit',
          createdAt: DateTime(2026, 9, 1).toIso8601String(),
          price: 10,
        ),
      ];
}

/// Whatever products a test puts on the shelf.
class _Products extends ProductService {
  _Products(this.products);
  final List<Product> products;

  @override
  Future<List<Product>> getAllProducts() async => products;
}

/// Customers answered at once, without walking a real ledger.
class _Utang extends UtangService {
  _Utang([this.customers = const []]);
  final List<Customer> customers;

  @override
  Future<List<Customer>> getCustomers() async => customers;
}
