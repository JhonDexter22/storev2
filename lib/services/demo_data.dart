import 'dart:math';

import '../database/database_helper.dart';

/// A year of a busy store, for trying the app on a real phone.
///
/// Performance only shows itself after months of trading, and nobody should
/// have to wait months to see it. Available in debug and profile builds only
/// — see the Settings row that calls it — and never in a release.
///
/// Replaces everything: products, sales, returns, closed days and utang. Staff
/// are left alone, and so are settings.
class DemoData {
  DemoData({DatabaseHelper? dbHelper, Random? random})
      : dbHelper = dbHelper ?? DatabaseHelper.instance,
        _rnd = random ?? Random(2026);

  final DatabaseHelper dbHelper;
  final Random _rnd;

  static const productCount = 300;
  static const days = 365;

  /// What a sari-sari shelf actually holds, by category. Each base is sold in
  /// a few sizes or flavours to reach [productCount].
  static const _shelf = {
    'Noodles': ['Pancit canton', 'Instant mami', 'Instant noodles, beef', 'Instant noodles, chicken', 'Cup noodles'],
    'Canned goods': ['Sardines in tomato sauce', 'Corned beef', 'Meat loaf', 'Tuna flakes', 'Condensed milk', 'Evaporated milk'],
    'Drinks': ['Cola', 'Lemon soda', 'Orange juice drink', 'Bottled water', 'Iced tea', 'Energy drink', '3-in-1 coffee', 'Chocolate drink'],
    'Snacks': ['Cheese curls', 'Potato chips', 'Corn chips', 'Peanuts', 'Chicharon', 'Candy', 'Chocolate bar'],
    'Biscuit': ['Crackers', 'Cream sandwich', 'Butter cookies', 'Wafer', 'Graham crackers'],
    'Rice': ['Rice, regular', 'Rice, dinorado', 'Rice, sinandomeng'],
    'Condiments': ['Soy sauce', 'Vinegar', 'Fish sauce', 'Cooking oil', 'Salt', 'Sugar', 'Ketchup', 'Seasoning mix'],
    'Toiletries': ['Shampoo sachet', 'Conditioner sachet', 'Bath soap', 'Toothpaste', 'Detergent powder', 'Fabric conditioner'],
    'Household': ['Candle', 'Matches', 'AA battery', 'Trash bags', 'Load card'],
  };

  static const _variants = ['small', 'medium', 'large', 'family size', 'twin pack', 'sachet', '6s', 'hot & spicy'];

  static const _customers = [
    'Aling Rosa', 'Mang Ben', 'Ate Joy', 'Kuya Jun', 'Aling Cora', 'Mang Tonyo',
    'Ate Lorna', 'Kuya Dodong', 'Aling Pacing', 'Mang Pido', 'Ate Weng', 'Nanay Lita',
    'Tatay Ramon', 'Ate Beng', 'Kuya Rey', 'Aling Nida', 'Mang Caloy', 'Ate Tess',
  ];

  /// Seeds the store and reports progress from 0 to 1 as it goes, so a phone
  /// that takes half a minute over it can say so.
  Future<void> loadYear({
    List<String> cashiers = const ['Owner'],
    void Function(double progress)? onProgress,
  }) async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final staff = cashiers.isEmpty ? const ['Owner'] : cashiers;

    await db.transaction((txn) async {
      for (final t in [
        'utang_entries', 'customers', 'refund_items', 'refunds',
        'shifts', 'sale_items', 'sales', 'products',
      ]) {
        await txn.delete(t);
      }
    });

    // ── Products ────────────────────────────────────────────────────────
    final names = <(String name, String category)>[];
    var v = 0;
    while (names.length < productCount) {
      for (final MapEntry(key: category, value: bases) in _shelf.entries) {
        for (final base in bases) {
          if (names.length >= productCount) break;
          final variant = _variants[(v + base.length) % _variants.length];
          names.add(('$base, $variant', category));
        }
      }
      v++;
    }
    // Duplicate names from the wrap-around get a number so each is distinct.
    final seen = <String, int>{};
    final prices = <double>[];
    var batch = db.batch();
    for (var i = 0; i < names.length; i++) {
      var (name, category) = names[i];
      final n = seen.update(name, (c) => c + 1, ifAbsent: () => 1);
      if (n > 1) name = '$name $n';
      final price = [6, 8, 10, 12, 15, 18, 20, 25, 28, 35, 45, 52, 60, 75, 95, 120][_rnd.nextInt(16)].toDouble();
      prices.add(price);
      final minStock = 3 + _rnd.nextInt(8);
      batch.insert('products', {
        'name': name,
        // Most well stocked, some low, a few out — so the badges and the
        // Restock tab have something to show.
        'stock': switch (_rnd.nextInt(20)) {
          0 => 0,
          1 || 2 => 1 + _rnd.nextInt(minStock),
          _ => minStock + 5 + _rnd.nextInt(60),
        },
        'min_stock': minStock,
        'category': category,
        'created_at': today.subtract(Duration(days: days + 30 - i ~/ 10)).toIso8601String(),
        'price': price,
        'sku': '480${(1000000000 + i * 7919).toString().substring(0, 10)}',
      });
    }
    await batch.commit(noResult: true);
    final ids = (await db.query('products', columns: ['id'], orderBy: 'id ASC'))
        .map((r) => r['id'] as int)
        .toList();

    // ── Customers ───────────────────────────────────────────────────────
    batch = db.batch();
    for (final name in _customers) {
      batch.insert('customers', {
        'name': name,
        'created_at': today.subtract(const Duration(days: days)).toIso8601String(),
        if (_rnd.nextBool()) 'phone': '09${170000000 + _rnd.nextInt(99999999)}',
      });
    }
    await batch.commit(noResult: true);
    final customerIds = (await db.query('customers', columns: ['id']))
        .map((r) => r['id'] as int)
        .toList();

    // ── A year of days ──────────────────────────────────────────────────
    var saleId = 0;
    const methods = ['Cash', 'Cash', 'Cash', 'Cash', 'Cash', 'GCash', 'GCash', 'Utang'];
    for (var back = days; back >= 0; back--) {
      final day = today.subtract(Duration(days: back));
      // Busier at the weekend and at month's end, when wages come in.
      final weekend = day.weekday >= DateTime.saturday;
      final payday = day.day >= 28 || day.day <= 2 || day.day == 15;
      final perDay = 40 + _rnd.nextInt(25) + (weekend ? 15 : 0) + (payday ? 15 : 0);

      batch = db.batch();
      var cashTaken = 0.0, allTaken = 0.0, count = 0;
      for (var n = 0; n < perDay; n++) {
        // Open 6 am to 10 pm.
        final at = day.add(Duration(minutes: 360 + (n * 960 ~/ perDay) + _rnd.nextInt(10)));
        if (at.isAfter(now)) break;
        saleId++;

        var subtotal = 0.0, items = 0;
        final lines = <Map<String, Object?>>[];
        for (var l = 0, k = 1 + _rnd.nextInt(4); l < k; l++) {
          // A few products sell most, as on any real shelf.
          final idx = (pow(_rnd.nextDouble(), 2.2) * ids.length).floor().clamp(0, ids.length - 1);
          final qty = 1 + (_rnd.nextInt(6) == 0 ? _rnd.nextInt(4) : 0);
          final total = prices[idx] * qty;
          subtotal += total;
          items += qty;
          lines.add({
            'sale_id': saleId,
            'product_id': ids[idx],
            'name': names[idx].$1,
            'unit_price': prices[idx],
            'qty': qty,
            'line_total': total,
            'discount': 0.0,
          });
        }
        final discount = _rnd.nextInt(60) == 0 ? (subtotal * 0.2).roundToDouble() : 0.0;
        if (discount > 0) {
          // Spread onto the first line; the reports only need the totals to agree.
          lines.first['discount'] = discount;
        }
        final total = subtotal - discount;
        final method = methods[_rnd.nextInt(methods.length)];
        final tendered = method == 'Cash' ? ((total / 50).ceil() * 50).toDouble() : 0.0;

        final reference =
            'S${day.year}${_two(day.month)}${_two(day.day)}-${saleId.toString().padLeft(4, '0')}';
        batch.insert('sales', {
          'id': saleId,
          'reference': reference,
          'created_at': at.toIso8601String(),
          'subtotal': subtotal,
          'total': total,
          'payment_method': method,
          'cash_received': tendered,
          'change_amount': method == 'Cash' ? tendered - total : 0.0,
          'item_count': items,
          'discount': discount,
          'discount_reason': discount > 0 ? 'Senior citizen' : '',
          'cashier': staff[_rnd.nextInt(staff.length)],
        });
        for (final line in lines) {
          batch.insert('sale_items', line);
        }
        if (method == 'Utang') {
          batch.insert('utang_entries', {
            'customer_id': customerIds[_rnd.nextInt(customerIds.length)],
            'sale_id': saleId,
            'created_at': at.toIso8601String(),
            'amount': total,
            'kind': 'charge',
          });
        }
        if (_rnd.nextInt(180) == 0) {
          batch.insert('refunds', {
            'sale_id': saleId,
            'sale_reference': reference,
            'created_at': at.add(const Duration(minutes: 20)).toIso8601String(),
            'amount': lines.first['line_total'],
            'reason': 'Damaged',
            'method': 'Cash',
            'cashier': staff.first,
          });
        }
        if (method == 'Cash') cashTaken += total;
        allTaken += total;
        count++;
      }

      // Utang collected: a few customers pay something most days.
      for (var p = 0, k = _rnd.nextInt(3); p < k; p++) {
        batch.insert('utang_entries', {
          'customer_id': customerIds[_rnd.nextInt(customerIds.length)],
          'created_at': day.add(Duration(hours: 17, minutes: _rnd.nextInt(180))).toIso8601String(),
          'amount': -(50.0 + _rnd.nextInt(8) * 25),
          'kind': 'payment',
          'method': 'Cash',
        });
      }

      // Every day but today has been closed.
      if (back > 0) {
        final variance = [0.0, 0.0, 0.0, -20.0, 10.0][_rnd.nextInt(5)];
        batch.insert('shifts', {
          'closed_at': day.add(const Duration(hours: 22, minutes: 15)).toIso8601String(),
          'opened_at': day.add(const Duration(hours: 6)).toIso8601String(),
          'cashier': staff.first,
          'terminal': 'Terminal 1',
          'opening_float': 1000.0,
          'cash_sales': cashTaken,
          'expected': 1000 + cashTaken,
          'counted': 1000 + cashTaken + variance,
          'variance': variance,
          'denominations': '{}',
          'total_sales': allTaken,
          'sale_count': count,
        });
      }
      await batch.commit(noResult: true);
      onProgress?.call((days - back + 1) / (days + 1));
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

