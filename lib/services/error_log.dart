import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/app_info.dart';

/// One thing that went wrong.
class ErrorEntry {
  const ErrorEntry({
    required this.at,
    required this.kind,
    required this.where,
    required this.message,
    required this.stack,
    this.count = 1,
    this.lastAt,
    this.version = AppInfo.version,
  });

  final DateTime at;

  /// `flutter` (a framework error, usually a build or layout failure),
  /// `uncaught` (an async error nothing handled), or `caught` (handled by the
  /// app, which carried on, but worth knowing about).
  final String kind;

  /// Where it happened: the code that caught it, or the tab that was open.
  final String where;
  final String message;

  /// The top of the stack trace — enough to find the line, not the whole
  /// framework beneath it.
  final String stack;

  /// The same error repeating back to back is kept as one entry with a
  /// count, so a failure on every frame does not push everything else out.
  final int count;
  final DateTime? lastAt;

  final String version;

  ErrorEntry repeated(DateTime now) => ErrorEntry(
        at: at,
        kind: kind,
        where: where,
        message: message,
        stack: stack,
        count: count + 1,
        lastAt: now,
        version: version,
      );

  bool sameAs(ErrorEntry other) =>
      kind == other.kind && where == other.where && message == other.message;

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'kind': kind,
        'where': where,
        'message': message,
        'stack': stack,
        if (count > 1) 'count': count,
        if (lastAt != null) 'lastAt': lastAt!.toIso8601String(),
        'version': version,
      };

  static ErrorEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    if (at == null) return null;
    return ErrorEntry(
      at: at,
      kind: '${json['kind'] ?? 'caught'}',
      where: '${json['where'] ?? ''}',
      message: '${json['message'] ?? ''}',
      stack: '${json['stack'] ?? ''}',
      count: json['count'] is int ? json['count'] as int : 1,
      lastAt: DateTime.tryParse('${json['lastAt']}'),
      version: '${json['version'] ?? ''}',
    );
  }

  /// As it reads in a shared report.
  String toReport() {
    final b = StringBuffer()
      ..writeln('${at.toIso8601String()}  [$kind]  $where'
          '${count > 1 ? '  ×$count (last ${lastAt?.toIso8601String()})' : ''}'
          '  v$version')
      ..writeln(message);
    if (stack.isNotEmpty) b.writeln(stack);
    return b.toString();
  }
}

/// Everything that went wrong on this phone, kept on this phone.
///
/// Before this, a failure in a shop left no trace: most were caught and
/// hidden so the till kept working, and the rest scrolled past in a console
/// nobody was watching. Now each one is written down with the time, where it
/// happened and the app version, readable from Settings and shareable from
/// there — and it travels inside a backup, so a report arrives with the data
/// it happened on.
///
/// Nothing is sent anywhere. Recording must never fail, so every step here
/// swallows its own errors: a broken error log cannot be allowed to break the
/// thing it is logging.
class ErrorLog extends ChangeNotifier {
  ErrorLog._();

  static final ErrorLog instance = ErrorLog._();

  /// The newest entries kept. Older ones are dropped as new ones arrive.
  static const maxEntries = 300;

  /// Stack lines kept per entry.
  static const stackLines = 12;

  /// The file name inside the log directory, and inside a backup archive.
  static const fileName = 'errors.jsonl';

  final List<ErrorEntry> _entries = [];
  File? _file;
  Future<void>? _writing;
  bool _dirty = false;

  /// What the person was looking at, set by the tab bar as it changes, so an
  /// error with no better location still says roughly where it came from.
  String screen = '';

  /// Newest first.
  List<ErrorEntry> get entries => List.unmodifiable(_entries.reversed);

  int get count => _entries.length;

  /// Entries that happened, or happened again, after [seen]. All of them
  /// when the log has never been looked at.
  int newerThan(DateTime? seen) => seen == null
      ? _entries.length
      : _entries.where((e) => (e.lastAt ?? e.at).isAfter(seen)).length;

  /// Loads what earlier sessions recorded and starts writing to [directory].
  ///
  /// Until this is called the log lives in memory only — which is what tests
  /// and anything that runs before `main` has a directory get.
  Future<void> init(Directory directory) async {
    try {
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, fileName));
      final earlier = <ErrorEntry>[];
      if (await file.exists()) {
        for (final line in await file.readAsLines()) {
          try {
            final e = ErrorEntry.fromJson(jsonDecode(line));
            if (e != null) earlier.add(e);
          } catch (_) {
            // A half-written last line from a killed app: skip it.
          }
        }
      }
      _entries.insertAll(0, earlier);
      _trim();
      _file = file;
      if (_entries.length != earlier.length) _scheduleWrite();
      notifyListeners();
    } catch (_) {
      // No log file then; the in-memory log still works for this session.
    }
  }

  /// Records an error the app caught and carried on from.
  static void caught(Object error, StackTrace? stack, String where) =>
      instance.record(kind: 'caught', error: error, stack: stack, where: where);

  void record({
    required String kind,
    required Object error,
    StackTrace? stack,
    String? where,
    DateTime? now,
  }) {
    try {
      final at = now ?? DateTime.now();
      final entry = ErrorEntry(
        at: at,
        kind: kind,
        where: (where == null || where.isEmpty) ? screen : where,
        message: _shorten('$error', 2000),
        stack: _top(stack),
      );
      if (_entries.isNotEmpty && _entries.last.sameAs(entry)) {
        _entries[_entries.length - 1] = _entries.last.repeated(at);
      } else {
        _entries.add(entry);
        _trim();
      }
      _scheduleWrite();
      notifyListeners();
    } catch (_) {}
  }

  /// A framework error — a widget that failed to build or lay out.
  void recordFlutterError(FlutterErrorDetails details) {
    // The summary names the widget that failed ("The relevant error-causing
    // widget was: ..."), which is worth more than the exception alone.
    String described;
    try {
      described = details.toString(minLevel: DiagnosticLevel.info);
    } catch (_) {
      described = details.exceptionAsString();
    }
    record(kind: 'flutter', error: described, stack: details.stack);
  }

  Future<void> clear() async {
    _entries.clear();
    _scheduleWrite();
    notifyListeners();
    await _writing;
  }

  /// The whole log as readable text, newest first, for sharing.
  ///
  /// [device] is a line about the screen it was sent from — size, text
  /// scale, language — which the log itself cannot know, and which is often
  /// what explains a layout error on one phone and not another.
  String toReport({String? device}) {
    final b = StringBuffer()
      ..writeln('${AppInfo.name} error log · v${AppInfo.version} · '
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    if (device != null) b.writeln(device);
    b
      ..writeln('${_entries.length} entries, newest first')
      ..writeln();
    for (final e in entries) {
      b
        ..writeln(e.toReport())
        ..writeln('—');
    }
    return b.toString();
  }

  /// The log as stored, one JSON object per line — what goes into a backup.
  String toJsonLines() =>
      _entries.map((e) => jsonEncode(e.toJson())).join('\n');

  /// Waits for anything still being written. For tests and for a backup
  /// that wants the file on disk to be current.
  Future<void> flush() async {
    while (_writing != null) {
      await _writing;
    }
  }

  void _trim() {
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  /// Writes are chained, not timed: a burst of errors becomes one write of
  /// the latest state, and no timer is left behind for a test to trip over.
  void _scheduleWrite() {
    if (_file == null) return;
    _dirty = true;
    _writing ??= _drain();
  }

  Future<void> _drain() async {
    try {
      while (_dirty) {
        _dirty = false;
        final text = toJsonLines();
        await _file!.writeAsString(text.isEmpty ? '' : '$text\n', flush: true);
      }
    } catch (_) {
      // Disk full or gone: keep the entries in memory and carry on.
    } finally {
      _writing = null;
    }
  }

  static String _top(StackTrace? stack) {
    if (stack == null) return '';
    final lines = '$stack'.split('\n').where((l) => l.trim().isNotEmpty);
    return lines.take(stackLines).join('\n');
  }

  static String _shorten(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  @visibleForTesting
  void resetForTests() {
    _entries.clear();
    _file = null;
    _writing = null;
    _dirty = false;
    screen = '';
  }
}
