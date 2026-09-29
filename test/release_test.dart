import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/app_info.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/services/demo_data.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/shift_service.dart';

void main() {
  group('what goes out with the app', () {
    test('the version shown in Settings is the one being built', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(r'^version:\s*([0-9.]+)', multiLine: true)
          .firstMatch(pubspec)!
          .group(1);
      expect(AppInfo.version, version);
    });

    test('the Android app id is ours, not the template\'s', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "ph.jhedev.basepoint"'));
      expect(gradle, isNot(contains('com.example')));
    });

    test('the launcher shows the app\'s name', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:label="${AppInfo.name}"'));
    });
  });

  group('the demo year', () {
    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
      await DemoData().loadYear(cashiers: ['Nena', 'May']);
    });

    Future<int> count(String sql) async {
      final db = await DatabaseHelper.instance.database;
      return (await db.rawQuery(sql)).first.values.first! as int;
    }

    test('is the size the performance work was measured at', () async {
      expect(await count('SELECT COUNT(*) FROM products'), DemoData.productCount);
      final sales = await count('SELECT COUNT(*) FROM sales');
      expect(sales, greaterThan(18000));
      expect(await count('SELECT COUNT(*) FROM sale_items'), greaterThan(sales));
    });

    test('has no sales from later today', () async {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('SELECT MAX(created_at) AS m FROM sales');
      expect(DateTime.parse(rows.first['m'] as String).isAfter(DateTime.now()),
          isFalse);
    });

    test('every day but today is closed, so today is an open shift', () async {
      final shift = await ShiftService().currentShiftSales();
      final n = DateTime.now();
      expect(shift.openedAt.isBefore(DateTime(n.year, n.month, n.day)), isTrue);
      expect(await count('SELECT COUNT(*) FROM shifts'), DemoData.days);
    });

    test('every utang sale is on someone\'s tab', () async {
      final utangSales =
          await count("SELECT COUNT(*) FROM sales WHERE payment_method = 'Utang'");
      final charges = await count(
          "SELECT COUNT(*) FROM utang_entries WHERE kind = 'charge' AND sale_id IS NOT NULL");
      expect(charges, utangSales);
    });

    test('the reports add up: revenue equals the lines less discounts', () async {
      final month = await SalesService().getPeriodStats(30);
      final db = await DatabaseHelper.instance.database;
      final lines = await db.rawQuery('''
        SELECT SUM(si.line_total - si.discount) AS v FROM sale_items si
        JOIN sales s ON s.id = si.sale_id WHERE s.created_at >= ?
      ''', [SalesService.windowStart(30).toIso8601String()]);
      expect((lines.first['v'] as num).toDouble(), closeTo(month.revenue, 0.01));
    });

    test('cashiers come from the roster', () async {
      final db = await DatabaseHelper.instance.database;
      final names = await db.rawQuery('SELECT DISTINCT cashier FROM sales');
      expect(names.map((r) => r['cashier']).toSet(), {'Nena', 'May'});
    });
  });
}
