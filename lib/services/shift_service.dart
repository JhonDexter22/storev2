import '../database/database_helper.dart';
import '../models/shift_model.dart';

class ShiftService {
  final dbHelper = DatabaseHelper.instance;

  /// Total sales and count since the last close (or start of day if this is
  /// the first close), so a shift card reports its own shift rather than the
  /// whole day.
  Future<({double total, int count, DateTime openedAt})> currentShiftSales() async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final lastClose = await db.query('shifts', orderBy: 'id DESC', limit: 1);
    final since = lastClose.isEmpty
        ? startOfDay
        : DateTime.parse(lastClose.first['closed_at'] as String);

    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(total),0) AS total, COUNT(*) AS count '
      'FROM sales WHERE created_at > ?',
      [since.toIso8601String()],
    );
    return (
      total: (rows.first['total'] as num).toDouble(),
      count: (rows.first['count'] as num).toInt(),
      openedAt: since,
    );
  }

  Future<Shift> closeShift({
    required String cashier,
    required String terminal,
    required double openingFloat,
    required double cashSales,
    required double counted,
    required Map<int, int> denominations,
    required double totalSales,
    required int saleCount,
    required DateTime openedAt,
  }) async {
    final db = await dbHelper.database;
    final expected = openingFloat + cashSales;
    final shift = Shift(
      closedAt: DateTime.now().toIso8601String(),
      openedAt: openedAt.toIso8601String(),
      cashier: cashier,
      terminal: terminal,
      openingFloat: openingFloat,
      cashSales: cashSales,
      expected: expected,
      counted: counted,
      variance: counted - expected,
      denominations: denominations,
      totalSales: totalSales,
      saleCount: saleCount,
    );

    final id = await db.insert('shifts', {
      'closed_at': shift.closedAt,
      'opened_at': shift.openedAt,
      'cashier': shift.cashier,
      'terminal': shift.terminal,
      'opening_float': shift.openingFloat,
      'cash_sales': shift.cashSales,
      'expected': shift.expected,
      'counted': shift.counted,
      'variance': shift.variance,
      'denominations': shift.denominationsJson,
      'total_sales': shift.totalSales,
      'sale_count': shift.saleCount,
    });

    final row = await db.query('shifts', where: 'id = ?', whereArgs: [id]);
    return Shift.fromMap(row.first);
  }

  Future<List<Shift>> getShifts({int limit = 20}) async {
    final db = await dbHelper.database;
    final rows = await db.query('shifts', orderBy: 'id DESC', limit: limit);
    return rows.map((m) => Shift.fromMap(m)).toList();
  }
}
