import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/shift_service.dart';

void main() {
  final sales = SalesService();
  final shifts = ShiftService();
  final products = ProductService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Each suite gets its own in-memory store; sharing one file makes
    // suites clobber each other when they run in parallel.
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('refund_items');
    await db.delete('refunds');
    await db.delete('sale_items');
    await db.delete('sales');
    await db.delete('shifts');
    await db.delete('products');
  });

  Future<Product> addProduct({
    String name = 'SkyFlakes',
    double price = 10,
    int stock = 20,
    int minStock = 5,
  }) async {
    final id = await products.insertProduct(Product(
      name: name,
      stock: stock,
      minStock: minStock,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    return Product(
      id: id,
      name: name,
      stock: stock,
      minStock: minStock,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    );
  }

  Future<int> stockOf(int id) async {
    final db = await DatabaseHelper.instance.database;
    final r = await db.query('products', columns: ['stock'], where: 'id = ?', whereArgs: [id]);
    return r.first['stock'] as int;
  }

  group('recordSale', () {
    test('writes the sale with a reference tied to its id', () async {
      final p = await addProduct(price: 12.5, stock: 10);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
        cashReceived: 50,
        changeAmount: 25,
      );

      expect(sale.total, closeTo(25, 0.001));
      expect(sale.subtotal, closeTo(25, 0.001));
      expect(sale.itemCount, 2);
      expect(sale.paymentMethod, 'Cash');
      expect(sale.cashReceived, closeTo(50, 0.001));
      expect(sale.changeAmount, closeTo(25, 0.001));
      expect(sale.reference, endsWith(sale.id!.toString().padLeft(4, '0')));
      expect(sale.reference, startsWith('S'));
    });

    test('snapshots the unit price onto the line', () async {
      final p = await addProduct(price: 12.5, stock: 10);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
      );

      final items = await sales.getSaleItems(sale.id!);
      expect(items, hasLength(1));
      expect(items.first.unitPrice, closeTo(12.5, 0.001));
      expect(items.first.qty, 2);
      expect(items.first.lineTotal, closeTo(25, 0.001));
    });

    test('decrements stock by the quantity sold', () async {
      final p = await addProduct(stock: 10);
      await sales.recordSale(lines: [CartLine(product: p, qty: 3)], paymentMethod: 'Cash');
      expect(await stockOf(p.id!), 7);
    });

    test('never drives stock negative', () async {
      final p = await addProduct(stock: 2);
      await sales.recordSale(lines: [CartLine(product: p, qty: 5)], paymentMethod: 'Cash');
      expect(await stockOf(p.id!), 0);
    });

    test('a credit sale records no cash tendered', () async {
      final p = await addProduct(price: 40, stock: 5);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 1)],
        paymentMethod: 'Utang',
      );
      expect(sale.cashReceived, 0);
      expect(sale.changeAmount, 0);
      expect(sale.total, closeTo(40, 0.001));
    });

    test('stock is decremented relative to the database, not the loaded copy',
        () async {
      // POS loads the catalogue at stock 10...
      final loaded = await addProduct(stock: 10);

      // ...then stock moves underneath it (a restock, or a return going back on
      // the shelf) before the cashier finishes the sale.
      final db = await DatabaseHelper.instance.database;
      await db.rawUpdate('UPDATE products SET stock = stock + 5 WHERE id = ?', [loaded.id]);
      expect(await stockOf(loaded.id!), 15);

      // Selling 2 must leave 13. Computing 10 - 2 from the stale copy would
      // write 8 and silently destroy the 5 units that arrived in between.
      await sales.recordSale(lines: [CartLine(product: loaded, qty: 2)], paymentMethod: 'Cash');

      expect(await stockOf(loaded.id!), 13);
    });
  });

  group('addStock', () {
    test('adds relative to the database, surviving a concurrent sale', () async {
      final loaded = await addProduct(stock: 10);

      // A sale is rung while the restock sheet is open.
      await sales.recordSale(lines: [CartLine(product: loaded, qty: 4)], paymentMethod: 'Cash');
      expect(await stockOf(loaded.id!), 6);

      // Restocking 5 must land on 11, not on the stale 10 + 5 = 15.
      await products.addStock(loaded.id!, 5);

      expect(await stockOf(loaded.id!), 11);
    });

    test('clamps at zero', () async {
      final p = await addProduct(stock: 3);
      await products.addStock(p.id!, -10);
      expect(await stockOf(p.id!), 0);
    });
  });

  group('recordRefund', () {
    test('refunds at the price the item sold for, not the current price',
        () async {
      final p = await addProduct(price: 10, stock: 10);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
      );

      // The shelf price changes after the sale.
      await products.updateProduct(Product(
        id: p.id,
        name: p.name,
        stock: 8,
        minStock: p.minStock,
        category: p.category,
        createdAt: p.createdAt,
        price: 99,
      ));

      final refund = await sales.recordRefund(
        sale: sale,
        lines: {p.id!: 2},
        reason: 'Damaged',
        method: 'Cash',
        restock: false,
        isVoid: true,
      );

      expect(refund.amount, closeTo(20, 0.001),
          reason: 'the customer paid 10 each, so 20 comes back');
    });

    test('returning to stock raises stock; writing off does not', () async {
      final p = await addProduct(stock: 10);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 4)],
        paymentMethod: 'Cash',
      );
      expect(await stockOf(p.id!), 6);

      await sales.recordRefund(
        sale: sale,
        lines: {p.id!: 1},
        reason: 'Damaged',
        method: 'Cash',
        restock: false,
        isVoid: false,
      );
      expect(await stockOf(p.id!), 6, reason: 'written off, stock unchanged');

      await sales.recordRefund(
        sale: sale,
        lines: {p.id!: 2},
        reason: 'Wrong item',
        method: 'Cash',
        restock: true,
        isVoid: false,
      );
      expect(await stockOf(p.id!), 8, reason: 'two units back on the shelf');
    });

    test('only the selected lines are refunded', () async {
      final a = await addProduct(name: 'A', price: 10, stock: 10);
      final b = await addProduct(name: 'B', price: 30, stock: 10);
      final sale = await sales.recordSale(
        lines: [CartLine(product: a, qty: 2), CartLine(product: b, qty: 1)],
        paymentMethod: 'Cash',
      );

      final refund = await sales.recordRefund(
        sale: sale,
        lines: {b.id!: 1},
        reason: 'Expired',
        method: 'Cash',
        restock: true,
        isVoid: false,
      );

      expect(refund.amount, closeTo(30, 0.001));
      expect(await stockOf(a.id!), 8, reason: 'A was not returned');
      expect(await stockOf(b.id!), 10, reason: 'B came back');
    });

    test('a line cannot be returned twice', () async {
      final p = await addProduct(stock: 10);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 3)],
        paymentMethod: 'Cash',
      );

      await sales.recordRefund(
        sale: sale,
        lines: {p.id!: 2},
        reason: 'Damaged',
        method: 'Cash',
        restock: true,
        isVoid: false,
      );

      final remaining = await sales.getReturnableLines(sale.id!);
      expect(remaining.first.alreadyReturned, 2);
      expect(remaining.first.returnable, 1,
          reason: 'only the third unit is still returnable');
    });

    test('the void flag is persisted', () async {
      final p = await addProduct(stock: 10);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 1)],
        paymentMethod: 'Cash',
      );
      final refund = await sales.recordRefund(
        sale: sale,
        lines: {p.id!: 1},
        reason: 'Changed mind',
        method: 'Cash',
        restock: true,
        isVoid: true,
      );
      expect(refund.isVoid, isTrue);
      expect(refund.restocked, isTrue);
    });
  });

  group('cashSalesToday', () {
    test('counts cash in and nets off cash refunds', () async {
      final p = await addProduct(price: 100, stock: 20);
      final cashSale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
      );
      await sales.recordSale(lines: [CartLine(product: p, qty: 1)], paymentMethod: 'GCash');

      expect(await sales.cashSalesToday(), closeTo(200, 0.001),
          reason: 'only the cash sale lands in the drawer');

      await sales.recordRefund(
        sale: cashSale,
        lines: {p.id!: 1},
        reason: 'Damaged',
        method: 'Cash',
        restock: true,
        isVoid: false,
      );

      expect(await sales.cashSalesToday(), closeTo(100, 0.001),
          reason: 'a cash refund comes back out of the drawer');
    });

    test('a GCash refund does not touch the drawer', () async {
      final p = await addProduct(price: 100, stock: 20);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
      );
      await sales.recordRefund(
        sale: sale,
        lines: {p.id!: 1},
        reason: 'Damaged',
        method: 'GCash',
        restock: true,
        isVoid: false,
      );
      expect(await sales.cashSalesToday(), closeTo(200, 0.001));
    });
  });

  group('closeShift', () {
    test('expected is float plus cash sales, variance is counted minus expected',
        () async {
      final shift = await shifts.closeShift(
        cashier: 'May',
        terminal: 'Terminal 1',
        openingFloat: 1000,
        cashSales: 250,
        counted: 1200,
        denominations: {1000: 1, 100: 2},
        totalSales: 250,
        saleCount: 3,
        openedAt: DateTime.now().subtract(const Duration(hours: 6)),
      );

      expect(shift.expected, closeTo(1250, 0.001));
      expect(shift.variance, closeTo(-50, 0.001), reason: 'short by 50');
    });

    test('an over drawer records a positive variance', () async {
      final shift = await shifts.closeShift(
        cashier: 'May',
        terminal: 'Terminal 1',
        openingFloat: 1000,
        cashSales: 0,
        counted: 1020,
        denominations: {1000: 1, 20: 1},
        totalSales: 0,
        saleCount: 0,
        openedAt: DateTime.now(),
      );
      expect(shift.variance, closeTo(20, 0.001));
    });

    test('the denomination breakdown round-trips and sums to counted', () async {
      final denoms = {1000: 1, 100: 2, 20: 3, 1: 4};
      await shifts.closeShift(
        cashier: 'May',
        terminal: 'Terminal 1',
        openingFloat: 0,
        cashSales: 0,
        counted: 1264,
        denominations: denoms,
        totalSales: 0,
        saleCount: 0,
        openedAt: DateTime.now(),
      );

      final stored = (await shifts.getShifts()).first;
      expect(stored.denominations, denoms);
      final summed = stored.denominations.entries
          .fold<int>(0, (s, e) => s + e.key * e.value);
      expect(summed, 1264, reason: 'the drawer must add up to what was counted');
    });

    test('a shift reports only the sales since the previous close', () async {
      final p = await addProduct(price: 50, stock: 50);
      await sales.recordSale(lines: [CartLine(product: p, qty: 1)], paymentMethod: 'Cash');

      await shifts.closeShift(
        cashier: 'May',
        terminal: 'Terminal 1',
        openingFloat: 0,
        cashSales: 50,
        counted: 50,
        denominations: {50: 1},
        totalSales: 50,
        saleCount: 1,
        openedAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      // Push the first sale and the close firmly into the past. Both are
      // stamped with DateTime.now(), and on Windows that clock can tick as
      // coarsely as 15ms — under load the close and the next sale land on the
      // same tick and the boundary comparison becomes a coin toss.
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now();
      await db.update('sales',
          {'created_at': now.subtract(const Duration(minutes: 2)).toIso8601String()});
      await db.update('shifts',
          {'closed_at': now.subtract(const Duration(minutes: 1)).toIso8601String()});

      // A sale rung after the close belongs to the next shift, not the last one.
      await sales.recordSale(lines: [CartLine(product: p, qty: 2)], paymentMethod: 'Cash');

      final current = await shifts.currentShiftSales();
      expect(current.count, 1, reason: 'only the post-close sale');
      expect(current.total, closeTo(100, 0.001));
    });
  });

  group('getPeriodStats', () {
    test('sums only what falls inside the window', () async {
      final p = await addProduct(price: 25, stock: 100);
      await sales.recordSale(lines: [CartLine(product: p, qty: 2)], paymentMethod: 'Cash');

      // Backdate a sale well outside today.
      final db = await DatabaseHelper.instance.database;
      await db.insert('sales', {
        'reference': 'OLD',
        'created_at': DateTime.now().subtract(const Duration(days: 20)).toIso8601String(),
        'subtotal': 999,
        'total': 999,
        'payment_method': 'Cash',
        'cash_received': 999,
        'change_amount': 0,
        'item_count': 1,
      });

      final today = await sales.getPeriodStats(1);
      expect(today.revenue, closeTo(50, 0.001));
      expect(today.transactions, 1);
      expect(today.itemsSold, 2);

      final month = await sales.getPeriodStats(30);
      expect(month.revenue, closeTo(1049, 0.001), reason: 'both sales are in 30 days');
    });

    test('the daily series has one slot per day, newest last', () async {
      final p = await addProduct(price: 10, stock: 100);
      await sales.recordSale(lines: [CartLine(product: p, qty: 1)], paymentMethod: 'Cash');

      final week = await sales.getPeriodStats(7);
      expect(week.dailyRevenue, hasLength(7));
      expect(week.dailyRevenue.last, closeTo(10, 0.001),
          reason: 'today is the last bar');
      expect(week.dailyRevenue.take(6).every((v) => v == 0), isTrue);
    });

    test('avgSale is zero rather than NaN with no transactions', () async {
      final stats = await sales.getPeriodStats(1);
      expect(stats.transactions, 0);
      expect(stats.avgSale, 0);
      expect(stats.avgSale.isNaN, isFalse);
    });
  });

  group('reports breakdowns', () {
    test('top products rank by revenue, not units', () async {
      final cheap = await addProduct(name: 'Cheap', price: 5, stock: 100);
      final pricey = await addProduct(name: 'Pricey', price: 200, stock: 100);
      await sales.recordSale(
        lines: [CartLine(product: cheap, qty: 10)], // 50
        paymentMethod: 'Cash',
      );
      await sales.recordSale(
        lines: [CartLine(product: pricey, qty: 1)], // 200
        paymentMethod: 'Cash',
      );

      final top = await sales.topProducts(1);
      expect(top.first.label, 'Pricey');
      expect(top.first.value, closeTo(200, 0.001));
      expect(top.last.label, 'Cheap');
      expect(top.last.units, 10);
    });

    test('payment mix groups by method and sums to revenue', () async {
      final p = await addProduct(price: 100, stock: 100);
      await sales.recordSale(lines: [CartLine(product: p, qty: 1)], paymentMethod: 'Cash');
      await sales.recordSale(lines: [CartLine(product: p, qty: 2)], paymentMethod: 'GCash');

      final mix = await sales.paymentMix(1);
      final total = mix.fold<double>(0, (s, r) => s + r.value);
      final stats = await sales.getPeriodStats(1);

      expect(mix.map((e) => e.label).toSet(), {'Cash', 'GCash'});
      expect(total, closeTo(stats.revenue, 0.001),
          reason: 'the mix must account for every peso of revenue');
    });
  });
}
