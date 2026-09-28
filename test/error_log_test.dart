import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/screens/error_log_screen.dart';
import 'package:storev2/services/error_log.dart';
import 'package:storev2/services/export_service.dart';
import 'package:storev2/services/restore_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:archive/archive.dart';

void main() {
  final log = ErrorLog.instance;
  late Directory temp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    log.resetForTests();
    temp = await Directory.systemTemp.createTemp('storev2-errors');
  });

  tearDown(() async {
    await log.flush();
    log.resetForTests();
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  StackTrace here() => StackTrace.current;

  group('recording', () {
    test('an error is kept with where it happened and the top of its stack', () {
      ErrorLog.caught(StateError('printer gone'), here(), 'printing');

      final e = log.entries.single;
      expect(e.kind, 'caught');
      expect(e.where, 'printing');
      expect(e.message, contains('printer gone'));
      expect(e.stack, isNotEmpty);
      expect(e.stack.split('\n').length, lessThanOrEqualTo(ErrorLog.stackLines));
    });

    test('with no location given, the open tab stands in', () {
      log.screen = 'Sell tab';
      log.record(kind: 'uncaught', error: 'boom');
      expect(log.entries.single.where, 'Sell tab');
    });

    test('newest first', () {
      ErrorLog.caught('first', null, 'a');
      ErrorLog.caught('second', null, 'b');
      expect(log.entries.map((e) => e.message), ['second', 'first']);
    });

    test('the same error back to back is one entry with a count', () {
      final t = DateTime(2026, 9, 28, 10);
      for (var i = 0; i < 50; i++) {
        log.record(kind: 'flutter', error: 'overflow', where: 'Sell tab', now: t.add(Duration(seconds: i)));
      }
      final e = log.entries.single;
      expect(e.count, 50);
      expect(e.at, t);
      expect(e.lastAt, t.add(const Duration(seconds: 49)));
    });

    test('only the newest are kept', () {
      for (var i = 0; i < ErrorLog.maxEntries + 25; i++) {
        ErrorLog.caught('error $i', null, 'x');
      }
      expect(log.count, ErrorLog.maxEntries);
      expect(log.entries.first.message, 'error ${ErrorLog.maxEntries + 24}');
      expect(log.entries.last.message, 'error 25');
    });

    test('a framework error names the widget that failed', () {
      log.recordFlutterError(FlutterErrorDetails(
        exception: FlutterError('A RenderFlex overflowed by 12 pixels.'),
        stack: here(),
        library: 'rendering library',
        context: ErrorDescription('during layout'),
      ));
      final e = log.entries.single;
      expect(e.kind, 'flutter');
      expect(e.message, contains('RenderFlex overflowed'));
    });
  });

  group('on disk', () {
    test('what one session records, the next can read', () async {
      await log.init(temp);
      ErrorLog.caught('lost connection', here(), 'printing');
      await log.flush();

      log.resetForTests();
      await log.init(temp);
      expect(log.entries.single.message, 'lost connection');
      expect(log.entries.single.where, 'printing');
    });

    test('errors from before the file was open are kept too', () async {
      ErrorLog.caught('too early', null, 'startup');
      await log.init(temp);
      await log.flush();

      log.resetForTests();
      await log.init(temp);
      expect(log.entries.single.message, 'too early');
    });

    test('a half-written last line from a killed app is skipped', () async {
      File('${temp.path}/${ErrorLog.fileName}').writeAsStringSync(
          '{"at":"2026-09-28T10:00:00.000","kind":"caught","where":"x","message":"ok","stack":""}\n'
          '{"at":"2026-09-28T10:0');
      await log.init(temp);
      expect(log.entries.single.message, 'ok');
    });

    test('clearing empties the file as well', () async {
      await log.init(temp);
      ErrorLog.caught('gone soon', null, 'x');
      await log.clear();
      await log.flush();

      log.resetForTests();
      await log.init(temp);
      expect(log.count, 0);
    });

    test('a directory that cannot be written leaves the log working in memory',
        () async {
      final blocker = File('${temp.path}/not-a-dir')..writeAsStringSync('');
      await log.init(Directory(blocker.path));
      ErrorLog.caught('still here', null, 'x');
      await log.flush();
      expect(log.entries.single.message, 'still here');
    });
  });

  group('in a backup', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.load();
      await DatabaseHelper.instance.clearAllData();
    });

    test('the log travels with the data it happened on', () async {
      ErrorLog.caught('printer gone', here(), 'printing');
      final path = await ExportService().writeArchive(temp);
      final bytes = await File(path).readAsBytes();

      final entry = ZipDecoder().decodeBytes(bytes).findFile(ErrorLog.fileName);
      expect(entry, isNotNull);
      expect(String.fromCharCodes(entry!.content as List<int>), contains('printer gone'));

      // A restore reads the store's tables and nothing else.
      expect(RestoreService.readArchive(bytes).keys, isNot(contains(ErrorLog.fileName)));
    });

    test('an empty log adds nothing', () async {
      final path = await ExportService().writeArchive(temp);
      final zip = ZipDecoder().decodeBytes(await File(path).readAsBytes());
      expect(zip.findFile(ErrorLog.fileName), isNull);
    });
  });

  group('the screen', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ErrorLogScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('says so when nothing has gone wrong', (tester) async {
      await pump(tester);
      expect(find.text('Nothing has gone wrong'), findsOneWidget);
      expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
    });

    testWidgets('lists what went wrong, and opens one to its stack', (tester) async {
      ErrorLog.caught(StateError('printer gone'), here(), 'printing');
      await pump(tester);

      expect(find.text('printing'), findsOneWidget);
      expect(find.text('Handled'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);

      await tester.tap(find.textContaining('printer gone'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('clearing asks first', (tester) async {
      ErrorLog.caught('printer gone', null, 'printing');
      await pump(tester);

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Clear the error log?'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing has gone wrong'), findsOneWidget);
    });
  });
}
