import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:storev2/models/staff.dart';
import 'package:storev2/services/staff_service.dart';
import 'package:storev2/widgets/pin_sheet.dart';

void main() {
  /// Records what the sheet handed over, so a test can prove the sheet is the
  /// thing collecting digits and the service is the thing judging them.
  late List<String> submitted;

  setUp(() => submitted = []);

  /// A phone, not the 800x600 default: the sheet is tall, and the default
  /// surface is short enough that Confirm falls off the bottom.
  void usePhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpSheet(
    WidgetTester tester,
    Future<PinResult> Function(String) verify, {
    void Function(bool)? onResult,
  }) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final ok = await PinSheet.show(
                context,
                verify: (pin) {
                  submitted.add(pin);
                  return verify(pin);
                },
                title: 'Manager PIN',
                hint: 'Enter the manager PIN.',
                confirmLabel: 'Confirm',
              );
              onResult?.call(ok);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(find.text(d));
      await tester.pump();
    }
  }

  testWidgets('a correct PIN closes the sheet with true', (tester) async {
    bool? result;
    await pumpSheet(
      tester,
      (_) async => const PinAccepted(Staff(id: 1, name: 'Nena', role: 'Manager')),
      onResult: (ok) => result = ok,
    );

    await type(tester, '2468');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(submitted, ['2468']);
    expect(result, isTrue);
    expect(find.text('Confirm'), findsNothing, reason: 'the sheet should be gone');
  });

  testWidgets('a wrong PIN keeps the sheet open and says what is left',
      (tester) async {
    await pumpSheet(tester, (_) async => const PinRejected(4));

    await type(tester, '0000');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('4 tries left'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget, reason: 'still open for a retry');
  });

  testWidgets('one try left is singular', (tester) async {
    await pumpSheet(tester, (_) async => const PinRejected(1));

    await type(tester, '0000');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 try left'), findsOneWidget);
  });

  testWidgets('a lockout disables the keypad and counts down', (tester) async {
    await pumpSheet(
      tester,
      (_) async => const PinLockedOut(Duration(seconds: 3)),
    );

    await type(tester, '0000');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.textContaining('Try again in 3s'), findsOneWidget);

    // Keys are inert while locked: tapping does not refill the entry, so the
    // Confirm button cannot be re-enabled by mashing the pad.
    final before = submitted.length;
    await type(tester, '2468');
    await tester.pump();
    final confirm = tester.widget<ElevatedButton>(
      find.ancestor(of: find.text('Confirm'), matching: find.byType(ElevatedButton)),
    );
    expect(confirm.onPressed, isNull);
    expect(submitted.length, before, reason: 'nothing was submitted while locked');

    // And it releases itself rather than needing the sheet reopened.
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Try again in 2s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('Try again'), findsNothing);
    expect(find.text('Enter the manager PIN.'), findsOneWidget);
  });

  testWidgets('Confirm stays disabled until four digits are entered',
      (tester) async {
    await pumpSheet(tester, (_) async => const PinRejected(4));

    ElevatedButton confirmButton() => tester.widget<ElevatedButton>(
          find.ancestor(
              of: find.text('Confirm'), matching: find.byType(ElevatedButton)),
        );

    expect(confirmButton().onPressed, isNull);
    await type(tester, '246');
    expect(confirmButton().onPressed, isNull);
    await type(tester, '8');
    expect(confirmButton().onPressed, isNotNull);
  });

  group('capture mode', () {
    Future<String?> pumpCapture(WidgetTester tester, String digits,
        {bool cancel = false}) async {
      usePhoneSurface(tester);
      String? captured;
      var returned = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                captured = await PinSheet.capture(
                  context,
                  title: 'New PIN',
                  hint: 'Choose four digits.',
                  confirmLabel: 'Continue',
                );
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await type(tester, digits);
      await tester.tap(find.text(cancel ? 'Cancel' : 'Continue'));
      await tester.pumpAndSettle();
      expect(returned, isTrue, reason: 'the sheet should have closed');
      return captured;
    }

    testWidgets('returns the digits it collected', (tester) async {
      expect(await pumpCapture(tester, '9876'), '9876');
    });

    testWidgets('nothing judges the entry, so any code is accepted',
        (tester) async {
      // There is nothing to check a new PIN against; the sheet only collects.
      expect(await pumpCapture(tester, '0000'), '0000');
    });

    testWidgets('cancelling returns null rather than a PIN', (tester) async {
      expect(await pumpCapture(tester, '9876', cancel: true), isNull);
    });
  });

  testWidgets('Cancel returns false without ever calling verify',
      (tester) async {
    bool? result;
    await pumpSheet(
      tester,
      (_) async => fail('verify should not run when the sheet is cancelled'),
      onResult: (ok) => result = ok,
    );

    await type(tester, '2468');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(submitted, isEmpty);
  });
}
