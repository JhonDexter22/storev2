import '../database/database_helper.dart';
import '../models/cart_line.dart';
import '../models/discount.dart';
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
    this.discountGiven = 0,
  });

  final double revenue;
  final double previousRevenue;
  final int transactions;
  final int itemsSold;
  final List<double> dailyRevenue;

  /// Pesos given away in the window. Not part of [revenue] — it is the money
  /// that did not come in, which is exactly why it is worth showing.
  final double discountGiven;

  /// What the period would have taken at full price.
  double get grossRevenue => revenue + discountGiven;

  double get deltaPct {
    if (previousRevenue <= 0) return revenue > 0 ? 1 : 0;
    return (revenue - previousRevenue) / previousRevenue;
  }

  double get avgSale => transactions == 0 ? 0 : revenue / transactions;
}

/// One discount, as an auditor would want to read it.
class DiscountRecord {
  DiscountRecord({
    required this.reference,
    required this.at,
    required this.amount,
    required this.reason,
    required this.cashier,
    required this.subtotal,
  });

  final String reference;
  final DateTime at;
  final double amount;
  final String reason;

  /// Empty on sales taken before cashiers were recorded — reported as unknown
  /// rather than blamed on whoever happens to be signed in now.
  final String cashier;
  final double subtotal;

  /// What share of the sale was given away, for spotting an outlier.
  double get share => subtotal <= 0 ? 0 : amount / subtotal;
}

class SalesService {
  final dbHelper = DatabaseHelper.instance;

  /// Splits [discountAmount] across [lines] in proportion to what each is
  /// worth, to the centavo.
  ///
  /// Proportional shares almost never sum back to the total — three lines
  /// splitting ₱10.00 give ₱3.33 each and lose a centavo. The remainder goes
  /// on the largest line, so the parts add up to the whole exactly and a full
  /// return of every line refunds precisely what was taken.
  static List<double> allocateDiscount(List<double> lineTotals, double discountAmount) {
    final shares = List<double>.filled(lineTotals.length, 0);
    if (discountAmount <= 0 || lineTotals.isEmpty) return shares;

    final subtotal = lineTotals.fold<double>(0, (a, b) => a + b);
    if (subtotal <= 0) return shares;

    var assigned = 0.0;
    var largest = 0;
    for (var i = 0; i < lineTotals.length; i++) {
      shares[i] = (lineTotals[i] / subtotal * discountAmount * 100).roundToDouble() / 100;
      assigned += shares[i];
      if (lineTotals[i] > lineTotals[largest]) largest = i;
    }

    final remainder = ((discountAmount - assigned) * 100).roundToDouble() / 100;
    if (remainder != 0) {
      shares[largest] = ((shares[largest] + remainder) * 100).roundToDouble() / 100;
    }
    return shares;
  }

  Future<Sale> recordSale({
    required List<CartLine> lines,
    required String paymentMethod,
    double cashReceived = 0,
    double changeAmount = 0,
    Discount discount = Discount.none,
    String cashier = '',
  }) async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    final subtotal = lines.fold<double>(0, (s, l) => s + l.lineTotal);
    final itemCount = lines.fold<int>(0, (s, l) => s + l.qty);
    final discountAmount = discount.amountOn(subtotal);
    final shares = allocateDiscount(
      lines.map((l) => l.lineTotal).toList(),
      discountAmount,
    );

    late int saleId;
    await db.transaction((txn) async {
      saleId = await txn.insert('sales', {
        'reference': '',
        'created_at': now.toIso8601String(),
        'subtotal': subtotal,
        'total': subtotal - discountAmount,
        'payment_method': paymentMethod,
        'cash_received': cashReceived,
        'change_amount': changeAmount,
        'item_count': itemCount,
        'discount': discountAmount,
        'discount_reason': discountAmount > 0 ? discount.reason : '',
        'cashier': cashier,
      });

      final reference = 'S${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}-${saleId.toString().padLeft(4, '0')}';
      await txn.update('sales', {'reference': reference}, where: 'id = ?', whereArgs: [saleId]);

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': line.product.id,
          'name': line.product.name,
          'unit_price': line.product.price,
          'qty': line.qty,
          'line_total': line.lineTotal,
          'discount': shares[i],
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

    double revenue = 0, prevRevenue = 0, discountGiven = 0;
    int tx = 0, items = 0;
    final daily = List<double>.filled(days, 0);

    for (final s in sales) {
      final d = s.createdAtDate;
      final dayStart = DateTime(d.year, d.month, d.day);
      if (!dayStart.isBefore(windowStart)) {
        revenue += s.total;
        discountGiven += s.discount;
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
      discountGiven: discountGiven,
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
  ///
  /// Net of each line's share of any discount, so this and [paymentMix] and
  /// the headline revenue all add up to the same money.
  Future<List<BreakdownRow>> topProducts(int days, {int limit = 5}) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT si.name AS label,
             SUM(si.line_total - si.discount) AS value,
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

  /// Every discount in the period, newest first.
  ///
  /// The reason field is mandatory at the till precisely so this list means
  /// something; without somewhere to read it, requiring it was theatre.
  Future<List<DiscountRecord>> discountsGiven(int days, {int limit = 50}) async {
    final db = await dbHelper.database;
    final rows = await db.query(
      'sales',
      where: 'discount > 0 AND created_at >= ?',
      whereArgs: [windowStart(days).toIso8601String()],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows
        .map((m) => DiscountRecord(
              reference: m['reference'] as String,
              at: DateTime.parse(m['created_at'] as String),
              amount: (m['discount'] as num).toDouble(),
              reason: (m['discount_reason'] as String?)?.trim() ?? '',
              cashier: (m['cashier'] as String?)?.trim() ?? '',
              subtotal: (m['subtotal'] as num).toDouble(),
            ))
        .toList();
  }

  /// Discounts grouped by the reason given, largest first.
  Future<List<BreakdownRow>> discountsByReason(int days) async {
    return _discountBreakdown(
        days, "COALESCE(NULLIF(discount_reason, ''), 'No reason given')");
  }

  /// Discounts grouped by who rang the sale up.
  ///
  /// The point of the whole reason-and-cashier trail: one person giving away
  /// noticeably more than the others is the thing worth seeing.
  Future<List<BreakdownRow>> discountsByCashier(int days) async {
    return _discountBreakdown(
        days, "COALESCE(NULLIF(cashier, ''), 'Not recorded')");
  }

  Future<List<BreakdownRow>> _discountBreakdown(int days, String labelExpr) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery(
      '''
      SELECT $labelExpr AS label,
             SUM(discount) AS value,
             COUNT(*) AS units
      FROM sales
      WHERE discount > 0 AND created_at >= ?
      GROUP BY label
      ORDER BY value DESC
      ''',
      [windowStart(days).toIso8601String()],
    );
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
             SUM(si.line_total - si.discount) AS value,
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
    String cashier = '',
  }) async {
    final db = await dbHelper.database;
    final items = await getSaleItems(sale.id!);
    final now = DateTime.now();

    double amount = 0;
    final refundItems = <Map<String, dynamic>>[];
    for (final item in items) {
      final qty = lines[item.productId] ?? 0;
      if (qty <= 0) continue;
      // Priced at what the customer paid, not the shelf price: refunding
      // `unitPrice * qty` on a discounted sale hands back money that never
      // came in. Returning the whole sale returns exactly the sale total.
      final lineTotal = qty == item.qty
          ? item.netTotal
          : (item.netUnitPrice * qty * 100).roundToDouble() / 100;
      amount += lineTotal;
      refundItems.add({
        'product_id': item.productId,
        'name': item.name,
        'qty': qty,
        'unit_price': item.netUnitPrice,
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
        'cashier': cashier,
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
