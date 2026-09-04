import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/main.dart';
import 'package:storev2/models/staff.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  setUpAll(() {
    // The app reads products from sqflite as soon as a screen mounts, and the
    // plain sqflite plugin has no factory in the test VM.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Each suite gets its own in-memory store; sharing one file makes
    // suites clobber each other when they run in parallel.
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
  });

  testWidgets('App boots and shows the bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const RestockApp());
    // Not pumpAndSettle: the loading spinner animates forever, so it never
    // reaches a settled frame. The chrome under test renders on frame one.
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('POS'), findsOneWidget);
    expect(find.text('Restock'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    // "Products" is the default tab, so it also appears as the screen title
    // and as a stat label — one match is not the right expectation.
    expect(find.text('Products'), findsWidgets);
  });

  testWidgets('Products screen shows the ruled stat row', (WidgetTester tester) async {
    await tester.pumpWidget(const RestockApp());
    await tester.pump();

    expect(find.text('Products'), findsWidgets);
    for (final label in ['Units', 'Low', 'Out']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  group('SettingsService', () {
    test('falls back to defaults on a fresh install', () async {
      final s = SettingsService.instance;
      expect(s.printReceipt, isTrue);
      expect(s.autoBackup, isFalse);
      expect(s.defaultMinStock, 5);
      expect(s.cashier, 'May');
    });

    test('persists a changed value across a reload', () async {
      final s = SettingsService.instance;
      await s.setAutoBackup(true);
      await s.setDefaultMinStock(12);
      await s.setCashier('Nena');

      // Re-read from storage the way a fresh launch would.
      await s.load();

      expect(s.autoBackup, isTrue);
      expect(s.defaultMinStock, 12);
      expect(s.cashier, 'Nena');
    });

    test('a single-word name has one initial', () {
      expect(const Staff(name: 'May', role: 'Cashier', pin: '1111').initials, 'M');
      expect(
        const Staff(name: 'Ana Reyes', role: 'Cashier', pin: '0000').initials,
        'AR',
      );
    });

    test('notifies listeners when a setting changes', () async {
      final s = SettingsService.instance;
      var notified = 0;
      void listener() => notified++;
      s.addListener(listener);
      await s.setScanSound(false);
      s.removeListener(listener);

      expect(notified, greaterThan(0));
    });
  });
}
