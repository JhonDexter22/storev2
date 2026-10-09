import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:storev2/widgets/launch_intro.dart';

void main() {
  late int taps;

  Widget app() => MaterialApp(
        builder: (context, child) => LaunchIntro(child: child!),
        home: Scaffold(
          body: Center(
            child: TextButton(onPressed: () => taps++, child: const Text('Sell')),
          ),
        ),
      );

  setUp(() => taps = 0);

  testWidgets('holds taps while it plays, then hands the screen to the app', (tester) async {
    await tester.pumpWidget(app());
    // The app is built under the intro from the first frame.
    expect(find.text('Sell'), findsOneWidget);

    await tester.tap(find.text('Sell'), warnIfMissed: false);
    expect(taps, 0);

    await tester.pump(LaunchIntro.hold);
    await tester.pump(LaunchIntro.duration ~/ 2);
    await tester.tap(find.text('Sell'), warnIfMissed: false);
    expect(taps, 0);

    await tester.pumpAndSettle();
    await tester.tap(find.text('Sell'));
    expect(taps, 1);
  });

  testWidgets('does not play with the phone\'s animations turned off', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(app());
    await tester.pump();

    await tester.tap(find.text('Sell'));
    expect(taps, 1);
  });

  test('the Android splash is the intro\'s first frame', () {
    const res = 'android/app/src/main/res';
    // The vector draws the 62.5-unit glyph at LaunchIntro.glyphHeight.
    final scale = LaunchIntro.glyphHeight / 62.5;
    final mark = File('$res/drawable/splash_mark.xml').readAsStringSync();
    expect(mark, contains('android:scaleX="$scale"'));
    expect(mark, contains('android:scaleY="$scale"'));

    for (final styles in ['values-v31', 'values-night-v31']) {
      final xml = File('$res/$styles/styles.xml').readAsStringSync();
      expect(xml, contains('@drawable/splash_mark'), reason: styles);
      expect(xml, contains('@color/ic_launcher_background'), reason: styles);
    }
    for (final drawable in ['drawable', 'drawable-v21']) {
      final xml = File('$res/$drawable/launch_background.xml').readAsStringSync();
      expect(xml, contains('@drawable/splash_mark'), reason: drawable);
      expect(xml, contains('@color/ic_launcher_background'), reason: drawable);
    }
  });
}
