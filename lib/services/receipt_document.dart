import 'dart:typed_data';

import '../core/design_tokens.dart' show formatPeso;
import '../models/shift_model.dart';
import 'escpos.dart';

/// One element of a receipt, independent of how it reaches paper.
///
/// Receipts go two places — the printer and the Share sheet — and a customer
/// comparing the two should see the same document. One model rendered twice is
/// the only way that stays true as the receipt changes.
sealed class ReceiptBlock {
  const ReceiptBlock();
}

/// The store's name, at the top.
class ReceiptTitle extends ReceiptBlock {
  const ReceiptTitle(this.text);
  final String text;
}

/// Centred small print — the reference, the date, the thank-you.
class ReceiptCentred extends ReceiptBlock {
  const ReceiptCentred(this.text);
  final String text;
}

/// A label and a figure, the figure hard against the right edge.
class ReceiptRow extends ReceiptBlock {
  const ReceiptRow(this.left, this.right, {this.strong = false});
  final String left;
  final String right;
  final bool strong;
}

/// Left-aligned prose that wraps.
class ReceiptNote extends ReceiptBlock {
  const ReceiptNote(this.text);
  final String text;
}

/// The one figure the customer looks for, printed double size.
class ReceiptHeadline extends ReceiptBlock {
  const ReceiptHeadline(this.label, this.value);
  final String label;
  final String value;
}

class ReceiptRule extends ReceiptBlock {
  const ReceiptRule();
}

class ReceiptGap extends ReceiptBlock {
  const ReceiptGap();
}

/// One line of a sale, as it appears on paper.
class ReceiptLineItem {
  const ReceiptLineItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String name;
  final int qty;
  final double unitPrice;
  final double lineTotal;
}

/// Assembles the receipts the app prints, and renders them.
class ReceiptDocument {
  /// A sale, as handed over at the till.
  ///
  /// Takes plain figures rather than a saved row so the success screen can
  /// print the sale it has just taken without reading it back out again.
  static List<ReceiptBlock> sale({
    required String storeName,
    required String reference,
    required DateTime time,
    required List<ReceiptLineItem> items,
    required double subtotal,
    required double total,
    required String method,
    String cashier = '',
    String discountLabel = '',
    double discountAmount = 0,
    double cashReceived = 0,
    double change = 0,
    String? chargedTo,
  }) {
    final onCredit = chargedTo != null;
    return [
      ReceiptTitle(storeName),
      ReceiptCentred(reference),
      ReceiptCentred(_stamp(time)),
      if (cashier.isNotEmpty) ReceiptCentred('Served by $cashier'),
      const ReceiptRule(),
      for (final item in items) ...[
        ReceiptRow('${item.qty} x ${item.name}', formatPeso(item.lineTotal)),
        // Only worth the paper when there is more than one: for a single item
        // the unit price is the line total, printed twice.
        if (item.qty > 1)
          ReceiptNote('    @ ${formatPeso(item.unitPrice)} each'),
      ],
      const ReceiptRule(),
      if (discountAmount > 0) ...[
        ReceiptRow('Subtotal', formatPeso(subtotal)),
        ReceiptRow(discountLabel.isEmpty ? 'Discount' : discountLabel,
            '-${formatPeso(discountAmount)}'),
      ],
      ReceiptHeadline(onCredit ? 'ON TAB' : 'TOTAL', formatPeso(total)),
      const ReceiptGap(),
      if (onCredit)
        ReceiptRow('Charged to', chargedTo)
      else ...[
        ReceiptRow('Paid by', method),
        if (method == 'Cash') ...[
          ReceiptRow('Cash', formatPeso(cashReceived)),
          ReceiptRow('Change', formatPeso(change), strong: true),
        ],
      ],
      const ReceiptGap(),
      // An unpaid balance is the whole point of the slip on a tab sale, so it
      // says so rather than looking like a paid receipt.
      if (onCredit)
        const ReceiptCentred('NOT YET PAID')
      else
        const ReceiptCentred('Thank you! Come again'),
    ];
  }

  /// The end-of-shift cash count — for the shopkeeper, not a customer.
  static List<ReceiptBlock> shift(Shift s, {required String storeName}) {
    final over = s.variance > 0;
    final short = s.variance < 0;
    return [
      ReceiptTitle(storeName),
      const ReceiptCentred('SHIFT SUMMARY'),
      ReceiptCentred(_stamp(s.closedAtDate)),
      const ReceiptRule(),
      ReceiptRow('Cashier', s.cashier),
      ReceiptRow('Terminal', s.terminal),
      if (s.openedAtDate != null) ReceiptRow('Opened', _clock(s.openedAtDate!)),
      ReceiptRow('Closed', _clock(s.closedAtDate)),
      const ReceiptRule(),
      ReceiptRow('Sales', '${s.saleCount}'),
      ReceiptRow('Sales total', formatPeso(s.totalSales)),
      const ReceiptGap(),
      ReceiptRow('Opening float', formatPeso(s.openingFloat)),
      ReceiptRow('Cash sales', formatPeso(s.cashSales)),
      ReceiptRow('Expected', formatPeso(s.expected)),
      ReceiptRow('Counted', formatPeso(s.counted)),
      const ReceiptRule(),
      ReceiptHeadline(
        short ? 'SHORT' : (over ? 'OVER' : 'BALANCED'),
        formatPeso(s.variance.abs()),
      ),
      if (s.denominations.isNotEmpty) ...[
        const ReceiptGap(),
        const ReceiptNote('Counted as:'),
        for (final d in _sortedDenominations(s.denominations))
          ReceiptRow('  ${formatPeso(d.key)} x ${d.value}',
              formatPeso(d.key * d.value)),
      ],
      const ReceiptGap(),
      ReceiptRow('Signature', '_' * 12),
    ];
  }

  static List<MapEntry<int, int>> _sortedDenominations(Map<int, int> d) =>
      d.entries.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.key.compareTo(a.key));

  // --------------------------------------------------------------- rendering

  /// The document as plain text — what the Share sheet sends.
  static String asText(List<ReceiptBlock> blocks, {int cols = 32}) {
    final out = <String>[];
    for (final b in blocks) {
      switch (b) {
        case ReceiptTitle(:final text):
          out.addAll(EscPos.centre(text.toUpperCase(), cols));
        case ReceiptCentred(:final text):
          out.addAll(EscPos.centre(text, cols));
        case ReceiptRow(:final left, :final right):
          out.addAll(EscPos.row(left, right, cols));
        case ReceiptNote(:final text):
          out.addAll(EscPos.wrap(text, cols));
        case ReceiptHeadline(:final label, :final value):
          out.addAll(EscPos.row(label, value, cols));
        case ReceiptRule():
          out.add('-' * cols);
        case ReceiptGap():
          out.add('');
      }
    }
    return out.join('\n');
  }

  /// The document as ESC/POS bytes — what goes down the Bluetooth socket.
  static Uint8List asBytes(List<ReceiptBlock> blocks, PaperWidth paper) {
    final p = EscPos(paper)..reset();
    for (final b in blocks) {
      switch (b) {
        case ReceiptTitle(:final text):
          p
            ..align(EscAlign.centre)
            ..bold(true)
            ..lines(EscPos.wrap(text.toUpperCase(), p.cols))
            ..bold(false)
            ..align(EscAlign.left);
        case ReceiptCentred(:final text):
          p
            ..align(EscAlign.centre)
            ..lines(EscPos.wrap(text, p.cols))
            ..align(EscAlign.left);
        case ReceiptRow(:final left, :final right, :final strong):
          p
            ..bold(strong)
            ..lines(EscPos.row(left, right, p.cols))
            ..bold(false);
        case ReceiptNote(:final text):
          p.lines(EscPos.wrap(text, p.cols));
        case ReceiptHeadline(:final label, :final value):
          // Double size halves the columns, so this has to be laid out against
          // half the width or the figure runs off the edge of the paper.
          p
            ..big(true)
            ..lines(EscPos.row(label, value, p.cols ~/ 2))
            ..big(false);
        case ReceiptRule():
          p.rule();
        case ReceiptGap():
          p.line();
      }
    }
    p.cut();
    return p.bytes();
  }

  static String _stamp(DateTime t) =>
      '${_two(t.day)}/${_two(t.month)}/${t.year}  ${_clock(t)}';

  static String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  static String _two(int v) => v.toString().padLeft(2, '0');
}
