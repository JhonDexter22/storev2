import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/main.dart';
import 'package:storev2/screens/cashier_switch_screen.dart';
import 'package:storev2/services/scan_feedback.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  final settings = SettingsService.instance;

  setUpAll(() {
    sqfliteFfiInit();
    // No-isolate, so a query finishes on the microtask queue the tester drains.
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings.resetForTests();
    await settings.load();
    final db = await DatabaseHelper.instance.database;
    await db.delete('staff');
  });

  group('signing out', () {
    test('lasts until someone signs in', () async {
      await settings.signOut();
      expect(settings.signedOut, isTrue);

      settings.resetForTests();
      await settings.load();
      expect(settings.signedOut, isTrue, reason: 'a restart is not a way past it');

      await settings.setCashier('Ronel');
      expect(settings.signedOut, isFalse);
    });

    Future<void> lock(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await settings.signOut();
                  if (context.mounted) await CashierSwitchScreen.showSignedOut(context);
                },
                child: const Text('the till'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('the till'));
      await tester.pumpAndSettle();
    }

    Future<void> enter(WidgetTester tester, String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.tap(find.text('Sign in').last);
      await tester.pumpAndSettle();
    }

    testWidgets('the lock has no way back to the till', (tester) async {
      await lock(tester);
      expect(find.text('Signed out — pick who is at the till and enter their code.'),
          findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);

      // The system Back gesture is refused too.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Sign in to the till'), findsOneWidget);
    });

    testWidgets('even the person who signed out needs their code', (tester) async {
      await lock(tester);
      // May is the default signed-in cashier; before, tapping her did nothing.
      await tester.tap(find.text('May'));
      await tester.pumpAndSettle();
      expect(find.text("Enter May's code to sign in."), findsWidgets);

      await enter(tester, '1111');
      expect(find.text('the till'), findsOneWidget, reason: 'unlocked, back at the till');
      expect(settings.signedOut, isFalse);
    });

    testWidgets('a wrong code keeps it locked', (tester) async {
      await lock(tester);
      await tester.tap(find.text('May'));
      await tester.pumpAndSettle();
      for (final d in '9999'.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.tap(find.text('Sign in').last);
      await tester.pumpAndSettle();

      expect(settings.signedOut, isTrue);
      expect(find.text('the till'), findsNothing);
    });

    testWidgets('an app closed while signed out reopens on the lock', (tester) async {
      await settings.signOut();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const RestockApp());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Sign in to the till'), findsOneWidget);
    });
  });

  group('scan sound', () {
    final calls = <MethodCall>[];
    var answer = true;

    setUp(() {
      calls.clear();
      answer = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ScanFeedback.channel, (call) async {
        calls.add(call);
        return answer;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ScanFeedback.channel, null);
    });

    test('beeps high for a known code and low for an unknown one', () async {
      await ScanFeedback.found();
      await ScanFeedback.unknown();
      expect(calls.map((c) => c.arguments), [
        {'ok': true},
        {'ok': false},
      ]);
    });

    test('the switch in Settings silences it', () async {
      await settings.setScanSound(false);
      await ScanFeedback.found();
      expect(calls, isEmpty);
    });

    test('falls back to the system click when no tone could play', () async {
      final platform = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platform.add(call.method);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      answer = false;
      await ScanFeedback.found();
      expect(platform, contains('SystemSound.play'));
      expect(platform, contains('HapticFeedback.vibrate'));
    });
  });
}
