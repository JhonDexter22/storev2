import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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

  /// Side of the square every product photo is stored at. Thumbnails are
  /// 40–52px and the card photo is under 200px wide, so anything larger is
  /// disk and decode time for nothing.
  static const squareSide = 600;

  /// Squares and shrinks a freshly taken or picked photo, then keeps it.
  ///
  /// A phone camera hands back a tall 4:3 frame of the shelf; the thumbnail
  /// shows the middle of it anyway, so cropping to that square up front
  /// makes every product picture the same shape and a fraction of the size.
  /// Falls back to keeping the original untouched if it cannot be decoded.
  Future<String> keepSquared(String sourcePath, {DateTime? now}) async {
    final source = File(sourcePath);
    if (!await source.exists()) return sourcePath;
    try {
      final bytes = await source.readAsBytes();
      final squared = await compute(_squareJpeg, bytes);
      if (squared == null) return keep(sourcePath, now: now);
      final dir = await directory();
      final stamp = (now ?? DateTime.now()).microsecondsSinceEpoch;
      var target = p.join(dir.path, '$stamp.jpg');
      var attempt = 1;
      while (await File(target).exists()) {
        target = p.join(dir.path, '$stamp-$attempt.jpg');
        attempt++;
      }
      await File(target).writeAsBytes(squared, flush: true);
      return target;
    } catch (_) {
      return keep(sourcePath, now: now);
    }
  }

  /// Runs in an isolate: decoding a camera frame on the UI thread would
  /// freeze the sheet for a visible moment.
  static Uint8List? _squareJpeg(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // Cameras record orientation as metadata; bake it in so the crop is of
    // the picture the shopkeeper saw, not the sensor's idea of "up".
    final upright = img.bakeOrientation(decoded);
    final side = upright.width < upright.height ? upright.width : upright.height;
    final cropped = img.copyCrop(
      upright,
      x: (upright.width - side) ~/ 2,
      y: (upright.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final sized = side > squareSide
        ? img.copyResize(cropped, width: squareSide, height: squareSide, interpolation: img.Interpolation.average)
        : cropped;
    return Uint8List.fromList(img.encodeJpg(sized, quality: 85));
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

  /// A second copy of a kept photo, for a duplicated product. Two products
  /// pointing at one file would lose the picture together when either was
  /// deleted.
  Future<String> duplicate(String path, {DateTime? now}) async {
    final source = File(path);
    if (!await source.exists()) return path;
    final dir = await directory();
    var ext = p.extension(path);
    if (ext.isEmpty) ext = '.jpg';
    final stamp = (now ?? DateTime.now()).microsecondsSinceEpoch;
    var target = p.join(dir.path, '$stamp$ext');
    var attempt = 1;
    while (await File(target).exists()) {
      target = p.join(dir.path, '$stamp-$attempt$ext');
      attempt++;
    }
    await source.copy(target);
    return target;
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
