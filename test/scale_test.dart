import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/widgets/product_thumb.dart';

/// What keeps the app quick after a year of trading, rather than only on the
/// day it was installed. Timings are not asserted — they depend on the
/// machine — but the things that decide them are: which indexes a query
/// uses, how much it binds, and how much it decodes.
void main() {
  final sales = SalesService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('sale_items');
    await db.delete('sales');
  });

  /// A sale at exactly [at], with one line, inserted directly so a test can
  /// put it on any day.
  Future<int> saleAt(DateTime at, double total, {double discount = 0}) async {
    final db = await DatabaseHelper.instance.database;
    final id = await db.insert('sales', {
      'reference': 'S',
      'created_at': at.toIso8601String(),
      'subtotal': total + discount,
      'total': total,
      'payment_method': 'Cash',
      'item_count': 2,
      'discount': discount,
    });
    await db.insert('sale_items', {
      'sale_id': id,
      'product_id': 1,
      'name': 'SkyFlakes',
      'unit_price': total / 2,
      'qty': 2,
      'line_total': total,
    });
    return id;
  }

  DateTime today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  group('period figures, summed by the database', () {
    test('each sale lands on its own day\'s bar', () async {
      await saleAt(today().add(const Duration(hours: 9)), 10);
      await saleAt(today().subtract(const Duration(days: 3)).add(const Duration(hours: 15)), 30);
      await saleAt(today().subtract(const Duration(days: 6)).add(const Duration(hours: 8)), 60);

      final week = await sales.getPeriodStats(7);
      expect(week.dailyRevenue, [60, 0, 0, 30, 0, 0, 10]);
      expect(week.revenue, 100);
      expect(week.transactions, 3);
      expect(week.itemsSold, 6);
    });

    test('midnight belongs to the day it starts', () async {
      final start = today().subtract(const Duration(days: 6));
      await saleAt(start, 5);
      await saleAt(start.subtract(const Duration(minutes: 1)), 7);

      final week = await sales.getPeriodStats(7);
      expect(week.revenue, 5, reason: '00:00 on the first day is inside');
      expect(week.dailyRevenue.first, 5);
      expect(week.previousRevenue, 7, reason: '23:59 the night before is not');
    });

    test('the previous period is the same length, just before', () async {
      await saleAt(today().add(const Duration(hours: 10)), 100);
      await saleAt(today().subtract(const Duration(days: 8)), 40);
      await saleAt(today().subtract(const Duration(days: 13)), 2);
      await saleAt(today().subtract(const Duration(days: 14)), 999);

      final week = await sales.getPeriodStats(7);
      expect(week.revenue, 100);
      expect(week.previousRevenue, 42, reason: 'days 7–13 back, and no further');
    });

    test('discounts given are summed with the rest', () async {
      await saleAt(today().add(const Duration(hours: 9)), 80, discount: 20);
      await saleAt(today().add(const Duration(hours: 10)), 50);

      final day = await sales.getPeriodStats(1);
      expect(day.discountGiven, 20);
      expect(day.revenue, 130);
    });
  });

  group('a busy month', () {
    // Past the 999 placeholders the SQLite in Android 10 and 11 allows in one
    // statement, which a month of a busy store is.
    const count = 1234;

    Future<List<int>> manySalesToday() async {
      final db = await DatabaseHelper.instance.database;
      final ids = <int>[];
      await db.transaction((txn) async {
        for (var i = 0; i < count; i++) {
          final id = await txn.insert('sales', {
            'reference': 'S-$i',
            'created_at': today().add(Duration(seconds: 30 + i)).toIso8601String(),
            'subtotal': 10,
            'total': 10,
            'payment_method': 'Cash',
            'item_count': 1,
          });
          await txn.insert('sale_items', {
            'sale_id': id,
            'product_id': 1,
            'name': 'Line $i',
            'unit_price': 10,
            'qty': 1,
            'line_total': 10,
          });
          ids.add(id);
        }
      });
      return ids;
    }

    test('lists every sale with its lines attached', () async {
      await manySalesToday();
      final list = await sales.getSalesForPeriod(1);
      expect(list, hasLength(count));
      expect(list.every((s) => s.items.length == 1), isTrue);
    });

    test('looks up every sale asked for by id', () async {
      final ids = await manySalesToday();
      final found = await sales.getSalesByIds(ids);
      expect(found, hasLength(count));
      expect(found.values.every((s) => s.items.length == 1), isTrue);
    });

    test('never binds more than the oldest supported SQLite allows', () {
      expect(SalesService.maxBoundIds, lessThanOrEqualTo(999));
    });
  });

  group('the lookups every screen makes use an index', () {
    Future<String> plan(String sql, [List<Object?> args = const []]) async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
      return rows.map((r) => r['detail']).join(' | ');
    }

    final since = DateTime(2026).toIso8601String();

    test('sales in a period', () async {
      expect(await plan('SELECT * FROM sales WHERE created_at >= ?', [since]),
          contains('idx_sales_created'));
    });

    test('the lines of a sale', () async {
      expect(await plan('SELECT * FROM sale_items WHERE sale_id IN (1, 2)'),
          contains('idx_sale_items_sale'));
    });

    test('lines joined to their sales by date, for Popular and Reports', () async {
      final p = await plan(
          'SELECT si.product_id, SUM(si.qty) FROM sale_items si '
          'JOIN sales s ON s.id = si.sale_id WHERE s.created_at >= ? '
          'GROUP BY si.product_id',
          [since]);
      expect(p, contains('idx_sales_created'));
      expect(p, contains('idx_sale_items_sale'));
    });

    test('refunds of a sale, and their lines', () async {
      expect(await plan('SELECT * FROM refunds WHERE sale_id = ?', [1]),
          contains('idx_refunds_sale'));
      expect(await plan('SELECT * FROM refund_items WHERE refund_id = ?', [1]),
          contains('idx_refund_items_refund'));
    });
  });

  group('product photos', () {
    testWidgets('a thumbnail is decoded near the size it is drawn',
        (tester) async {
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: ProductThumb(
          product: Product(
            name: 'SkyFlakes',
            stock: 1,
            minStock: 1,
            category: 'Biscuit',
            createdAt: '2026-09-01',
            price: 10,
            imagePath: '${Directory.systemTemp.path}/photo.jpg',
          ),
          size: 44,
        ),
      ));

      final provider = tester.widget<Image>(find.byType(Image)).image;
      expect(provider, isA<ResizeImage>());
      final resized = provider as ResizeImage;
      // 44 logical px at 3x is 132 device px; twice that is the bound.
      expect(resized.width, 264);
      expect(resized.height, 264);
      expect(resized.policy, ResizeImagePolicy.fit);
    });
  });
}
