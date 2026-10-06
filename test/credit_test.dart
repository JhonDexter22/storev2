import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/design_tokens.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/screens/cash_count_screen.dart';
import 'package:storev2/screens/utang_screen.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/shift_service.dart';
import 'package:storev2/services/utang_service.dart';

void main() {
  final utang = UtangService();

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

  Future<int> owing(String name, double amount) async {
    final id = await utang.addCustomer(name);
    await utang.charge(customerId: id, amount: amount);
    return id;
  }

  Future<double> balanceOf(int id) async =>
      (await utang.getCustomers()).firstWhere((c) => c.id == id).balance;

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  group('utang paid in cash is in the drawer', () {
    test('the expected figure counts it; GCash does not', () async {
      final id = await owing('Aling Nena', 800);
      await utang.recordPayment(customerId: id, amount: 500, method: 'Cash');
      await utang.recordPayment(customerId: id, amount: 100, method: 'GCash');

      final drawer = await ShiftService().drawerNow();
      expect(drawer.utangCash, 500);
      expect(drawer.expected, SettingsService.instance.openingFloat + 500);
    });

    testWidgets('Cash count shows it as its own line', (tester) async {
      final id = await owing('Aling Nena', 800);
      await utang.recordPayment(customerId: id, amount: 500, method: 'Cash');
      await pump(tester, const CashCountScreen());

      expect(find.text('Utang paid in cash'), findsOneWidget);
      expect(find.text(formatPeso(SettingsService.instance.openingFloat + 500)), findsOneWidget);
    });

    test('a day close records it, and counts it in what was expected', () async {
      final shift = await ShiftService().closeShift(
        cashier: 'JD',
        terminal: 'Terminal 1',
        openingFloat: 1000,
        cashSales: 300,
        utangCash: 500,
        counted: 1800,
        denominations: const {1000: 1, 500: 1, 100: 3},
        totalSales: 300,
        saleCount: 3,
        openedAt: DateTime.now(),
      );
      expect(shift.utangCash, 500);
      expect(shift.expected, 1800);
      expect(shift.variance, 0);
    });
  });

  group('recording a payment', () {
    Future<void> openPayment(WidgetTester tester) async {
      await pump(tester, const UtangScreen());
      await tester.tap(find.text('Payment'));
      await tester.pumpAndSettle();
    }

    Future<void> enter(WidgetTester tester, String amount) async {
      await tester.enterText(find.byType(TextField).last, amount);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Record payment'));
      await tester.pumpAndSettle();
    }

    testWidgets('cannot pay more than is owed', (tester) async {
      final id = await owing('Aling Nena', 500);
      await openPayment(tester);
      await enter(tester, '600');

      expect(find.text('Aling Nena only owes ${formatPeso(500)}'), findsOneWidget);
      expect(await balanceOf(id), 500);
    });

    testWidgets('says so when the amount is missing', (tester) async {
      await owing('Aling Nena', 500);
      await openPayment(tester);
      await enter(tester, '');
      expect(find.text('Enter an amount'), findsOneWidget);
    });

    testWidgets('takes an amount written with a comma', (tester) async {
      final id = await owing('Aling Nena', 1500);
      await openPayment(tester);
      await enter(tester, '1,000');
      expect(await balanceOf(id), 500);
    });

    testWidgets('offers the store\'s payment types, not Utang', (tester) async {
      await owing('Aling Nena', 500);
      await openPayment(tester);
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Utang'), findsNothing);
    });

    testWidgets('can be undone', (tester) async {
      final id = await owing('Aling Nena', 500);
      await openPayment(tester);
      await enter(tester, '200');

      expect(find.text('Paid ${formatPeso(200)} · Aling Nena now owes ${formatPeso(300)}'),
          findsOneWidget);
      expect(await balanceOf(id), 300);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await balanceOf(id), 500);
    });
  });

  testWidgets('a long book can be searched by name', (tester) async {
    for (final n in ['Aling Nena', 'Mang Jose', 'Ate Liza', 'Kuya Ben', 'Lola Iska', 'Tita Baby']) {
      await owing(n, 100);
    }
    await pump(tester, const UtangScreen());

    await tester.enterText(find.byType(TextField), 'jose');
    await tester.pump();
    expect(find.text('Mang Jose'), findsOneWidget);
    expect(find.text('Aling Nena'), findsNothing);
  });

  group('credit limits', () {
    test('a customer follows the store default unless they have their own', () async {
      await SettingsService.instance.setCreditLimit(500);
      final plain = await utang.addCustomer('Aling Nena');
      final trusted = await utang.addCustomer('Mang Jose', creditLimit: 2000);
      final unlimited = await utang.addCustomer('Kuya Ben', creditLimit: 0);
      final all = {for (final c in await utang.getCustomers()) c.id: c};

      expect(creditLimitFor(all[plain]!), 500);
      expect(creditLimitFor(all[trusted]!), 2000);
      expect(isOverLimit(all[trusted]!, balance: 1500), isFalse);
      expect(isOverLimit(all[plain]!, balance: 1500), isTrue);
      expect(isOverLimit(all[unlimited]!, balance: 99999), isFalse, reason: '0 means no limit');
    });

    test('a store default of 0 means no limit for anyone without their own', () async {
      await SettingsService.instance.setCreditLimit(0);
      await utang.addCustomer('Aling Nena');
      final c = (await utang.getCustomers()).single;
      expect(isOverLimit(c, balance: 50000), isFalse);
    });

    test('editing a customer can put them back on the default', () async {
      final id = await utang.addCustomer('Mang Jose', creditLimit: 2000);
      await utang.updateCustomer(id, name: 'Mang Jose', creditLimit: null);
      expect((await utang.getCustomers()).single.creditLimit, isNull);
    });

    test('the store default travels in a backup', () async {
      await SettingsService.instance.setCreditLimit(1200);
      final exported = SettingsService.instance.exportSettings();
      await SettingsService.instance.setCreditLimit(500);
      await SettingsService.instance.importSettings(exported);
      expect(SettingsService.instance.creditLimit, 1200);
    });

    testWidgets('the card says who is over their limit', (tester) async {
      await SettingsService.instance.setCreditLimit(500);
      await owing('Aling Nena', 800);
      final jose = await utang.addCustomer('Mang Jose', creditLimit: 2000);
      await utang.charge(customerId: jose, amount: 800);
      await pump(tester, const UtangScreen());
      // Aling Nena is past the store's ₱500, and the card says by how much;
      // Mang Jose is within his own ₱2,000.
      expect(find.text('Over the ₱500.00 limit by ₱300.00'), findsOneWidget);
    });

    testWidgets('the last charge or payment says when, on a line of its own', (tester) async {
      await owing('Aling Nena', 300);
      await pump(tester, const UtangScreen());
      expect(find.text('Charged ₱300.00'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('the three totals stand the same height', (tester) async {
      await owing('Aling Nena', 300);
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: UtangScreen()));
      await tester.pumpAndSettle();

      double bottom(String label) => tester
          .getBottomLeft(find.ancestor(of: find.text(label), matching: find.byType(Container)).first)
          .dy;
      // "Collected today" wraps here; its tile no longer stands taller.
      expect(bottom('Collected today'), bottom('Total owed'));
      expect(bottom('Overdue'), bottom('Total owed'));
    });
  });

  testWidgets('settled customers fold away, but a search still finds them', (tester) async {
    await owing('Aling Nena', 300);
    final jose = await owing('Mang Jose', 100);
    await utang.recordPayment(customerId: jose, amount: 100, method: 'Cash');
    await pump(tester, const UtangScreen());

    expect(find.text('Settled · 1'), findsOneWidget);
    expect(find.text('Mang Jose'), findsNothing);
    await tester.tap(find.text('Settled · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Mang Jose'), findsOneWidget);
  });

  testWidgets('a payment taken in the customer panel can be undone there', (tester) async {
    final id = await owing('Aling Nena', 500);
    await pump(tester, const UtangScreen());
    await tester.tap(find.text('Aling Nena'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '200');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Record payment'));
    await tester.pumpAndSettle();

    // In the panel itself — the card behind it says the same thing.
    final panel = find.byType(BottomSheet);
    expect(find.descendant(of: panel, matching: find.text('Paid ${formatPeso(200)}')), findsOneWidget);
    expect(await balanceOf(id), 300);
    await tester.tap(find.descendant(of: panel, matching: find.text('Undo')));
    await tester.pumpAndSettle();
    expect(await balanceOf(id), 500);
  });
}
