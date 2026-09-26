import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/l10n/tr.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/models/staff.dart';
import 'package:storev2/screens/setup_screen.dart';
import 'package:storev2/services/first_run.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/services/staff_service.dart';

/// Records what setup asked for instead of touching the database, which runs
/// outside a widget test's fake clock.
class _FakeStaff extends StaffService {
  ({String name, String pin})? claimed;

  @override
  Future<Staff> claimStore({required String name, required String pin}) async {
    claimed = (name: name.trim(), pin: pin);
    return Staff(id: 1, name: name.trim(), role: 'Manager', isManager: true);
  }
}

void main() {
  final settings = SettingsService.instance;
  final staff = StaffService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings.resetForTests();
    await settings.load();
    await DatabaseHelper.instance.clearAllData();
    // Not covered by clearAllData, on purpose; each test starts from the
    // roster a new install is seeded with.
    await (await DatabaseHelper.instance.database).delete('staff');
  });

  group('whether setup runs', () {
    test('a brand-new install gets it', () async {
      expect(await FirstRun.needed(), isTrue);
    });

    test('a store already in use is let straight in, and never asked again',
        () async {
      await ProductService().insertProduct(Product(
        name: 'SkyFlakes',
        stock: 4,
        minStock: 1,
        category: 'Biscuit',
        createdAt: DateTime(2026, 9, 1).toIso8601String(),
        price: 10,
      ));
      expect(await FirstRun.needed(), isFalse);
      expect(settings.setupDone, isTrue);

      await DatabaseHelper.instance.clearAllData();
      expect(await FirstRun.needed(), isFalse,
          reason: 'emptying the store later is not a new install');
    });

    test('a finished setup is not run again', () async {
      await settings.markSetupDone();
      expect(await FirstRun.needed(), isFalse);
    });
  });

  group('claimStore', () {
    test('the owner replaces the starting roster', () async {
      final owner = await staff.claimStore(name: '  Lito Cruz ', pin: '4826');

      expect(owner.name, 'Lito Cruz');
      expect(owner.isManager, isTrue);
      expect(owner.onStartingPin, isFalse);
      final roster = await staff.roster(includeInactive: true);
      expect(roster.map((s) => s.name), ['Lito Cruz']);
    });

    test('the owner\'s PIN opens manager actions and the shipped one does not',
        () async {
      await staff.claimStore(name: 'Lito', pin: '4826');

      expect(await staff.verifyManagerPin('4826'), isA<PinAccepted>());
      expect(await staff.verifyManagerPin('2468'), isA<PinRejected>());
      expect(await staff.onStartingPin(), isEmpty);
    });

    test('the owner may share a name with a placeholder', () async {
      final owner = await staff.claimStore(name: 'May', pin: '4826');
      expect(owner.isManager, isTrue);
      expect((await staff.roster()).map((s) => s.name), ['May']);
    });

    test('someone whose PIN was already changed is a real person and stays',
        () async {
      final may = (await staff.byName('May'))!;
      await staff.setPin(may.id!, '9090');

      await staff.claimStore(name: 'Lito', pin: '4826');

      expect((await staff.roster()).map((s) => s.name), ['May', 'Lito']);
    });

    test('a blank name or a short PIN is refused before anything changes',
        () async {
      await expectLater(staff.claimStore(name: ' ', pin: '4826'),
          throwsA(isA<StaffValidationException>()));
      await expectLater(staff.claimStore(name: 'Lito', pin: '12'),
          throwsA(isA<StaffValidationException>()));
      expect((await staff.roster()).length, StaffService.seedRoster.length);
    });
  });

  group('setStoreName', () {
    test('is trimmed', () async {
      await settings.setStoreName('  Tindahan ni Lito ');
      expect(settings.storeName, 'Tindahan ni Lito');
    });

    test('a blank name is ignored rather than printed', () async {
      await settings.setStoreName('Tindahan ni Lito');
      await settings.setStoreName('   ');
      expect(settings.storeName, 'Tindahan ni Lito');
    });
  });

  group('the setup screens', () {
    late _FakeStaff fake;
    late bool finished;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      fake = _FakeStaff();
      finished = false;
      await tester.pumpWidget(MaterialApp(
        home: SetupScreen(staff: fake, onFinished: () => finished = true),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    /// Types into the one field on screen, then lets the button beside it
    /// catch up before anything taps it.
    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pumpAndSettle();
    }

    Future<void> enterPin(WidgetTester tester, String pin, String confirm) async {
      for (final d in pin.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tap(tester, confirm);
    }

    testWidgets('a new store is set up start to finish', (tester) async {
      await pump(tester);
      expect(find.text('Welcome'), findsOneWidget);

      await tap(tester, 'Set up my store');
      expect(find.text('Step 1 of 3'), findsOneWidget);
      await type(tester, 'Tindahan ni Lito');
      await tap(tester, 'Next');

      expect(find.text('Who runs the store?'), findsOneWidget);
      await type(tester, 'Lito');
      await tap(tester, 'Choose a PIN');
      await enterPin(tester, '4826', 'Continue');
      await enterPin(tester, '4826', 'Save PIN');

      expect(find.text('Cash in the drawer to start'), findsOneWidget);
      await type(tester, '1500');
      await tap(tester, 'Finish setup');

      expect(find.text("You're ready, Lito"), findsOneWidget);
      expect(fake.claimed, (name: 'Lito', pin: '4826'));
      expect(settings.storeName, 'Tindahan ni Lito');
      expect(settings.openingFloat, 1500);
      expect(settings.cashier, 'Lito');
      expect(settings.setupDone, isTrue,
          reason: 'saved before the last screen, so closing the app there '
              'does not run setup again');

      await tap(tester, 'Add my products');
      expect(finished, isTrue);
    });

    testWidgets('two different PINs are caught and nothing moves on',
        (tester) async {
      await pump(tester);
      await tap(tester, 'Set up my store');
      await type(tester, 'Tindahan ni Lito');
      await tap(tester, 'Next');
      await type(tester, 'Lito');
      await tap(tester, 'Choose a PIN');
      await enterPin(tester, '4826', 'Continue');
      await enterPin(tester, '4827', 'Save PIN');

      expect(find.text('Those two PINs did not match. Try again.'), findsOneWidget);
      expect(find.text('Who runs the store?'), findsOneWidget);
    });

    testWidgets('Next waits for a store name', (tester) async {
      await pump(tester);
      await tap(tester, 'Set up my store');

      final next = tester.widget<ElevatedButton>(
          find.ancestor(of: find.text('Next'), matching: find.byType(ElevatedButton)));
      expect(next.onPressed, isNull);
    });

    testWidgets('back returns to the previous question with its answer',
        (tester) async {
      await pump(tester);
      await tap(tester, 'Set up my store');
      await type(tester, 'Tindahan ni Lito');
      await tap(tester, 'Next');

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      expect(find.text('What is your store called?'), findsOneWidget);
      expect(find.text('Tindahan ni Lito'), findsOneWidget);
    });

    // Every step at the sizes and in the language most likely to overflow:
    // Filipino runs longer, and a 360-wide phone is the smallest in use.
    for (final (name, size, lang) in [
      ('small phone, in Filipino', const Size(360, 690), AppLanguage.fil),
      ('tablet, in English', const Size(1180, 800), AppLanguage.en),
    ]) {
      testWidgets('every step fits on a $name', (tester) async {
        await settings.setLanguage(lang);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        fake = _FakeStaff();
        await tester.pumpWidget(MaterialApp(
          home: SetupScreen(staff: fake, onFinished: () {}),
        ));
        await tester.pumpAndSettle();

        await tap(tester, tr('Set up my store'));
        await type(tester, 'Tindahan ni Aling Nena at mga Anak');
        await tap(tester, tr('Next'));
        await type(tester, 'Maria Clara de los Santos');
        await tap(tester, tr('Choose a PIN'));
        await enterPin(tester, '4826', tr('Continue'));
        await enterPin(tester, '4826', tr('Save PIN'));
        await tap(tester, tr('Finish setup'));

        expect(find.text(tr("You're ready, {name}", {'name': 'Maria Clara de los Santos'})),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await settings.setLanguage(AppLanguage.en);
      });
    }

    testWidgets('nothing is saved until the last step', (tester) async {
      await pump(tester);
      await tap(tester, 'Set up my store');
      await type(tester, 'Tindahan ni Lito');
      await tap(tester, 'Next');

      expect(settings.storeName, 'Sari-Sari Store');
      expect(settings.setupDone, isFalse);
      expect(fake.claimed, isNull);
    });
  });
}
