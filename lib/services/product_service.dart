import '../database/database_helper.dart';
import '../models/product_model.dart';

class ProductService {
  final dbHelper = DatabaseHelper.instance;

  Future<int> insertProduct(Product product) async {
    final db = await dbHelper.database;
    return await db.insert('products', product.toMap());
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

  /// Adds [delta] to the stored stock, clamped at zero.
  ///
  /// Prefer this over [updateStock] for restocks and any other adjustment: it
  /// is relative, so it cannot clobber a sale that landed in between. Use
  /// [updateStock] only when the user is stating what the stock actually is.
  Future<int> addStock(int id, int delta) async {
    final db = await dbHelper.database;
    return db.rawUpdate(
      'UPDATE products SET stock = MAX(0, stock + ?) WHERE id = ?',
      [delta, id],
    );
  }

  /// [addStock] for several products at once — a delivery, a market run —
  /// in one transaction, so a save either lands whole or not at all.
  /// [deltas] is productId → units; a negative delta takes them back (Undo).
  Future<void> addStockBatch(Map<int, int> deltas) async {
    if (deltas.isEmpty) return;
    final db = await dbHelper.database;
    await db.transaction((txn) async {
      for (final e in deltas.entries) {
        await txn.rawUpdate(
          'UPDATE products SET stock = MAX(0, stock + ?) WHERE id = ?',
          [e.value, e.key],
        );
      }
    });
  }

  Future<int> updateStock(int id, int newStock) async {
    final db = await dbHelper.database;
    return await db.update(
      'products',
      {'stock': newStock},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Sets every product's minimum at once — the "apply to every product"
  /// choice beside the default.
  Future<int> setAllMinStock(int minStock) async {
    final db = await dbHelper.database;
    return db.rawUpdate('UPDATE products SET min_stock = ?', [minStock]);
  }

  Future<int> updateProduct(Product product) async {
    final db = await dbHelper.database;
    return await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await dbHelper.database;
    return await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
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