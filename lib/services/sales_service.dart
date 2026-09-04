import '../database/database_helper.dart';
import '../models/cart_line.dart';
import '../models/refund_model.dart';
import '../models/sale_model.dart';

/// One row of a proportional-bar breakdown (top products, payment mix,
/// category mix). [value] is money unless stated otherwise.
class BreakdownRow {
  BreakdownRow({required this.label, required this.value, this.units = 0});

  final String label;
  final double value;
  final int units;
}

/// A line of a sale that can still be returned, with how much of it is left.
class ReturnableLine {
  ReturnableLine({required this.item, required this.alreadyReturned});

  final SaleItem item;
  final int alreadyReturned;

  int get returnable => item.qty - alreadyReturned;
}

class PeriodStats {
  PeriodStats({
    required this.revenue,
    required this.previousRevenue,
    required this.transactions,
    required this.itemsSold,
    required this.dailyRevenue,
  });

  final double revenue;
  final double previousRevenue;
  final int transactions;
  final int itemsSold;
  final List<double> dailyRevenue;

  double get deltaPct {
    if (previousRevenue <= 0) return revenue > 0 ? 1 : 0;
    return (revenue - previousRevenue) / previousRevenue;
  }

  double get avgSale => transactions == 0 ? 0 : revenue / transactions;
}

class SalesService {
  final dbHelper = DatabaseHelper.instance;

  Future<Sale> recordSale({
    required List<CartLine> lines,
    required String paymentMethod,
    double cashReceived = 0,
    double changeAmount = 0,
  }) async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    final subtotal = lines.fold<double>(0, (s, l) => s + l.lineTotal);
    final itemCount = lines.fold<int>(0, (s, l) => s + l.qty);

    late int saleId;
    await db.transaction((txn) async {
      saleId = await txn.insert('sales', {
        'reference': '',
        'created_at': now.toIso8601String(),
        'subtotal': subtotal,
        'total': subtotal,
        'payment_method': paymentMethod,
        'cash_received': cashReceived,
        'change_amount': changeAmount,
        'item_count': itemCount,
      });

      final reference = 'S${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}-${saleId.toString().padLeft(4, '0')}';
      await txn.update('sales', {'reference': reference}, where: 'id = ?', whereArgs: [saleId]);

      for (final line in lines) {
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': line.product.id,
          'name': line.product.name,
          'unit_price': line.product.price,
          'qty': line.qty,
          'line_total': line.lineTotal,
        });
        // Decrement relative to the stored value, not the copy POS loaded.
        // Writing an absolute `loadedStock - qty` would clobber any change made
        // in between — a restock, or a return going back on the shelf.
        await txn.rawUpdate(
          'UPDATE products SET stock = MAX(0, stock - ?) WHERE id = ?',
          [line.qty, line.product.id],
        );
      }
    });

    final rows = await db.query('sales', where: 'id = ?', whereArgs: [saleId]);
    return Sale.fromMap(rows.first);
  }

  Future<List<Sale>> getRecentSales({int limit = 10}) async {
    final db = await dbHelper.database;
    final result = await db.query('sales', orderBy: 'id DESC', limit: limit);
    return result.map((m) => Sale.fromMap(m)).toList();
  }

  Future<List<SaleItem>> getSaleItems(int saleId) async {
    final db = await dbHelper.database;
    final result = await db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
    return result.map((m) => SaleItem.fromMap(m)).toList();
  }

  /// Revenue/tx/items for the last [days] days (today inclusive), plus the
  /// same window immediately before it for the delta comparison, plus a
  /// per-day revenue series (oldest first) for the bar chart.
  Future<PeriodStats> getPeriodStats(int days) async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final windowStart = todayStart.subtract(Duration(days: days - 1));
    final prevWindowStart = windowStart.subtract(Duration(days: days));

    final rows = await db.query(
      'sales',
      where: 'created_at >= ?',
      whereArgs: [prevWindowStart.toIso8601String()],
      orderBy: 'created_at ASC',
    );
    final sales = rows.map((m) => Sale.fromMap(m)).toList();

    double revenue = 0, prevRevenue = 0;
    int tx = 0, items = 0;
    final daily = List<double>.filled(days, 0);

    for (final s in sales) {
      final d = s.createdAtDate;
      final dayStart = DateTime(d.year, d.month, d.day);
      if (!dayStart.isBefore(windowStart)) {
        revenue += s.total;
        tx += 1;
        items += s.itemCount;
        final idx = dayStart.difference(windowStart).inDays;
        if (idx >= 0 && idx < days) daily[idx] += s.total;
      } else if (!dayStart.isBefore(prevWindowStart)) {
        prevRevenue += s.total;
      }
    }

    return PeriodStats(
      revenue: revenue,
      previousRevenue: prevRevenue,
      transactions: tx,
      itemsSold: items,
      dailyRevenue: daily,
    );
  }

  /// Start of the window for a `days`-long period ending today (inclusive).
  static DateTime windowStart(int days) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
  }

  // ── Reports ────────────────────────────────────────────────────────────

  /// Products by revenue over the period, highest first, so bar length and
  /// figures always agree.
  Future<List<BreakdownRow>> topProducts(int days, {int limit = 5}) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT si.name AS label,
             SUM(si.line_total) AS value,
             SUM(si.qty) AS units
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE s.created_at >= ?
      GROUP BY si.name
      ORDER BY value DESC
      LIMIT ?
    ''', [windowStart(days).toIso8601String(), limit]);
    return rows
        .map((m) => BreakdownRow(
              label: m['label'] as String,
              value: (m['value'] as num).toDouble(),
              units: (m['units'] as num).toInt(),
            ))
        .toList();
  }

  Future<List<BreakdownRow>> paymentMix(int days) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT payment_method AS label, SUM(total) AS value, COUNT(*) AS units
      FROM sales
      WHERE created_at >= ?
      GROUP BY payment_method
      ORDER BY value DESC
    ''', [windowStart(days).toIso8601String()]);
    return rows
        .map((m) => BreakdownRow(
              label: m['label'] as String,
              value: (m['value'] as num).toDouble(),
              units: (m['units'] as num).toInt(),
            ))
        .toList();
  }

  /// Category comes from the product record; a line whose product was since
  /// deleted falls back to "Other" rather than vanishing from the total.
  Future<List<BreakdownRow>> categoryMix(int days) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(NULLIF(p.category, ''), 'Other') AS label,
             SUM(si.line_total) AS value,
             SUM(si.qty) AS units
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      LEFT JOIN products p ON p.id = si.product_id
      WHERE s.created_at >= ?
      GROUP BY label
      ORDER BY value DESC
    ''', [windowStart(days).toIso8601String()]);
    return rows
        .map((m) => BreakdownRow(
              label: m['label'] as String,
              value: (m['value'] as num).toDouble(),
              units: (m['units'] as num).toInt(),
            ))
        .toList();
  }

  // ── Returns ────────────────────────────────────────────────────────────

  /// Every refund inside the period, newest first. Not capped — the rows must
  /// sum to the header total.
  Future<List<Refund>> getRefunds(int days) async {
    final db = await dbHelper.database;
    final rows = await db.query(
      'refunds',
      where: 'created_at >= ?',
      whereArgs: [windowStart(days).toIso8601String()],
      orderBy: 'id DESC',
    );
    return rows.map((m) => Refund.fromMap(m)).toList();
  }

  /// Sale lines with the quantity already refunded subtracted, so a line can
  /// never be returned twice.
  Future<List<ReturnableLine>> getReturnableLines(int saleId) async {
    final db = await dbHelper.database;
    final items = await getSaleItems(saleId);
    final returned = await db.rawQuery('''
      SELECT ri.product_id AS pid, SUM(ri.qty) AS qty
      FROM refund_items ri
      JOIN refunds r ON r.id = ri.refund_id
      WHERE r.sale_id = ?
      GROUP BY ri.product_id
    ''', [saleId]);

    final byProduct = <int, int>{
      for (final r in returned) r['pid'] as int: (r['qty'] as num).toInt(),
    };

    return items
        .map((i) => ReturnableLine(item: i, alreadyReturned: byProduct[i.productId] ?? 0))
        .toList();
  }

  /// Records a refund. [lines] is productId -> quantity being returned.
  /// When [restock] is true the returned units go back into stock, which can
  /// clear a product off the restock list.
  Future<Refund> recordRefund({
    required Sale sale,
    required Map<int, int> lines,
    required String reason,
    required String method,
    required bool restock,
    required bool isVoid,
  }) async {
    final db = await dbHelper.database;
    final items = await getSaleItems(sale.id!);
    final now = DateTime.now();

    double amount = 0;
    final refundItems = <Map<String, dynamic>>[];
    for (final item in items) {
      final qty = lines[item.productId] ?? 0;
      if (qty <= 0) continue;
      final lineTotal = item.unitPrice * qty;
      amount += lineTotal;
      refundItems.add({
        'product_id': item.productId,
        'name': item.name,
        'qty': qty,
        'unit_price': item.unitPrice,
        'line_total': lineTotal,
      });
    }

    late int refundId;
    await db.transaction((txn) async {
      refundId = await txn.insert('refunds', {
        'sale_id': sale.id,
        'sale_reference': sale.reference,
        'created_at': now.toIso8601String(),
        'amount': amount,
        'reason': reason,
        'method': method,
        'is_void': isVoid ? 1 : 0,
        'restocked': restock ? 1 : 0,
      });

      for (final ri in refundItems) {
        await txn.insert('refund_items', {...ri, 'refund_id': refundId});
        if (restock) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [ri['qty'], ri['product_id']],
          );
        }
      }
    });

    final row = await db.query('refunds', where: 'id = ?', whereArgs: [refundId]);
    return Refund.fromMap(row.first);
  }

  // ── Cash count ─────────────────────────────────────────────────────────

  /// Cash taken today. Only cash counts toward the drawer — GCash and card
  /// never land in it.
  Future<double> cashSalesToday() async {
    final db = await dbHelper.database;
    final start = windowStart(1).toIso8601String();

    final sold = await db.rawQuery(
      "SELECT SUM(total) AS v FROM sales WHERE payment_method = 'Cash' AND created_at >= ?",
      [start],
    );
    final refunded = await db.rawQuery(
      "SELECT SUM(amount) AS v FROM refunds WHERE method = 'Cash' AND created_at >= ?",
      [start],
    );

    final in_ = (sold.first['v'] as num?)?.toDouble() ?? 0;
    final out = (refunded.first['v'] as num?)?.toDouble() ?? 0;
    return in_ - out;
  }
}
