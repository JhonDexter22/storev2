import 'dart:io';

import 'package:path/path.dart' as p;

import '../database/database_helper.dart';

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
  ExportService({DatabaseHelper? dbHelper})
      : dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper dbHelper;

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
  Future<List<ExportFile>> buildAll() async {
    final db = await dbHelper.database;
    final files = <ExportFile>[];

    for (final table in tables) {
      final rows = await db.query(table);
      final headers = rows.isNotEmpty
          ? rows.first.keys.toList()
          : await _columnNames(table);
      files.add(ExportFile(
        name: '$table.csv',
        csv: toCsv(headers, [
          for (final row in rows) [for (final h in headers) row[h]],
        ]),
        rows: rows.length,
      ));
    }
    return files;
  }

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
    final target = Directory(p.join(directory.path, 'storev2-backup-$stamp'));
    await target.create(recursive: true);

    final paths = <String>[];
    for (final file in await buildAll()) {
      final out = File(p.join(target.path, file.name));
      await out.writeAsString(file.csv);
      paths.add(out.path);
    }
    return paths;
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
