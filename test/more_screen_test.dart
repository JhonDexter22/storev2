import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/design_tokens.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/l10n/tr.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/settings_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/utang_service.dart';

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

  Future<void> sell(double price, {String method = 'Cash'}) async {
    final id = await products.insertProduct(Product(
      name: 'Item ${DateTime.now().microsecondsSinceEpoch}',
      stock: 10,
      minStock: 1,
      category: 'Snacks',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    final p = (await products.getAllProducts()).firstWhere((x) => x.id == id);
    await sales.recordSale(lines: [CartLine(product: p, qty: 1)], paymentMethod: method);
  }

  /// A big balance and a cash sale: the widest figures these rows carry.
  Future<void> sellForUtangAndCash() async {
    await sell(2855);
    final utang = UtangService();
    final id = await utang.addCustomer('Aling Nena');
    await utang.charge(customerId: id, amount: 223007);
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
  }

  String drawer(double cash) => formatPeso(SettingsService.instance.openingFloat + cash);

  group('the Cash count figure', () {
    testWidgets('is the cash expected in the drawer, not all sales', (tester) async {
      await sell(50);
      await sell(200, method: 'GCash');
      await pump(tester);

      expect(find.text(drawer(50)), findsOneWidget);
      expect(find.text(formatPeso(250)), findsNothing);
    });

    testWidgets('is fresh after coming back from a row', (tester) async {
      await pump(tester);
      expect(find.text(drawer(0)), findsOneWidget);

      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      await sell(40);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(find.text(drawer(40)), findsOneWidget);
    });
  });

  testWidgets('the rows speak plainly, under a heading that fits them', (tester) async {
    await pump(tester);
    expect(find.text('MONEY'), findsOneWidget);
    expect(find.text('TODAY'), findsNothing);
    expect(find.text('Count and close the day'), findsOneWidget);
    expect(find.textContaining('reconciliation'), findsNothing);
    expect(find.textContaining('variance'), findsNothing);
  });

  testWidgets('the day is closed from a row called Close day, as on Home', (tester) async {
    await pump(tester);
    expect(find.text('Close day'), findsOneWidget);
    expect(find.text('Cash count'), findsNothing);
  });

  testWidgets('the cashier card names the store and the day, not a terminal', (tester) async {
    await pump(tester);
    expect(find.textContaining('Sari-Sari Store · '), findsOneWidget);
    expect(find.textContaining('Terminal'), findsNothing);
  });

  testWidgets('a tablet puts the menu in two columns, Lock till on screen', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    final reports = tester.getTopLeft(find.text('Reports'));
    final returns = tester.getTopLeft(find.text('Returns & voids'));
    expect(returns.dx, greaterThan(reports.dx + 300));
    expect(returns.dy, closeTo(reports.dy, 1));
    expect(tester.getBottomLeft(find.text('Lock till')).dy, lessThan(800));
  });

  testWidgets('Staff opens straight onto Manage staff', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();
    // The sheet's title, over the screen's own Manage staff button.
    expect(find.text('Manage staff'), findsNWidgets(2));
  });

  testWidgets('the till is locked from a row, which says what it does', (tester) async {
    await pump(tester);
    expect(find.text('Sign out'), findsNothing);
    expect(find.text('A code is needed to sell again'), findsOneWidget);

    await tester.tap(find.text('Lock till'));
    await tester.pumpAndSettle();
    expect(find.text('Lock the till?'), findsOneWidget);
    expect(find.text('Lock'), findsOneWidget);
  });

  for (final lang in AppLanguage.values) {
    testWidgets('descriptions fit beside their figures on a small phone, in ${lang.name}',
        (tester) async {
      // A day with cash and someone owing, so both rows carry a figure.
      await sellForUtangAndCash();
      await SettingsService.instance.setLanguage(lang);
      addTearDown(() => SettingsService.instance.setLanguage(AppLanguage.en));
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();

      for (final text in ['Count and close the day', 'Past days and drawer checks', 'Who owes, oldest first']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(tr(text)));
        expect(paragraph.didExceedMaxLines, isFalse, reason: '"${tr(text)}" is cut off');
      }
    });
  }
}
