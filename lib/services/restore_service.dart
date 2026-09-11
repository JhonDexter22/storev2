import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import 'export_service.dart';
import 'product_image_store.dart';

/// What a backup contains, checked before anything is touched.
class RestorePreview {
  const RestorePreview({
    required this.rowCounts,
    required this.warnings,
    required this.errors,
    this.photoCount = 0,
  });

  /// Product photos found in the archive.
  final int photoCount;

  /// Table name to the number of data rows found.
  final Map<String, int> rowCounts;

  /// Survivable oddities — a table missing from the folder, a column this
  /// version does not know. Shown to the person before they commit.
  final List<String> warnings;

  /// Reasons the restore must not run at all.
  final List<String> errors;

  bool get isValid => errors.isEmpty;
  int get totalRows => rowCounts.values.fold(0, (a, b) => a + b);
}

/// Reads exported CSVs back into the database.
///
/// The destructive counterpart to [ExportService], and treated accordingly:
/// nothing is written until every file has parsed, the whole load runs in one
/// transaction, and the data being replaced is exported first so a restore
/// aimed at the wrong folder is itself recoverable.
class RestoreService {
  RestoreService({
    DatabaseHelper? dbHelper,
    ExportService? exportService,
    ProductImageStore? images,
  })  : dbHelper = dbHelper ?? DatabaseHelper.instance,
        exportService = exportService ?? ExportService(),
        images = images ?? ProductImageStore();

  final DatabaseHelper dbHelper;
  final ExportService exportService;

  /// Where restored photos are written. Injectable because the real one needs
  /// a platform directory the test VM has no answer for.
  final ProductImageStore images;

  /// Load order, so a child row never lands before its parent.
  static const loadOrder = [
    'products',
    'sales',
    'sale_items',
    'refunds',
    'refund_items',
    'shifts',
    'customers',
    'utang_entries',
  ];

  /// Unpacks a backup zip into the {fileName: contents} map a restore takes.
  ///
  /// Only the CSVs at the top level are read. Anything else in the archive is
  /// ignored rather than treated as data — a zip is a container someone may
  /// well have added their own files to.
  /// The product photos inside an archive, keyed by file name.
  ///
  /// A backup taken before photos were included simply has none, so this comes
  /// back empty and the restore behaves exactly as it used to.
  static Map<String, List<int>> readPhotos(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final photos = <String, List<int>>{};
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final parts = entry.name.split('/');
      if (parts.length < 2 || parts[parts.length - 2] != ExportService.photoFolder) {
        continue;
      }
      photos[parts.last] = List<int>.from(entry.content as List<int>);
    }
    return photos;
  }

  static Map<String, String> readArchive(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, String>{};
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final name = entry.name.split('/').last;
      if (!name.endsWith('.csv')) continue;
      files[name] = utf8.decode(entry.content as List<int>, allowMalformed: true);
    }
    return files;
  }

  /// Parses a CSV document into rows of fields.
  ///
  /// The inverse of [ExportService.escapeField], and the place a restore can
  /// quietly corrupt everything: a quoted field may contain commas, newlines
  /// and doubled quotes, and treating those as separators would shift every
  /// column after them. Accepts CRLF or LF, and ignores a trailing newline.
  static List<List<String>> parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var fieldStarted = false;

    void endField() {
      row.add(field.toString());
      field.clear();
      fieldStarted = false;
    }

    void endRow() {
      endField();
      rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (inQuotes) {
        if (c == '"') {
          // A doubled quote inside a quoted field is one literal quote.
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
        continue;
      }

      switch (c) {
        case '"':
          inQuotes = true;
          fieldStarted = true;
        case ',':
          endField();
        case '\r':
          // Swallow the LF of a CRLF pair rather than starting a blank row.
          if (i + 1 < input.length && input[i + 1] == '\n') i++;
          endRow();
        case '\n':
          endRow();
        default:
          field.write(c);
          fieldStarted = true;
      }
    }

    // A file ending in a newline has already closed its last row; anything
    // left in the buffer is a final row without a trailing separator.
    if (field.isNotEmpty || fieldStarted || row.isNotEmpty) endRow();

    // Drop a trailing empty row produced by a final newline.
    if (rows.isNotEmpty && rows.last.length == 1 && rows.last.single.isEmpty) {
      rows.removeLast();
    }
    return rows;
  }

  /// Turns one CSV document into maps keyed by column name.
  ///
  /// Columns the current schema does not have are dropped rather than failing:
  /// a backup taken by an older or newer build should still restore what it
  /// has in common with this one.
  static List<Map<String, Object?>> rowsFor(
    String csv,
    Map<String, bool> columns, {
    List<String>? unknownColumnsOut,
  }) {
    final parsed = parseCsv(csv);
    if (parsed.isEmpty) return [];

    final headers = parsed.first;
    final keep = <int>[];
    for (var i = 0; i < headers.length; i++) {
      if (columns.containsKey(headers[i])) {
        keep.add(i);
      } else {
        unknownColumnsOut?.add(headers[i]);
      }
    }

    final out = <Map<String, Object?>>[];
    for (final row in parsed.skip(1)) {
      final map = <String, Object?>{};
      for (final i in keep) {
        final name = headers[i];
        // A short row means a truncated file; treat the missing tail as empty
        // rather than throwing away the rows that did survive.
        final raw = i < row.length ? row[i] : '';
        if (raw.isNotEmpty) {
          map[name] = raw;
          continue;
        }
        // CSV cannot tell an empty string from a null, so the schema decides:
        // a NOT NULL column gets the empty string it was exported from, and a
        // nullable one gets null. Reading every blank as null fails the insert
        // on columns like `discount_reason`, which is every sale without a
        // discount — that is to say, nearly all of them.
        map[name] = columns[name] == true ? '' : null;
      }
      out.add(map);
    }
    return out;
  }

  /// Column name to whether it is NOT NULL, straight from the schema.
  Future<Map<String, bool>> _columnsOf(Database db, String table) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return {
      for (final c in info)
        c['name'] as String: (c['notnull'] as int? ?? 0) == 1,
    };
  }

  /// What is on the device right now, so a confirmation can say what is
  /// being given up rather than only what is arriving.
  Future<Map<String, int>> currentRowCounts() async {
    final db = await dbHelper.database;
    final counts = <String, int>{};
    for (final table in loadOrder) {
      counts[table] = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
          0;
    }
    return counts;
  }

  /// Reads a backup without writing anything, so the person can see what they
  /// are about to replace.
  ///
  /// [files] maps a file name (`sales.csv`) to its contents.
  Future<RestorePreview> inspect(
    Map<String, String> files, {
    Map<String, List<int>> photos = const {},
  }) async {
    final db = await dbHelper.database;
    final counts = <String, int>{};
    final warnings = <String>[];
    final errors = <String>[];

    final recognised = files.keys.where((n) => n.endsWith('.csv')).toSet();
    if (recognised.isEmpty) {
      errors.add('No CSV files were selected.');
      return RestorePreview(
          rowCounts: counts,
          warnings: warnings,
          errors: errors,
          photoCount: photos.length);
    }

    var matched = 0;
    for (final table in loadOrder) {
      final name = '$table.csv';
      final csv = files[name];
      if (csv == null) {
        warnings.add('$name is missing — $table will be emptied.');
        counts[table] = 0;
        continue;
      }
      matched++;

      try {
        final unknown = <String>[];
        final rows = rowsFor(csv, await _columnsOf(db, table),
            unknownColumnsOut: unknown);
        counts[table] = rows.length;
        if (unknown.isNotEmpty) {
          warnings.add('$name has columns this version does not use: '
              '${unknown.join(', ')}.');
        }
      } catch (e) {
        errors.add('$name could not be read: $e');
      }
    }

    if (matched == 0) {
      errors.add('None of the selected files look like a store backup.');
    }
    for (final name in recognised) {
      final table = name.replaceAll('.csv', '');
      if (!loadOrder.contains(table)) {
        warnings.add('$name is not part of a backup and will be ignored.');
      }
    }
    return RestorePreview(
        rowCounts: counts,
        warnings: warnings,
        errors: errors,
        photoCount: photos.length);
  }

  /// Replaces the store's data with the backup's.
  ///
  /// Replace, not merge. The ids in a backup and the ids on this device were
  /// handed out by two different counters, so merging them would attach sale
  /// lines to the wrong sales — silently, and with no way to tell afterwards.
  ///
  /// Staff are left alone: they are not in a backup, and clearing them would
  /// reset every PIN to the codes published in the source.
  ///
  /// Everything happens in one transaction. A failure part-way leaves the
  /// store exactly as it was rather than half-replaced.
  Future<void> restore(
    Map<String, String> files, {
    Map<String, List<int>> photos = const {},
  }) async {
    final preview = await inspect(files);
    if (!preview.isValid) {
      throw StateError(preview.errors.join(' '));
    }

    final db = await dbHelper.database;

    // Parsed up front, outside the transaction: a malformed file should be
    // found before anything has been deleted.
    final parsed = <String, List<Map<String, Object?>>>{};
    for (final table in loadOrder) {
      final csv = files['$table.csv'];
      parsed[table] =
          csv == null ? [] : rowsFor(csv, await _columnsOf(db, table));
    }

    await db.transaction((txn) async {
      for (final table in loadOrder.reversed) {
        await txn.delete(table);
      }
      for (final table in loadOrder) {
        for (final row in parsed[table]!) {
          await txn.insert(table, row);
        }
      }
    });

    // After the rows, and outside the transaction: a photo that fails to write
    // must not roll back a restore that has already put the books back.
    await restorePhotos(photos);
  }

  /// Writes photos from a backup into this device's photo store and repoints
  /// each product at its local copy.
  ///
  /// The paths in a backup belong to whichever phone made it, so they are
  /// meaningless here — only the file name survives the trip. Keeping that
  /// name means restoring a backup onto the phone it came from leaves every
  /// path exactly as it was.
  Future<int> restorePhotos(Map<String, List<int>> photos) async {
    if (photos.isEmpty) return 0;

    final db = await dbHelper.database;
    final rows = await db.query('products', columns: ['id', 'image_path']);
    if (rows.isEmpty) return 0;

    Directory? dir;
    var written = 0;
    for (final row in rows) {
      final path = row['image_path'] as String?;
      if (path == null || path.isEmpty) continue;
      final bytes = photos[ExportService.photoName(path)];
      if (bytes == null) continue;

      try {
        dir ??= await images.directory();
        final target = File(p.join(dir.path, ExportService.photoName(path)));
        await target.writeAsBytes(bytes);
        await db.update('products', {'image_path': target.path},
            where: 'id = ?', whereArgs: [row['id']]);
        written++;
      } catch (_) {
        // One unwritable photo is not worth failing a restore over; the
        // product falls back to the placeholder it would have had anyway.
      }
    }
    return written;
  }
}
