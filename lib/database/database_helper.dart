import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  /// Overrides where the database lives. Left null in production; tests set it
  /// (typically to `inMemoryDatabasePath`) so each suite gets its own store
  /// instead of sharing one file and interfering with each other.
  static String? testDatabasePath;

  /// Drops the cached connection so the next access reopens. Tests only.
  static Future<void> resetForTests() async {
    await _database?.close();
    _database = null;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('restock.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final override = testDatabasePath;
    final path = override ?? join(await getDatabasesPath(), filePath);

    return await openDatabase(
      path,
      version: 6,
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
    await _createReturnsAndShiftTables(db);
    await _createUtangTables(db);
  }

  /// Store credit ("utang"). The ledger is append-only: a charge is a positive
  /// amount, a payment is negative, and a customer's balance is their sum. That
  /// keeps history intact instead of overwriting a running total.
  Future _createUtangTables(Database db) async {
    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE utang_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        sale_id INTEGER,
        created_at TEXT NOT NULL,
        amount REAL NOT NULL,
        kind TEXT NOT NULL,
        method TEXT,
        note TEXT,
        FOREIGN KEY(customer_id) REFERENCES customers(id)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_utang_customer ON utang_entries(customer_id, created_at)');
  }

  /// Refunds cover both partial returns and full voids — a void is just a
  /// return of every line, so both leave the same trail.
  Future _createReturnsAndShiftTables(Database db) async {
    await db.execute('''
      CREATE TABLE refunds(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        sale_reference TEXT NOT NULL,
        created_at TEXT NOT NULL,
        amount REAL NOT NULL,
        reason TEXT NOT NULL,
        method TEXT NOT NULL,
        is_void INTEGER NOT NULL DEFAULT 0,
        restocked INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY(sale_id) REFERENCES sales(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE refund_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        refund_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        qty INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        line_total REAL NOT NULL,
        FOREIGN KEY(refund_id) REFERENCES refunds(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE shifts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        closed_at TEXT NOT NULL,
        cashier TEXT NOT NULL,
        terminal TEXT NOT NULL,
        opening_float REAL NOT NULL,
        cash_sales REAL NOT NULL,
        expected REAL NOT NULL,
        counted REAL NOT NULL,
        variance REAL NOT NULL,
        denominations TEXT NOT NULL,
        opened_at TEXT NOT NULL DEFAULT '',
        total_sales REAL NOT NULL DEFAULT 0,
        sale_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// v5 adds the figures the shift-history card needs: when the shift opened,
  /// and total sales across all payment methods (not just the cash that lands
  /// in the drawer).
  Future _upgradeShiftsToV5(Database db) async {
    for (final sql in [
      "ALTER TABLE shifts ADD COLUMN opened_at TEXT NOT NULL DEFAULT ''",
      'ALTER TABLE shifts ADD COLUMN total_sales REAL NOT NULL DEFAULT 0',
      'ALTER TABLE shifts ADD COLUMN sale_count INTEGER NOT NULL DEFAULT 0',
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {
        // Column already present — safe to ignore on repeated upgrades.
      }
    }
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
    if (oldVersion < 4) {
      await _createReturnsAndShiftTables(db);
    }
    if (oldVersion < 5) {
      // A v4 database has a shifts table without the v5 columns; a database
      // created fresh at v5 already has them, so guard the ALTERs.
      await _upgradeShiftsToV5(db);
    }
    if (oldVersion < 6) {
      await _createUtangTables(db);
    }
  }
// Idagdag ito sa loob ng DatabaseHelper class
  Future<int> insertProduct(Map<String, dynamic> product) async {
    final db = await instance.database;
    // I-insert sa table mo. Kapag successful, ibabalik nito ang bagong id ng product.
    return await db.insert('products', product);
  }

  /// Wipes all store data (products, sales, refunds, shifts and the utang
  /// ledger). Irreversible.
  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('utang_entries');
    await db.delete('customers');
    await db.delete('refund_items');
    await db.delete('refunds');
    await db.delete('shifts');
    await db.delete('sale_items');
    await db.delete('sales');
    await db.delete('products');
  }


}