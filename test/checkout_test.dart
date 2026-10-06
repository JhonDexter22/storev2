import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/change_breakdown.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/l10n/tr.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/checkout_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/utang_service.dart';

void main() {
  final products = ProductService();
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

  Future<void> pump(WidgetTester tester, double price) async {
    final id = await products.insertProduct(Product(
      name: 'Kopiko',
      stock: 10,
      minStock: 1,
      category: 'Drinks',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    final p = (await products.getAllProducts()).firstWhere((x) => x.id == id);
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: CheckoutScreen(lines: [CartLine(product: p, qty: 1)])));
    await tester.pumpAndSettle();
  }

  TextField cashField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first);

  group('cash received', () {
    testWidgets('reads "1,000" as a thousand', (tester) async {
      await pump(tester, 37);
      await tester.enterText(find.byType(TextField).first, '1,000');
      await tester.pump();
      expect(find.text('Cash received is less than the amount due.'), findsNothing);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('Exact shows the centavos it records', (tester) async {
      await pump(tester, 27.5);
      await tester.tap(find.text('Exact'));
      await tester.pump();
      expect(cashField(tester).controller!.text, '27.50');
    });

    testWidgets('offers the next notes up from what is due', (tester) async {
      await pump(tester, 37);
      expect(find.text('₱50'), findsOneWidget);
      expect(find.text('₱100'), findsOneWidget);
      expect(find.text('₱200'), findsOneWidget);
      expect(find.text('₱1,000'), findsNothing);
    });

    testWidgets('above a thousand, offers round amounts above it', (tester) async {
      await pump(tester, 1240);
      expect(find.text('₱1,500'), findsOneWidget);
      expect(find.text('₱2,000'), findsOneWidget);
    });
  });

  Future<List<CartLine>> items(int n, {double price = 10}) async {
    final out = <CartLine>[];
    for (var i = 1; i <= n; i++) {
      final id = await products.insertProduct(Product(
        name: 'Item $i',
        stock: 10,
        minStock: 1,
        category: 'Snacks',
        createdAt: DateTime.now().toIso8601String(),
        price: price * i,
      ));
      out.add(CartLine(
        product: (await products.getAllProducts()).firstWhere((x) => x.id == id),
        qty: 1,
      ));
    }
    return out;
  }

  Future<void> pumpLines(WidgetTester tester, List<CartLine> lines, {Size size = const Size(390, 1400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: CheckoutScreen(lines: lines)));
    await tester.pumpAndSettle();
  }

  group('the checkout screen', () {
    testWidgets('the button says what is missing until it can be pressed', (tester) async {
      await pump(tester, 37);
      expect(find.text('Enter cash received'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '20');
      await tester.pump();
      expect(find.text('Short by ₱17.00'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '50');
      await tester.pump();
      expect(find.text('Complete sale · ₱37.00'), findsOneWidget);

      await tester.tap(find.text('Utang'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a customer'), findsOneWidget);
    });

    testWidgets('prices line up on the right, however long the name', (tester) async {
      await pumpLines(tester, await items(3, price: 5));
      // ₱5.00, ₱10.00 and ₱15.00: different widths, one right edge.
      final edges = [
        for (final p in ['₱5.00', '₱10.00', '₱15.00']) tester.getTopRight(find.text(p)).dx,
      ];
      expect(edges.toSet(), hasLength(1));
    });

    testWidgets('a long basket folds on a phone, and opens on tap', (tester) async {
      await pumpLines(tester, await items(7));
      expect(find.text('Item 4'), findsOneWidget);
      expect(find.text('Item 5'), findsNothing);
      await tester.tap(find.text('+3 more items'));
      await tester.pumpAndSettle();
      expect(find.text('Item 7'), findsOneWidget);
    });

    testWidgets('one extra line is shown, not folded', (tester) async {
      await pumpLines(tester, await items(5));
      expect(find.text('Item 5'), findsOneWidget);
      expect(find.textContaining('more item'), findsNothing);
    });

    testWidgets('on a tablet the payment types fit one row of their panel', (tester) async {
      await pumpLines(tester, await items(2), size: const Size(1194, 834));
      final ys = [
        for (final t in ['Cash', 'GCash', 'Card', 'Utang']) tester.getCenter(find.text(t)).dy,
      ];
      // Within a pixel: the selected one's thicker border nudges it by half.
      // A second row would be ~80 px down.
      expect(ys.reduce(max) - ys.reduce(min), lessThan(1));
    });
  });

  group('change breakdown', () {
    List<String> pieces(double change) => [
          for (final p in changeBreakdown(change)) '${p.centavos}x${p.count}',
        ];

    test('uses the fewest bills and coins', () {
      expect(pieces(67), ['5000x1', '1000x1', '500x1', '100x2']);
      expect(pieces(1885), ['100000x1', '50000x1', '20000x1', '10000x1', '5000x1', '2000x1', '1000x1', '500x1']);
    });

    test('has no ₱2 coin, and counts centavos in 25¢', () {
      expect(pieces(22.5), ['2000x1', '100x2', '25x2']);
    });

    test('is empty when nothing is owed', () {
      expect(changeBreakdown(0), isEmpty);
    });
  });

  group('the done screen', () {
    Future<void> complete(WidgetTester tester) async {
      await tester.tap(find.textContaining('Complete sale'));
      await tester.pumpAndSettle();
    }

    testWidgets('leads with the change and the bills and coins that make it', (tester) async {
      await pump(tester, 33);
      await tester.tap(find.text('₱100'));
      await tester.pumpAndSettle();
      await complete(tester);

      expect(find.textContaining('Paid · Cash ·'), findsOneWidget);
      expect(find.text('Change to give'), findsOneWidget);
      expect(find.text('₱67.00'), findsOneWidget);
      for (final chip in ['₱50', '₱10', '₱5', '₱1 ×2']) {
        expect(find.text(chip), findsOneWidget, reason: chip);
      }
      expect(find.text('₱33.00 total · ₱100.00 received'), findsOneWidget);
      expect(find.text('1 × Kopiko'), findsOneWidget);
    });

    testWidgets('says "No change" rather than a big ₱0.00', (tester) async {
      await pump(tester, 33);
      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      await complete(tester);

      expect(find.text('No change'), findsOneWidget);
      expect(find.text('₱0.00'), findsNothing);
    });

    testWidgets('a GCash sale shows what was paid, with no change', (tester) async {
      await pump(tester, 33);
      await tester.tap(find.text('GCash'));
      await tester.pumpAndSettle();
      await complete(tester);

      expect(find.text('Paid with GCash'), findsOneWidget);
      expect(find.text('Change to give'), findsNothing);
    });

    testWidgets('a long basket folds, and opens on tap', (tester) async {
      final lines = <CartLine>[];
      for (var i = 1; i <= 7; i++) {
        final id = await products.insertProduct(Product(
          name: 'Item $i',
          stock: 10,
          minStock: 1,
          category: 'Snacks',
          createdAt: DateTime.now().toIso8601String(),
          price: 10,
        ));
        lines.add(CartLine(
          product: (await products.getAllProducts()).firstWhere((x) => x.id == id),
          qty: 1,
        ));
      }
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: CheckoutScreen(lines: lines)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      await complete(tester);

      expect(find.text('7 items'), findsOneWidget);
      expect(find.text('1 × Item 4'), findsOneWidget);
      expect(find.text('1 × Item 5'), findsNothing);
      await tester.tap(find.text('+3 more items'));
      await tester.pumpAndSettle();
      expect(find.text('1 × Item 7'), findsOneWidget);
    });
  });

  group('charging to a tab', () {
    Future<void> chooseUtang(WidgetTester tester) async {
      await tester.tap(find.text('Utang'));
      await tester.pumpAndSettle();
    }

    testWidgets('can start a tab for someone new without leaving the sale', (tester) async {
      await pump(tester, 37);
      await chooseUtang(tester);
      expect(find.text('Add their name to start a tab.'), findsOneWidget);

      await tester.tap(find.text('New customer'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Aling Nena');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text("On Aling Nena's tab"), findsOneWidget);
      expect((await utang.getCustomers()).single.name, 'Aling Nena');
    });

    testWidgets('says whose tab in Filipino too', (tester) async {
      await SettingsService.instance.setLanguage(AppLanguage.fil);
      addTearDown(() => SettingsService.instance.setLanguage(AppLanguage.en));
      await utang.addCustomer('Aling Nena');
      await pump(tester, 37);
      await chooseUtang(tester);
      await tester.tap(find.text('Aling Nena'));
      await tester.pumpAndSettle();
      expect(find.text('Nasa utang ni Aling Nena'), findsOneWidget);
    });

    testWidgets('the done screen shows where the tab now stands', (tester) async {
      final id = await utang.addCustomer('Aling Nena', creditLimit: 100);
      await utang.charge(customerId: id, amount: 80);
      await pump(tester, 37);
      await chooseUtang(tester);
      await tester.tap(find.text('Aling Nena'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Charge to utang'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Charged to utang ·'), findsOneWidget);
      expect(find.text("Added to Aling Nena's tab"), findsOneWidget);
      expect(find.text('Aling Nena now owes'), findsOneWidget);
      expect(find.text('₱117.00'), findsOneWidget);
      expect(find.text('Over the ₱100.00 limit by ₱17.00'), findsOneWidget);
    });

    testWidgets('a long book can be searched', (tester) async {
      for (final n in ['Aling Nena', 'Mang Jose', 'Ate Liza', 'Kuya Ben', 'Lola Iska', 'Tita Baby']) {
        await utang.addCustomer(n);
      }
      await pump(tester, 37);
      await chooseUtang(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Search name or number'), 'jose');
      await tester.pump();
      expect(find.text('Mang Jose'), findsOneWidget);
      expect(find.text('Aling Nena'), findsNothing);
    });
  });
}
