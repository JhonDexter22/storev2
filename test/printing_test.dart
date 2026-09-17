import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:storev2/models/shift_model.dart';
import 'package:storev2/services/escpos.dart';
import 'package:storev2/services/printer_service.dart';
import 'package:storev2/services/receipt_document.dart';
import 'package:storev2/services/settings_service.dart';

/// A printer that never existed: records what it was asked to do and can be
/// told to fail at any step.
class FakeTransport implements PrinterTransport {
  FakeTransport({
    this.supported = true,
    this.permitted = true,
    this.bluetoothOn = true,
    this.connectedAtStart = false,
    this.connectSucceeds = true,
    this.writeSucceedsAfter = 0,
    this.throwOnWrite = false,
  });

  bool supported;
  bool permitted;
  bool bluetoothOn;
  bool connectedAtStart;
  bool connectSucceeds;

  /// Writes fail until this many have been attempted, then succeed.
  int writeSucceedsAfter;
  bool throwOnWrite;

  final List<String> calls = [];
  final List<List<int>> written = [];
  int writeAttempts = 0;
  bool _connected = false;

  @override
  Future<bool> get isSupported async => supported;

  @override
  Future<bool> get hasPermission async => permitted;

  @override
  Future<bool> get isBluetoothOn async => bluetoothOn;

  @override
  Future<bool> get isConnected async => _connected || connectedAtStart;

  @override
  Future<List<PrinterDevice>> paired() async {
    calls.add('paired');
    return const [
      PrinterDevice(name: 'RPP02N', address: '00:11:22:33:44:55'),
      PrinterDevice(name: '', address: 'AA:BB:CC:DD:EE:FF'),
    ];
  }

  @override
  Future<bool> connect(String address) async {
    calls.add('connect $address');
    if (connectSucceeds) _connected = true;
    return connectSucceeds;
  }

  @override
  Future<bool> write(List<int> bytes) async {
    calls.add('write');
    writeAttempts++;
    if (throwOnWrite) throw StateError('socket closed');
    if (writeAttempts <= writeSucceedsAfter) return false;
    written.add(bytes);
    return true;
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    _connected = false;
    connectedAtStart = false;
  }
}

/// True if [needle] appears anywhere in [haystack].
bool containsRun(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var hit = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return true;
  }
  return false;
}

bool hasText(List<int> bytes, String text) =>
    containsRun(bytes, EscPos.encode(text));

void main() {
  final settings = SettingsService.instance;
  final printer = PrinterService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await settings.load();
  });

  group('encoding', () {
    test('plain ASCII goes through untouched', () {
      expect(EscPos.encode('Total 50.00'), 'Total 50.00'.codeUnits);
    });

    test('the peso sign becomes P', () {
      // Code page 437 predates the peso sign and no common thermal code page
      // carries it, so ₱ would print as a wrong glyph or nothing at all.
      expect(EscPos.encode('₱50.00'), 'P50.00'.codeUnits);
    });

    test('no receipt ever sends UTF-8 down the wire', () {
      final bytes = ReceiptDocument.asBytes(
        ReceiptDocument.sale(
          storeName: 'Aling Niña\'s Store',
          reference: 'S20260909-0001',
          time: DateTime(2026, 9, 9, 15, 4),
          items: const [
            ReceiptLineItem(
                name: 'Piattos', qty: 1, unitPrice: 20, lineTotal: 20),
          ],
          subtotal: 20,
          total: 20,
          method: 'Cash',
          cashReceived: 50,
          change: 30,
        ),
        PaperWidth.mm58,
      );
      // 0xE2 leads the UTF-8 encoding of ₱; a printer reading it as CP437
      // would print three pieces of line-drawing junk.
      expect(bytes.contains(0xE2), isFalse);
      expect(bytes.every((b) => b <= 0xFF), isTrue);
    });

    test('Filipino names keep their tilde', () {
      // Niño and Peña are ordinary names here — printing Ni?o is not fine.
      expect(EscPos.encode('Niño'), [0x4E, 0x69, 0xA4, 0x6F]);
      expect(EscPos.encode('Peña'), [0x50, 0x65, 0xA4, 0x61]);
    });

    test('a character with no representation becomes a question mark', () {
      expect(EscPos.encode('日'), [0x3F]);
    });

    test('smart punctuation is flattened rather than mangled', () {
      expect(EscPos.encode('“it’s”'), '"it\'s"'.codeUnits);
    });
  });

  group('layout', () {
    test('a row fills the paper exactly', () {
      final lines = EscPos.row('Total', 'P50.00', 32);
      expect(lines, hasLength(1));
      expect(lines.single.length, 32);
      expect(lines.single, endsWith('P50.00'));
      expect(lines.single, startsWith('Total'));
    });

    test('a long name wraps and the figure lands on the last line', () {
      final lines =
          EscPos.row('3 x Lucky Me Pancit Canton Kalamansi', 'P105.00', 32);
      expect(lines.length, greaterThan(1));
      // The amount column has to stay straight however long the name is.
      expect(lines.last.length, 32);
      expect(lines.last, endsWith('P105.00'));
      for (final l in lines) {
        expect(l.length, lessThanOrEqualTo(32));
      }
    });

    test('a word too long to fit is split rather than dropped', () {
      final lines = EscPos.wrap('A' * 40, 32);
      expect(lines, ['A' * 32, 'A' * 8]);
    });

    test('an indent survives the wrap', () {
      // Without this the unit price loses its indent and reads as a line of
      // its own rather than as part of the item above it.
      expect(EscPos.wrap('    @ P10.00 each', 32), ['    @ P10.00 each']);
      expect(EscPos.wrap('  one two three', 9), ['  one two', '  three']);
      for (final l in EscPos.wrap('  ${'A' * 20}', 10)) {
        expect(l.length, lessThanOrEqualTo(10));
      }
    });

    test('an indented row keeps its indent and its column', () {
      final line = EscPos.row('  P500.00 x 4', 'P2,000.00', 32).single;
      expect(line, startsWith('  P500.00 x 4'));
      expect(line.length, 32);
    });

    test('wrapping breaks at words', () {
      expect(EscPos.wrap('one two three four', 9), ['one two', 'three', 'four']);
    });

    test('centring never overflows the paper', () {
      for (final l in EscPos.centre('A very long store name indeed', 20)) {
        expect(l.length, lessThanOrEqualTo(20));
      }
    });

    test('80 mm paper is wider than 58 mm', () {
      expect(PaperWidth.mm58.cols, 32);
      expect(PaperWidth.mm80.cols, 48);
      expect(EscPos.row('Total', 'P50.00', PaperWidth.mm80.cols).single.length,
          48);
    });
  });

  group('the sale receipt', () {
    List<dynamic> cashSale({double discount = 0, String? tab}) =>
        ReceiptDocument.sale(
          storeName: 'Aling Nena Store',
          reference: 'S20260909-0007',
          time: DateTime(2026, 9, 9, 15, 4),
          cashier: 'May',
          items: const [
            ReceiptLineItem(
                name: 'SkyFlakes', qty: 3, unitPrice: 15, lineTotal: 45),
            ReceiptLineItem(
                name: 'Kopiko', qty: 1, unitPrice: 12, lineTotal: 12),
          ],
          subtotal: 57,
          total: 57 - discount,
          method: tab == null ? 'Cash' : 'Utang',
          discountLabel: discount > 0 ? 'Senior citizen 20%' : '',
          discountAmount: discount,
          cashReceived: tab == null ? 100 : 0,
          change: tab == null ? 100 - (57 - discount) : 0,
          chargedTo: tab,
        );

    test('carries what a customer needs to query it', () {
      final text = ReceiptDocument.asText(cashSale().cast());
      expect(text, contains('ALING NENA STORE'));
      expect(text, contains('S20260909-0007'));
      expect(text, contains('09/09/2026'));
      expect(text, contains('Served by May'));
      expect(text, contains('3 x SkyFlakes'));
      expect(text, contains('₱45.00'));
      expect(text, contains('TOTAL'));
      expect(text, contains('₱57.00'));
      expect(text, contains('₱43.00')); // change
    });

    test('a unit price is shown only where it is not already obvious', () {
      final text = ReceiptDocument.asText(cashSale().cast());
      // Three of a thing needs its unit price; one of a thing does not, and
      // printing it twice just uses paper.
      expect(text, contains('    @ ₱15.00 each'));
      expect(text, isNot(contains('@ ₱12.00 each')));
    });

    test('a discount is itemised, not folded into the total', () {
      final text = ReceiptDocument.asText(cashSale(discount: 11.4).cast());
      expect(text, contains('Subtotal'));
      expect(text, contains('₱57.00'));
      expect(text, contains('Senior citizen 20%'));
      expect(text, contains('-₱11.40'));
      expect(text, contains('₱45.60'));
    });

    test('a sale on the tab says it is not paid', () {
      final text = ReceiptDocument.asText(cashSale(tab: 'Aling Nena').cast());
      expect(text, contains('ON TAB'));
      expect(text, contains('Charged to'));
      expect(text, contains('Aling Nena'));
      expect(text, contains('NOT YET PAID'));
      // Nothing was tendered, so there is no change to print.
      expect(text, isNot(contains('Change')));
      expect(text, isNot(contains('Thank you')));
    });

    test('the printed copy says the same as the shared copy', () {
      final blocks = cashSale(discount: 11.4).cast<ReceiptBlock>();
      final text = ReceiptDocument.asText(blocks);
      final bytes = ReceiptDocument.asBytes(blocks, PaperWidth.mm58);

      // A customer comparing the slip in their hand with the copy sent to
      // their phone must see the same figures.
      for (final needle in [
        'S20260909-0007',
        '3 x SkyFlakes',
        'Senior citizen 20%',
        'Served by May',
      ]) {
        expect(text, contains(needle));
        expect(hasText(bytes, needle), isTrue, reason: '$needle missing');
      }
    });

    test('the byte stream is a complete job', () {
      final bytes =
          ReceiptDocument.asBytes(cashSale().cast(), PaperWidth.mm58);
      // Initialise first, or a receipt inherits the last job's double height.
      expect(bytes.take(2), [0x1B, 0x40]);
      // Feed past the tear bar, then cut.
      expect(containsRun(bytes, [0x1D, 0x56, 0x42, 0x00]), isTrue);
      expect(bytes.length, greaterThan(200));
    });

    test('the total is printed double size against half the width', () {
      final bytes =
          ReceiptDocument.asBytes(cashSale().cast(), PaperWidth.mm58);
      expect(containsRun(bytes, [0x1D, 0x21, 0x11]), isTrue, reason: 'no big');
      expect(containsRun(bytes, [0x1D, 0x21, 0x00]), isTrue, reason: 'no reset');
      // Laid out for 16 columns, not 32 — at double width the paper holds half
      // as many characters and the amount would otherwise run off the edge.
      expect(hasText(bytes, 'TOTAL     P57.00'), isTrue);
    });
  });

  group('the shift summary', () {
    Shift shift({double variance = -25}) => Shift(
          closedAt: DateTime(2026, 9, 9, 20, 30).toIso8601String(),
          openedAt: DateTime(2026, 9, 9, 8, 0).toIso8601String(),
          cashier: 'Ronel',
          terminal: 'Terminal 1',
          openingFloat: 1000,
          cashSales: 3200,
          expected: 4200,
          counted: 4200 + variance,
          variance: variance,
          totalSales: 5100,
          saleCount: 42,
          denominations: const {500: 4, 100: 12, 20: 5, 1: 0},
        );

    test('says short or over in a word, not just a sign', () {
      expect(ReceiptDocument.asText(ReceiptDocument.shift(shift(),
              storeName: 'Aling Nena Store')),
          contains('SHORT'));
      expect(
          ReceiptDocument.asText(ReceiptDocument.shift(shift(variance: 25),
              storeName: 'Aling Nena Store')),
          contains('OVER'));
      expect(
          ReceiptDocument.asText(ReceiptDocument.shift(shift(variance: 0),
              storeName: 'Aling Nena Store')),
          contains('BALANCED'));
    });

    test('reproduces the drawer, largest note first', () {
      final text = ReceiptDocument.asText(
          ReceiptDocument.shift(shift(), storeName: 'Aling Nena Store'));
      expect(text, contains('  ₱500.00 x 4'));
      expect(text, contains('₱2,000.00'));
      expect(text, contains('₱100.00 x 12'));
      // A denomination nobody counted is noise on a narrow roll.
      expect(text, isNot(contains('₱1.00 x 0')));
      expect(text.indexOf('₱500.00 x 4'), lessThan(text.indexOf('₱20.00 x 5')));
    });

    test('leaves a line to sign', () {
      final text = ReceiptDocument.asText(
          ReceiptDocument.shift(shift(), storeName: 'Aling Nena Store'));
      expect(text, contains('Signature'));
      expect(text, contains('Ronel'));
      expect(text, contains('42'));
    });
  });

  group('printing', () {
    late FakeTransport fake;

    setUp(() async {
      fake = FakeTransport();
      printer.resetForTests(fake);
      await settings.setPrinter('00:11:22:33:44:55', name: 'RPP02N');
    });

    List<ReceiptBlock> doc() => const [ReceiptTitle('Store'), ReceiptRule()];

    test('with no printer chosen it says so instead of failing silently',
        () async {
      await settings.setPrinter(null);
      final r = await printer.printDocument(doc());
      expect(r, isA<PrintNoPrinter>());
      expect(r.message, contains('Settings'));
      expect(fake.calls, isEmpty);
    });

    test('a good print connects once and writes once', () async {
      final r = await printer.printDocument(doc());
      expect(r.ok, isTrue);
      expect(fake.calls, ['connect 00:11:22:33:44:55', 'write']);
      expect(fake.written.single.take(2), [0x1B, 0x40]);
    });

    test('an already-open socket is reused', () async {
      fake.connectedAtStart = true;
      await printer.printDocument(doc());
      expect(fake.calls, ['write']);
    });

    test('a stale socket is dropped and retried once', () async {
      fake.connectedAtStart = true;
      fake.writeSucceedsAfter = 1;

      final r = await printer.printDocument(doc());

      // The first write failed, so nothing was printed and the retry cannot
      // produce a second copy.
      expect(r.ok, isTrue);
      expect(fake.calls,
          ['write', 'disconnect', 'connect 00:11:22:33:44:55', 'write']);
      expect(fake.written, hasLength(1));
    });

    test('it gives up after one retry rather than looping', () async {
      fake.connectedAtStart = true;
      fake.writeSucceedsAfter = 99;

      final r = await printer.printDocument(doc());
      expect(r, isA<PrintFailed>());
      expect((r as PrintFailed).detail, 'write refused');
      expect(fake.writeAttempts, 2);
    });

    test('each failure tells the shopkeeper a different thing to do', () async {
      fake.bluetoothOn = false;
      expect((await printer.printDocument(doc())).message,
          contains('Bluetooth is off'));

      fake
        ..bluetoothOn = true
        ..permitted = false;
      expect((await printer.printDocument(doc())).message, contains('Allow'));

      fake
        ..permitted = true
        ..supported = false;
      expect(await printer.printDocument(doc()), isA<PrintUnsupported>());

      fake
        ..supported = true
        ..connectSucceeds = false;
      final r = await printer.printDocument(doc());
      expect(r.message, contains('switched on'));
      expect((r as PrintFailed).detail, 'connect refused');
    });

    test('a printer going out of range does not take the screen down',
        () async {
      fake.throwOnWrite = true;
      final r = await printer.printDocument(doc());
      // A thrown PlatformException mid-sale must become a message, not a
      // crash on the screen holding the customer's change.
      expect(r, isA<PrintFailed>());
      expect((r as PrintFailed).detail, contains('socket closed'));
    });

    test('the paper width setting reaches the paper', () async {
      await settings.setPaperWidth(PaperWidth.mm80);
      await printer.printDocument(const [ReceiptRule()]);
      expect(hasText(fake.written.single, '-' * 48), isTrue);

      await settings.setPaperWidth(PaperWidth.mm58);
      await printer.printDocument(const [ReceiptRule()]);
      expect(hasText(fake.written.last, '-' * 32), isTrue);
    });

    test('the test page proves the width is right', () async {
      await printer.printTestPage();
      expect(hasText(fake.written.single, 'Printer test'), isTrue);
      expect(hasText(fake.written.single, '58 mm'), isTrue);
    });

    test('a printer with no name is listed by its address', () async {
      final found = await printer.pairedPrinters();
      expect(found.first.label, 'RPP02N');
      expect(found.last.label, 'AA:BB:CC:DD:EE:FF');
    });

    test('choosing a printer survives a restart', () async {
      expect(printer.hasPrinter, isTrue);
      expect(settings.printerName, 'RPP02N');
      await settings.setPrinter(null);
      expect(printer.hasPrinter, isFalse);
      expect(settings.printerName, '');
    });
  });
}
