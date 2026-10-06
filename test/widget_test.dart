import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/main.dart';
import 'package:storev2/models/staff.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  setUpAll(() {
    // The app reads products from sqflite as soon as a screen mounts, and the
    // plain sqflite plugin has no factory in the test VM.
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

  testWidgets('App boots and shows the bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const RestockApp());
    // Not pumpAndSettle: the loading spinner animates forever, so it never
    // reaches a settled frame. The chrome under test renders on frame one.
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Sell'), findsOneWidget);
    expect(find.text('Restock'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
  });

  testWidgets('the tab labels are in the app font, not the system one', (WidgetTester tester) async {
    await tester.pumpWidget(const RestockApp());
    await tester.pump();

    for (final label in ['Home', 'Sell', 'More']) {
      final style = DefaultTextStyle.of(tester.element(find.text(label))).style;
      expect(style.fontFamily, startsWith('PlusJakartaSans'), reason: label);
    }
  });

  testWidgets('the app opens on the till', (WidgetTester tester) async {
    await tester.pumpWidget(const RestockApp());
    await tester.pump();
    // Sell's own search box, and its tab drawn as the selected one.
    expect(find.text('Search products'), findsOneWidget);
    expect(find.byIcon(Icons.point_of_sale_rounded), findsOneWidget);
  });

  testWidgets('Products screen shows the inventory summary', (WidgetTester tester) async {
    await tester.pumpWidget(const RestockApp());
    await tester.pump();
    // The app opens on Sell; go to Products.
    await tester.tap(find.text('Products'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Products'), findsWidgets);
    // The header carries the summary subtitle (still loading on frame one,
    // since this suite's database factory never settles under the fake
    // clock), the search field and the Add button.
    expect(find.textContaining(RegExp(r'on hand|Loading')), findsOneWidget);
    expect(find.text('Search name or SKU'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('the part of the Sell button above the bar opens Sell', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const RestockApp());
    await tester.pump();
    // The app opens on Sell; start from Home so there is somewhere to come from.
    await tester.tap(find.text('Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The circle's centre is its icon's centre. An unselected tab's icon sits 26
    // below the bar's top edge (9 to the pill, half its 34 height), which
    // locates the edge without reaching into the bar's private layout.
    final sell = tester.getCenter(find.byIcon(Icons.point_of_sale_outlined));
    // Home is selected now, so measure from an unselected tab: More.
    final barTop = tester.getCenter(find.byIcon(Icons.grid_view_outlined)).dy - 26;
    final aboveBar = Offset(sell.dx, sell.dy - 20);
    expect(aboveBar.dy, lessThan(barTop), reason: 'the tap must land above the bar');

    await tester.tapAt(aboveBar);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byIcon(Icons.point_of_sale_rounded), findsOneWidget);
    expect(find.text('Search products'), findsOneWidget);
  });

  group('SettingsService', () {
    test('falls back to defaults on a fresh install', () async {
      final s = SettingsService.instance;
      expect(s.printReceipt, isTrue);
      // On by default: a shopkeeper who never heard the store lives on this
      // phone alone would never think to switch it on.
      expect(s.autoBackup, isTrue);
      expect(s.defaultMinStock, 5);
      expect(s.cashier, 'May');
    });

    test('persists a changed value across a reload', () async {
      final s = SettingsService.instance;
      await s.setAutoBackup(false);
      await s.setDefaultMinStock(12);
      await s.setCashier('Nena');

      // Re-read from storage the way a fresh launch would.
      await s.load();

      expect(s.autoBackup, isFalse);
      expect(s.defaultMinStock, 12);
      expect(s.cashier, 'Nena');
    });

    test('a single-word name has one initial', () {
      expect(const Staff(name: 'May', role: 'Cashier').initials, 'M');
      expect(const Staff(name: 'Ana Reyes', role: 'Cashier').initials, 'AR');
    });

    test('a name that is already initials stays whole', () {
      expect(Staff.initialsOf('JD'), 'JD');
      expect(Staff.initialsOf('Jo'), 'J');
      expect(Staff.initialsOf('  '), '?');
    });

    test('notifies listeners when a setting changes', () async {
      final s = SettingsService.instance;
      var notified = 0;
      void listener() => notified++;
      s.addListener(listener);
      await s.setScanSound(false);
      s.removeListener(listener);

      expect(notified, greaterThan(0));
    });
  });
}
