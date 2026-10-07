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
    // The form can add a manager too, so the button no longer says cashier.
    expect(find.text('Add staff'), findsOneWidget);
    expect(find.text('Add a cashier'), findsNothing);
  });

  testWidgets('the starting-PIN warning has its own way to fix it', (tester) async {
    await pump(tester);
    expect(find.textContaining('Change them below'), findsNothing);
    await tester.tap(find.text('Change PINs'));
    await tester.pumpAndSettle();
    // Manage staff, saying "PIN" as the warning does.
    expect(find.textContaining('still on the starting PIN'), findsWidgets);
    expect(find.textContaining('starting code'), findsNothing);
  });

  testWidgets('a cashier is offered Make manager; a manager Make cashier', (tester) async {
    await pump(tester);
    await openActionsFor(tester, 'Ronel');
    expect(find.text('Make manager'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await openActionsFor(tester, 'Nena');
    expect(find.text('Make cashier'), findsOneWidget);
  });

  group('changing a role', () {
    test('makes a cashier a manager, and back', () async {
      final ronel = (await staff.byName('Ronel'))!;
      await staff.setManager(ronel.id!, isManager: true);
      final promoted = (await staff.byName('Ronel'))!;
      expect(promoted.isManager, isTrue);
      expect(promoted.role, 'Manager');

      await staff.setManager(ronel.id!, isManager: false);
      expect((await staff.byName('Ronel'))!.isManager, isFalse);
    });

    test('never leaves the store without a manager', () async {
      final nena = (await staff.byName('Nena'))!;
      expect(() => staff.setManager(nena.id!, isManager: false), throwsA(isA<StaffValidationException>()));
      expect((await staff.byName('Nena'))!.isManager, isTrue);

      // With a second manager, the first can step down.
      await staff.setManager((await staff.byName('Ronel'))!.id!, isManager: true);
      await staff.setManager(nena.id!, isManager: false);
      expect((await staff.byName('Nena'))!.isManager, isFalse);
    });
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
