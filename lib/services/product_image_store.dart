import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/product_model.dart';
import 'product_service.dart';

/// Where product photos live.
///
/// image_picker hands back a file in the app's *cache* directory, and saving
/// that path saves a photo Android is free to delete — it clears cache under
/// storage pressure, and "Clear cache" wipes it outright. The shopkeeper would
/// find their photos replaced by the grey placeholder with nothing to explain
/// it, so every picked photo is copied somewhere durable before its path is
/// written to the database.
class ProductImageStore {
  /// [root] is only for tests; production uses the app documents directory,
  /// which survives everything short of uninstalling.
  ProductImageStore({Directory? root}) : _root = root;

  final Directory? _root;

  static const folderName = 'product_photos';

  Future<Directory> directory() async {
    final base = _root ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, folderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies a photo into permanent storage and returns its new path.
  ///
  /// Always copies rather than only when the source looks temporary: a path
  /// into the shared gallery is no safer, because the owner can delete the
  /// picture there and the product would lose its photo just the same.
  Future<String> keep(String sourcePath, {DateTime? now}) async {
    final source = File(sourcePath);
    // Nothing to copy — hand the path back rather than inventing an empty
    // file the thumbnail would fail on anyway.
    if (!await source.exists()) return sourcePath;

    final dir = await directory();
    if (p.equals(p.dirname(sourcePath), dir.path)) return sourcePath;

    final stamp = (now ?? DateTime.now()).microsecondsSinceEpoch;
    var ext = p.extension(sourcePath);
    if (ext.isEmpty) ext = '.png';

    // A timestamp alone is not unique enough: Windows resolves the clock to
    // about 15ms, so two photos saved in quick succession can land on the same
    // microsecond and the second would silently overwrite the first.
    var target = p.join(dir.path, '$stamp$ext');
    var attempt = 1;
    while (await File(target).exists()) {
      target = p.join(dir.path, '$stamp-$attempt$ext');
      attempt++;
    }

    await source.copy(target);
    return target;
  }

  /// Copies photos that earlier versions left in the cache, before Android
  /// gets round to deleting them. Returns how many were rescued.
  ///
  /// Runs at startup and is deliberately silent: a shopkeeper should not have
  /// to understand what a cache directory is to keep their pictures.
  Future<int> rescueStrays(ProductService products) async {
    final dir = await directory();
    var rescued = 0;
    for (final product in await products.getAllProducts()) {
      final path = product.imagePath;
      if (path == null || path.isEmpty) continue;
      if (p.equals(p.dirname(path), dir.path)) continue;
      if (!await File(path).exists()) continue;

      final kept = await keep(path);
      if (kept == path) continue;
      await products.updateProduct(product.copyWith(imagePath: kept));
      rescued++;
    }
    return rescued;
  }

  /// Removes a photo no product points at any more. Failure is not worth
  /// reporting: a leftover file costs kilobytes, and a crash costs the sale.
  Future<void> discard(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final dir = await directory();
      if (!p.equals(p.dirname(path), dir.path)) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// True if [product] points at a photo that is no longer on disk — the
  /// symptom of the cache having been cleared.
  static Future<bool> isMissing(Product product) async {
    final path = product.imagePath;
    if (path == null || path.isEmpty) return false;
    return !await File(path).exists();
  }
}
