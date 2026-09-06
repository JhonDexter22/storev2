/// How a discount is expressed at the till.
enum DiscountKind { percent, amount }

/// Money taken off a sale, with the reason it was given.
///
/// The reason is not decoration. A discount is the easiest way for cash to
/// leave a till without a sale explaining it, so every one is recorded with
/// who gave it and why, and reports show the total separately from revenue.
class Discount {
  const Discount({
    required this.kind,
    required this.value,
    required this.reason,
  });

  /// Percent (0–100) or a peso amount, depending on [kind].
  final double value;
  final DiscountKind kind;
  final String reason;

  static const none = Discount(kind: DiscountKind.amount, value: 0, reason: '');

  /// The reasons a sari-sari store actually uses.
  ///
  /// Senior citizen and PWD are 20% because Philippine law sets that rate, so
  /// they are presets rather than something a cashier types each time and
  /// occasionally gets wrong.
  static const presets = [
    (label: 'Senior citizen', kind: DiscountKind.percent, value: 20.0),
    (label: 'PWD', kind: DiscountKind.percent, value: 20.0),
    (label: 'Suki', kind: DiscountKind.percent, value: 5.0),
  ];

  bool get isZero => value <= 0;

  /// The peso amount this takes off [subtotal], rounded to centavos.
  ///
  /// Clamped at the subtotal: a discount can bring a sale to zero but never
  /// below it, or the till would owe the customer money for buying something.
  double amountOn(double subtotal) {
    if (subtotal <= 0 || value <= 0) return 0;
    final raw = kind == DiscountKind.percent ? subtotal * value / 100 : value;
    final capped = raw > subtotal ? subtotal : raw;
    return (capped * 100).roundToDouble() / 100;
  }

  /// What to show on the checkout row: "Senior citizen · 20%".
  String label(double subtotal) {
    if (isZero) return '';
    final how = kind == DiscountKind.percent
        ? '${value % 1 == 0 ? value.toStringAsFixed(0) : value}%'
        : 'fixed';
    return reason.isEmpty ? how : '$reason · $how';
  }
}
