import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/models/stock_move.dart';
import 'package:storev2/screens/stock_history_screen.dart';
import 'package:storev2/services/export_service.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/restore_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/stock_history.dart';

void main() {
  final products = ProductService();
  final sales = SalesService();
  final history = StockHistory();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'active_cashier': 'Nena'});
    await SettingsService.instance.load();
    await DatabaseHelper.instance.clearAllData();
  });

  Future<Product> addProduct({String name = 'Kopiko', int stock = 10}) async {
    final p = Product(
      name: name,
      stock: stock,
      minStock: 3,
      category: 'Coffee',
      createdAt: DateTime.now().toIso8601String(),
      price: 8,
    );
    final id = await products.insertProduct(p);
    return p.copyWith(id: id);
  }

  Future<int> stockOf(int id) async {
    final db = await DatabaseHelper.instance.database;
    return (await db.query('products', where: 'id = ?', whereArgs: [id])).single['stock'] as int;
  }

  /// The product's history, oldest first, as kind / change / after.
  Future<List<(StockMoveKind, int, int)>> trail(int id) async => [
        for (final m in (await history.moves(productId: id)).reversed) (m.kind, m.delta, m.stockAfter),
      ];

  group('every way stock changes is logged', () {
    test('a new product logs its opening stock; one with none logs nothing', () async {
      final p = await addProduct(stock: 24);
      final empty = await addProduct(name: 'Yelo', stock: 0);

      final first = (await history.moves(productId: p.id)).single;
      expect(first.kind, StockMoveKind.added);
      expect((first.delta, first.stockAfter), (24, 24));
      expect(first.cashier, 'Nena');
      expect(first.productName, 'Kopiko');
      expect(await history.moves(productId: empty.id), isEmpty);
    });

    test('a sale logs what left, with who rang it and the receipt', () async {
      final p = await addProduct(stock: 10);
      final sale = await sales.recordSale(
          lines: [CartLine(product: p, qty: 3)], paymentMethod: 'Cash', cashier: 'May');

      final sold = (await history.moves(productId: p.id)).first;
      expect(sold.kind, StockMoveKind.sale);
      expect((sold.delta, sold.stockAfter), (-3, 7));
      expect(sold.cashier, 'May');
      expect(sold.reference, sale.reference);
      expect(sold.shortRef, startsWith('#'));
    });

    test('a sale logs what really left the shelf, never below zero', () async {
      final p = await addProduct(stock: 2);
      await sales.recordSale(lines: [CartLine(product: p, qty: 3)], paymentMethod: 'Cash');
      // Nothing left to take: no row for a change that did not happen.
      await sales.recordSale(lines: [CartLine(product: p, qty: 1)], paymentMethod: 'Cash');

      expect(await trail(p.id!), [(StockMoveKind.added, 2, 2), (StockMoveKind.sale, -2, 0)]);
    });

    test('a quick item touches no stock and logs nothing', () async {
      final quick = Product.quick(name: 'Yelo', price: 5, id: -1);
      await sales.recordSale(lines: [CartLine(product: quick, qty: 2)], paymentMethod: 'Cash');
      expect(await history.moves(), isEmpty);
    });

    test('a return to the shelf is logged against the sale; a write-off is not', () async {
      final p = await addProduct(stock: 10);
      final sale = await sales.recordSale(
          lines: [CartLine(product: p, qty: 4)], paymentMethod: 'Cash', cashier: 'May');
      await sales.recordRefund(
          sale: sale, lines: {p.id!: 1}, reason: 'Changed mind', method: 'Cash',
          restock: true, isVoid: false, cashier: 'Nena');
      await sales.recordRefund(
          sale: sale, lines: {p.id!: 1}, reason: 'Damaged', method: 'Cash', restock: false, isVoid: false);

      final back = (await history.moves(productId: p.id)).first;
      expect(back.kind, StockMoveKind.returned);
      expect((back.delta, back.stockAfter), (1, 7));
      expect(back.reference, sale.reference);
      expect(back.cashier, 'Nena');
      expect((await history.moves(productId: p.id)).length, 3, reason: 'new, sold, returned');
    });

    test('a restock and its Undo are both kept', () async {
      final p = await addProduct(stock: 5);
      await products.addStock(p.id!, 24);
      await products.addStock(p.id!, -24, kind: StockMoveKind.undo);

      expect(await trail(p.id!), [
        (StockMoveKind.added, 5, 5),
        (StockMoveKind.restock, 24, 29),
        (StockMoveKind.undo, -24, 5),
      ]);
    });

    test('Stock in logs each product, and lands whole', () async {
      final a = await addProduct(name: 'Kopiko', stock: 1);
      final b = await addProduct(name: 'SkyFlakes', stock: 0);
      await products.addStockBatch({a.id!: 12, b.id!: 6});

      final ins = await history.moves(kinds: {StockMoveKind.stockIn});
      expect({for (final m in ins) m.productName: (m.delta, m.stockAfter)},
          {'Kopiko': (12, 13), 'SkyFlakes': (6, 6)});
    });

    test('a count typed in by hand logs the difference, and only a real one', () async {
      final p = await addProduct(stock: 10);
      await products.updateStock(p.id!, 7);
      await products.updateStock(p.id!, 7);

      final byHand = await history.moves(productId: p.id, kinds: {StockMoveKind.count});
      expect(byHand.map((m) => (m.delta, m.stockAfter)), [(-3, 7)]);
      expect(byHand.single.kind.byHand, isTrue);
    });

    test('saving a product\'s details leaves stock alone', () async {
      final p = await addProduct(stock: 10);
      // A sale lands after the Products screen loaded its copy at 10.
      await sales.recordSale(lines: [CartLine(product: p, qty: 4)], paymentMethod: 'Cash');
      await products.updateProduct(p.copyWith(imagePath: '/photos/kopiko.jpg'));

      expect(await stockOf(p.id!), 6, reason: 'the stale 10 must not come back');
      expect((await history.moves(productId: p.id)).length, 2, reason: 'new and sold only');
    });

    test('deleting keeps the history; Undo puts the product and its stock back', () async {
      final p = await addProduct(stock: 9);
      await products.deleteProduct(p.id!);

      final gone = (await history.moves()).first;
      expect(gone.kind, StockMoveKind.deleted);
      expect((gone.delta, gone.stockAfter), (-9, 0));
      expect(gone.productName, 'Kopiko');

      await products.restoreDeleted(p);
      expect(await stockOf(p.id!), 9);
      expect(await trail(p.id!), [
        (StockMoveKind.added, 9, 9),
        (StockMoveKind.deleted, -9, 0),
        (StockMoveKind.undo, 9, 9),
      ]);
    });
  });

  group('reading it back', () {
    test('newest first, by product, by kind, a page at a time', () async {
      final a = await addProduct(name: 'Kopiko', stock: 50);
      final b = await addProduct(name: 'SkyFlakes', stock: 50);
      for (var i = 0; i < 3; i++) {
        await sales.recordSale(
            lines: [CartLine(product: a, qty: 1), CartLine(product: b, qty: 2)],
            paymentMethod: 'Cash');
      }

      final all = await history.moves();
      expect(all.length, 8);
      expect(all.first.id! > all.last.id!, isTrue);
      expect((await history.moves(productId: b.id)).every((m) => m.productId == b.id), isTrue);
      expect((await history.moves(kinds: {StockMoveKind.sale})).length, 6);
      expect((await history.moves(limit: 5)).length, 5);
      expect((await history.moves(limit: 5, offset: 5)).length, 3);
    });
  });

  group('backups', () {
    test('carry the stock history', () async {
      final p = await addProduct(stock: 4);
      await products.addStock(p.id!, 6);
      final files = {for (final f in await ExportService().buildAll()) f.name: f.csv};
      expect(files.keys, contains('stock_moves.csv'));

      await DatabaseHelper.instance.clearAllData();
      await RestoreService().restore(files);
      expect(await trail(p.id!), [(StockMoveKind.added, 4, 4), (StockMoveKind.restock, 6, 10)]);
    });

    test('one from before the history restores without a warning, and empties it', () async {
      final p = await addProduct(stock: 4);
      final files = {for (final f in await ExportService().buildAll()) f.name: f.csv}
        ..remove('stock_moves.csv');
      await products.addStock(p.id!, 6);

      final preview = await RestoreService().inspect(files);
      expect(preview.warnings.where((w) => w.contains('stock_moves')), isEmpty);
      await RestoreService().restore(files);
      expect(await history.moves(), isEmpty);
    });
  });

  group('the screen', () {
    Future<void> open(WidgetTester tester, {Product? product}) async {
      await tester.pumpWidget(MaterialApp(home: StockHistoryScreen(product: product)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    testWidgets('a product\'s history says what, how many, what was left and who', (tester) async {
      late Product p;
      await tester.runAsync(() async {
        p = await addProduct(stock: 10);
        await sales.recordSale(
            lines: [CartLine(product: p, qty: 2)], paymentMethod: 'Cash', cashier: 'May');
        await products.updateStock(p.id!, 5);
      });
      await open(tester, product: p);

      expect(find.text('Stock history'), findsOneWidget);
      expect(find.text('Kopiko'), findsOneWidget, reason: 'the product, in the header');
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Sold'), findsOneWidget);
      expect(find.text('−2'), findsOneWidget);
      expect(find.text('8 in stock'), findsOneWidget);
      expect(find.textContaining('May · '), findsOneWidget);
      expect(find.text('Changed by hand'), findsOneWidget);
      expect(find.text('−3'), findsOneWidget);
      expect(find.text('New product'), findsOneWidget);
      expect(find.text('+10'), findsOneWidget);
    });

    testWidgets('the store-wide log names products and filters to changes by hand', (tester) async {
      await tester.runAsync(() async {
        final a = await addProduct(name: 'Kopiko', stock: 10);
        await addProduct(name: 'SkyFlakes', stock: 4);
        await products.updateStock(a.id!, 6);
      });
      await open(tester);

      expect(find.text('Every product'), findsOneWidget);
      expect(find.text('SkyFlakes'), findsOneWidget);

      await tester.tap(find.text('By hand'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('SkyFlakes'), findsNothing);
      expect(find.text('Kopiko'), findsOneWidget);
      expect(find.textContaining('Changed by hand'), findsOneWidget);

      await tester.tap(find.text('Returns'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet'), findsOneWidget);
    });
  });
}
