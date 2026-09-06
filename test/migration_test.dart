import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/services/staff_service.dart';

/// The schemas this app actually shipped, written out by hand.
///
/// Deliberately not built from [DatabaseHelper]'s own `_createDB`: a migration
/// test that reuses the current schema proves only that the current schema
/// equals itself. These are the tables as they existed at each version, so an
/// upgrade is exercised against what is really on a shopkeeper's phone.
class _Historical {
  /// Applies every schema step up to and including [version].
  static Future<void> createAt(Database db, int version) async {
    // v1 — products only, before prices existed.
    await db.execute('''
      CREATE TABLE products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        stock INTEGER NOT NULL,
        min_stock INTEGER NOT NULL,
        category TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    if (version >= 2) {
      await db.execute('ALTER TABLE products ADD COLUMN price REAL NOT NULL DEFAULT 0.0');
      await db.execute('ALTER TABLE products ADD COLUMN sku TEXT');
      await db.execute('ALTER TABLE products ADD COLUMN image_path TEXT');
    }

    if (version >= 3) {
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

    if (version >= 4) {
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
          denominations TEXT NOT NULL
        )
      ''');
    }

    if (version >= 5) {
      await db.execute("ALTER TABLE shifts ADD COLUMN opened_at TEXT NOT NULL DEFAULT ''");
      await db.execute('ALTER TABLE shifts ADD COLUMN total_sales REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE shifts ADD COLUMN sale_count INTEGER NOT NULL DEFAULT 0');
    }

    if (version >= 6) {
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

    if (version >= 7) {
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
          locked_until TEXT
        )
      ''');
      await db.execute('CREATE UNIQUE INDEX idx_staff_name ON staff(name)');
    }

    if (version >= 8) {
      await db.execute(
          'ALTER TABLE staff ADD COLUMN pin_is_default INTEGER NOT NULL DEFAULT 0');
    }

    if (version >= 9) {
      await db.execute('ALTER TABLE sales ADD COLUMN discount REAL NOT NULL DEFAULT 0');
      await db.execute("ALTER TABLE sales ADD COLUMN discount_reason TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE sales ADD COLUMN cashier TEXT NOT NULL DEFAULT ''");
      await db.execute('ALTER TABLE sale_items ADD COLUMN discount REAL NOT NULL DEFAULT 0');
      await db.execute("ALTER TABLE refunds ADD COLUMN cashier TEXT NOT NULL DEFAULT ''");
    }
  }

  /// Puts one representative row in every table that exists at [version], so
  /// an upgrade has real data to preserve rather than empty tables.
  static Future<void> seed(Database db, int version) async {
    await db.insert('products', {
      'name': 'Lucky Me, Pancit Canton',
      'stock': 12,
      'min_stock': 5,
      'category': 'Noodles',
      'created_at': '2026-01-02T03:04:05.000000',
      if (version >= 2) 'price': 17.5,
      if (version >= 2) 'sku': '4800016',
    });

    if (version >= 3) {
      await db.insert('sales', {
        'reference': 'S20260102-0001',
        'created_at': '2026-01-02T03:04:05.000000',
        'subtotal': 35.0,
        'total': 35.0,
        'payment_method': 'Cash',
        'cash_received': 50.0,
        'change_amount': 15.0,
        'item_count': 2,
      });
      await db.insert('sale_items', {
        'sale_id': 1,
        'product_id': 1,
        'name': 'Lucky Me, Pancit Canton',
        'unit_price': 17.5,
        'qty': 2,
        'line_total': 35.0,
      });
    }

    if (version >= 4) {
      await db.insert('refunds', {
        'sale_id': 1,
        'sale_reference': 'S20260102-0001',
        'created_at': '2026-01-02T05:00:00.000000',
        'amount': 17.5,
        'reason': 'Damaged',
        'method': 'Cash',
        'is_void': 0,
        'restocked': 1,
      });
      await db.insert('refund_items', {
        'refund_id': 1,
        'product_id': 1,
        'name': 'Lucky Me, Pancit Canton',
        'qty': 1,
        'unit_price': 17.5,
        'line_total': 17.5,
      });
      await db.insert('shifts', {
        'closed_at': '2026-01-02T20:00:00.000000',
        'cashier': 'May',
        'terminal': 'Terminal 1',
        'opening_float': 1000.0,
        'cash_sales': 35.0,
        'expected': 1035.0,
        'counted': 1035.0,
        'variance': 0.0,
        'denominations': '{"1000":1,"20":1,"10":1,"5":1}',
      });
    }

    if (version >= 6) {
      await db.insert('customers', {
        'name': 'Aling Nena',
        'created_at': '2026-01-02T03:04:05.000000',
      });
      await db.insert('utang_entries', {
        'customer_id': 1,
        'created_at': '2026-01-02T03:04:05.000000',
        'amount': 120.0,
        'kind': 'charge',
        'note': 'Sardinas',
      });
    }

    if (version >= 7) {
      await db.insert('staff', {
        'name': 'May',
        'role': 'Cashier',
        'pin_salt': 'c2FsdHNhbHRzYWx0c2ExMg==',
        'pin_hash': 'aGFzaA==',
        'pin_iterations': 20000,
        'is_manager': 0,
        'active': 1,
        'created_at': '2026-01-02T03:04:05.000000',
      });
    }
  }
}

void main() {
  late Directory temp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('storev2-migration');
  });

  tearDown(() async {
    await DatabaseHelper.resetForTests();
    DatabaseHelper.testDatabasePath = null;
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// Lays down a database as it looked at [version], seeds it, then opens it
  /// through [DatabaseHelper] — which is what runs the real upgrade path.
  Future<Database> upgradeFrom(int version) async {
    final path = '${temp.path}/restock.db';
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, v) async {
          await _Historical.createAt(db, v);
          await _Historical.seed(db, v);
        },
      ),
    );
    await old.close();

    await DatabaseHelper.resetForTests();
    DatabaseHelper.testDatabasePath = path;
    return DatabaseHelper.instance.database;
  }

  Future<Set<String>> columnsOf(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((c) => c['name'] as String).toSet();
  }

  Future<int> countOf(Database db, String table) async =>
      Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
      0;

  group('every shipped version upgrades to the current one', () {
    for (var from = 1; from <= 9; from++) {
      test('v$from reaches v9 with its data intact', () async {
        final db = await upgradeFrom(from);

        expect(await db.getVersion(), 9);

        // The product predates every migration, so it is the row that proves
        // an upgrade moved the schema without touching the data.
        final product = (await db.query('products')).single;
        expect(product['name'], 'Lucky Me, Pancit Canton');
        expect(product['stock'], 12);
        expect(product['min_stock'], 5);
        expect(product['category'], 'Noodles');
        expect(product['created_at'], '2026-01-02T03:04:05.000000');

        // Columns added at v2 exist either way; a v1 row gets the declared
        // default rather than null, which would break every price calculation.
        expect(await columnsOf(db, 'products'),
            containsAll(['price', 'sku', 'image_path']));
        expect(product['price'], from >= 2 ? 17.5 : 0.0);

        // Every table the current app expects must be present, whatever the
        // database started as.
        for (final table in [
          'products',
          'sales',
          'sale_items',
          'refunds',
          'refund_items',
          'shifts',
          'customers',
          'utang_entries',
          'staff',
        ]) {
          expect(await countOf(db, table), isNonNegative,
              reason: '$table should exist after upgrading from v$from');
        }
      });
    }
  });

  group('data added before a migration survives it', () {
    test('a v3 sale keeps its figures and gains the v9 columns', () async {
      final db = await upgradeFrom(3);
      final sale = (await db.query('sales')).single;

      expect(sale['reference'], 'S20260102-0001');
      expect(sale['total'], 35.0);
      expect(sale['cash_received'], 50.0);
      expect(sale['change_amount'], 15.0);

      // Defaults chosen to be true of a sale taken before discounts existed:
      // it had none, and nobody recorded who rang it.
      expect(sale['discount'], 0.0);
      expect(sale['discount_reason'], '');
      expect(sale['cashier'], '');
    });

    test('a v3 sale line gains a zero discount, not a null', () async {
      final db = await upgradeFrom(3);
      final item = (await db.query('sale_items')).single;
      expect(item['line_total'], 35.0);
      // Null here would break the net-total arithmetic everywhere it is read.
      expect(item['discount'], 0.0);
    });

    test('a v4 refund and shift survive to v9', () async {
      final db = await upgradeFrom(4);

      final refund = (await db.query('refunds')).single;
      expect(refund['amount'], 17.5);
      expect(refund['reason'], 'Damaged');
      expect(refund['cashier'], '');

      final shift = (await db.query('shifts')).single;
      expect(shift['cashier'], 'May');
      expect(shift['counted'], 1035.0);
      expect(shift['denominations'], '{"1000":1,"20":1,"10":1,"5":1}');
      // The v5 columns, defaulted rather than guessed.
      expect(shift['opened_at'], '');
      expect(shift['total_sales'], 0.0);
      expect(shift['sale_count'], 0);
    });

    test('a v6 utang ledger survives to v9', () async {
      final db = await upgradeFrom(6);
      expect((await db.query('customers')).single['name'], 'Aling Nena');
      final entry = (await db.query('utang_entries')).single;
      expect(entry['amount'], 120.0);
      expect(entry['kind'], 'charge');
      expect(entry['note'], 'Sardinas');
    });
  });

  group('staff across the v7 and v8 boundaries', () {
    test('a v7 install is flagged as still on the starting PINs', () async {
      final db = await upgradeFrom(7);
      final row = (await db.query('staff')).single;

      expect(row['name'], 'May');
      expect(row['pin_hash'], 'aGFzaA==', reason: 'the PIN must not be reset');
      // A v7 database had no way to record this, so the upgrade assumes the
      // worst and shows the warning rather than staying quiet.
      expect(row['pin_is_default'], 1);
    });

    test('a v8 install keeps whatever flag it already had', () async {
      final path = '${temp.path}/restock.db';
      final old = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (db, v) async {
            await _Historical.createAt(db, v);
            await _Historical.seed(db, v);
            // Someone who already rotated off the shipped code.
            await db.update('staff', {'pin_is_default': 0});
          },
        ),
      );
      await old.close();

      await DatabaseHelper.resetForTests();
      DatabaseHelper.testDatabasePath = path;
      final db = await DatabaseHelper.instance.database;

      expect((await db.query('staff')).single['pin_is_default'], 0,
          reason: 'upgrading must not re-flag a PIN that was already changed');
    });

    test('an upgrade from before v7 leaves the roster empty to be seeded',
        () async {
      final db = await upgradeFrom(6);
      // StaffService fills it on first read; creating rows here would mean
      // hashing during a migration.
      expect(await countOf(db, 'staff'), 0);
      expect((await StaffService().roster()).length,
          StaffService.seedRoster.length);
    });
  });

  group('the ladder is safe to re-run', () {
    test('reopening an upgraded database changes nothing', () async {
      final db = await upgradeFrom(1);
      final before = await db.query('products');
      await DatabaseHelper.resetForTests();

      final again = await DatabaseHelper.instance.database;
      expect(await again.getVersion(), 9);
      expect(await again.query('products'), before);
    });

    test('a database already at v9 is left alone', () async {
      final db = await upgradeFrom(9);
      expect(await db.getVersion(), 9);
      expect((await db.query('products')).single['price'], 17.5);
    });
  });
}
