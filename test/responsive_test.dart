import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/core/responsive.dart';
import 'package:storev2/main.dart';
import 'package:storev2/services/settings_service.dart';
import 'package:storev2/widgets/brand_mark.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // No-isolate, so a query finishes on the microtask queue the tester
    // drains. With the isolate factory the loading spinner never stops and
    // pumpAndSettle times out.
    databaseFactory = databaseFactoryFfiNoIsolate;
    // Each suite gets its own in-memory store; sharing one file makes
    // suites clobber each other when they run in parallel.
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.load();
  });

  /// Drives the app at a specific logical size, the way a phone or tablet
  /// would report it.
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const RestockApp());
    await tester.pump();
  }

  testWidgets('phone width keeps the bottom navigation', (tester) async {
    await pumpAt(tester, const Size(390, 812));

    expect(find.byType(BottomNavigationBar), findsNothing); // custom bar, not Material's
    // The tab labels live in the bottom bar on phone; the rail is absent.
    expect(find.text('Restock'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('tablet width swaps the bottom bar for a left rail', (tester) async {
    await pumpAt(tester, const Size(1180, 800));

    // Same destinations, still exactly one of each — the rail replaces the bar
    // rather than being drawn alongside it.
    for (final label in ['Home', 'Sell', 'Restock', 'More']) {
      expect(find.text(label), findsOneWidget, reason: '$label should appear once');
    }
  });

  group('the rail stays put', () {
    testWidgets('a screen opened from More keeps the rail on tablet',
        (tester) async {
      await pumpAt(tester, const Size(1180, 800));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Closed days'));
      await tester.pumpAndSettle();

      // The whole point of a rail: you can jump straight to POS from a screen
      // opened out of the More hub, without backing out first.
      expect(find.text('Closed days'), findsWidgets);
      for (final label in ['Home', 'Sell', 'Restock', 'More']) {
        expect(find.text(label), findsOneWidget, reason: '$label left the rail');
      }
    });

    testWidgets('the phone still gives a pushed screen the whole display',
        (tester) async {
      await pumpAt(tester, const Size(390, 812));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Closed days'));
      await tester.pumpAndSettle();

      // Unchanged on a phone: the bottom bar gets out of the way, which is
      // what was verified on the device.
      expect(find.text('Sell'), findsNothing);
      expect(find.text('Restock'), findsNothing);
    });

    testWidgets('switching tabs leaves the pushed screen behind',
        (tester) async {
      await pumpAt(tester, const Size(1180, 800));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Closed days'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Restock'));
      await tester.pumpAndSettle();

      // Otherwise the Restock tab would open onto last night's shift history.
      expect(find.text('Restock center'), findsOneWidget);
    });
  });

  group('a short window', () {
    // A tablet in split screen, or anything wide and low: the rail used to
    // run out of height and cut off More.
    testWidgets('still shows every tab on the rail', (tester) async {
      await pumpAt(tester, const Size(914, 384));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['Home', 'Products', 'Sell', 'Restock', 'More']) {
        expect(find.text(label).hitTestable(), findsOneWidget, reason: '$label should be reachable');
      }
    });

    testWidgets('gives up the logo first, and keeps it while there is room', (tester) async {
      await pumpAt(tester, const Size(914, 384));
      await tester.pumpAndSettle();
      expect(find.byType(BrandMark), findsNothing);

      await pumpAt(tester, const Size(1180, 800));
      await tester.pumpAndSettle();
      expect(find.byType(BrandMark), findsOneWidget);
    });
  });

  group('OrientationPolicy', () {
    late List<MethodCall> calls;

    setUp(() {
      OrientationPolicy.reset();
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') calls.add(call);
        return null;
      });
    });

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    testWidgets('keeps a phone upright, however it is held', (tester) async {
      // A Poco F5 Pro, upright and sideways: the same phone either way.
      await OrientationPolicy.applyFor(const Size(411, 914));
      await OrientationPolicy.applyFor(const Size(914, 411));
      expect(calls.single.arguments, ['DeviceOrientation.portraitUp']);
    });

    testWidgets('lets a tablet turn', (tester) async {
      await OrientationPolicy.applyFor(const Size(1180, 820));
      expect(calls.single.arguments, isEmpty);
    });

    testWidgets('lets go when a foldable opens out to tablet size', (tester) async {
      await OrientationPolicy.applyFor(const Size(400, 880));
      await OrientationPolicy.applyFor(const Size(840, 880));
      expect([for (final c in calls) c.arguments], [
        ['DeviceOrientation.portraitUp'],
        isEmpty,
      ]);
    });

    test('a phone is anything under 600 on its short side', () {
      expect(OrientationPolicy.isPhone(const Size(599, 1300)), isTrue);
      expect(OrientationPolicy.isPhone(const Size(600, 960)), isFalse);
    });
  });

  group('Breakpoints', () {
    testWidgets('840 is the tablet threshold', (tester) async {
      late bool narrow;
      late bool wide;

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(839, 800)),
        child: Builder(builder: (c) {
          narrow = Breakpoints.isTablet(c);
          return const SizedBox();
        }),
      ));
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(840, 800)),
        child: Builder(builder: (c) {
          wide = Breakpoints.isTablet(c);
          return const SizedBox();
        }),
      ));

      expect(narrow, isFalse);
      expect(wide, isTrue);
    });
  });
}
