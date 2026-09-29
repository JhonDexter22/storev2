import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';

import 'package:path/path.dart' as p;

import '../database/database_helper.dart';
import 'settings_service.dart';
import 'error_log.dart';

/// A table as read from the database: a header and plain value rows.
typedef RawTable = ({
  String name,
  List<String> headers,
  List<List<Object?>> rows,
});

/// One exported table.
class ExportFile {
  const ExportFile({required this.name, required this.csv, required this.rows});

  /// File name including the extension, e.g. `sales.csv`.
  final String name;
  final String csv;

  /// Data rows, not counting the header.
  final int rows;
}

/// Writes the store's data out as CSV so it can leave the device.
///
/// Everything lives in one SQLite file on one phone. A dropped handset is the
/// whole history — sales, stock, and who owes what — so this exists to make
/// that recoverable, not as a reporting nicety.
///
/// Plain CSV rather than a database copy: a shopkeeper can open it in any
/// spreadsheet, and a restore does not depend on this app still existing.
class ExportService {
  ExportService({DatabaseHelper? dbHelper, SettingsService? settings})
      : dbHelper = dbHelper ?? DatabaseHelper.instance,
        settings = settings ?? SettingsService.instance;

  final DatabaseHelper dbHelper;

  /// Where the store's name, payment types and preferences come from.
  final SettingsService settings;

  /// The tables exported, in the order a person would want to read them.
  ///
  /// `staff` is deliberately absent: the rows are PIN salts and hashes, and
  /// putting those into a file destined for a share sheet would undo the point
  /// of hashing them.
  static const tables = [
    'products',
    'sales',
    'sale_items',
    'refunds',
    'refund_items',
    'shifts',
    'customers',
    'utang_entries',
  ];

  /// Escapes one field for CSV.
  ///
  /// Quotes anything containing a comma, a quote, a newline or leading and
  /// trailing spaces, and doubles embedded quotes. Product names in a sari-sari
  /// store routinely contain commas ("Lucky Me, Pancit Canton"), and getting
  /// this wrong shifts every later column by one without any error.
  static String escapeField(Object? value) {
    if (value == null) return '';
    final s = '$value';
    final needsQuotes = s.contains(',') ||
        s.contains('"') ||
        s.contains('\n') ||
        s.contains('\r') ||
        s != s.trim();
    if (!needsQuotes) return s;
    return '"${s.replaceAll('"', '""')}"';
  }

  /// Builds a CSV document. Rows are written in the order given, and \r\n line
  /// endings are used because that is what spreadsheet software expects.
  static String toCsv(List<String> headers, List<List<Object?>> rows) {
    final buffer = StringBuffer();
    buffer.write(headers.map(escapeField).join(','));
    buffer.write('\r\n');
    for (final row in rows) {
      buffer.write(row.map(escapeField).join(','));
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  /// Reads every table and renders it as CSV, in memory.
  ///
  /// An empty table still produces a file with its header row: a missing file
  /// is ambiguous ("did the export fail?") where an empty one is not.
  Future<List<ExportFile>> buildAll() async => render(await _readTables());

  /// Every exported table as a header and plain value rows — nothing but
  /// strings and numbers, so it can be handed to another isolate.
  Future<List<RawTable>> _readTables() async {
    final db = await dbHelper.database;
    final out = <RawTable>[];
    for (final table in tables) {
      final rows = await db.query(table);
      final headers = rows.isNotEmpty
          ? rows.first.keys.toList()
          : await _columnNames(table);
      out.add((
        name: table,
        headers: headers,
        rows: [
          for (final row in rows) [for (final h in headers) row[h]],
        ],
      ));
    }
    return out;
  }

  /// Turns read tables into CSV files.
  static List<ExportFile> render(List<RawTable> tables) => [
        for (final t in tables)
          ExportFile(
            name: '${t.name}.csv',
            csv: toCsv(t.headers, t.rows),
            rows: t.rows.length,
          ),
      ];

  /// Column names straight from the schema, so an empty table still gets a
  /// header that matches a populated one.
  Future<List<String>> _columnNames(String table) async {
    final db = await dbHelper.database;
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.map((c) => c['name'] as String).toList();
  }

  /// Writes the CSVs into [directory] and returns the paths.
  ///
  /// Named with the date so successive exports sit beside each other rather
  /// than overwriting: a backup that silently replaces the previous one is one
  /// backup, not a history.
  Future<List<String>> writeTo(Directory directory, {DateTime? now}) async {
    final stamp = _stamp(now ?? DateTime.now());
    final target = Directory(p.join(directory.path, 'basepoint-backup-$stamp'));
    await target.create(recursive: true);

    final paths = <String>[];
    for (final file in await buildAll()) {
      final out = File(p.join(target.path, file.name));
      await out.writeAsString(file.csv);
      paths.add(out.path);
    }
    return paths;
  }

  /// Packs the whole backup into one zip and returns its path.
  ///
  /// One file rather than eight, because restoring meant picking every CSV
  /// by hand — a long-press and six taps on a phone, during the one situation
  /// where nobody wants fiddly. The CSVs are still plain inside it, so a
  /// spreadsheet is one unzip away.
  Future<String> writeArchive(Directory directory, {DateTime? now}) async {
    final stamp = _stamp(now ?? DateTime.now());
    final raw = await _readTables();
    final photos = await collectPhotos();
    // Settings that were never loaded would read as defaults, and restoring
    // those would wipe the real ones — better to carry none.
    final prefs = settings.isLoaded
        ? utf8.encode(jsonEncode(settings.exportSettings()))
        : null;
    final path = p.join(directory.path, 'basepoint-backup-$stamp.zip');
    // The phone's error log rides along, so a problem reported from a shop
    // arrives with the data it happened on. A restore ignores it.
    final errors = ErrorLog.instance.count == 0
        ? null
        : utf8.encode(ErrorLog.instance.toJsonLines());

    final problem = await _packInBackground(raw, photos, prefs, errors, path);
    if (problem != null) {
      throw StateError('The backup did not check out: $problem');
    }
    return path;
  }

  /// Runs [_pack] off the UI isolate.
  ///
  /// After a year of trading, building the CSVs and the zip is seconds of
  /// work on a budget phone; done on the UI isolate, the "Exporting…" spinner
  /// froze and a tap in that time could raise Android's "app isn't
  /// responding". Only the database reads stay behind, because the database
  /// plugin lives on the UI isolate.
  ///
  /// Static, so the closure carries only the plain data it is given and not
  /// this service's database handle, which cannot cross isolates.
  static Future<String?> _packInBackground(
    List<RawTable> raw,
    Map<String, List<int>> photos,
    List<int>? prefs,
    List<int>? errors,
    String path,
  ) =>
      Isolate.run(() => _pack(raw, photos, prefs, errors, path));

  /// Writes the archive to [path] and checks it. Returns what is wrong with
  /// it, or null — having deleted the file in the first case, so a broken
  /// backup is never left where it could be shared.
  static Future<String?> _pack(
    List<RawTable> raw,
    Map<String, List<int>> photos,
    List<int>? prefs,
    List<int>? errors,
    String path,
  ) async {
    final files = render(raw);
    final archive = Archive();
    for (final file in files) {
      final bytes = utf8.encode(file.csv);
      archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
    }
    for (final entry in photos.entries) {
      archive.addFile(ArchiveFile(
          '$photoFolder/${entry.key}', entry.value.length, entry.value));
    }
    if (prefs != null) {
      archive.addFile(ArchiveFile(settingsFile, prefs.length, prefs));
    }
    if (errors != null) {
      archive.addFile(ArchiveFile(ErrorLog.fileName, errors.length, errors));
    }

    final out = File(path);
    await out.writeAsBytes(ZipEncoder().encode(archive), flush: true);

    // Read back off the disk, not from memory: the backup is only as good as
    // the file that leaves the phone, and a full disk or a bad write is found
    // here rather than on the day it is needed.
    final problem = verifyArchive(
      await out.readAsBytes(),
      files: files,
      photos: photos,
      withSettings: prefs != null,
    );
    if (problem != null) {
      try {
        await out.delete();
      } catch (_) {}
    }
    return problem;
  }

  /// Where the store's settings sit inside the archive.
  static const settingsFile = 'settings.json';

  /// Checks that a written archive holds exactly what went into it.
  ///
  /// Returns what is wrong, or null if it all matches. Every CSV is compared
  /// character for character and every photo byte for byte — a row count
  /// alone would pass a file whose prices had been mangled.
  static String? verifyArchive(
    List<int> bytes, {
    required List<ExportFile> files,
    required Map<String, List<int>> photos,
    bool withSettings = false,
  }) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      return 'the zip cannot be opened ($e)';
    }

    List<int>? read(String name) {
      final entry = archive.findFile(name);
      return entry == null ? null : entry.content as List<int>;
    }

    bool same(List<int> a, List<int> b) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }

    for (final file in files) {
      final got = read(file.name);
      if (got == null) return '${file.name} is missing';
      if (utf8.decode(got, allowMalformed: true) != file.csv) {
        return '${file.name} does not match the store';
      }
    }
    for (final MapEntry(key: name, value: expected) in photos.entries) {
      final got = read('$photoFolder/$name');
      if (got == null) return 'photo $name is missing';
      if (!same(got, expected)) return 'photo $name does not match';
    }
    if (withSettings && read(settingsFile) == null) {
      return '$settingsFile is missing';
    }
    return null;
  }

  /// Where photos sit inside the archive, kept apart from the CSVs so a
  /// restore can tell data from pictures without guessing at file names.
  static const photoFolder = 'photos';

  /// The archive entry name for a stored photo path.
  ///
  /// Splits on either separator: the path was written by whichever platform
  /// took the photo, and the backup has to be readable on the other one.
  static String photoName(String path) =>
      path.split('/').last.split('\\').last;

  /// Every product photo still on disk, keyed by file name.
  ///
  /// Without these a backup restores the books and leaves grey placeholders
  /// where the pictures were — the numbers survive a lost phone and the
  /// shopkeeper's own work does not.
  ///
  /// Keyed by base name rather than full path so the archive carries nothing
  /// about this particular device, and two products sharing a photo pack it
  /// once.
  Future<Map<String, List<int>>> collectPhotos() async {
    final db = await dbHelper.database;
    final rows = await db.query('products', columns: ['image_path']);
    final photos = <String, List<int>>{};

    for (final row in rows) {
      final path = row['image_path'] as String?;
      if (path == null || path.isEmpty) continue;
      final name = p.basename(path.replaceAll(r'\', '/'));
      if (photos.containsKey(name)) continue;
      final file = File(path);
      // A path whose file has already gone is not worth failing the whole
      // backup over: the rest of the store still needs to get out.
      try {
        if (await file.exists()) photos[name] = await file.readAsBytes();
      } catch (e, st) {
        ErrorLog.caught(e, st, 'backup: reading a photo');
      }
    }
    return photos;
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
  }

  /// How stale the last backup is, or null if there has never been one.
  static Duration? sinceLastBackup(String? lastBackupIso, {DateTime? now}) {
    if (lastBackupIso == null || lastBackupIso.isEmpty) return null;
    final at = DateTime.tryParse(lastBackupIso);
    if (at == null) return null;
    return (now ?? DateTime.now()).difference(at);
  }
}
