import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/l10n/fil.dart';
import 'package:storev2/l10n/tr.dart';
import 'package:storev2/main.dart';
import 'package:storev2/services/settings_service.dart';

/// Every literal handed to tr() / trCount() anywhere under lib/, read from
/// the source the same way a reviewer would find them.
Map<String, String> _keysInSource() {
  const lit = r'''('(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")''';
  final patterns = [
    RegExp(r'\btr\(\s*' + lit),
    RegExp(r'\btrCount\([^,;]+?,\s*' + lit + r'\s*,\s*' + lit),
    RegExp(r'\btr\(\s*[A-Za-z_.!]+\s*\?\s*' + lit + r'\s*:\s*' + lit),
  ];
  String unquote(String l) {
    final body = l.substring(1, l.length - 1);
    return body.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1] == 'n' ? '\n' : m[1]!);
  }

  final keys = <String, String>{};
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart') || f.path.endsWith('fil.dart')) continue;
    final src = f.readAsStringSync();
    for (final p in patterns) {
      for (final m in p.allMatches(src)) {
        for (var i = 1; i <= m.groupCount; i++) {
          final g = m.group(i);
          if (g != null) keys.putIfAbsent(unquote(g), () => f.path);
        }
      }
    }
  }
  return keys;
}

Set<String> _placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m[1]!).toSet();

void main() {
  group('the Filipino dictionary', () {
    final keys = _keysInSource();

    test('finds the strings (sanity check on the scanner)', () {
      expect(keys.length, greaterThan(400));
      expect(keys, contains('Record payment'));
    });

    test('has an entry for every string the app translates', () {
      final missing = keys.keys.where((k) => !fil.containsKey(k)).toList()..sort();
      expect(missing, isEmpty,
          reason: 'Add these to lib/l10n/fil.dart:\n${missing.map((k) => '  $k  (${keys[k]})').join('\n')}');
    });

    test('never builds a key with string interpolation', () {
      final bad = keys.keys.where((k) => k.contains(r'$')).toList();
      expect(bad, isEmpty, reason: 'Use {placeholders} instead: $bad');
    });

    test('keeps every placeholder in the translation', () {
      final broken = [
        for (final e in fil.entries)
          if (!_placeholders(e.value).containsAll(_placeholders(e.key))) e.key,
      ];
      expect(broken, isEmpty, reason: 'Placeholders dropped in: $broken');
    });

    test('has no leftover entries nobody uses', () {
      // Names that reach tr() from data rather than a literal: tab labels,
      // category chips, reasons, payment methods, roles, discount presets.
      const fromData = {
        'Home', 'Sell', 'Popular', 'Cash', 'GCash', 'Card', 'Utang',
        'Store credit', 'Manager', 'Cashier', 'Damaged', 'Wrong item',
        'Expired', 'Changed mind', 'Senior citizen', 'PWD', 'Suki',
      };
      final unused = fil.keys.where((k) => !keys.containsKey(k) && !fromData.contains(k)).toList();
      expect(unused, isEmpty, reason: 'Stale entries: $unused');
    });
  });

  group('tr()', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      SettingsService.instance.resetForTests();
      await SettingsService.instance.load();
    });

    test('is English by default and fills placeholders', () {
      expect(tr('Record payment'), 'Record payment');
      expect(tr('{n} left', {'n': 3}), '3 left');
      expect(trCount(1, '{n} item', '{n} items'), '1 item');
      expect(trCount(4, '{n} item', '{n} items'), '4 items');
    });

    test('speaks Filipino once chosen, and falls back to English for anything unknown', () async {
      await SettingsService.instance.setLanguage(AppLanguage.fil);
      expect(tr('Record payment'), 'Itala ang bayad');
      expect(tr('{n} left', {'n': 3}), '3 na lang');
      expect(tr('Biscuit'), 'Biscuit'); // a shopkeeper's own category
      expect(trMonth(9), 'Set');
      await SettingsService.instance.setLanguage(AppLanguage.en);
    });
  });

  group('switching language in the running app', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      SettingsService.instance.resetForTests();
      await SettingsService.instance.load();
    });

    testWidgets('relabels every screen in place, without a restart', (tester) async {
      tester.view.physicalSize = const Size(390, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(() => SettingsService.instance.setLanguage(AppLanguage.en));

      await tester.pumpWidget(const RestockApp());
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Sell'), findsOneWidget);
      expect(find.text('Search name or SKU'), findsOneWidget);

      await SettingsService.instance.setLanguage(AppLanguage.fil);
      await tester.pumpAndSettle();

      expect(find.text('Benta'), findsOneWidget);
      expect(find.text('Paninda'), findsWidgets);
      expect(find.text('Hanapin ang pangalan o SKU'), findsOneWidget);
      expect(find.text('Sell'), findsNothing);

      // The tab the shopkeeper was on is still the one showing.
      await tester.tap(find.text('Iba pa'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Mga ulat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
