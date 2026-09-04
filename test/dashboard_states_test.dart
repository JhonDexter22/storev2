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
}
