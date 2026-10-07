import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/design_tokens.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/l10n/tr.dart';
import 'package:storev2/models/shift_model.dart';
import 'package:storev2/screens/shift_history_screen.dart';
import 'package:storev2/services/receipt_document.dart';
import 'package:storev2/services/settings_service.dart';

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
    await DatabaseHelper.instance.clearAllData();
  });

  /// A close [daysAgo] days back, with [variance] as counted minus expected.
  Future<void> close({int daysAgo = 0, double variance = 0, double sales = 500, double utangCash = 0, String cashier = 'May'}) async {
    final db = await DatabaseHelper.instance.database;
    final at = DateTime.now().subtract(Duration(days: daysAgo, minutes: 1));
    final expected = 1000 + sales + utangCash;
    await db.insert('shifts', {
      'closed_at': at.toIso8601String(),
      'opened_at': at.subtract(const Duration(hours: 8)).toIso8601String(),
      'cashier': cashier,
      'terminal': 'Terminal 1',
      'opening_float': 1000.0,
      'cash_sales': sales,
      'utang_cash': utangCash,
      'expected': expected,
      'counted': expected + variance,
      'variance': variance,
      'denominations': '',
      'total_sales': sales,
      'sale_count': 5,
    });
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ShiftHistoryScreen()));
    await tester.pumpAndSettle();
  }

  // Each day card ends in a chevron; the card itself opens the count.
  Finder cards() => find.byIcon(Icons.chevron_right_rounded);

  group('utang paid in cash', () {
    testWidgets('is a line in the close\'s detail', (tester) async {
      await close(utangCash: 300);
      await pump(tester);
      await tester.tap(cards().first);
      await tester.pumpAndSettle();
      expect(find.text('Utang paid in cash'), findsOneWidget);
      expect(find.text(formatPeso(300)), findsOneWidget);
    });

    test('is on the printed slip, so its lines add up', () {
      final slip = ReceiptDocument.shift(
        Shift(
          closedAt: DateTime.now().toIso8601String(),
          cashier: 'May',
          terminal: 'Terminal 1',
          openingFloat: 1000,
          cashSales: 500,
          utangCash: 300,
          expected: 1800,
          counted: 1800,
          variance: 0,
          denominations: const {},
        ),
        storeName: 'Jhed',
      );
      final rows = {for (final b in slip.whereType<ReceiptRow>()) b.left: b.right};
      expect(rows['Utang paid in cash'], formatPeso(300));
      expect(rows['Expected'], formatPeso(1800));
    });
  });

  testWidgets('the count is every close, and older ones are a tap away', (tester) async {
    for (var i = 0; i < 25; i++) {
      await close(daysAgo: i);
    }
    await pump(tester);
    expect(find.text('25 closes recorded'), findsOneWidget);
    expect(cards(), findsNWidgets(20));

    await tester.tap(find.text('Show older'));
    await tester.pumpAndSettle();
    expect(cards(), findsNWidgets(25));
    expect(find.text('Show older'), findsNothing);
  });

  testWidgets('the totals say their window, and keep to it', (tester) async {
    await close(daysAgo: 1, sales: 500, variance: -50);
    await close(daysAgo: 45, sales: 9000, variance: -900);
    await pump(tester);

    expect(find.text('LAST 30 DAYS'), findsOneWidget);
    expect(find.text(formatPeso(500)), findsWidgets);
    expect(find.text('Short · 1 day'), findsOneWidget);
    expect(find.text(formatPeso(9500)), findsNothing);
  });

  testWidgets('a short day and an over day do not cancel out', (tester) async {
    await close(daysAgo: 1, variance: -500);
    await close(daysAgo: 2, variance: 450);
    await pump(tester);
    expect(find.text('Short · 1 day'), findsOneWidget);
    expect(find.text(formatPeso(500)), findsWidgets);
    expect(find.text('Over · 1 day'), findsOneWidget);
    expect(find.text(formatPeso(450)), findsWidgets);
    expect(find.text(formatPeso(-50)), findsNothing);
  });

  testWidgets("one cashier's closes can be picked out", (tester) async {
    await close(daysAgo: 1, variance: -100);
    await close(daysAgo: 2, variance: -200, cashier: 'JD');
    await close(daysAgo: 3, variance: 0, cashier: 'JD');
    await pump(tester);
    expect(find.text('Everyone'), findsOneWidget);

    await tester.tap(find.text('JD'));
    await tester.pumpAndSettle();
    expect(cards(), findsNWidgets(2));
    expect(find.text('Short · 1 day'), findsOneWidget);
    expect(find.text(formatPeso(200)), findsWidgets);
  });

  testWidgets('one cashier gets no cashier chips', (tester) async {
    await close(daysAgo: 1);
    await pump(tester);
    expect(find.text('Everyone'), findsNothing);
  });

  testWidgets('a window across midnight names the day it opened', (tester) async {
    await close(daysAgo: 1);
    // Opened a full day before it closed, so the window crosses midnight.
    final db = await DatabaseHelper.instance.database;
    final closed = DateTime.now().subtract(const Duration(days: 1));
    final opened = closed.subtract(const Duration(days: 1));
    await db.update('shifts', {
      'closed_at': closed.toIso8601String(),
      'opened_at': opened.toIso8601String(),
    });
    await pump(tester);
    expect(find.textContaining('${trDay(opened)} '), findsOneWidget);
  });

  testWidgets('Short shows only the short drawers', (tester) async {
    await close(daysAgo: 1, variance: 0);
    await close(daysAgo: 2, variance: -50);
    await close(daysAgo: 3, variance: 20);
    await pump(tester);
    expect(cards(), findsNWidgets(3));

    await tester.tap(find.text('Short'));
    await tester.pumpAndSettle();
    expect(cards(), findsOneWidget);
    expect(find.text('Short ${formatPeso(50)}'), findsOneWidget);
  });

  testWidgets('a balanced drawer says Balanced, under the new name', (tester) async {
    await close();
    await pump(tester);
    expect(find.text('Closed days'), findsOneWidget);
    expect(find.text('Balanced'), findsOneWidget);
    expect(find.text('Exact'), findsNothing);
  });

  testWidgets('a card carries its sales, with no View count row', (tester) async {
    await close(sales: 500);
    await pump(tester);
    expect(find.text('₱500.00 · 5 sales'), findsOneWidget);
    expect(find.text('View count'), findsNothing);
  });

  testWidgets('a day from another year says which', (tester) async {
    await close(daysAgo: 400);
    await pump(tester);
    final then = DateTime.now().subtract(const Duration(days: 400, minutes: 1));
    expect(find.textContaining('${trDay(then)} ${then.year}'), findsOneWidget);
  });

  testWidgets('a tablet puts the days in two columns', (tester) async {
    for (var d = 0; d < 3; d++) {
      await close(daysAgo: d);
    }
    tester.view.physicalSize = const Size(1194, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ShiftHistoryScreen()));
    await tester.pumpAndSettle();

    final chevrons = find.byIcon(Icons.chevron_right_rounded);
    final a = tester.getCenter(chevrons.at(0));
    final b = tester.getCenter(chevrons.at(1));
    expect(b.dy, a.dy);
    expect(b.dx, greaterThan(a.dx + 300));
  });
}
