import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/responsive.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/cashier_switch_screen.dart';
import 'package:storev2/screens/checkout_screen.dart';
import 'package:storev2/screens/dashboard_screen.dart';
import 'package:storev2/screens/restock_screen.dart';
import 'package:storev2/screens/settings_screen.dart';
import 'package:storev2/screens/shift_history_screen.dart';
import 'package:storev2/screens/store_settings_screen.dart';
import 'package:storev2/screens/utang_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/utang_service.dart';

/// Tablet artboard size from the handoff. Every screen below is pumped at this
/// size, because a RenderFlex overflow is an exception in a test — which is
/// the point: the overflows found during this redesign were all found by eye
/// on a device, one screenshot at a time.
const _tablet = Size(1180, 800);
const _phone = Size(390, 812);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // No-isolate, so a query completes on the microtask queue the widget
    // tester already drains. The ordinary ffi factory hands the work to a
    // second isolate, which a test's fake clock never waits for: every screen
    // below would sit on its loading state forever.
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    await DatabaseHelper.instance.clearAllData();
  });

  Future<void> pumpAt(WidgetTester tester, Widget screen, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  Future<Product> seedProduct({
    required String name,
    int stock = 10,
    int minStock = 5,
    double price = 20,
  }) async {
    final svc = ProductService();
    final id = await svc.insertProduct(Product(
      name: name,
      stock: stock,
      minStock: minStock,
      category: 'Snacks',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    return (await svc.getAllProducts()).firstWhere((p) => p.id == id);
  }

  Future<void> seedCustomers(List<String> names) async {
    final utang = UtangService();
    for (final name in names) {
      await utang.addCustomer(name);
    }
  }

  group('renders at tablet width without overflowing', () {
    testWidgets('dashboard', (tester) async {
      await seedProduct(name: 'SkyFlakes', stock: 2);
      await seedProduct(name: 'Kopiko', stock: 0);
      await pumpAt(tester, const DashboardScreen(), _tablet);

      // The two lists sit side by side, so both headings are on screen at once.
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Recent sales'), findsOneWidget);
    });

    testWidgets('dashboard with nothing low still aligns both columns',
        (tester) async {
      await seedProduct(name: 'SkyFlakes', stock: 50);
      await pumpAt(tester, const DashboardScreen(), _tablet);

      // The phone drops the block entirely; the tablet keeps the column and
      // says why it is empty, or the two lists stop lining up.
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Everything is stocked'), findsOneWidget);
    });

    testWidgets('restock', (tester) async {
      await seedProduct(name: 'Kopiko', stock: 0);
      await seedProduct(name: 'SkyFlakes', stock: 2);
      await pumpAt(tester, const RestockScreen(), _tablet);

      expect(find.text('Critical'), findsOneWidget);
      expect(find.text('Low stock'), findsOneWidget);
    });

    testWidgets('restock with only one urgency keeps both columns',
        (tester) async {
      await seedProduct(name: 'Kopiko', stock: 0);
      await pumpAt(tester, const RestockScreen(), _tablet);

      expect(find.text('Nothing is running low'), findsOneWidget);
    });

    testWidgets('checkout', (tester) async {
      final p = await seedProduct(name: 'SkyFlakes', price: 12.5);
      await pumpAt(
        tester,
        CheckoutScreen(lines: [CartLine(product: p, qty: 3)]),
        _tablet,
      );

      // Summary on the left, payment on the right — both visible at once,
      // which is the reason for the split.
      expect(find.text('Payment method'), findsOneWidget);
      expect(find.textContaining('SkyFlakes'), findsWidgets);
    });

    testWidgets('utang', (tester) async {
      await seedCustomers(['Aling Nena', 'Mang Tonyo', 'Ate Baby']);
      await pumpAt(tester, const UtangScreen(), _tablet);

      for (final name in ['Aling Nena', 'Mang Tonyo', 'Ate Baby']) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('shift history', (tester) async {
      await pumpAt(tester, const ShiftHistoryScreen(), _tablet);
    });

    testWidgets('cashier switch', (tester) async {
      await pumpAt(tester, const CashierSwitchScreen(), _tablet);
      expect(find.text('Sign in to the till'), findsOneWidget);
    });

    testWidgets('store settings', (tester) async {
      await pumpAt(tester, const StoreSettingsScreen(), _tablet);
      expect(find.text('Print receipt'), findsOneWidget);
    });

    testWidgets('more hub', (tester) async {
      await pumpAt(tester, const SettingsScreen(), _tablet);
      expect(find.text('More'), findsOneWidget);
    });
  });

  group('the same screens still render at phone width', () {
    testWidgets('dashboard', (tester) async {
      await seedProduct(name: 'SkyFlakes', stock: 50);
      await pumpAt(tester, const DashboardScreen(), _phone);
      expect(find.text('Recent sales'), findsOneWidget);
      // The phone drops the attention block when nothing is low, and shows no
      // placeholder — that behaviour is unchanged by the tablet work.
      expect(find.text('Everything is stocked'), findsNothing);
    });

    testWidgets('restock', (tester) async {
      await seedProduct(name: 'Kopiko', stock: 0);
      await pumpAt(tester, const RestockScreen(), _phone);
      expect(find.text('Critical'), findsOneWidget);
      // No empty-column placeholder on the phone; the section is simply absent.
      expect(find.text('Nothing is running low'), findsNothing);
    });

    testWidgets('checkout', (tester) async {
      final p = await seedProduct(name: 'SkyFlakes', price: 12.5);
      await pumpAt(
        tester,
        CheckoutScreen(lines: [CartLine(product: p, qty: 3)]),
        _phone,
      );
      expect(find.text('Payment method'), findsOneWidget);
    });
  });

  group('Breakpoints.pagePadding', () {
    /// [available] stands in for the width a list actually gets, which on a
    /// tablet is the window minus the navigation rail.
    Future<EdgeInsets> paddingAt(
      WidgetTester tester,
      Size window,
      double available,
    ) async {
      late EdgeInsets result;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: window),
        child: Builder(builder: (c) {
          result = Breakpoints.pagePadding(c, available);
          return const SizedBox();
        }),
      ));
      return result;
    }

    testWidgets('phone width keeps the ordinary screen padding', (tester) async {
      final p = await paddingAt(tester, const Size(390, 812), 390);
      expect(p.left, 20);
      expect(p.right, 20);
    });

    testWidgets('tablet width centres a column of at most 720', (tester) async {
      // 1180 window, 96 of it taken by the rail.
      final p = await paddingAt(tester, const Size(1180, 800), 1084);
      expect(p.left, p.right, reason: 'the column has to be centred');
      expect(1084 - p.left - p.right, Breakpoints.maxReadingWidth,
          reason: 'the column measures from the space it was given, not the '
              'window, or the rail makes it narrower and off-centre');
    });

    testWidgets('a tablet-width window with a narrow pane is left alone',
        (tester) async {
      // A pane narrower than the cap gets the phone padding rather than a
      // negative inset.
      final p = await paddingAt(tester, const Size(1180, 800), 600);
      expect(p.left, 20);
      expect(p.right, 20);
    });

    testWidgets('top and bottom pass through unchanged', (tester) async {
      late EdgeInsets p;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(1180, 800)),
        child: Builder(builder: (c) {
          p = Breakpoints.pagePadding(c, 1084, top: 6, bottom: 40);
          return const SizedBox();
        }),
      ));
      expect(p.top, 6);
      expect(p.bottom, 40);
    });
  });
}
