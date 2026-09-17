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
      // A printer that reports no name is still usable, listed by address.
      expect(find.text('AA:BB:CC:DD:EE:FF'), findsNWidgets(2));

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
      final button = find.ancestor(
        of: find.text('Print a test receipt'),
        matching: find.byWidgetPredicate((w) => w is ElevatedButton),
      );
      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

      await tester.tap(find.text('RPP02N'));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(hasText(fake.written.single, 'Printer test'), isTrue);
      expect(find.text('Printed'), findsOneWidget);
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

    testWidgets('with no printer it says where to set one up', (tester) async {
      await settings.setPrintReceipt(false);
      await sell(tester);

      await tester.tap(find.text('Print receipt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('pick one in Settings'), findsOneWidget);
      expect(fake.written, isEmpty);
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
}

class _EmptyTransport extends FakeTransport {
  @override
  Future<List<PrinterDevice>> paired() async => const [];
}
