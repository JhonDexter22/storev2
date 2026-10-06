import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/core/design_tokens.dart';
import 'package:storev2/screens/product_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/widgets/product_card.dart';
import 'package:storev2/widgets/product_thumb.dart';

void main() {
  final products = ProductService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    final db = await DatabaseHelper.instance.database;
    await db.delete('products');
  });

  Future<void> seed({String name = 'SkyFlakes', String? sku, String category = 'Biscuit', int stock = 50}) =>
      products.insertProduct(Product(
        name: name,
        stock: stock,
        minStock: 5,
        category: category,
        createdAt: DateTime.now().toIso8601String(),
        price: 10,
        sku: sku,
      ));

  /// A phone-sized screen with the New product sheet open.
  Future<void> openNewProduct(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ProductsScreen(key: UniqueKey())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  Finder field(String hint) => find.widgetWithText(TextFormField, hint);

  Future<void> fill(WidgetTester tester,
      {String name = 'Kopiko', String category = 'Drinks', String price = '12', String? sku}) async {
    await tester.enterText(field('e.g. SkyFlakes'), name);
    await tester.enterText(field('e.g. Biscuits'), category);
    await tester.enterText(field('0.00'), price);
    if (sku != null) await tester.enterText(field('Optional'), sku);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save product'));
    await tester.pumpAndSettle();
  }

  testWidgets('Save is on screen without scrolling the form', (tester) async {
    await openNewProduct(tester);
    expect(find.text('Save product').hitTestable(), findsOneWidget);
  });

  testWidgets('a price of zero is refused', (tester) async {
    await openNewProduct(tester);
    await fill(tester, price: '0');
    await save(tester);

    expect(find.text('Price must be more than ₱0'), findsOneWidget);
    expect(await products.getAllProducts(), isEmpty);
  });

  testWidgets('a barcode already on another product is refused', (tester) async {
    await seed(sku: '4800016');
    await openNewProduct(tester);
    await fill(tester, sku: '4800016');
    await save(tester);

    expect(find.text('Already used by SkyFlakes'), findsOneWidget);
    expect((await products.getAllProducts()).length, 1);
  });

  testWidgets('editing a product keeps its own barcode', (tester) async {
    await seed(sku: '4800016');
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ProductsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SkyFlakes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Already used by'), findsNothing);
    expect(find.text('Save changes'), findsNothing);
  });

  group('closing the sheet', () {
    testWidgets('an untouched form closes without asking', (tester) async {
      await openNewProduct(tester);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('New product'), findsNothing);
    });

    testWidgets('a filled-in form asks first', (tester) async {
      await openNewProduct(tester);
      await tester.enterText(field('e.g. SkyFlakes'), 'Kopiko');
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('New product'), findsOneWidget);
      expect(find.text('Kopiko'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('New product'), findsNothing);
    });
  });

  group('the restock warning', () {
    Finder warning() =>
        find.text('Stock is at or below the minimum — this product will show in Restock.');

    testWidgets('is not shown on a blank form', (tester) async {
      await openNewProduct(tester);
      expect(warning(), findsNothing);
    });

    testWidgets('appears once stock is set at or under the minimum', (tester) async {
      await openNewProduct(tester);
      final form = find
          .descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.text('Current stock'), 200, scrollable: form);
      final plus = find.descendant(
          of: find.ancestor(of: find.text('Current stock'), matching: find.byType(Row)).first,
          matching: find.byIcon(Icons.add_rounded));
      await tester.tap(plus);
      await tester.pump();
      await tester.scrollUntilVisible(warning(), 200, scrollable: form);
      expect(warning(), findsOneWidget);
    });
  });

  group('products without a photo', () {
    test('show initials that tell neighbours apart', () {
      expect(PhotoPlaceholder.initialsOf('Candy, small'), 'CS');
      expect(PhotoPlaceholder.initialsOf('Candy, large'), 'CL');
      expect(PhotoPlaceholder.initialsOf('3-in-1 coffee, 6s'), '36');
      // The variant after the comma, not the second word: these were all SI.
      expect(PhotoPlaceholder.initialsOf('Sardines in tomato sauce, large'), 'SL');
      expect(PhotoPlaceholder.initialsOf('Sardines in tomato sauce, medium'), 'SM');
      expect(PhotoPlaceholder.initialsOf('Sardines in tomato sauce, twin pack'), 'ST');
      expect(PhotoPlaceholder.initialsOf('Instant mami'), 'IM');
      expect(PhotoPlaceholder.initialsOf('SkyFlakes'), 'S');
      expect(PhotoPlaceholder.initialsOf('  '), '');
    });

    testWidgets('never show the word "photo"', (tester) async {
      await seed();
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ProductsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('photo'), findsNothing);
      expect(find.text('S'), findsOneWidget);
    });
  });

  group('the grid card', () {
    Widget card(int stock) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              height: 180 / ProductCard.aspectRatio,
              child: ProductCard(
                product: Product(
                  name: 'Kopiko',
                  stock: stock,
                  minStock: 5,
                  category: 'Drinks',
                  createdAt: '2026-09-30',
                  price: 12,
                ),
                onTap: () {},
              ),
            ),
          ),
        );

    testWidgets('says nothing when stock is fine', (tester) async {
      await tester.pumpWidget(card(40));
      expect(find.text('In stock'), findsNothing);
    });

    testWidgets('flags low and out', (tester) async {
      await tester.pumpWidget(card(3));
      expect(find.text('Low stock'), findsOneWidget);
      await tester.pumpWidget(card(0));
      expect(find.text('Out of stock'), findsOneWidget);
    });
  });

  group('categories', () {
    testWidgets('an existing one is a tap away', (tester) async {
      await seed();
      await openNewProduct(tester);
      await tester.tap(find.text('Biscuit'));
      await tester.pump();

      final category = tester.widget<TextFormField>(find.byType(TextFormField).at(2));
      expect(category.controller!.text, 'Biscuit');
    });

    testWidgets('a different case joins the existing one', (tester) async {
      await seed();
      await openNewProduct(tester);
      await fill(tester, category: 'biscuit');
      await save(tester);

      final saved = (await products.getAllProducts()).firstWhere((p) => p.name == 'Kopiko');
      expect(saved.category, 'Biscuit');
    });
  });

  group('stock that leaves without a sale', () {
    Future<void> openEdit(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ProductsScreen(key: UniqueKey())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SkyFlakes'));
      await tester.pumpAndSettle();
    }

    Future<void> step(WidgetTester tester, IconData icon) async {
      final form = find
          .descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.text('Current stock'), 200, scrollable: form);
      final row = find.ancestor(of: find.text('Current stock'), matching: find.byType(Row)).first;
      await tester.tap(find.descendant(of: row, matching: find.byIcon(icon)));
      await tester.pump();
    }

    testWidgets('lowering it in the edit sheet asks for the manager', (tester) async {
      await seed();
      await openEdit(tester);
      await step(tester, Icons.remove_rounded);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Manager PIN'), findsOneWidget);
      expect((await products.getAllProducts()).single.stock, 50);
    });

    testWidgets('raising it does not', (tester) async {
      await seed();
      await openEdit(tester);
      await step(tester, Icons.add_rounded);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Manager PIN'), findsNothing);
      expect((await products.getAllProducts()).single.stock, 51);
    });

    testWidgets('deleting a product that still has stock asks for the manager', (tester) async {
      await seed();
      await openEdit(tester);
      final form = find
          .descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.text('Delete product'), 200, scrollable: form);
      await tester.tap(find.text('Delete product'));
      await tester.pumpAndSettle();
      expect(find.text('Manager PIN'), findsOneWidget);
      expect(await products.getAllProducts(), isNotEmpty);
    });

    testWidgets('an empty product deletes without one', (tester) async {
      await seed(stock: 0);
      await openEdit(tester);
      final form = find
          .descendant(of: find.byType(SingleChildScrollView), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.text('Delete product'), 200, scrollable: form);
      await tester.tap(find.text('Delete product'));
      await tester.pumpAndSettle();
      expect(find.text('Manager PIN'), findsNothing);
      expect(await products.getAllProducts(), isEmpty);
    });
  });

  testWidgets('the header counts products, not units', (tester) async {
    await seed(); // 50 at ₱10
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ProductsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('1 product · ₱500.00 on hand'), findsOneWidget);
  });

  group('the list', () {
    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: ProductsScreen(key: UniqueKey())));
      await tester.pumpAndSettle();
    }

    testWidgets('a stock bar only once stock dips under twice the minimum', (tester) async {
      await seed(name: 'Healthy', stock: 50); // min 5: comfortable
      await seed(name: 'Thinning', stock: 8); // under 10, not yet low
      await seed(name: 'Low', stock: 3);
      await pumpAt(tester, const Size(390, 800));

      Finder bar(String name) => find.descendant(
            of: find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first,
            matching: find.byType(FractionallySizedBox),
          );
      expect(bar('Healthy'), findsNothing);
      expect(bar('Thinning'), findsOneWidget);
      expect(bar('Low'), findsOneWidget);
    });

    testWidgets('a name that needs attention gets two lines', (tester) async {
      await seed(name: 'Argentina Corned Beef Big 260g', stock: 2);
      await seed(name: 'SkyFlakes', stock: 50);
      await pumpAt(tester, const Size(390, 800));
      expect(tester.widget<Text>(find.text('Argentina Corned Beef Big 260g')).maxLines, 2);
      expect(tester.widget<Text>(find.text('SkyFlakes')).maxLines, 1);
    });

    testWidgets('a tablet shows two rows side by side', (tester) async {
      for (final n in ['Alpha', 'Bravo', 'Charlie']) {
        await seed(name: n);
      }
      await pumpAt(tester, const Size(1194, 834));
      final a = tester.getTopLeft(find.text('Alpha'));
      final b = tester.getTopLeft(find.text('Bravo'));
      expect(b.dy, a.dy);
      expect(b.dx, greaterThan(a.dx + 300));
      // An odd one out sits alone on the next line, at the left.
      expect(tester.getTopLeft(find.text('Charlie')).dx, a.dx);
    });
  });

  testWidgets('the price field shows ₱ before anything is typed', (tester) async {
    await openNewProduct(tester);
    expect(find.descendant(of: field('0.00'), matching: find.text('₱')), findsOneWidget);
  });

  test('a product without a photo wears its category colour by default', () {
    final thumb = ProductThumb(
      product: Product(name: 'Kopiko', stock: 1, minStock: 1, category: 'Drinks', createdAt: '', price: 1),
    );
    expect(thumb.tinted, isTrue);
  });
}
