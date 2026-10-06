import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/design_tokens.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/pos_screen.dart';
import 'package:storev2/services/held_sales.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/widgets/product_card.dart';
import 'package:storev2/widgets/product_thumb.dart';

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

  Future<void> seed(String name, {int stock = 20, int minStock = 5, String? imagePath}) =>
      products.insertProduct(Product(
        name: name,
        stock: stock,
        minStock: minStock,
        category: 'Snacks',
        createdAt: DateTime.now().toIso8601String(),
        price: 10,
        imagePath: imagePath,
      ));

  Future<void> pump(WidgetTester tester, {double textScale = 1.0}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: PosScreen(key: UniqueKey()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('search', () {
    testWidgets('has a clear button', (tester) async {
      await seed('Kopiko');
      await seed('SkyFlakes');
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'kop');
      await tester.pump();
      expect(find.text('SkyFlakes'), findsNothing);

      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(find.text('SkyFlakes'), findsOneWidget);
    });

    testWidgets('is empty again for the next customer', (tester) async {
      await seed('Kopiko');
      await seed('SkyFlakes');
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'kop');
      await tester.pump();
      await tester.tap(find.text('Kopiko'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exact'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Complete sale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New sale'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
      expect(find.text('SkyFlakes'), findsOneWidget);
    });

    testWidgets('no match says what was searched, and clears in one tap', (tester) async {
      await seed('Kopiko');
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'yelo');
      await tester.pump();
      expect(find.text('No match for "yelo"'), findsOneWidget);

      await tester.tap(find.text('Clear search'));
      await tester.pump();
      expect(find.text('Kopiko'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('Repeat last sale steps aside while searching', (tester) async {
      await seed('Kopiko');
      final p = (await products.getAllProducts()).single;
      await sales.recordSale(lines: [CartLine(product: p, qty: 1)], paymentMethod: 'Cash', cashReceived: 10);
      await pump(tester);
      expect(find.text('Repeat last sale'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'kop');
      await tester.pump();
      expect(find.text('Repeat last sale'), findsNothing);

      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(find.text('Repeat last sale'), findsOneWidget);
    });
  });

  testWidgets('bringing back the last held sale stays on the till', (tester) async {
    HeldSales.instance.reset();
    addTearDown(HeldSales.instance.reset);
    await seed('Kopiko');
    await pump(tester);
    await tester.tap(find.text('Kopiko'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hold'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Held'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kopiko').last);
    await tester.pumpAndSettle();

    // The sheet emptied as it closed, and its "close when empty" used to pop
    // the route underneath it — the till — leaving a blank screen.
    expect(find.byType(PosScreen), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
  });

  testWidgets('products are A–Z with out of stock last', (tester) async {
    await seed('Zesto');
    await seed('Biscocho', stock: 0);
    await seed('Argentina corned beef');
    await pump(tester);

    final y = [
      for (final name in ['Argentina corned beef', 'Zesto', 'Biscocho'])
        tester.getTopLeft(find.text(name)).dy + tester.getTopLeft(find.text(name)).dx / 1000,
    ];
    expect(y, orderedEquals([...y]..sort()));
  });

  group('tiles', () {
    testWidgets('six fit on a phone when products have no photos', (tester) async {
      const names = ['Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot'];
      for (final n in names) {
        await seed(n);
      }
      await pump(tester);
      for (final n in names) {
        expect(find.text(n).hitTestable(), findsOneWidget, reason: n);
      }
    });

    testWidgets('do not clip with larger text', (tester) async {
      await seed('Instant noodles, beef, sachet');
      await pump(tester, textScale: 1.3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('show a photo as a square, not a sliver', (tester) async {
      await seed('Sardines, family size', imagePath: 'missing.jpg');
      await seed('Sardines, large');
      await seed('Sardines, medium');
      await pump(tester);
      final thumb = tester.getSize(find.descendant(
          of: find.ancestor(of: find.text('Sardines, family size'), matching: find.byType(ProductCard)),
          matching: find.byType(ProductThumb)).last);
      expect(thumb.width, thumb.height);
      expect(thumb.width, lessThan(60));
    });

    testWidgets('stay tall once most products have photos', (tester) async {
      await seed('Alpha', imagePath: 'missing-a.jpg');
      await seed('Bravo', imagePath: 'missing-b.jpg');
      await seed('Charlie');
      await pump(tester);
      final card = tester.getSize(find.ancestor(
              of: find.text('Alpha'), matching: find.byType(GestureDetector))
          .first);
      expect(card.height, greaterThan(200));
    });
  });

  testWidgets('low stock is not badged at the till; out of stock still is',
      (tester) async {
    await seed('Kopiko', stock: 2);
    await seed('Zesto', stock: 0);
    await pump(tester);
    expect(find.text('Low stock'), findsNothing);
    expect(find.text('Out of stock'), findsOneWidget);
  });

  group('tiles without a photo', () {
    test('take a colour from their category, the same every time', () {
      expect(CategoryTint.of('Noodles'), same(CategoryTint.of(' noodles ')));
      // Never a status colour, so a tint does not read as "out" or "low".
      for (final c in ['Noodles', 'Drinks', 'Biscuit', 'Canned goods', 'Snacks', 'Household']) {
        final fill = CategoryTint.of(c).fill;
        expect([AppColors.dangerFill, AppColors.warningFill, AppColors.successFill], isNot(contains(fill)));
      }
    });

    testWidgets('leave the category line to the colour', (tester) async {
      await seed('Kopiko');
      await pump(tester);
      // Only the filter chip says "Snacks" now.
      expect(find.text('Snacks'), findsOneWidget);
    });

    testWidgets('count healthy stock in grey, low in amber', (tester) async {
      await seed('Kopiko', stock: 20);
      await seed('Zesto', stock: 2);
      await pump(tester);
      expect(tester.widget<Text>(find.text('20 left')).style!.color, AppColors.muted);
      expect(tester.widget<Text>(find.text('2 left')).style!.color, AppColors.warningText);
    });
  });

  testWidgets('a best seller that is out of stock waits at the end of Popular',
      (tester) async {
    await seed('Kopiko', stock: 3);
    await seed('Zesto');
    await seed('SkyFlakes');
    final all = await products.getAllProducts();
    Product named(String n) => all.firstWhere((p) => p.name == n);
    // Kopiko outsells both and sells out doing it.
    for (var i = 0; i < 3; i++) {
      await sales.recordSale(lines: [CartLine(product: named('Kopiko'), qty: 1)], paymentMethod: 'Cash');
    }
    await sales.recordSale(lines: [CartLine(product: named('Zesto'), qty: 1)], paymentMethod: 'Cash');
    await sales.recordSale(lines: [CartLine(product: named('SkyFlakes'), qty: 1)], paymentMethod: 'Cash');

    await pump(tester);
    await tester.tap(find.text('Popular'));
    await tester.pumpAndSettle();

    // Within the grid: the last sale's pill also names a product.
    double at(String n) {
      final pos = tester.getTopLeft(find.descendant(of: find.byType(GridView), matching: find.text(n)));
      return pos.dy * 1000 + pos.dx;
    }

    expect(at('Kopiko'), greaterThan(at('Zesto')));
    expect(at('Kopiko'), greaterThan(at('SkyFlakes')));
  });

  testWidgets('the quantity badge opens the quantity picker', (tester) async {
    await seed('Kopiko');
    await pump(tester);
    await tester.tap(find.text('Kopiko'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('qty-badge')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 in cart'), findsOneWidget);
  });

  group('scanning', () {
    final kopiko = Product(id: 7, name: 'Kopiko', stock: 2, minStock: 1, category: 'Drinks', createdAt: '', price: 12);

    test('never takes the cart past what is on the shelf', () {
      // Two already rung up, two in stock: a third scan adds nothing.
      final r = addScannedToCart({7: 2}, {7: 1}, [kopiko]);
      expect(r.cart[7], 2);
      expect(r.short, same(kopiko));
    });

    test('adds what there is room for', () {
      final r = addScannedToCart({7: 1}, {7: 3}, [kopiko]);
      expect(r.cart[7], 2);
      expect(r.short, same(kopiko));
    });

    test('says nothing when it all fits', () {
      final r = addScannedToCart({}, {7: 2}, [kopiko]);
      expect(r.cart[7], 2);
      expect(r.short, isNull);
    });
  });

  testWidgets('clearing the sale can be undone', (tester) async {
    await seed('Kopiko');
    await seed('Zesto');
    await pump(tester);
    await tester.tap(find.text('Kopiko'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zesto'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2 items'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('2 items'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('the backup pill starts a backup when tapped', (tester) async {
    await seed('Kopiko');
    await pump(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('No backup'));
    await tester.pump();
    // The export itself needs the phone's file system and share sheet, which
    // a widget test does not have; that the pill answers is the point.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
