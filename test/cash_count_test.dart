import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/design_tokens.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/l10n/tr.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/models/shift_model.dart';
import 'package:storev2/screens/cash_count_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/shift_service.dart';
import 'package:storev2/services/shift_summary.dart';
import 'package:storev2/widgets/day_close_view.dart';

void main() {
  final products = ProductService();
  final sales = SalesService();
  final shifts = ShiftService();

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

  Future<void> sellForCash(double price) async {
    final id = await products.insertProduct(Product(
      name: 'Item ${DateTime.now().microsecondsSinceEpoch}',
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
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: CashCountScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('there is no button that balances the drawer without counting it',
      (tester) async {
    await pump(tester);
    expect(find.text('Count exact'), findsNothing);
  });

  test('a second close in a day does not expect the first one\'s cash', () async {
    final float = SettingsService.instance.openingFloat;
    await sellForCash(100);
    await shifts.closeShift(
      cashier: 'May',
      terminal: 'Terminal 1',
      openingFloat: float,
      cashSales: 100,
      counted: float + 100,
      denominations: const {},
      totalSales: 100,
      saleCount: 1,
      openedAt: DateTime.now(),
    );
    // A moment later, so the next sale is after the close.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await sellForCash(50);

    final drawer = await shifts.drawerNow();
    expect(drawer.cashSales, 50);
    expect(drawer.expected, float + 50);
  });

  testWidgets('a count can be typed, not just tapped', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const ValueKey('count-20')), '37');
    await tester.pump();
    expect(find.text(formatPeso(740)), findsWidgets);

    // + and − still work, and agree with what was typed.
    final plus = find.descendant(
        of: find.ancestor(of: find.byKey(const ValueKey('count-20')), matching: find.byType(Row)).first,
        matching: find.byIcon(Icons.add_rounded));
    await tester.tap(plus);
    await tester.pump();
    expect(find.text('38'), findsOneWidget);
    expect(find.text(formatPeso(760)), findsWidgets);
  });

  testWidgets('note and coin follow the app language', (tester) async {
    await SettingsService.instance.setLanguage(AppLanguage.fil);
    addTearDown(() => SettingsService.instance.setLanguage(AppLanguage.en));
    await pump(tester);
    expect(find.text('papel'), findsWidgets);
    expect(find.text('barya'), findsWidgets);
    expect(find.text('note'), findsNothing);
  });

  testWidgets('the close is called Close day, as on Home', (tester) async {
    await pump(tester);
    // The screen's title and its button; the title used to say Cash count.
    expect(find.text('Close day'), findsNWidgets(2));
    expect(find.text('Cash count'), findsNothing);
    expect(find.text('Close shift'), findsNothing);
  });

  testWidgets('says which day it closes, and writes ₱1,000 as everywhere else', (tester) async {
    await pump(tester);
    expect(find.textContaining('Since '), findsOneWidget);
    expect(find.textContaining('Terminal'), findsNothing);
    expect(find.text('₱1,000'), findsOneWidget);
    expect(find.text('₱1000'), findsNothing);
  });

  test('Recount takes back the close, so the day is not recorded twice', () async {
    final shifts = ShiftService();
    Future<Shift> close() async {
      final s = await shifts.currentShiftSales();
      return shifts.closeShift(
        cashier: 'May', terminal: 'Terminal 1', openingFloat: 1000, cashSales: 0,
        counted: 997, denominations: const {}, totalSales: s.total, saleCount: s.count, openedAt: s.openedAt);
    }

    final first = await close();
    await shifts.undoClose(first);
    expect(await shifts.closeCount(), 0);
    // Counted again and closed: one close, with the second count.
    await close();
    expect(await shifts.closeCount(), 1);
  });

  testWidgets('the summary leads with the drawer, and a short one is not ticked', (tester) async {
    final shifts = ShiftService();
    final s = await shifts.currentShiftSales();
    final shift = await shifts.closeShift(
        cashier: 'May', terminal: 'Terminal 1', openingFloat: 1000, cashSales: 0,
        counted: 997, denominations: const {}, totalSales: 0, saleCount: 0, openedAt: s.openedAt);
    final summary = await ShiftSummaryService().forShift(shift);
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: DayCloseView(summary: summary, onDone: () {})));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('CASH DRAWER')).dy,
        lessThan(tester.getTopLeft(find.text('SALES')).dy));
    expect(find.text('Short'), findsOneWidget);
    // The one tick left is the Done button's; the badge at the top is a "!".
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);
  });

  test('only the latest close can be taken back', () async {
    final shifts = ShiftService();
    final s = await shifts.currentShiftSales();
    Future<Shift> close() => shifts.closeShift(
        cashier: 'May', terminal: 'Terminal 1', openingFloat: 1000, cashSales: 0,
        counted: 1000, denominations: const {}, totalSales: 0, saleCount: 0, openedAt: s.openedAt);
    final older = await close();
    await close();
    await shifts.undoClose(older);
    expect(await shifts.closeCount(), 2);
  });
}
