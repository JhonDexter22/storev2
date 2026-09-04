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

  Future<int> updateStock(int id, int newStock) async {
    final db = await dbHelper.database;
    return await db.update(
      'products',
      {'stock': newStock},
      where: 'id = ?',
      whereArgs: [id],
    );
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