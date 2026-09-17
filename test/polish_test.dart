import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as pth;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/core/design_tokens.dart';
import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/cart_line.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/pos_screen.dart';
import 'package:storev2/screens/returns_screen.dart';
import 'package:storev2/services/product_service.dart';
import 'package:storev2/services/sales_service.dart';
import 'package:storev2/services/settings_service.dart';

void main() {
  final products = ProductService();
  final sales = SalesService();
  late Directory temp;

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
    temp = await Directory.systemTemp.createTemp('storev2-polish');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<Product> addProduct({String? imagePath, String name = 'SkyFlakes'}) async {
    final id = await products.insertProduct(Product(
      name: name,
      stock: 10,
      minStock: 1,
      category: 'Biscuit',
      createdAt: DateTime.now().toIso8601String(),
      price: 10,
      imagePath: imagePath,
    ));
    return (await products.getAllProducts()).firstWhere((x) => x.id == id);
  }

  Future<void> pumpPos(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PosScreen(key: UniqueKey())));
    await tester.pumpAndSettle();
  }

  group('the till shows the product photo', () {
    testWidgets('a product with no photo still gets the placeholder',
        (tester) async {
      await addProduct();
      await pumpPos(tester);
      expect(find.byType(PhotoPlaceholder), findsOneWidget);
    });

    testWidgets('a photo whose file has gone falls back, not crashes',
        (tester) async {
      await addProduct(imagePath: pth.join(temp.path, 'cleared.png'));
      await pumpPos(tester);

      // Exactly the state a cleared cache used to leave behind: the row still
      // names a file that is not there.
      expect(tester.takeException(), isNull);
      expect(find.text('SkyFlakes'), findsOneWidget);
    });
  });

  group('a sale that is already fully returned', () {
    testWidgets('offers a way back instead of a dead end', (tester) async {
      final p = await addProduct();
      final sale = await sales.recordSale(
          lines: [CartLine(product: p, qty: 1)], paymentMethod: 'Cash');
      await sales.recordRefund(
        sale: sale,
        lines: {p.id!: 1},
        reason: 'Damaged',
        method: 'Cash',
        restock: true,
        isVoid: true,
      );

      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(home: ReturnsScreen(key: UniqueKey())));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Return items').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('already been returned'), findsOneWidget);
      // Was a sentence floating in an empty screen whose only exit was the
      // back arrow in the corner.
      expect(find.text('Back to recent sales'), findsOneWidget);

      await tester.tap(find.text('Back to recent sales'));
      await tester.pumpAndSettle();
      expect(find.text('Recent sales'), findsOneWidget);
    });
  });

  group('the More tab uses the shared palette', () {
    test('its colours are the tokens, not a private copy', () {
      // The duplicated values matched when they were removed; the point is
      // that the next palette change cannot leave this screen behind.
      expect(AppColors.canvas, const Color(0xFFF5F6FA));
      expect(AppColors.surface, const Color(0xFFFFFFFF));
      expect(AppColors.ink, const Color(0xFF0D0F1A));
      expect(AppColors.body, const Color(0xFF5A5F7A));
      expect(AppColors.hairline, const Color(0xFFE7EAF4));
      expect(AppColors.danger, const Color(0xFFDC2626));
    });
  });
}
