import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/backup_status.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/services/product_image_store.dart';
import 'package:storev2/services/product_service.dart';

void main() {
  final products = ProductService();
  late Directory temp;
  late Directory cache;
  late ProductImageStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    await DatabaseHelper.instance.clearAllData();
    temp = await Directory.systemTemp.createTemp('storev2-photos');
    cache = await Directory(p.join(temp.path, 'cache')).create(recursive: true);
    store = ProductImageStore(root: temp);
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  /// A photo where image_picker leaves one: the app's cache directory.
  Future<File> pickedPhoto({String name = 'scaled_45.png'}) async {
    final f = File(p.join(cache.path, name));
    await f.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    return f;
  }

  Future<Product> addProduct({String? imagePath}) async {
    final id = await products.insertProduct(Product(
      name: 'SkyFlakes',
      stock: 4,
      minStock: 1,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: 10,
      imagePath: imagePath,
    ));
    return (await products.getAllProducts()).firstWhere((x) => x.id == id);
  }

  group('keeping a photo', () {
    test('a picked photo is copied out of the cache', () async {
      final picked = await pickedPhoto();
      final kept = await store.keep(picked.path);

      // The whole point: the saved path must not be the picker's cache file,
      // which Android deletes without warning.
      expect(kept, isNot(picked.path));
      expect(p.dirname(kept), (await store.directory()).path);
      expect(await File(kept).readAsBytes(), await picked.readAsBytes());
    });

    test('the original is left alone', () async {
      final picked = await pickedPhoto();
      await store.keep(picked.path);
      // Copy, not move: the picker owns that file and may still be reading it.
      expect(await picked.exists(), isTrue);
    });

    test('the extension is preserved', () async {
      final picked = await pickedPhoto(name: 'holiday.jpg');
      expect(p.extension(await store.keep(picked.path)), '.jpg');
    });

    test('two photos in the same moment do not collide', () async {
      final a = await pickedPhoto(name: 'a.png');
      final b = await pickedPhoto(name: 'b.png');
      final keptA = await store.keep(a.path, now: DateTime(2026, 9, 10));
      final keptB = await store.keep(b.path, now: DateTime(2026, 9, 10));
      // Same timestamp; the second must not silently overwrite the first.
      expect(keptA, isNot(keptB));
      expect(await File(keptA).exists(), isTrue);
      expect(await File(keptB).exists(), isTrue);
    });

    test('a photo already in the store is not copied again', () async {
      final picked = await pickedPhoto();
      final once = await store.keep(picked.path);
      expect(await store.keep(once), once);
      expect((await (await store.directory()).list().toList()), hasLength(1));
    });

    test('a path to nothing is handed back rather than faked', () async {
      final missing = p.join(cache.path, 'gone.png');
      expect(await store.keep(missing), missing);
    });
  });

  group('rescuing photos earlier versions left behind', () {
    test('a cached photo is moved into the store and the row updated',
        () async {
      final picked = await pickedPhoto();
      final product = await addProduct(imagePath: picked.path);

      expect(await store.rescueStrays(products), 1);

      final after = (await products.getAllProducts()).single;
      expect(after.imagePath, isNot(picked.path));
      expect(p.dirname(after.imagePath!), (await store.directory()).path);
      expect(await File(after.imagePath!).exists(), isTrue);
      expect(after.name, product.name, reason: 'nothing else should change');
    });

    test('it runs clean a second time', () async {
      await addProduct(imagePath: (await pickedPhoto()).path);
      expect(await store.rescueStrays(products), 1);
      // Startup runs this every launch; it must not keep making copies.
      expect(await store.rescueStrays(products), 0);
      expect(await (await store.directory()).list().toList(), hasLength(1));
    });

    test('a product with no photo is untouched', () async {
      await addProduct();
      expect(await store.rescueStrays(products), 0);
    });

    test('a path whose file is already gone is skipped, not crashed on',
        () async {
      // The exact state a cleared cache leaves behind.
      await addProduct(imagePath: p.join(cache.path, 'deleted.png'));
      expect(await store.rescueStrays(products), 0);
      expect((await products.getAllProducts()).single.imagePath,
          endsWith('deleted.png'));
    });

    test('a store with no products is not an error', () async {
      expect(await store.rescueStrays(products), 0);
    });
  });

  group('a photo that has gone missing', () {
    test('is detected so the placeholder is honest', () async {
      final gone = await addProduct(imagePath: p.join(cache.path, 'x.png'));
      expect(await ProductImageStore.isMissing(gone), isTrue);

      final kept = await addProduct(imagePath: (await pickedPhoto()).path);
      expect(await ProductImageStore.isMissing(kept), isFalse);
    });

    test('no photo at all is not "missing"', () async {
      expect(await ProductImageStore.isMissing(await addProduct()), isFalse);
    });
  });

  group('discard', () {
    test('removes a photo this store owns', () async {
      final kept = await store.keep((await pickedPhoto()).path);
      await store.discard(kept);
      expect(await File(kept).exists(), isFalse);
    });

    test('refuses to touch a file outside the store', () async {
      final picked = await pickedPhoto();
      await store.discard(picked.path);
      // Deleting from the gallery on the shopkeeper's behalf would be theft
      // of their own picture.
      expect(await picked.exists(), isTrue);
    });

    test('a null or missing path is a no-op', () async {
      await store.discard(null);
      await store.discard('');
      await store.discard(p.join(cache.path, 'nope.png'));
    });
  });

  group('what the till header says about backups', () {
    final now = DateTime(2026, 9, 10, 12);

    test('never backed up says so plainly', () {
      final s = BackupStatus.from(null, now: now);
      // The pill it replaced said "Synced" on a store that had never been
      // backed up anywhere.
      expect(s.label, 'No backup');
      expect(s.level, BackupLevel.none);
    });

    test('backed up today reads as done', () {
      final s = BackupStatus.from(now.subtract(const Duration(hours: 3)), now: now);
      expect(s.label, 'Backed up');
      expect(s.level, BackupLevel.fresh);
    });

    test('a few days old shows its age and stays calm', () {
      final s = BackupStatus.from(now.subtract(const Duration(days: 3)), now: now);
      expect(s.label, 'Backup · 3d');
      expect(s.level, BackupLevel.fresh);
    });

    test('a week turns it into a warning', () {
      expect(BackupStatus.from(now.subtract(const Duration(days: 6)), now: now).level,
          BackupLevel.fresh);
      expect(BackupStatus.from(now.subtract(const Duration(days: 7)), now: now).level,
          BackupLevel.stale);
      expect(BackupStatus.from(now.subtract(const Duration(days: 40)), now: now).label,
          'Backup · 40d');
    });

    test('a wrong clock does not produce a backup from the future', () {
      final s = BackupStatus.from(now.add(const Duration(days: 3)), now: now);
      expect(s.label, 'Backed up');
      expect(s.level, BackupLevel.fresh);
    });
  });
}
