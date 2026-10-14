import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:storev2/services/held_sales.dart';
import 'package:storev2/services/open_sale.dart';

/// Clearing, restoring or loading the demo year replaces every product, so
/// a sale rung up against the old ones must not come back against the new.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HeldSales.instance.reset();
    OpenSale.instance.reset();
  });

  test('held sales are dropped, and stay dropped after a restart', () async {
    await HeldSales.instance.load();
    await HeldSales.instance.hold({1: 2}, label: 'Kopiko ×2');
    expect(HeldSales.instance.count, 1);

    await HeldSales.instance.clear();
    expect(HeldSales.instance.count, 0);

    HeldSales.instance.reset(); // a fresh start; preferences are kept
    await HeldSales.instance.load();
    expect(HeldSales.instance.count, 0);
  });

  test('the open sale is dropped, and stays dropped after a restart', () async {
    await OpenSale.instance.load();
    OpenSale.instance.lines[1] = 2;
    OpenSale.instance.save();

    await OpenSale.instance.clear();
    expect(OpenSale.instance.lines, isEmpty);

    OpenSale.instance.reset();
    await OpenSale.instance.load();
    expect(OpenSale.instance.lines, isEmpty);
  });

  test('clearing before the till has opened still drops what was saved', () async {
    SharedPreferences.setMockInitialValues({
      'held_sales': '[{"id":"a","heldAt":"2026-10-14T09:00:00.000","label":"Kopiko","lines":{"1":1}}]',
      'open_sale': '{"lines":{"1":1},"quick":{}}',
    });
    await HeldSales.instance.clear();
    await OpenSale.instance.clear();

    HeldSales.instance.reset();
    OpenSale.instance.reset();
    await HeldSales.instance.load();
    await OpenSale.instance.load();
    expect(HeldSales.instance.count, 0);
    expect(OpenSale.instance.lines, isEmpty);
  });
}
