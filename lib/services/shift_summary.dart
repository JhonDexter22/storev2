import '../database/database_helper.dart';
import '../models/shift_model.dart';
import 'sales_service.dart';

/// Everything an owner wants to know about a shift, in one object: what came
/// in, how it was paid, what sold, what was given away or handed back, and
/// whether the drawer balanced. Built from a time window so it works for the
/// shift being closed now and for any shift in history.
class ShiftSummary {
  const ShiftSummary({
    required this.from,
    required this.to,
    required this.revenue,
    required this.transactions,
    required this.items,
    required this.byMethod,
    required this.topProducts,
    required this.discounts,
    required this.refunds,
    required this.refundCount,
    required this.utangCharged,
    this.shift,
  });

  final DateTime from;
  final DateTime to;

  /// Net of discounts, before refunds.
  final double revenue;
  final int transactions;
  final int items;

  /// Payment method → amount, largest first.
  final List<BreakdownRow> byMethod;

  /// Best sellers by units, with their net revenue.
  final List<BreakdownRow> topProducts;
  final double discounts;
  final double refunds;
  final int refundCount;

  /// Sales put on a customer's tab — money owed, not money in hand.
  final double utangCharged;

  /// The drawer reconciliation, once the shift has been closed.
  final Shift? shift;

  double get net => revenue - refunds;
  double get averageSale => transactions == 0 ? 0 : revenue / transactions;

  ShiftSummary withShift(Shift s) => ShiftSummary(
        from: from,
        to: to,
        revenue: revenue,
        transactions: transactions,
        items: items,
        byMethod: byMethod,
        topProducts: topProducts,
        discounts: discounts,
        refunds: refunds,
        refundCount: refundCount,
        utangCharged: utangCharged,
        shift: s,
      );
}

class ShiftSummaryService {
  final dbHelper = DatabaseHelper.instance;

  /// Sums the window `(from, to]` — the same open-ended start
  /// [ShiftService.currentShiftSales] uses, so a sale rung at the exact
  /// second of the last close is not counted twice.
  Future<ShiftSummary> build(DateTime from, DateTime to) async {
    final db = await dbHelper.database;
    final args = [from.toIso8601String(), to.toIso8601String()];

    final head = await db.rawQuery('''
      SELECT COALESCE(SUM(total), 0) AS revenue,
             COUNT(*) AS transactions,
             COALESCE(SUM(item_count), 0) AS items,
             COALESCE(SUM(discount), 0) AS discounts,
             COALESCE(SUM(CASE WHEN LOWER(payment_method) = 'utang' THEN total ELSE 0 END), 0) AS utang
      FROM sales WHERE created_at > ? AND created_at <= ?
    ''', args);

    final methods = await db.rawQuery('''
      SELECT payment_method AS label, SUM(total) AS value, COUNT(*) AS units
      FROM sales WHERE created_at > ? AND created_at <= ?
      GROUP BY payment_method ORDER BY value DESC
    ''', args);

    final top = await db.rawQuery('''
      SELECT si.name AS label,
             SUM(si.line_total - si.discount) AS value,
             SUM(si.qty) AS units
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      WHERE s.created_at > ? AND s.created_at <= ?
      GROUP BY si.name ORDER BY units DESC, value DESC LIMIT 5
    ''', args);

    final refunds = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS amount, COUNT(*) AS count
      FROM refunds WHERE created_at > ? AND created_at <= ?
    ''', args);

    final h = head.first;
    final r = refunds.first;
    return ShiftSummary(
      from: from,
      to: to,
      revenue: (h['revenue'] as num).toDouble(),
      transactions: (h['transactions'] as num).toInt(),
      items: (h['items'] as num).toInt(),
      discounts: (h['discounts'] as num).toDouble(),
      utangCharged: (h['utang'] as num).toDouble(),
      byMethod: [
        for (final m in methods)
          BreakdownRow(
            label: m['label'] as String,
            value: (m['value'] as num).toDouble(),
            units: (m['units'] as num).toInt(),
          ),
      ],
      topProducts: [
        for (final t in top)
          BreakdownRow(
            label: t['label'] as String,
            value: (t['value'] as num).toDouble(),
            units: (t['units'] as num).toInt(),
          ),
      ],
      refunds: (r['amount'] as num).toDouble(),
      refundCount: (r['count'] as num).toInt(),
    );
  }

  /// The summary for a shift that has already been closed.
  Future<ShiftSummary> forShift(Shift s) async {
    final from = s.openedAt.isEmpty
        ? DateTime.parse(s.closedAt).subtract(const Duration(days: 1))
        : DateTime.parse(s.openedAt);
    final summary = await build(from, DateTime.parse(s.closedAt));
    return summary.withShift(s);
  }
}
