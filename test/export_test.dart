import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/discount.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/services/export_service.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/utang_service.dart';

void main() {
  final export = ExportService();
  final sales = SalesService();
  final products = ProductService();
  final utang = UtangService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    await DatabaseHelper.instance.clearAllData();
  });

  Future<Product> addProduct({String name = 'SkyFlakes', double price = 10}) async {
    final id = await products.insertProduct(Product(
      name: name,
      stock: 20,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    ));
    return Product(
      id: id,
      name: name,
      stock: 20,
      minStock: 5,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: price,
    );
  }

  /// Splits a CSV line the way a reader would, respecting quoting.
  List<String> parseLine(String line) {
    final out = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        out.add(field.toString());
        field.clear();
      } else {
        field.write(c);
      }
    }
    out.add(field.toString());
    return out;
  }

  group('escapeField', () {
    test('plain text is left alone', () {
      expect(ExportService.escapeField('SkyFlakes'), 'SkyFlakes');
      expect(ExportService.escapeField(42), '42');
      expect(ExportService.escapeField(12.5), '12.5');
    });

    test('null becomes an empty field, not the word null', () {
      // 'null' in a price column would import as text and poison the sum.
      expect(ExportService.escapeField(null), '');
    });

    test('a comma forces quoting', () {
      // Real sari-sari stock: "Lucky Me, Pancit Canton". Unquoted, every later
      // column shifts by one and nothing reports an error.
      expect(ExportService.escapeField('Lucky Me, Pancit Canton'),
          '"Lucky Me, Pancit Canton"');
    });

    test('quotes are doubled and the field wrapped', () {
      expect(ExportService.escapeField('7" pan'), '"7"" pan"');
    });

    test('newlines are quoted rather than breaking the row', () {
      expect(ExportService.escapeField('two\nlines'), '"two\nlines"');
      expect(ExportService.escapeField('crlf\r\nhere'), '"crlf\r\nhere"');
    });

    test('leading and trailing spaces are preserved by quoting', () {
      // Unquoted, a spreadsheet trims them and a name silently changes.
      expect(ExportService.escapeField('  padded  '), '"  padded  "');
    });
  });

  group('toCsv', () {
    test('writes a header then a row per record', () {
      final csv = ExportService.toCsv(['id', 'name'], [
        [1, 'Kopiko'],
        [2, 'SkyFlakes'],
      ]);
      expect(csv, 'id,name\r\n1,Kopiko\r\n2,SkyFlakes\r\n');
    });

    test('an empty table still gets its header', () {
      // A missing header is ambiguous — did the export fail, or is it empty?
      expect(ExportService.toCsv(['id', 'name'], []), 'id,name\r\n');
    });

    test('an escaped field survives a round trip', () {
      final csv = ExportService.toCsv(
        ['name', 'note'],
        [
          ['Lucky Me, Pancit', 'said "hello"'],
        ],
      );
      final line = csv.split('\r\n')[1];
      expect(parseLine(line), ['Lucky Me, Pancit', 'said "hello"']);
    });
  });

  group('buildAll', () {
    test('covers every table and never the staff credentials', () async {
      final names = (await export.buildAll()).map((f) => f.name).toList();
      expect(names, ExportService.tables.map((t) => '$t.csv').toList());
      // Salts and hashes in a file headed for a share sheet would undo the
      // point of hashing them.
      expect(names, isNot(contains('staff.csv')));
    });

    test('an empty store exports headers and no rows', () async {
      final files = await export.buildAll();
      for (final file in files) {
        expect(file.rows, 0, reason: '${file.name} should be empty');
        expect(file.csv.trim().split('\r\n').length, 1,
            reason: '${file.name} should be header-only');
        expect(file.csv, isNotEmpty);
      }
    });

    test('a sale with a discount exports its figures', () async {
      final p = await addProduct(name: 'Lucky Me, Pancit Canton', price: 50);
      await sales.recordSale(
        lines: [CartLine(product: p, qty: 2)],
        paymentMethod: 'Cash',
        cashier: 'Nena',
        discount: const Discount(
            kind: DiscountKind.percent, value: 20, reason: 'Senior citizen'),
      );

      final files = await export.buildAll();
      final salesCsv = files.firstWhere((f) => f.name == 'sales.csv');
      expect(salesCsv.rows, 1);

      final lines = salesCsv.csv.trim().split('\r\n');
      final headers = parseLine(lines[0]);
      final row = parseLine(lines[1]);
      String value(String column) => row[headers.indexOf(column)];

      expect(value('subtotal'), '100.0');
      expect(value('discount'), '20.0');
      expect(value('total'), '80.0');
      expect(value('discount_reason'), 'Senior citizen');
      expect(value('cashier'), 'Nena');
    });

    test('a comma in a product name does not shift the columns', () async {
      await addProduct(name: 'Lucky Me, Pancit Canton');
      final csv =
          (await export.buildAll()).firstWhere((f) => f.name == 'products.csv');
      final lines = csv.csv.trim().split('\r\n');
      final headers = parseLine(lines[0]);
      final row = parseLine(lines[1]);

      expect(row.length, headers.length, reason: 'the row must still line up');
      expect(row[headers.indexOf('name')], 'Lucky Me, Pancit Canton');
      expect(row[headers.indexOf('category')], 'Biscuit');
    });

    test('the utang ledger is included', () async {
      final id = await utang.addCustomer('Aling Nena');
      await utang.charge(customerId: id, amount: 120, note: 'Test');
      final files = await export.buildAll();
      expect(files.firstWhere((f) => f.name == 'customers.csv').rows, 1);
      expect(files.firstWhere((f) => f.name == 'utang_entries.csv').rows, 1);
    });
  });

  group('writeTo', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('storev2-export-test');
    });

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    test('writes one file per table into a dated folder', () async {
      await addProduct();
      final paths = await export.writeTo(temp, now: DateTime(2026, 9, 5, 14, 30));

      expect(paths.length, ExportService.tables.length);
      for (final path in paths) {
        expect(File(path).existsSync(), isTrue, reason: '$path should exist');
        expect(path, contains('storev2-backup-20260905-1430'));
      }
    });

    test('a second export does not overwrite the first', () async {
      await addProduct();
      final first = await export.writeTo(temp, now: DateTime(2026, 9, 5, 14, 30));
      final second = await export.writeTo(temp, now: DateTime(2026, 9, 5, 16, 45));

      // A backup that replaces the previous one is one backup, not a history.
      expect(first.first, isNot(second.first));
      expect(File(first.first).existsSync(), isTrue);
      expect(File(second.first).existsSync(), isTrue);
    });

    test('the written file is what buildAll produced', () async {
      await addProduct(name: 'Lucky Me, Pancit Canton');
      final paths = await export.writeTo(temp);
      final written =
          await File(paths.firstWhere((p) => p.endsWith('products.csv'))).readAsString();
      final built =
          (await export.buildAll()).firstWhere((f) => f.name == 'products.csv').csv;
      expect(written, built);
    });
  });

  group('sinceLastBackup', () {
    test('never backed up reads as null, not as zero', () {
      // Zero would mean "just backed up", which is the opposite of the truth.
      expect(ExportService.sinceLastBackup(null), isNull);
      expect(ExportService.sinceLastBackup(''), isNull);
      expect(ExportService.sinceLastBackup('not a date'), isNull);
    });

    test('measures from the stamp to now', () {
      final since = ExportService.sinceLastBackup(
        DateTime(2026, 9, 1).toIso8601String(),
        now: DateTime(2026, 9, 9),
      );
      expect(since!.inDays, 8);
    });
  });
}
