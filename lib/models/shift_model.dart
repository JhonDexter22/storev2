class Shift {
  Shift({
    this.id,
    required this.closedAt,
    required this.cashier,
    required this.terminal,
    required this.openingFloat,
    required this.cashSales,
    required this.expected,
    required this.counted,
    required this.variance,
    required this.denominations,
    this.openedAt = '',
    this.totalSales = 0,
    this.saleCount = 0,
  });

  final int? id;
  final String closedAt;
  final String openedAt;

  /// Sales across every payment method, not just the cash in the drawer.
  final double totalSales;
  final int saleCount;
  final String cashier;
  final String terminal;
  final double openingFloat;
  final double cashSales;
  final double expected;
  final double counted;

  /// counted - expected. Negative is short, positive is over.
  final double variance;

  /// Denomination value -> count, stored so the drawer can be reproduced
  /// exactly rather than derived back from the total.
  final Map<int, int> denominations;

  DateTime get closedAtDate => DateTime.parse(closedAt);
  DateTime? get openedAtDate =>
      openedAt.isEmpty ? null : DateTime.tryParse(openedAt);

  String get denominationsJson =>
      denominations.entries.map((e) => '${e.key}:${e.value}').join(',');

  static Map<int, int> parseDenominations(String raw) {
    final map = <int, int>{};
    if (raw.trim().isEmpty) return map;
    for (final pair in raw.split(',')) {
      final parts = pair.split(':');
      if (parts.length != 2) continue;
      final k = int.tryParse(parts[0]);
      final v = int.tryParse(parts[1]);
      if (k != null && v != null) map[k] = v;
    }
    return map;
  }

  factory Shift.fromMap(Map<String, dynamic> m) => Shift(
        id: m['id'],
        closedAt: m['closed_at'],
        cashier: m['cashier'],
        terminal: m['terminal'],
        openingFloat: (m['opening_float'] as num).toDouble(),
        cashSales: (m['cash_sales'] as num).toDouble(),
        expected: (m['expected'] as num).toDouble(),
        counted: (m['counted'] as num).toDouble(),
        variance: (m['variance'] as num).toDouble(),
        denominations: parseDenominations(m['denominations'] as String? ?? ''),
        openedAt: m['opened_at'] as String? ?? '',
        totalSales: (m['total_sales'] as num?)?.toDouble() ?? 0,
        saleCount: (m['sale_count'] as num?)?.toInt() ?? 0,
      );
}
