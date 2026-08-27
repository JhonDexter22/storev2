import '../database/database_helper.dart';
import '../models/cart_line.dart';
import '../models/sale_model.dart';

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
        final newStock = line.product.stock - line.qty;
        await txn.update(
          'products',
          {'stock': newStock < 0 ? 0 : newStock},
          where: 'id = ?',
          whereArgs: [line.product.id],
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
}
