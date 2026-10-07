import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/checkout_screen.dart';
import 'package:storev2/screens/printer_screen.dart';
import 'package:storev2/services/escpos.dart';
import 'package:storev2/services/printer_service.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/settings_service.dart';

import 'printing_test.dart' show FakeTransport, hasText;

void main() {
  final settings = SettingsService.instance;
  final printer = PrinterService.instance;
  final products = ProductService();
  late FakeTransport fake;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings.resetForTests();
    await settings.load();
    await DatabaseHelper.instance.clearAllData();
    fake = FakeTransport();
    printer.resetForTests(fake);
  });

  Future<void> pumpPrinterScreen(WidgetTester tester) async {
    // Tall enough that the whole settings page is laid out: a ListView does
    // not build what is below the fold, and an unbuilt button cannot be
    // checked for being disabled.
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(key: UniqueKey(), home: const PrinterScreen()));
    await tester.pumpAndSettle();
  }

  group('choosing a printer', () {
    testWidgets('paired printers are listed and one can be chosen',
        (tester) async {
      await pumpPrinterScreen(tester);

      expect(find.text('RPP02N'), findsOneWidget);
      expect(find.text('00:11:22:33:44:55'), findsOneWidget);
      // A printer that reports no name is still usable: called "Unnamed
      // device", its address under it once rather than twice.
      expect(find.text('Unnamed device'), findsOneWidget);
      expect(find.text('AA:BB:CC:DD:EE:FF'), findsOneWidget);

      await tester.tap(find.text('RPP02N'));
      await tester.pumpAndSettle();

      expect(settings.printerAddress, '00:11:22:33:44:55');
      expect(find.text('Printing to RPP02N'), findsOneWidget);
    });

    testWidgets('with Bluetooth off it says so rather than showing nothing',
        (tester) async {
      fake.bluetoothOn = false;
      await pumpPrinterScreen(tester);

      // An empty list would read as "no printers paired", sending the
      // shopkeeper to the wrong settings screen.
      expect(find.textContaining('Bluetooth is off'), findsOneWidget);
      expect(find.text('RPP02N'), findsNothing);
    });

    testWidgets('nothing paired points at the phone settings', (tester) async {
      printer.resetForTests(_EmptyTransport());
      await pumpPrinterScreen(tester);
      expect(find.textContaining('Nothing paired yet'), findsOneWidget);
    });

    testWidgets('the test print is blocked until a printer is chosen',
        (tester) async {
      await pumpPrinterScreen(tester);
      // ElevatedButton.icon builds a private subclass, which find.byType —
      // an exact runtime-type match — does not see.
      // Until then it says why it cannot be pressed.
      final button = find.ancestor(
        of: find.text('Pick a printer above'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

      // Choosing prints a test at once, so a wrong pick shows itself here.
      await tester.tap(find.text('RPP02N'));
      await tester.pumpAndSettle();
      expect(hasText(fake.written.single, 'Printer test'), isTrue);
      expect(find.text('Printed'), findsOneWidget);
      final ready = find.ancestor(
        of: find.text('Print a test receipt'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      expect(tester.widget<ElevatedButton>(ready).onPressed, isNotNull);

      await tester.tap(ready);
      await tester.pumpAndSettle();
      expect(fake.written.length, 2);
    });

    // OutlinedButton.icon is a private subclass; find.byType would miss it.
    Finder refreshButton() => find.ancestor(
        of: find.text('Refresh'), matching: find.byWidgetPredicate((w) => w is OutlinedButton));

    testWidgets('a message that says "tap Refresh" has the button in it', (tester) async {
      fake.bluetoothOn = false;
      await pumpPrinterScreen(tester);
      expect(find.textContaining('then tap Refresh'), findsOneWidget);
      expect(refreshButton(), findsOneWidget);

      // Switched on and refreshed from there: the printers appear.
      fake.bluetoothOn = true;
      await tester.tap(refreshButton());
      await tester.pumpAndSettle();
      expect(find.text('RPP02N'), findsOneWidget);
    });

    testWidgets('a phone that cannot print gets no Refresh to tap in vain', (tester) async {
      fake.supported = false;
      await pumpPrinterScreen(tester);
      expect(find.text('This device cannot print to a Bluetooth printer.'), findsOneWidget);
      expect(refreshButton(), findsNothing);
    });

    testWidgets('choosing something that is not a printer says so at once',
        (tester) async {
      fake.connectSucceeds = false;
      await pumpPrinterScreen(tester);
      await tester.tap(find.text('RPP02N'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Is it switched on?'), findsOneWidget);
    });

    testWidgets('likely printers come first, the rest under Other devices',
        (tester) async {
      printer.resetForTests(_MixedTransport());
      await pumpPrinterScreen(tester);

      final y = {
        for (final n in ['RPP02N', 'OTHER DEVICES', 'JBL Go 3'])
          n: tester.getTopLeft(find.text(n)).dy,
      };
      expect(y['RPP02N']!, lessThan(y['OTHER DEVICES']!));
      expect(y['OTHER DEVICES']!, lessThan(y['JBL Go 3']!));
    });

    testWidgets('a failed test print says what to do about it', (tester) async {
      fake.connectSucceeds = false;
      await settings.setPrinter('00:11:22:33:44:55', name: 'RPP02N');
      await pumpPrinterScreen(tester);

      await tester.tap(find.text('Print a test receipt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Is it switched on?'), findsOneWidget);
    });

    testWidgets('the paper width is a choice that sticks', (tester) async {
      await pumpPrinterScreen(tester);
      expect(settings.paperWidth, PaperWidth.mm58);

      await tester.tap(find.text('80 mm'));
      await tester.pumpAndSettle();
      expect(settings.paperWidth, PaperWidth.mm80);
      expect(find.text('48 characters'), findsOneWidget);
    });

    testWidgets('a printer can be forgotten', (tester) async {
      await settings.setPrinter('00:11:22:33:44:55', name: 'RPP02N');
      await pumpPrinterScreen(tester);

      await tester.tap(find.text('Forget this printer'));
      await tester.pumpAndSettle();
      expect(settings.printerAddress, isNull);
      expect(find.text('Forget this printer'), findsNothing);
    });
  });

  group('printing a sale', () {
    Future<Product> addProduct() async {
      final id = await products.insertProduct(Product(
        name: 'SkyFlakes',
        stock: 100,
        minStock: 5,
        category: 'Biscuit',
        createdAt: DateTime.now().toIso8601String(),
        price: 50,
      ));
      return Product(
        id: id,
        name: 'SkyFlakes',
        stock: 100,
        minStock: 5,
        category: 'Biscuit',
        createdAt: DateTime.now().toIso8601String(),
        price: 50,
      );
    }

    Future<void> sell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final p = await addProduct();
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: CheckoutScreen(lines: [CartLine(product: p, qty: 1)]),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('₱500'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Complete sale'));
      await tester.pumpAndSettle();
    }

    testWidgets('the Print receipt button prints the sale', (tester) async {
      await settings.setPrinter('00:11:22:33:44:55', name: 'RPP02N');
      await settings.setPrintReceipt(false);
      await sell(tester);

      expect(fake.written, isEmpty);
      await tester.tap(find.text('Print receipt'));
      await tester.pumpAndSettle();

      // The button did nothing at all before this; the test that matters is
      // that bytes reached the printer, not that a toast appeared.
      expect(fake.written, hasLength(1));
      expect(hasText(fake.written.single, '1 x SkyFlakes'), isTrue);
      expect(hasText(fake.written.single, 'P450.00'), isTrue); // change
    });

    testWidgets('with no printer the button goes to set one up', (tester) async {
      await settings.setPrintReceipt(false);
      await sell(tester);

      // A Print button that can only fail used to point at Settings in a
      // toast. It now opens the printer screen itself.
      expect(find.text('Print receipt'), findsNothing);
      await tester.tap(find.text('Set up printer'));
      await tester.pumpAndSettle();
      expect(find.byType(PrinterScreen), findsOneWidget);
      expect(fake.written, isEmpty);

      // Back with a printer chosen: the same sale can now be printed.
      await settings.setPrinter('00:11:22:33:44:55', name: 'RPP02N');
      Navigator.of(tester.element(find.byType(PrinterScreen))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Print receipt'));
      await tester.pumpAndSettle();
      expect(fake.written, hasLength(1));
    });

    testWidgets('"print automatically" prints without being asked',
        (tester) async {
      await settings.setPrinter('00:11:22:33:44:55', name: 'RPP02N');
      await settings.setPrintReceipt(true);
      await sell(tester);

      expect(fake.written, hasLength(1));
      // Silence on success: the paper is the confirmation.
      expect(find.text('Printed'), findsNothing);
    });

    testWidgets('an automatic print that fails is not hidden', (tester) async {
      await settings.setPrinter('00:11:22:33:44:55', name: 'RPP02N');
      await settings.setPrintReceipt(true);
      fake.connectSucceeds = false;
      await sell(tester);

      // The cashier would otherwise hand over nothing and never know.
      expect(find.textContaining('Is it switched on?'), findsOneWidget);
    });

    testWidgets('the setting off means no automatic print', (tester) async {
      await settings.setPrinter('00:11:22:33:44:55', name: 'RPP02N');
      await settings.setPrintReceipt(false);
      await sell(tester);
      expect(fake.written, isEmpty);
    });
  });

  test('the printer guess goes by the name', () {
    for (final name in ['RPP02N', 'MTP-II', 'POS-58', 'PT-210', 'Bluetooth Printer', 'XPrinter XP-58']) {
      expect(looksLikePrinter(name), isTrue, reason: name);
    }
    for (final name in ['JBL Go 3', 'Galaxy Buds2', 'Toyota Car Kit', 'Possum speaker', '']) {
      expect(looksLikePrinter(name), isFalse, reason: name);
    }
  });
}

/// A phone with earbuds paired before the printer, the usual order.
class _MixedTransport extends FakeTransport {
  @override
  Future<List<PrinterDevice>> paired() async => const [
        PrinterDevice(name: 'JBL Go 3', address: '11:11:11:11:11:11'),
        PrinterDevice(name: 'RPP02N', address: '00:11:22:33:44:55'),
      ];
}

class _EmptyTransport extends FakeTransport {
  @override
  Future<List<PrinterDevice>> paired() async => const [];
}
