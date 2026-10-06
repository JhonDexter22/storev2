import 'package:flutter_test/flutter_test.dart';

import 'package:storev2/models/product_model.dart';
import 'package:storev2/screens/barcode_scanner_screen.dart';

void main() {
  Product kopiko({int stock = 5}) =>
      Product(id: 7, name: 'Kopiko', stock: stock, minStock: 1, category: 'Drinks', createdAt: '', price: 12);
  final t0 = DateTime(2026, 10, 2, 9);

  group('a read', () {
    test('adds one unit on sight', () {
      final s = ScanSession();
      expect(s.add(kopiko()), ScanOutcome.added);
      expect(s.countOf(kopiko()), 1);
      expect(s.total, 1);
    });

    test('of the same code is ignored while it is still in frame', () {
      final s = ScanSession();
      s.saw('4800', t0);
      expect(s.isRepeat('4800', t0.add(const Duration(milliseconds: 300))), isTrue);
      expect(s.isRepeat('4800', t0.add(const Duration(seconds: 2))), isFalse,
          reason: 'after the guard, a second unit of the same item can be scanned');
    });

    test('of a different code is not held up by the last one', () {
      final s = ScanSession();
      s.saw('4800', t0);
      expect(s.isRepeat('9310', t0.add(const Duration(milliseconds: 100))), isFalse);
    });
  });

  group('stock', () {
    test('counts what the cart already holds', () {
      // Two on the shelf, two already rung up: nothing more can go in.
      final s = ScanSession(inCart: {7: 2});
      expect(s.add(kopiko(stock: 2)), ScanOutcome.full);
      expect(s.total, 0);
    });

    test('counts what this session already added', () {
      final s = ScanSession();
      final p = kopiko(stock: 2);
      expect(s.add(p), ScanOutcome.added);
      expect(s.add(p), ScanOutcome.added);
      expect(s.add(p), ScanOutcome.full);
      expect(s.countOf(p), 2, reason: 'the header must not claim 3');
    });

    test('a larger quantity is trimmed to what fits', () {
      final s = ScanSession(inCart: {7: 1});
      expect(s.add(kopiko(stock: 3), qty: 5), ScanOutcome.full);
      expect(s.countOf(kopiko(stock: 3)), 2);
    });
  });

  group('editing the last item', () {
    test('sets its count outright, within the shelf', () {
      final s = ScanSession(inCart: {7: 1});
      final p = kopiko(stock: 4);
      s.add(p);
      s.setCount(p, 10);
      expect(s.countOf(p), 3, reason: '4 on the shelf, 1 already in the cart');
    });

    test('to zero takes it out of the sale', () {
      final s = ScanSession();
      final p = kopiko();
      s.add(p);
      s.setCount(p, 0);
      expect(s.added.containsKey(7), isFalse);
      expect(s.total, 0);
    });
  });
}
