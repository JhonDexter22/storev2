import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/services/export_service.dart';
import 'package:storev2/services/product_image_store.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/restore_service.dart';

void main() {
  final export = ExportService();
  final products = ProductService();

  late Directory temp;
  late ProductImageStore images;
  late RestoreService restore;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    await DatabaseHelper.instance.clearAllData();
    temp = await Directory.systemTemp.createTemp('storev2-photo-backup');
    images = ProductImageStore(root: temp);
    restore = RestoreService(images: images);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// Bytes that are recognisably one picture rather than another.
  List<int> pixels(int seed) => [0x89, 0x50, 0x4E, 0x47, seed, seed + 1, seed + 2];

  /// A product whose photo is already in the durable store, as one added
  /// through the app would be.
  Future<Product> productWithPhoto({
    String name = 'SkyFlakes',
    int seed = 1,
    String file = 'photo-a.png',
  }) async {
    final dir = await images.directory();
    final photo = File(p.join(dir.path, file));
    await photo.writeAsBytes(pixels(seed));

    final id = await products.insertProduct(Product(
      name: name,
      stock: 4,
      minStock: 1,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: 10,
      imagePath: photo.path,
    ));
    return (await products.getAllProducts()).firstWhere((x) => x.id == id);
  }

  Future<Directory> outDir() =>
      Directory(p.join(temp.path, 'out')).create(recursive: true);

  group('packing photos', () {
    test('a product photo travels in the archive', () async {
      await productWithPhoto();
      final path = await export.writeArchive(await outDir());
      final bytes = await File(path).readAsBytes();

      final photos = RestoreService.readPhotos(bytes);
      expect(photos.keys, ['photo-a.png']);
      expect(photos['photo-a.png'], pixels(1));
      // The CSVs must still be readable exactly as before.
      expect(RestoreService.readArchive(bytes).keys,
          containsAll(ExportService.tables.map((t) => '$t.csv')));
    });

    test('the archive carries the file name, not this phone\'s path', () async {
      await productWithPhoto();
      final path = await export.writeArchive(await outDir());
      final names =
          RestoreService.readPhotos(await File(path).readAsBytes()).keys;
      // A path from the phone that made the backup means nothing on the phone
      // restoring it.
      expect(names.single, isNot(contains(temp.path)));
      expect(names.single, 'photo-a.png');
    });

    test('a photo whose file has gone does not fail the backup', () async {
      final dir = await images.directory();
      await products.insertProduct(Product(
        name: 'Kopiko',
        stock: 1,
        minStock: 1,
        category: 'Coffee',
        createdAt: DateTime.now().toIso8601String(),
        price: 12,
        imagePath: p.join(dir.path, 'cleared-by-android.png'),
      ));
      await productWithPhoto();

      final path = await export.writeArchive(await outDir());
      final photos = RestoreService.readPhotos(await File(path).readAsBytes());
      // The rest of the store still has to get out.
      expect(photos.keys, ['photo-a.png']);
      expect(RestoreService.readArchive(await File(path).readAsBytes())
          .containsKey('products.csv'), isTrue);
    });

    test('two products sharing one photo pack it once', () async {
      final first = await productWithPhoto();
      await products.insertProduct(Product(
        name: 'SkyFlakes 10s',
        stock: 2,
        minStock: 1,
        category: 'Biscuit',
        createdAt: DateTime.now().toIso8601String(),
        price: 18,
        imagePath: first.imagePath,
      ));

      final path = await export.writeArchive(await outDir());
      expect(RestoreService.readPhotos(await File(path).readAsBytes()),
          hasLength(1));
    });

    test('a store with no photos produces an archive with none', () async {
      await products.insertProduct(Product(
        name: 'Kopiko',
        stock: 1,
        minStock: 1,
        category: 'Coffee',
        createdAt: DateTime.now().toIso8601String(),
        price: 12,
      ));
      final path = await export.writeArchive(await outDir());
      expect(RestoreService.readPhotos(await File(path).readAsBytes()), isEmpty);
    });
  });

  group('restoring photos', () {
    test('a photo comes back and the product points at it', () async {
      await productWithPhoto();
      final path = await export.writeArchive(await outDir());
      final bytes = await File(path).readAsBytes();

      // Wipe the store and the photo, as a new phone would be.
      await DatabaseHelper.instance.clearAllData();
      await (await images.directory()).delete(recursive: true);

      await restore.restore(RestoreService.readArchive(bytes),
          photos: RestoreService.readPhotos(bytes));

      final product = (await products.getAllProducts()).single;
      expect(product.imagePath, isNotNull);
      expect(await File(product.imagePath!).exists(), isTrue);
      expect(await File(product.imagePath!).readAsBytes(), pixels(1));
      expect(p.dirname(product.imagePath!), (await images.directory()).path);
    });

    test('restoring onto the same phone leaves the path untouched', () async {
      final before = await productWithPhoto();
      final path = await export.writeArchive(await outDir());
      final bytes = await File(path).readAsBytes();

      await DatabaseHelper.instance.clearAllData();
      await restore.restore(RestoreService.readArchive(bytes),
          photos: RestoreService.readPhotos(bytes));

      // Keeping the file name means the round trip is exact, which is what
      // the byte-identical restore test depends on.
      expect((await products.getAllProducts()).single.imagePath,
          before.imagePath);
    });

    test('each product keeps its own photo', () async {
      await productWithPhoto(name: 'SkyFlakes', seed: 1, file: 'a.png');
      await productWithPhoto(name: 'Kopiko', seed: 50, file: 'b.png');
      final path = await export.writeArchive(await outDir());
      final bytes = await File(path).readAsBytes();

      await DatabaseHelper.instance.clearAllData();
      await (await images.directory()).delete(recursive: true);
      await restore.restore(RestoreService.readArchive(bytes),
          photos: RestoreService.readPhotos(bytes));

      final all = await products.getAllProducts();
      final sky = all.firstWhere((x) => x.name == 'SkyFlakes');
      final kopiko = all.firstWhere((x) => x.name == 'Kopiko');
      // Swapping two products' pictures is worse than losing both.
      expect(await File(sky.imagePath!).readAsBytes(), pixels(1));
      expect(await File(kopiko.imagePath!).readAsBytes(), pixels(50));
    });

    test('a photo the archive does not carry leaves the row alone', () async {
      await productWithPhoto();
      final path = await export.writeArchive(await outDir());
      final files = RestoreService.readArchive(await File(path).readAsBytes());

      await DatabaseHelper.instance.clearAllData();
      await restore.restore(files); // no photos passed

      // The path stays as recorded; the thumbnail falls back to the
      // placeholder rather than the app inventing a picture.
      expect((await products.getAllProducts()).single.imagePath, isNotNull);
    });

    test('an older backup with no photos still restores', () async {
      await productWithPhoto();
      final path = await export.writeArchive(await outDir());
      final bytes = await File(path).readAsBytes();

      await DatabaseHelper.instance.clearAllData();
      // Exactly what a pre-photos backup looks like: CSVs and nothing else.
      await restore.restore(RestoreService.readArchive(bytes), photos: const {});

      expect((await products.getAllProducts()).single.name, 'SkyFlakes');
    });

    test('the preview says how many photos are coming', () async {
      await productWithPhoto(file: 'a.png');
      await productWithPhoto(name: 'Kopiko', seed: 9, file: 'b.png');
      final path = await export.writeArchive(await outDir());
      final bytes = await File(path).readAsBytes();

      final preview = await restore.inspect(RestoreService.readArchive(bytes),
          photos: RestoreService.readPhotos(bytes));
      expect(preview.photoCount, 2);
      expect(preview.isValid, isTrue);
    });

    test('restoring nothing but photos writes nothing', () async {
      expect(await restore.restorePhotos(const {}), 0);
    });
  });

  group('the whole store survives a new phone', () {
    test('books and pictures both come back', () async {
      await productWithPhoto(name: 'Lucky Me, Pancit Canton', file: 'lm.png');
      final path = await export.writeArchive(await outDir());
      final bytes = await File(path).readAsBytes();

      // A different phone: new database, new photo directory.
      await DatabaseHelper.instance.clearAllData();
      final otherRoot = await Directory(p.join(temp.path, 'other-phone'))
          .create(recursive: true);
      final otherImages = ProductImageStore(root: otherRoot);
      final otherRestore = RestoreService(images: otherImages);

      await otherRestore.restore(RestoreService.readArchive(bytes),
          photos: RestoreService.readPhotos(bytes));

      final product = (await products.getAllProducts()).single;
      expect(product.name, 'Lucky Me, Pancit Canton');
      expect(p.dirname(product.imagePath!), (await otherImages.directory()).path);
      expect(await File(product.imagePath!).readAsBytes(), pixels(1));
    });
  });
}
