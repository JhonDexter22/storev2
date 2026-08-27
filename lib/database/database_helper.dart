import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('restock.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        stock INTEGER NOT NULL,
        min_stock INTEGER NOT NULL,
        category TEXT,
        created_at TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        sku TEXT,
        image_path TEXT
      )
    ''');
    await _createSalesTables(db);
  }

  Future _createSalesTables(Database db) async {
    await db.execute('''
      CREATE TABLE sales(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        reference TEXT NOT NULL,
        created_at TEXT NOT NULL,
        subtotal REAL NOT NULL,
        total REAL NOT NULL,
        payment_method TEXT NOT NULL,
        cash_received REAL NOT NULL DEFAULT 0,
        change_amount REAL NOT NULL DEFAULT 0,
        item_count INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sale_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        unit_price REAL NOT NULL,
        qty INTEGER NOT NULL,
        line_total REAL NOT NULL,
        FOREIGN KEY(sale_id) REFERENCES sales(id)
      )
    ''');
  }

  /// Migrates existing DB (v1 → v2) by adding the three new columns.
  /// Uses IF NOT EXISTS-style guards via try/catch so re-runs are safe.
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      for (final sql in [
        'ALTER TABLE products ADD COLUMN price REAL NOT NULL DEFAULT 0.0',
        'ALTER TABLE products ADD COLUMN sku TEXT',
        'ALTER TABLE products ADD COLUMN image_path TEXT',
      ]) {
        try {
          await db.execute(sql);
        } catch (_) {
          // Column may already exist on repeated upgrades — safe to ignore.
        }
      }
    }
    if (oldVersion < 3) {
      await _createSalesTables(db);
    }
  }
// Idagdag ito sa loob ng DatabaseHelper class
  Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await instance.database;
    // I-insert sa table mo. Kapag successful, ibabalik nito ang bagong id ng product.
    return await db.insert('products', product);
  }

  /// Wipes all store data (products and sales history). Irreversible.
  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('sale_items');
    await db.delete('sales');
    await db.delete('products');
  }


}