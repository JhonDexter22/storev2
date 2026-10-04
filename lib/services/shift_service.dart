import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import 'sales_service.dart';
import 'settings_service.dart';
import 'utang_service.dart';
import '../models/shift_model.dart';

class ShiftService {
  ShiftService({SalesService? sales, UtangService? utang})
      : _sales = sales,
        _utang = utang;

  final dbHelper = DatabaseHelper.instance;

  /// Injectable, so a screen that was handed its services computes the
  /// drawer from the same ones.
  final SalesService? _sales;
  final UtangService? _utang;

  /// When the drawer was last emptied: the last close, or the start of today
  /// if there has never been one. Every "since" on this screen counts from
  /// here — sales, cash and utang alike.
  Future<DateTime> shiftStart() async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    final lastClose = await db.query('shifts', orderBy: 'id DESC', limit: 1);
    return lastClose.isEmpty
        ? DateTime(now.year, now.month, now.day)
        : DateTime.parse(lastClose.first['closed_at'] as String);
  }

  /// Total sales and count since the last close (or start of day if this is
  /// the first close), so a shift card reports its own shift rather than the
  /// whole day.
  Future<({double total, int count, DateTime openedAt})> currentShiftSales() async {
    final db = await dbHelper.database;
    final since = await shiftStart();

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

  /// What should be in the drawer now, in its parts: the opening float,
  /// cash sales net of cash refunds, and utang paid back in cash — all since
  /// the last close. Cash count, Home and More all read it here so they
  /// cannot disagree.
  ///
  /// The cash used to run from midnight while the sales count ran from the
  /// last close, so a second close in a day expected the first one's cash
  /// all over again.
  Future<({double float, double cashSales, double utangCash, double expected})> drawerNow() async {
    final since = await shiftStart();
    final float = SettingsService.instance.openingFloat;
    final cashSales = await (_sales ?? SalesService()).cashSalesSince(since);
    final utangCash = await (_utang ?? UtangService()).cashCollectedSince(since);
    return (
      float: float,
      cashSales: cashSales,
      utangCash: utangCash,
      expected: float + cashSales + utangCash,
    );
  }

  Future<Shift> closeShift({
    required String cashier,
    required String terminal,
    required double openingFloat,
    required double cashSales,
    double utangCash = 0,
    required double counted,
    required Map<int, int> denominations,
    required double totalSales,
    required int saleCount,
    required DateTime openedAt,
  }) async {
    final db = await dbHelper.database;
    final expected = openingFloat + cashSales + utangCash;
    final shift = Shift(
      closedAt: DateTime.now().toIso8601String(),
      openedAt: openedAt.toIso8601String(),
      cashier: cashier,
      terminal: terminal,
      openingFloat: openingFloat,
      cashSales: cashSales,
      utangCash: utangCash,
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
      'utang_cash': shift.utangCash,
    });

    final row = await db.query('shifts', where: 'id = ?', whereArgs: [id]);
    return Shift.fromMap(row.first);
  }

  /// Newest first, a page at a time. [outcome] narrows to drawers that came
  /// up `short` or `over`.
  /// [cashier] narrows to the closes one person made.
  Future<List<Shift>> getShifts({int limit = 20, int offset = 0, String? outcome, String? cashier}) async {
    final db = await dbHelper.database;
    final where = [
      ?_outcomeWhere(outcome),
      if (cashier != null) 'cashier = ?',
    ];
    final rows = await db.query(
      'shifts',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: cashier == null ? null : [cashier],
      orderBy: 'id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((m) => Shift.fromMap(m)).toList();
  }

  /// Everyone who has closed a day, for the per-cashier filter.
  Future<List<String>> closingCashiers() async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery(
        "SELECT DISTINCT cashier FROM shifts WHERE cashier != '' ORDER BY cashier");
    return [for (final r in rows) r['cashier'] as String];
  }

  static String? _outcomeWhere(String? outcome) => switch (outcome) {
        'short' => 'variance < -0.005',
        'over' => 'variance > 0.005',
        _ => null,
      };

  /// Every close ever recorded.
  Future<int> closeCount() async {
    final db = await dbHelper.database;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM shifts')) ?? 0;
  }

  /// Sales, and shortages and overages kept apart, over closes in the last
  /// [days] days — optionally one [cashier]'s.
  ///
  /// Short and over used to be netted into one figure, so ₱500 short one day
  /// and ₱450 over another read as a harmless −₱50: the very leak this
  /// screen is for, hidden by its own total.
  Future<({double sales, double short, int shortDays, double over, int overDays})> totalsOver(
      int days, {String? cashier}) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(total_sales),0) AS s, '
      'COALESCE(SUM(CASE WHEN variance < -0.005 THEN -variance ELSE 0 END),0) AS short, '
      'COALESCE(SUM(CASE WHEN variance < -0.005 THEN 1 ELSE 0 END),0) AS short_n, '
      'COALESCE(SUM(CASE WHEN variance > 0.005 THEN variance ELSE 0 END),0) AS over, '
      'COALESCE(SUM(CASE WHEN variance > 0.005 THEN 1 ELSE 0 END),0) AS over_n '
      'FROM shifts WHERE closed_at >= ?${cashier == null ? '' : ' AND cashier = ?'}',
      [SalesService.windowStart(days).toIso8601String(), ?cashier],
    );
    final r = rows.first;
    return (
      sales: (r['s'] as num).toDouble(),
      short: (r['short'] as num).toDouble(),
      shortDays: (r['short_n'] as num).toInt(),
      over: (r['over'] as num).toDouble(),
      overDays: (r['over_n'] as num).toInt(),
    );
  }
}
