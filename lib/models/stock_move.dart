/// What moved a product's stock. Stored by [key], so renaming a value here
/// must not change its key.
enum StockMoveKind {
  sale('sale'),
  returned('return'),
  restock('restock'),
  stockIn('stock_in'),
  /// The stock typed in by hand on the product form.
  count('count'),
  added('new'),
  deleted('delete'),
  undo('undo');

  const StockMoveKind(this.key);

  final String key;

  static StockMoveKind fromKey(String key) =>
      values.firstWhere((k) => k.key == key, orElse: () => count);

  /// Changes someone made by hand, rather than the till making them: where
  /// missing stock hides, so the history can show just these.
  bool get byHand => this == count || this == deleted || this == undo;
}

/// One row of a product's stock history.
class StockMove {
  const StockMove({
    this.id,
    required this.productId,
    required this.productName,
    required this.createdAt,
    required this.kind,
    required this.delta,
    required this.stockAfter,
    this.cashier = '',
    this.reference = '',
  });

  final int? id;
  final int productId;

  /// The name when it moved, so a deleted product's rows still say what it was.
  final String productName;
  final String createdAt;
  final StockMoveKind kind;

  /// Units in (positive) or out (negative), as actually applied: stock never
  /// goes below zero, so a sale of 3 from 2 on the shelf is −2.
  final int delta;
  final int stockAfter;
  final String cashier;

  /// The sale's receipt number, for a sale or a return.
  final String reference;

  DateTime get createdAtDate => DateTime.parse(createdAt);

  /// "#0090" — the tail of the receipt number, as receipts and Returns show it.
  String get shortRef {
    if (reference.isEmpty) return '';
    final dash = reference.lastIndexOf('-');
    return dash == -1 ? reference : '#${reference.substring(dash + 1)}';
  }

  factory StockMove.fromMap(Map<String, Object?> m) => StockMove(
        id: m['id'] as int?,
        productId: m['product_id'] as int,
        productName: m['product_name'] as String? ?? '',
        createdAt: m['created_at'] as String,
        kind: StockMoveKind.fromKey(m['kind'] as String),
        delta: m['delta'] as int,
        stockAfter: m['stock_after'] as int,
        cashier: m['cashier'] as String? ?? '',
        reference: m['reference'] as String? ?? '',
      );
}
