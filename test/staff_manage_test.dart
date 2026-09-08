import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/screens/cashier_switch_screen.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/staff_service.dart';

void main() {
  final staff = StaffService();

  setUpAll(() {
    sqfliteFfiInit();
    // No-isolate, so a query finishes on the microtask queue the tester drains.
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
    final db = await DatabaseHelper.instance.database;
    await db.delete('staff');
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // A fresh key each time, so pumping again rebuilds the State and re-reads
    // the roster rather than reusing the one already mounted.
    await tester.pumpWidget(
        MaterialApp(home: CashierSwitchScreen(key: UniqueKey())));
    await tester.pumpAndSettle();
  }

  /// Opens Manage staff and picks [name].
  Future<void> openActionsFor(WidgetTester tester, String name) async {
    await tester.tap(find.text('Manage staff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  testWidgets('the roster screen offers staff management', (tester) async {
    await pump(tester);
    expect(find.text('Manage staff'), findsOneWidget);
    expect(find.text('Add a cashier'), findsOneWidget);
  });

  testWidgets('a person can be picked and acted on', (tester) async {
    await pump(tester);
    await openActionsFor(tester, 'Ronel');

    expect(find.text('Change PIN'), findsOneWidget);
    expect(find.text('Remove from roster'), findsOneWidget);
  });

  testWidgets('the signed-in cashier cannot be removed', (tester) async {
    await pump(tester);
    // May is the default signed-in cashier.
    await openActionsFor(tester, 'May');

    // Removing whoever is on the till would leave the app naming a cashier
    // who is no longer on the roster.
    expect(find.text('Sign in as someone else first.'), findsOneWidget);
    final tile = tester.widget<ListTile>(
      find.ancestor(
          of: find.text('Remove from roster'), matching: find.byType(ListTile)),
    );
    expect(tile.enabled, isFalse);
    expect(tile.onTap, isNull);
  });

  testWidgets('anyone else can be removed', (tester) async {
    await pump(tester);
    await openActionsFor(tester, 'Ronel');

    final tile = tester.widget<ListTile>(
      find.ancestor(
          of: find.text('Remove from roster'), matching: find.byType(ListTile)),
    );
    expect(tile.enabled, isTrue);
    expect(find.text('They keep their place in past sales and shifts.'),
        findsOneWidget);
  });

  testWidgets('a removed cashier drops off the sign-in list', (tester) async {
    await pump(tester);
    expect(find.text('Ronel'), findsOneWidget);

    // Done through the service rather than the manager gate: the gate has its
    // own tests, and this is about what the roster shows afterwards.
    await staff.deactivate((await staff.byName('Ronel'))!.id!);
    await pump(tester);

    expect(find.text('Ronel'), findsNothing);
    expect(find.text('May'), findsOneWidget);
    expect(find.text('Nena'), findsOneWidget);
  });

  testWidgets('removing the last manager is refused', (tester) async {
    await pump(tester);
    final nena = await staff.byName('Nena');

    // The screen would surface this as a message; the guarantee itself lives
    // in the service, because losing every manager means no shift can ever be
    // closed again.
    expect(
      () => staff.deactivate(nena!.id!),
      throwsA(isA<StaffValidationException>()),
    );
  });
}
