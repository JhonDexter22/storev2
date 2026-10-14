import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/barcode_scanner_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SettingsService.instance.resetForTests();
    await SettingsService.instance.load();
    await DatabaseHelper.instance.clearAllData();
    await ProductService().insertProduct(Product(
      name: 'Kopiko', sku: '4800', stock: 20, minStock: 5, category: 'Drinks',
      createdAt: DateTime.now().toIso8601String(), price: 12,
    ));
  });

  /// Opens the sale scanner from a page that records what it hands back.
  Future<List<ScannerResult?>> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final results = <ScannerResult?>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await Navigator.push<ScannerResult>(
            context,
            MaterialPageRoute(builder: (_) => const SimpleBarcodeScannerScreen.forSale()),
          )),
          child: const Text('Scan'),
        ),
      ),
    ));
    await tester.tap(find.text('Scan'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return results;
  }

  /// No camera in a test: the code goes in by hand, then onto the sale.
  Future<void> typeCode(WidgetTester tester, String code) async {
    await tester.tap(find.text('Enter code manually'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), code);
    await tester.tap(find.text('Look up'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('Add to sale'));
    await tester.pump();
  }

  testWidgets('goes back to the sale by itself once something is added', (tester) async {
    final results = await open(tester);
    expect(find.text('Back to the sale…'), findsNothing, reason: 'nothing added yet');

    await typeCode(tester, '4800');
    expect(find.text('Back to the sale…'), findsOneWidget);

    await tester.pump(SimpleBarcodeScannerScreen.autoReturnAfter);
    // The page slides away over a few frames.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(SimpleBarcodeScannerScreen), findsNothing);
    final sale = results.single as ScanSale;
    expect(sale.added.values.single, 1);
  });

  testWidgets('waits while the cashier is setting a count', (tester) async {
    await open(tester);
    await typeCode(tester, '4800');

    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(find.text('Back to the sale…'), findsNothing);
    await tester.pump(SimpleBarcodeScannerScreen.autoReturnAfter * 2);
    expect(find.byType(SimpleBarcodeScannerScreen), findsOneWidget);
  });
}
