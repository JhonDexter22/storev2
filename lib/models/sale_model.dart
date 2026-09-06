class SaleItem {
  final int? id;
  final int? saleId;
  final int productId;
  final String name;
  final double unitPrice;
  final int qty;
  final double lineTotal;

  /// This line's share of the sale's discount, in pesos.
  ///
  /// Allocated at the till rather than worked out again at refund time, so a
  /// return pays back exactly what was taken for this line and rounding cannot
  /// drift between the two calculations.
  final double discount;

  SaleItem({
    this.id,
    this.saleId,
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.qty,
    required this.lineTotal,
    this.discount = 0,
  });

  /// What the customer actually paid for this line.
  double get netTotal => lineTotal - discount;

  /// Per-unit price after the discount — what one of these is worth on a
  /// partial return.
  double get netUnitPrice => qty == 0 ? 0 : netTotal / qty;

  Map<String, dynamic> toMap() => {
        'id': id,
        'sale_id': saleId,
        'product_id': productId,
        'name': name,
        'unit_price': unitPrice,
        'qty': qty,
        'line_total': lineTotal,
        'discount': discount,
      };

  factory SaleItem.fromMap(Map<String, dynamic> map) => SaleItem(
        id: map['id'],
        saleId: map['sale_id'],
        productId: map['product_id'],
        name: map['name'],
        unitPrice: (map['unit_price'] as num).toDouble(),
        qty: map['qty'],
        lineTotal: (map['line_total'] as num).toDouble(),
        discount: (map['discount'] as num?)?.toDouble() ?? 0,
      );
}

class Sale {
  final int? id;
  final String reference;
  final String createdAt;
  final double subtotal;
  final double total;
  final String paymentMethod;
  final double cashReceived;
  final double changeAmount;
  final int itemCount;

  /// Pesos taken off, and why. Kept beside [subtotal] and [total] rather than
  /// folded into them, so a report can show what was given away.
  final double discount;
  final String discountReason;

  /// Who rang it up. Empty on sales taken before this was recorded.
  final String cashier;

  final List<SaleItem> items;

  Sale({
    this.id,
    required this.reference,
    required this.createdAt,
    required this.subtotal,
    required this.total,
    required this.paymentMethod,
    this.cashReceived = 0,
    this.changeAmount = 0,
    required this.itemCount,
    this.discount = 0,
    this.discountReason = '',
    this.cashier = '',
    this.items = const [],
  });

  DateTime get createdAtDate => DateTime.parse(createdAt);

  Map<String, dynamic> toMap() => {
        'id': id,
        'reference': reference,
        'created_at': createdAt,
        'subtotal': subtotal,
        'total': total,
        'payment_method': paymentMethod,
        'cash_received': cashReceived,
        'change_amount': changeAmount,
        'item_count': itemCount,
        'discount': discount,
        'discount_reason': discountReason,
        'cashier': cashier,
      };

  factory Sale.fromMap(Map<String, dynamic> map) => Sale(
        id: map['id'],
        reference: map['reference'],
        createdAt: map['created_at'],
        subtotal: (map['subtotal'] as num).toDouble(),
        total: (map['total'] as num).toDouble(),
        paymentMethod: map['payment_method'],
        cashReceived: (map['cash_received'] as num?)?.toDouble() ?? 0,
        changeAmount: (map['change_amount'] as num?)?.toDouble() ?? 0,
        itemCount: map['item_count'],
        discount: (map['discount'] as num?)?.toDouble() ?? 0,
        discountReason: map['discount_reason'] as String? ?? '',
        cashier: map['cashier'] as String? ?? '',
      );
}
