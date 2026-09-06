import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/discount.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';

void main() {
  final sales = SalesService();
  final products = ProductService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    for (final table in [
      'refund_items',
      'refunds',
      'sale_items',
      'sales',
      'products',
    ]) {
      await db.delete(table);
    }
  });

  Future<Product> addProduct({
    String name = 'SkyFlakes',
    double price = 10,
    int stock = 100,
  }) async {
    final id = await products.insertProduct(Product(
      name: name,
      stock: stock,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    return Product(
      id: id,
      name: name,
      stock: stock,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    );
  }

  const senior = Discount(
    kind: DiscountKind.percent,
    value: 20,
    reason: 'Senior citizen',
  );

  group('Discount.amountOn', () {
    test('a percent is taken off the subtotal', () {
      expect(senior.amountOn(100), closeTo(20, 0.001));
      expect(senior.amountOn(0), 0);
    });

    test('a fixed amount is taken as given', () {
      const off = Discount(kind: DiscountKind.amount, value: 15, reason: 'Suki');
      expect(off.amountOn(100), closeTo(15, 0.001));
    });

    test('it is rounded to centavos', () {
      // 20% of 33.33 is 6.666; a till cannot take two-thirds of a centavo.
      expect(senior.amountOn(33.33), closeTo(6.67, 0.0001));
    });

    test('it never exceeds the subtotal', () {
      const huge = Discount(kind: DiscountKind.amount, value: 500, reason: 'x');
      // A sale can be brought to zero, never below: otherwise the till would
      // owe the customer money for buying something.
      expect(huge.amountOn(80), closeTo(80, 0.001));
      const overPercent =
          Discount(kind: DiscountKind.percent, value: 150, reason: 'x');
      expect(overPercent.amountOn(80), closeTo(80, 0.001));
    });

    test('no discount takes nothing off', () {
      expect(Discount.none.amountOn(100), 0);
      expect(Discount.none.isZero, isTrue);
    });
  });

  group('allocateDiscount', () {
    test('splits in proportion to what each line is worth', () {
      final shares = SalesService.allocateDiscount([75, 25], 20);
      expect(shares, [15, 5]);
    });

    test('the parts always add back to the whole', () {
      // Three equal lines splitting 10.00 give 3.33 each and lose a centavo;
      // the remainder has to land somewhere or a full return under-refunds.
      final shares = SalesService.allocateDiscount([10, 10, 10], 10);
      expect(shares.reduce((a, b) => a + b), closeTo(10, 0.0001));
    });

    test('the rounding remainder goes on the largest line', () {
      final shares = SalesService.allocateDiscount([50, 10, 10], 10);
      expect(shares.reduce((a, b) => a + b), closeTo(10, 0.0001));
      expect(shares[0], greaterThan(shares[1]));
    });

    test('a zero discount allocates nothing', () {
      expect(SalesService.allocateDiscount([10, 20], 0), [0, 0]);
    });

    test('a zero subtotal cannot be divided by', () {
      expect(SalesService.allocateDiscount([0, 0], 5), [0, 0]);
      expect(SalesService.allocateDiscount([], 5), isEmpty);
    });
  });

  group('recordSale with a discount', () {
    test('subtotal stays gross and total is what was paid', () async {
      final p = await addProduct(price: 50);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
        discount: senior,
      );

      expect(sale.subtotal, closeTo(100, 0.001));
      expect(sale.discount, closeTo(20, 0.001));
      expect(sale.total, closeTo(80, 0.001));
      expect(sale.discountReason, 'Senior citizen');
    });

    test('the reason is not kept when no discount was given', () async {
      final p = await addProduct(price: 50);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 1)],
        paymentMethod: 'Cash',
        discount: const Discount(
            kind: DiscountKind.percent, value: 0, reason: 'Senior citizen'),
      );
      // A reason with no money behind it would show up in an audit as a
      // discount that never happened.
      expect(sale.discount, 0);
      expect(sale.discountReason, '');
    });

    test('the share lands on each line and sums to the sale discount',
        () async {
      final a = await addProduct(name: 'Kopiko', price: 75);
      final b = await addProduct(name: 'SkyFlakes', price: 25);
      final sale = await sales.recordSale(
        lines: [CartLine(product: a, qty: 1), CartLine(product: b, qty: 1)],
        paymentMethod: 'Cash',
        discount: senior,
      );

      final items = await sales.getSaleItems(sale.id!);
      expect(items.map((i) => i.discount), [15, 5]);
      expect(items.fold<double>(0, (s, i) => s + i.discount),
          closeTo(sale.discount, 0.0001));
      expect(items.fold<double>(0, (s, i) => s + i.netTotal),
          closeTo(sale.total, 0.0001));
    });

    test('the unit price stays the shelf price', () async {
      final p = await addProduct(price: 50);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
        discount: senior,
      );
      final item = (await sales.getSaleItems(sale.id!)).single;
      // What it cost and what was taken off are separate facts; folding the
      // discount into the price would lose the second one.
      expect(item.unitPrice, closeTo(50, 0.001));
      expect(item.lineTotal, closeTo(100, 0.001));
      expect(item.netUnitPrice, closeTo(40, 0.001));
    });

    test('an undiscounted sale is unchanged', () async {
      final p = await addProduct(price: 50);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
      );
      expect(sale.discount, 0);
      expect(sale.total, closeTo(sale.subtotal, 0.001));
      expect((await sales.getSaleItems(sale.id!)).single.discount, 0);
    });

    test('the cashier who rang it up is recorded', () async {
      final p = await addProduct();
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 1)],
        paymentMethod: 'Cash',
        cashier: 'Nena',
      );
      expect(sale.cashier, 'Nena');
    });
  });

  group('refunding a discounted sale', () {
    test('pays back what the customer paid, not the shelf price', () async {
      final p = await addProduct(price: 50);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
        discount: senior,
      );

      final refund = await sales.recordRefund(
        sale: sale,
        lines: {p.id!: 1},
        reason: 'Changed mind',
        method: 'Cash',
        restock: true,
        isVoid: false,
      );

      // They paid 40 for each of the two. Refunding 50 would hand back money
      // that never came into the till.
      expect(refund.amount, closeTo(40, 0.001));
    });

    test('returning everything returns exactly the sale total', () async {
      final a = await addProduct(name: 'Kopiko', price: 33.33);
      final b = await addProduct(name: 'SkyFlakes', price: 12.5);
      final sale = await sales.recordSale(
        lines: [CartLine(product: a, qty: 3), CartLine(product: b, qty: 1)],
        paymentMethod: 'Cash',
        discount: senior,
      );

      final refund = await sales.recordRefund(
        sale: sale,
        lines: {a.id!: 3, b.id!: 1},
        reason: 'Void',
        method: 'Cash',
        restock: true,
        isVoid: true,
      );

      // The whole point of allocating the discount per line: a full void has
      // to reconcile to the cent, whatever the rounding did.
      expect(refund.amount, closeTo(sale.total, 0.0001));
    });

    test('an undiscounted sale still refunds the full price', () async {
      final p = await addProduct(price: 50);
      final sale = await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
      );
      final refund = await sales.recordRefund(
        sale: sale,
        lines: {p.id!: 1},
        reason: 'Changed mind',
        method: 'Cash',
        restock: true,
        isVoid: false,
      );
      expect(refund.amount, closeTo(50, 0.001));
    });
  });

  group('reports', () {
    test('revenue is net and the discount is reported beside it', () async {
      final p = await addProduct(price: 50);
      await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
        discount: senior,
      );

      final stats = await sales.getPeriodStats(1);
      expect(stats.revenue, closeTo(80, 0.001), reason: 'what came in');
      expect(stats.discountGiven, closeTo(20, 0.001));
      expect(stats.grossRevenue, closeTo(100, 0.001));
    });

    test('the breakdowns reconcile with revenue', () async {
      final a = await addProduct(name: 'Kopiko', price: 75);
      final b = await addProduct(name: 'SkyFlakes', price: 25);
      await sales.recordSale(
        lines: [CartLine(product: a, qty: 1), CartLine(product: b, qty: 1)],
        paymentMethod: 'Cash',
        discount: senior,
      );

      final stats = await sales.getPeriodStats(1);
      final top = await sales.topProducts(1);
      final mix = await sales.paymentMix(1);
      final byCategory = await sales.categoryMix(1);

      // A dashboard reading 80 while "top products" adds to 100 is the kind of
      // discrepancy that makes a shopkeeper stop trusting the whole screen.
      for (final rows in [top, mix, byCategory]) {
        expect(rows.fold<double>(0, (s, r) => s + r.value),
            closeTo(stats.revenue, 0.0001));
      }
    });

    test('cash in the drawer is the discounted amount', () async {
      final p = await addProduct(price: 50);
      await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
        discount: senior,
      );
      expect(await sales.cashSalesToday(), closeTo(80, 0.001));
    });
  });
}
