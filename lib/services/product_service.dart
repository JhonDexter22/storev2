import '../database/database_helper.dart';
import '../models/product_model.dart';
import '../models/stock_move.dart';
import 'stock_history.dart';

class ProductService {
  final dbHelper = DatabaseHelper.instance;

  /// Adds a product; its opening stock goes into the stock history.
  Future<int> insertProduct(Product product) async {
    final db = await dbHelper.database;
    return db.transaction((txn) async {
      final id = await txn.insert('products', product.toMap());
      await StockHistory.log(txn,
          productId: id,
          productName: product.name,
          delta: product.stock,
          stockAfter: product.stock,
          kind: StockMoveKind.added);
      return id;
    });
  }

  /// Puts back a product [deleteProduct] took, with its id, so its sales and
  /// stock history point at it again. Its stock coming back is logged as an
  /// Undo.
  Future<void> restoreDeleted(Product product) async {
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert('products', product.toMap());
      await StockHistory.log(txn,
          productId: product.id!,
          productName: product.name,
          delta: product.stock,
          stockAfter: product.stock,
          kind: StockMoveKind.undo);
    });
  }

  Future<List<Product>> getAllProducts() async {
    final db = await dbHelper.database;
    final result = await db.query('products', orderBy: 'created_at DESC');
    return result.map((json) => Product.fromMap(json)).toList();
  }

  Future<List<Product>> getLowStockProducts() async {
    final db = await dbHelper.database;
    final result = await db.query(
      'products',
      where: 'stock <= min_stock',
    );
    return result.map((json) => Product.fromMap(json)).toList();
  }

  /// Adds [delta] to the stored stock, clamped at zero, and logs it as
  /// [kind] — a restock, or an Undo taking one back.
  ///
  /// Prefer this over [updateStock] for restocks and any other adjustment: it
  /// is relative, so it cannot clobber a sale that landed in between. Use
  /// [updateStock] only when the user is stating what the stock actually is.
  Future<void> addStock(int id, int delta, {StockMoveKind kind = StockMoveKind.restock}) async {
    final db = await dbHelper.database;
    await db.transaction((txn) => StockHistory.move(txn, id, delta, kind));
  }

  /// [addStock] for several products at once — a delivery, a market run —
  /// in one transaction, so a save either lands whole or not at all.
  /// [deltas] is productId → units; a negative delta takes them back, with
  /// [kind] [StockMoveKind.undo].
  Future<void> addStockBatch(Map<int, int> deltas, {StockMoveKind kind = StockMoveKind.stockIn}) async {
    if (deltas.isEmpty) return;
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      for (final e in deltas.entries) {
        await StockHistory.move(txn, e.key, e.value, kind);
      }
    });
  }

  /// Sets the stock to what someone counted on the shelf, and logs the
  /// difference as a change by hand.
  Future<void> updateStock(int id, int newStock) async {
    final db = await dbHelper.database;
    await db.transaction((txn) => StockHistory.setTo(txn, id, newStock, StockMoveKind.count));
  }

  /// Sets every product's minimum at once — the "apply to every product"
  /// choice beside the default.
  Future<int> setAllMinStock(int minStock) async {
    final db = await dbHelper.database;
    return db.rawUpdate('UPDATE products SET min_stock = ?', [minStock]);
  }

  /// Saves a product's details — everything but its stock.
  ///
  /// Stock is left out on purpose: [product] is a copy loaded some time ago,
  /// and writing its stock back would quietly undo every sale since (a photo
  /// snapped after a sale used to). Stock changes through [addStock] or
  /// [updateStock], which log them.
  Future<int> updateProduct(Product product) async {
    final db = await dbHelper.database;
    return await db.update(
      'products',
      product.toMap()..remove('stock'),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  /// Deletes a product; any stock it still had is logged as going with it.
  /// Its history stays, for the store-wide log and for [restoreDeleted].
  Future<int> deleteProduct(int id) async {
    final db = await dbHelper.database;
    return db.transaction((txn) async {
      final rows = await txn.query('products',
          columns: ['name', 'stock'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return 0;
      final stock = rows.first['stock'] as int;
      await StockHistory.log(txn,
          productId: id,
          productName: rows.first['name'] as String,
          delta: -stock,
          stockAfter: 0,
          kind: StockMoveKind.deleted);
      return txn.delete('products', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Another product already on [sku], if any. A barcode must point at one
  /// product, or the scanner at the till picks between them.
  Future<Product?> otherWithSku(String sku, {int? exceptId}) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'products',
      where: exceptId == null ? 'LOWER(sku) = ?' : 'LOWER(sku) = ? AND id != ?',
      whereArgs: [sku.toLowerCase(), ?exceptId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return Product.fromMap(result.first);
  }

  /// Returns products whose SKU matches [sku] (case-insensitive).
  Future<Product?> findBySku(String sku) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'products',
      where: 'LOWER(sku) = ?',
      whereArgs: [sku.toLowerCase()],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return Product.fromMap(result.first);
  }
}