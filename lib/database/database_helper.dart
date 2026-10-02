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
      version: 13,
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
    await _createStaffTable(db);
    await _createIndexes(db);
  }

  /// The lookups every screen makes, indexed so they stay quick after a year.
  ///
  /// Without these, "today's sales" reads every sale ever made, and a sale's
  /// lines are found by reading every line ever sold — invisible on a new
  /// install, and seconds on a budget phone after twelve months of trading.
  Future _createIndexes(Database db) async {
    for (final sql in [
      'CREATE INDEX IF NOT EXISTS idx_sales_created ON sales(created_at)',
      'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)',
      'CREATE INDEX IF NOT EXISTS idx_refunds_sale ON refunds(sale_id)',
      'CREATE INDEX IF NOT EXISTS idx_refunds_created ON refunds(created_at)',
      'CREATE INDEX IF NOT EXISTS idx_refund_items_refund ON refund_items(refund_id)',
    ]) {
      await db.execute(sql);
    }
  }

  /// Staff and their till PINs.
  ///
  /// Only the salt and the hash are stored — see `PinHasher` for what that is
  /// and is not worth. [failed_attempts] and [locked_until] back the lockout
  /// that does the real work of stopping someone guessing at the counter, and
  /// they live in the database rather than in memory so force-quitting the app
  /// does not clear them.
  Future _createStaffTable(Database db) async {
    await db.execute('''
      CREATE TABLE staff(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        pin_salt TEXT NOT NULL,
        pin_hash TEXT NOT NULL,
        pin_iterations INTEGER NOT NULL,
        is_manager INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        failed_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT,
        pin_is_default INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX idx_staff_name ON staff(name)');
  }

  /// Store credit ("utang"). The ledger is append-only: a charge is a positive
  /// amount, a payment is negative, and a customer's balance is their sum. That
  /// keeps history intact instead of overwriting a running total.
  Future _createUtangTables(Database db) async {
    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        phone TEXT,
        last_reminded_at TEXT,
        credit_limit REAL
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
        cashier TEXT NOT NULL DEFAULT '',
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
        sale_count INTEGER NOT NULL DEFAULT 0,
        utang_cash REAL NOT NULL DEFAULT 0
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

  /// v9 adds discounts and cashier attribution.
  ///
  /// The discount columns default to 0, which is the truth for every sale
  /// taken before this version: none of them had one. `cashier` defaults to
  /// empty rather than to whoever is signed in now — guessing would put a
  /// name on old sales that nobody can vouch for.
  Future _upgradeToV9(Database db) async {
    for (final sql in [
      'ALTER TABLE sales ADD COLUMN discount REAL NOT NULL DEFAULT 0',
      "ALTER TABLE sales ADD COLUMN discount_reason TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE sales ADD COLUMN cashier TEXT NOT NULL DEFAULT ''",
      'ALTER TABLE sale_items ADD COLUMN discount REAL NOT NULL DEFAULT 0',
      "ALTER TABLE refunds ADD COLUMN cashier TEXT NOT NULL DEFAULT ''",
    ]) {
      try {
        await db.execute(sql);
      } catch (_) {
        // Column already present on a database created fresh at v9.
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
        item_count INTEGER NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        discount_reason TEXT NOT NULL DEFAULT '',
        cashier TEXT NOT NULL DEFAULT ''
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
        discount REAL NOT NULL DEFAULT 0,
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
    if (oldVersion < 7) {
      await _createStaffTable(db);
    }
    if (oldVersion < 8) {
      // A v7 install seeded the starting codes and has no way to know it. Mark
      // everyone as still on a default so the warning appears; changing a PIN
      // clears the flag. A v8-fresh table already has the column, so guard it.
      try {
        await db.execute(
            'ALTER TABLE staff ADD COLUMN pin_is_default INTEGER NOT NULL DEFAULT 0');
        await db.update('staff', {'pin_is_default': 1});
      } catch (_) {
        // Column already present.
      }
    }
    if (oldVersion < 9) {
      await _upgradeToV9(db);
    }
    if (oldVersion < 10) {
      // v10: a phone number per customer, so a reminder can go straight to
      // their SMS, and when they were last reminded, so nobody is nagged
      // twice in a day. Both nullable — most suki are known by face.
      for (final sql in [
        'ALTER TABLE customers ADD COLUMN phone TEXT',
        'ALTER TABLE customers ADD COLUMN last_reminded_at TEXT',
      ]) {
        try {
          await db.execute(sql);
        } catch (_) {
          // Column already present on a database created fresh at v10.
        }
      }
    }
    if (oldVersion < 11) {
      await _createIndexes(db);
    }
    if (oldVersion < 12) {
      // v12: utang paid back in cash goes into the drawer, so a day close
      // records it beside cash sales. Closes before this had none counted.
      try {
        await db.execute('ALTER TABLE shifts ADD COLUMN utang_cash REAL NOT NULL DEFAULT 0');
      } catch (_) {
        // Column already present on a database created fresh at v12.
      }
    }
    if (oldVersion < 13) {
      // v13: a customer can have a credit limit of their own; null means the
      // store's default from Settings.
      try {
        await db.execute('ALTER TABLE customers ADD COLUMN credit_limit REAL');
      } catch (_) {
        // Column already present on a database created fresh at v13.
      }
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
  ///
  /// Staff are deliberately left alone. They are not store data, and clearing
  /// them would re-seed the roster with the starting PINs — a data wipe would
  /// quietly reset the manager's code to one printed in the source.
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