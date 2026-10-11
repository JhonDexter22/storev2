import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/stock_move.dart';
import 'settings_service.dart';

/// The one way stock changes: every write goes through [move] or [setTo],
/// which change the product and log the change in the same step. Pass them
/// the transaction the caller is already in, so the change and its record
/// land together or not at all.
class StockHistory {
  StockHistory({DatabaseHelper? dbHelper}) : dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper dbHelper;

  /// Adds [delta] to [productId]'s stock, never below zero, and logs what
  /// actually changed. Returns the stock after, or null when there is no such
  /// product (a quick item, or one deleted meanwhile).
  ///
  /// Relative on purpose: it reads the stored stock inside the transaction,
  /// so a sale and a restock landing together both count.
  static Future<int?> move(
    Transaction txn,
    int productId,
    int delta,
    StockMoveKind kind, {
    String? cashier,
    String reference = '',
  }) async {
    final row = await _product(txn, productId);
    if (row == null) return null;
    return _write(txn, productId, row, math.max(0, row.stock + delta), kind, cashier, reference);
  }

  /// Sets [productId]'s stock to [stock], as when someone counts the shelf
  /// and types what is there, and logs the difference.
  static Future<int?> setTo(
    Transaction txn,
    int productId,
    int stock,
    StockMoveKind kind, {
    String? cashier,
  }) async {
    final row = await _product(txn, productId);
    if (row == null) return null;
    return _write(txn, productId, row, math.max(0, stock), kind, cashier, '');
  }

  /// Logs stock that arrives or leaves with the product itself — a new
  /// product's opening stock, or what goes with a deleted one — without
  /// touching the products table.
  static Future<void> log(
    Transaction txn, {
    required int productId,
    required String productName,
    required int delta,
    required int stockAfter,
    required StockMoveKind kind,
    String? cashier,
  }) async {
    if (delta == 0) return;
    await txn.insert('stock_moves', {
      'product_id': productId,
      'product_name': productName,
      'created_at': DateTime.now().toIso8601String(),
      'kind': kind.key,
      'delta': delta,
      'stock_after': stockAfter,
      'cashier': cashier ?? SettingsService.instance.cashier,
      'reference': '',
    });
  }

  static Future<({int stock, String name})?> _product(Transaction txn, int productId) async {
    final rows = await txn.query('products',
        columns: ['stock', 'name'], where: 'id = ?', whereArgs: [productId], limit: 1);
    if (rows.isEmpty) return null;
    return (stock: rows.first['stock'] as int, name: rows.first['name'] as String);
  }

  static Future<int> _write(
    Transaction txn,
    int productId,
    ({int stock, String name}) before,
    int after,
    StockMoveKind kind,
    String? cashier,
    String reference,
  ) async {
    // Nothing moved — a sale of something already at zero, a count that
    // matches — so there is nothing to explain later.
    if (after == before.stock) return after;
    await txn.update('products', {'stock': after}, where: 'id = ?', whereArgs: [productId]);
    await txn.insert('stock_moves', {
      'product_id': productId,
      'product_name': before.name,
      'created_at': DateTime.now().toIso8601String(),
      'kind': kind.key,
      'delta': after - before.stock,
      'stock_after': after,
      'cashier': cashier ?? SettingsService.instance.cashier,
      'reference': reference,
    });
    return after;
  }

  // ── Reading ─────────────────────────────────────────────────────────────

  /// Newest first, a page at a time. [productId] narrows it to one product;
  /// [kinds] to some kinds of change.
  Future<List<StockMove>> moves({
    int? productId,
    Set<StockMoveKind>? kinds,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await dbHelper.database;
    final where = <String>[];
    final args = <Object?>[];
    if (productId != null) {
      where.add('product_id = ?');
      args.add(productId);
    }
    if (kinds != null && kinds.isNotEmpty) {
      where.add('kind IN (${List.filled(kinds.length, '?').join(', ')})');
      args.addAll(kinds.map((k) => k.key));
    }
    final rows = await db.query(
      'stock_moves',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      // The id breaks ties within the same instant: a sale's lines, a batch.
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(StockMove.fromMap).toList();
  }
}
