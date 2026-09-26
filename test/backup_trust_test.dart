import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/l10n/tr.dart';
import 'package:storev2/models/payment_type.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/services/escpos.dart';
import 'package:storev2/services/export_service.dart';
import 'package:storev2/services/product_image_store.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/restore_service.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  final settings = SettingsService.instance;
  final export = ExportService();
  final products = ProductService();

  late Directory temp;
  late RestoreService restore;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  /// A fresh install's preferences, the way a new phone starts.
  Future<void> freshPrefs([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    settings.resetForTests();
    await settings.load();
  }

  setUp(() async {
    await DatabaseHelper.instance.clearAllData();
    await freshPrefs();
    temp = await Directory.systemTemp.createTemp('storev2-backup-trust');
    restore = RestoreService(images: ProductImageStore(root: temp));
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<void> addProduct(String name) => products.insertProduct(Product(
        name: name,
        stock: 4,
        minStock: 1,
        category: 'Snacks',
        createdAt: DateTime(2026, 9, 1).toIso8601String(),
        price: 12,
      ));

  /// Everything a restore reads from one archive, as the Settings screen does.
  Future<void> restoreFrom(String path) async {
    final bytes = await File(path).readAsBytes();
    await restore.restore(
      RestoreService.readArchive(bytes),
      photos: RestoreService.readPhotos(bytes),
      settings: RestoreService.readSettings(bytes),
    );
  }

  group('store settings travel with the backup', () {
    test('a new phone gets the old one\'s name, payment types and choices',
        () async {
      await freshPrefs({'store_name': 'Aling Nena\'s'});
      await settings.addPaymentType('Maya');
      await settings.setPaymentTypeEnabled(PaymentType.builtInTypes[2], false);
      await settings.setOpeningFloat(1500);
      await settings.setDefaultMinStock(8);
      await settings.setPrintReceipt(false);
      await settings.setPaperWidth(PaperWidth.mm80);
      await settings.setLanguage(AppLanguage.fil);
      await addProduct('SkyFlakes');
      final path = await export.writeArchive(temp);

      await DatabaseHelper.instance.clearAllData();
      await freshPrefs();
      await restoreFrom(path);

      expect(settings.storeName, 'Aling Nena\'s');
      expect(settings.paymentTypes.map((t) => t.name),
          ['Cash', 'GCash', 'Utang', 'Maya']);
      expect(settings.openingFloat, 1500);
      expect(settings.defaultMinStock, 8);
      expect(settings.printReceipt, isFalse);
      expect(settings.paperWidth, PaperWidth.mm80);
      expect(settings.language, AppLanguage.fil);
    });

    test('this phone\'s printer and signed-in cashier stay put', () async {
      await settings.setPrinter('AA:BB', name: 'Old printer');
      await settings.setCashier('May');
      final path = await export.writeArchive(temp);

      await freshPrefs();
      await settings.setPrinter('CC:DD', name: 'New printer');
      await settings.setCashier('Nena');
      await restoreFrom(path);

      expect(settings.printerAddress, 'CC:DD');
      expect(settings.cashier, 'Nena');
    });

    test('restoring does not count as backing up', () async {
      final path = await export.writeArchive(temp);
      await freshPrefs();
      await restoreFrom(path);
      expect(settings.lastBackup, isNull);
    });

    test('the preview says settings are coming', () async {
      final bytes = await File(await export.writeArchive(temp)).readAsBytes();
      final preview = await restore.inspect(RestoreService.readArchive(bytes),
          settings: RestoreService.readSettings(bytes));
      expect(preview.hasSettings, isTrue);
    });

    test('an older backup without settings leaves this phone\'s alone',
        () async {
      await freshPrefs({'store_name': 'Tindahan ni Lito'});
      final archive = Archive();
      for (final f in await export.buildAll()) {
        final bytes = utf8.encode(f.csv);
        archive.addFile(ArchiveFile(f.name, bytes.length, bytes));
      }
      final bytes = ZipEncoder().encode(archive);

      expect(RestoreService.readSettings(bytes), isNull);
      await restore.restore(RestoreService.readArchive(bytes),
          settings: RestoreService.readSettings(bytes));
      expect(settings.storeName, 'Tindahan ni Lito');
    });

    test('a settings file that will not parse is treated as absent', () {
      final junk = utf8.encode('{not json');
      final archive = Archive()
        ..addFile(ArchiveFile(ExportService.settingsFile, junk.length, junk));
      expect(RestoreService.readSettings(ZipEncoder().encode(archive)), isNull);
    });

    test('settings never loaded are not written as defaults', () async {
      settings.resetForTests();
      final bytes = await File(await export.writeArchive(temp)).readAsBytes();
      expect(RestoreService.readSettings(bytes), isNull);
    });
  });

  group('importSettings', () {
    test('a value of the wrong type is skipped, not written', () async {
      final applied = await settings.importSettings({
        'store_name': 42,
        'print_receipt': 'yes',
        'custom_payment_types': ['Maya', 7],
        'default_min_stock': 3,
      });
      expect(applied, 1);
      expect(settings.storeName, 'Sari-Sari Store');
      expect(settings.printReceipt, isTrue);
      expect(settings.allPaymentTypes.map((t) => t.name), isNot(contains('Maya')));
      expect(settings.defaultMinStock, 3);
    });

    test('keys this version does not know are ignored', () async {
      final applied = await settings
          .importSettings({'last_backup': '2020-01-01', 'printer_address': 'X'});
      expect(applied, 0);
      expect(settings.lastBackup, isNull);
      expect(settings.printerAddress, isNull);
    });

    test('a whole-number float that came back as an int is accepted', () async {
      await settings.importSettings({'opening_float': 2000});
      expect(settings.openingFloat, 2000.0);
    });
  });

  group('the archive is checked before it leaves', () {
    Future<(List<int>, List<ExportFile>, Map<String, List<int>>)> built() async {
      await addProduct('Lucky Me, Pancit Canton');
      final path = await export.writeArchive(temp);
      return (
        await File(path).readAsBytes(),
        await export.buildAll(),
        await export.collectPhotos(),
      );
    }

    test('a good archive passes', () async {
      final (bytes, files, photos) = await built();
      expect(
          ExportService.verifyArchive(bytes,
              files: files, photos: photos, withSettings: true),
          isNull);
    });

    test('a truncated file is caught', () async {
      final (bytes, files, photos) = await built();
      expect(
          ExportService.verifyArchive(bytes.sublist(0, bytes.length ~/ 2),
              files: files, photos: photos),
          isNotNull);
    });

    test('a CSV that differs from the store is caught', () async {
      final (bytes, files, photos) = await built();
      final changed = [
        for (final f in files)
          f.name == 'products.csv'
              ? ExportFile(name: f.name, csv: '${f.csv}extra', rows: f.rows)
              : f,
      ];
      expect(
          ExportService.verifyArchive(bytes, files: changed, photos: photos),
          contains('products.csv'));
    });

    test('a photo that did not make it in is caught', () async {
      final (bytes, files, _) = await built();
      expect(
          ExportService.verifyArchive(bytes,
              files: files,
              photos: {
                'shelf.png': [1, 2, 3]
              }),
          contains('shelf.png'));
    });
  });
}
