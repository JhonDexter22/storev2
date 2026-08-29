class RefundItem {
  RefundItem({
    this.id,
    this.refundId,
    required this.productId,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });

  final int? id;
  final int? refundId;
  final int productId;
  final String name;
  final int qty;
  final double unitPrice;
  final double lineTotal;

  factory RefundItem.fromMap(Map<String, dynamic> m) => RefundItem(
        id: m['id'],
        refundId: m['refund_id'],
        productId: m['product_id'],
        name: m['name'],
        qty: m['qty'],
        unitPrice: (m['unit_price'] as num).toDouble(),
        lineTotal: (m['line_total'] as num).toDouble(),
      );
}

class Refund {
  Refund({
    this.id,
    required this.saleId,
    required this.saleReference,
    required this.createdAt,
    required this.amount,
    required this.reason,
    required this.method,
    required this.isVoid,
    required this.restocked,
    this.items = const [],
  });

  final int? id;
  final int saleId;
  final String saleReference;
  final String createdAt;
  final double amount;
  final String reason;
  final String method;
  final bool isVoid;
  final bool restocked;
  final List<RefundItem> items;

  DateTime get createdAtDate => DateTime.parse(createdAt);

  factory Refund.fromMap(Map<String, dynamic> m) => Refund(
        id: m['id'],
        saleId: m['sale_id'],
        saleReference: m['sale_reference'],
        createdAt: m['created_at'],
        amount: (m['amount'] as num).toDouble(),
        reason: m['reason'],
        method: m['method'],
        isVoid: (m['is_void'] as int) == 1,
        restocked: (m['restocked'] as int) == 1,
      );
}
