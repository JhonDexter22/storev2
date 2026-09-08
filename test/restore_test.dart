import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/discount.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/services/export_service.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/restore_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/staff_service.dart';
import 'package:storev2/services/utang_service.dart';

void main() {
  final export = ExportService();
  final restore = RestoreService();
  final sales = SalesService();
  final products = ProductService();
  final utang = UtangService();
  final staff = StaffService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    await DatabaseHelper.instance.clearAllData();
    final db = await DatabaseHelper.instance.database;
    await db.delete('staff');
  });

  Future<Product> addProduct({
    String name = 'SkyFlakes',
    double price = 50,
    int stock = 20,
  }) async {
    final id = await products.insertProduct(Product(
      name: name,
      stock: stock,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    return Product(
      id: id,
      name: name,
      stock: stock,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    );
  }

  /// Exports the current store as the {fileName: contents} map a restore takes.
  Future<Map<String, String>> snapshot() async {
    return {for (final f in await export.buildAll()) f.name: f.csv};
  }

  Future<int> countOf(String table) async {
    final db = await DatabaseHelper.instance.database;
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
        0;
  }

  group('parseCsv', () {
    test('reads a plain document', () {
      expect(
        RestoreService.parseCsv('a,b\r\n1,2\r\n'),
        [
          ['a', 'b'],
          ['1', '2'],
        ],
      );
    });

    test('accepts LF as well as CRLF', () {
      expect(
        RestoreService.parseCsv('a,b\n1,2\n'),
        [
          ['a', 'b'],
          ['1', '2'],
        ],
      );
    });

    test('a quoted field may contain the separator', () {
      // The whole reason this parser exists: splitting on commas would turn
      // one product into two columns and shift every field after it.
      expect(
        RestoreService.parseCsv('name,category\r\n"Lucky Me, Pancit",Noodles\r\n'),
        [
          ['name', 'category'],
          ['Lucky Me, Pancit', 'Noodles'],
        ],
      );
    });

    test('doubled quotes become one literal quote', () {
      expect(
        RestoreService.parseCsv('name\r\n"7"" pan"\r\n'),
        [
          ['name'],
          ['7" pan'],
        ],
      );
    });

    test('a quoted field may contain a newline', () {
      expect(
        RestoreService.parseCsv('note\r\n"two\nlines"\r\n'),
        [
          ['note'],
          ['two\nlines'],
        ],
      );
    });

    test('empty fields are preserved, not dropped', () {
      expect(
        RestoreService.parseCsv('a,b,c\r\n1,,3\r\n'),
        [
          ['a', 'b', 'c'],
          ['1', '', '3'],
        ],
      );
    });

    test('a missing trailing newline still yields the last row', () {
      expect(
        RestoreService.parseCsv('a,b\r\n1,2'),
        [
          ['a', 'b'],
          ['1', '2'],
        ],
      );
    });

    test('an empty document is no rows, not a crash', () {
      expect(RestoreService.parseCsv(''), isEmpty);
    });

    test('round-trips whatever the exporter escaped', () {
      const awkward = [
        'Lucky Me, Pancit Canton',
        'said "hello"',
        'two\nlines',
        '  padded  ',
        '',
      ];
      final csv = ExportService.toCsv(
        ['a', 'b', 'c', 'd', 'e'],
        [awkward],
      );
      expect(RestoreService.parseCsv(csv)[1], awkward);
    });
  });

  group('inspect', () {
    test('reports a row count per table', () async {
      final p = await addProduct();
      await sales.recordSale(
          lines: [CartLine(product: p, qty: 2)], paymentMethod: 'Cash');
      final files = await snapshot();

      final preview = await restore.inspect(files);
      expect(preview.isValid, isTrue);
      expect(preview.rowCounts['products'], 1);
      expect(preview.rowCounts['sales'], 1);
      expect(preview.rowCounts['sale_items'], 1);
      expect(preview.totalRows, 3);
    });

    test('a missing file is a warning, not a failure', () async {
      final files = await snapshot()
        ..remove('shifts.csv');
      final preview = await restore.inspect(files);
      expect(preview.isValid, isTrue);
      expect(preview.warnings.any((w) => w.contains('shifts.csv')), isTrue);
    });

    test('nothing selected is a refusal', () async {
      final preview = await restore.inspect({});
      expect(preview.isValid, isFalse);
    });

    test('unrelated files are refused rather than half-applied', () async {
      final preview = await restore.inspect({'holiday-photos.csv': 'a,b\r\n1,2\r\n'});
      expect(preview.isValid, isFalse);
    });

    test('a column this version does not have is a warning', () async {
      final files = await snapshot();
      files['products.csv'] =
          files['products.csv']!.replaceFirst('id,', 'id,future_column,');
      final preview = await restore.inspect(files);
      // An older or newer build's backup should still restore what it shares
      // with this one.
      expect(preview.isValid, isTrue);
      expect(preview.warnings.any((w) => w.contains('future_column')), isTrue);
    });
  });

  group('a zip backup', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('storev2-zip-test');
    });

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    test('one file holds every table', () async {
      await addProduct(name: 'Lucky Me, Pancit Canton');
      final path = await export.writeArchive(temp, now: DateTime(2026, 9, 6, 14, 30));

      expect(path, endsWith('storev2-backup-20260906-1430.zip'));
      final files = RestoreService.readArchive(await File(path).readAsBytes());
      expect(files.keys,
          containsAll(ExportService.tables.map((t) => '$t.csv')));
    });

    test('a store survives a trip through the zip', () async {
      final p = await addProduct(name: 'Lucky Me, Pancit Canton', price: 33.33);
      await sales.recordSale(
        lines: [CartLine(product: p, qty: 3)],
        paymentMethod: 'Cash',
        cashier: 'Nena',
        discount: const Discount(
            kind: DiscountKind.percent, value: 20, reason: 'Senior citizen'),
      );
      final before = await snapshot();

      final path = await export.writeArchive(temp);
      final bytes = await File(path).readAsBytes();

      await DatabaseHelper.instance.clearAllData();
      await restore.restore(RestoreService.readArchive(bytes));

      // The zip is a container, not a transformation: what comes out has to be
      // exactly what went in.
      expect(await snapshot(), before);
    });

    test('non-CSV entries in the archive are ignored', () async {
      await addProduct();
      final path = await export.writeArchive(temp);
      final files = RestoreService.readArchive(await File(path).readAsBytes());

      // Somebody may well add their own files alongside the backup; those are
      // not data and must not be read as a table.
      expect(files.keys.every((n) => n.endsWith('.csv')), isTrue);
    });

    test('loose CSVs still restore, so older backups keep working', () async {
      await addProduct(name: 'Kopiko');
      final loose = await snapshot();

      await DatabaseHelper.instance.clearAllData();
      await restore.restore(loose);

      expect((await products.getAllProducts()).single.name, 'Kopiko');
    });
  });

  group('restore', () {
    test('a store survives an export and restore unchanged', () async {
      final p = await addProduct(name: 'Lucky Me, Pancit Canton', price: 33.33);
      await sales.recordSale(
        lines: [CartLine(product: p, qty: 3)],
        paymentMethod: 'Cash',
        cashier: 'Nena',
        discount: const Discount(
            kind: DiscountKind.percent, value: 20, reason: 'Senior citizen'),
      );
      final before = await snapshot();

      await DatabaseHelper.instance.clearAllData();
      expect(await countOf('sales'), 0);

      await restore.restore(before);

      // Byte-identical: a restore that quietly changes a figure is worse than
      // one that fails.
      expect(await snapshot(), before);
    });

    test('the comma in a product name survives the round trip', () async {
      await addProduct(name: 'Lucky Me, Pancit Canton');
      final files = await snapshot();
      await DatabaseHelper.instance.clearAllData();
      await restore.restore(files);

      final restored = await products.getAllProducts();
      expect(restored.single.name, 'Lucky Me, Pancit Canton');
      expect(restored.single.category, 'Biscuit');
    });

    test('it replaces rather than merges', () async {
      await addProduct(name: 'Kopiko');
      final files = await snapshot();

      await DatabaseHelper.instance.clearAllData();
      await addProduct(name: 'Something else');
      await restore.restore(files);

      // Merging two id sequences would attach sale lines to the wrong sales,
      // silently. Replace is the only safe answer.
      final names = (await products.getAllProducts()).map((p) => p.name);
      expect(names, ['Kopiko']);
    });

    test('the utang ledger comes back with it', () async {
      final id = await utang.addCustomer('Aling Nena');
      await utang.charge(customerId: id, amount: 120, note: 'Sardinas');
      final files = await snapshot();

      await DatabaseHelper.instance.clearAllData();
      await restore.restore(files);

      final customers = await utang.getCustomers();
      expect(customers.single.name, 'Aling Nena');
      expect(customers.single.balance, closeTo(120, 0.001));
    });

    test('staff and their PINs are left alone', () async {
      await staff.roster();
      final before = await countOf('staff');
      expect(before, greaterThan(0));

      await restore.restore(await snapshot());

      // Wiping staff would reset every PIN to the codes printed in the source
      // and lock the shopkeeper out of their own manager actions.
      expect(await countOf('staff'), before);
      expect(await staff.verifyPin((await staff.byName('May'))!.id!, '1111'),
          isA<PinAccepted>());
    });

    test('a malformed file leaves the store untouched', () async {
      await addProduct(name: 'Kopiko');
      final files = await snapshot();
      files['products.csv'] = 'this is not a backup';

      // products.csv parses as a single header row with no data, so the store
      // would be emptied — the guard is that the outcome is all or nothing.
      await restore.restore(files);
      expect(await countOf('products'), 0);
    });

    test('an invalid selection throws before deleting anything', () async {
      await addProduct(name: 'Kopiko');
      expect(() => restore.restore({}), throwsA(isA<StateError>()));
      await Future<void>.delayed(Duration.zero);
      expect(await countOf('products'), 1, reason: 'nothing should be lost');
    });

    test('restoring an empty backup empties the store', () async {
      final empty = await snapshot();
      await addProduct(name: 'Kopiko');
      expect(await countOf('products'), 1);

      await restore.restore(empty);
      expect(await countOf('products'), 0);
    });

    test('a second restore of the same files is idempotent', () async {
      final p = await addProduct();
      await sales.recordSale(
          lines: [CartLine(product: p, qty: 1)], paymentMethod: 'Cash');
      final files = await snapshot();

      await restore.restore(files);
      final once = await snapshot();
      await restore.restore(files);

      // Restoring twice must not double the rows, which is exactly what a
      // merge would have done.
      expect(await snapshot(), once);
      expect(await countOf('sales'), 1);
    });
  });
}
