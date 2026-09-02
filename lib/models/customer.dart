/// How overdue a balance is. Thresholds are in days since the oldest
/// unsettled charge.
enum UtangStatus { current, dueSoon, overdue }

class Customer {
  const Customer({
    this.id,
    required this.name,
    required this.createdAt,
    this.balance = 0,
    this.oldestChargeAt,
    this.lastActivityAt,
    this.lastActivityAmount,
    this.lastActivityIsCharge = false,
  });

  final int? id;
  final String name;
  final String createdAt;

  /// Charges minus payments. Zero means settled.
  final double balance;

  /// When the currently-outstanding balance started — i.e. the first charge
  /// after the last time this customer was settled. Null when settled.
  final DateTime? oldestChargeAt;

  final DateTime? lastActivityAt;

  /// Amount of the most recent ledger entry, unsigned. The label is built in
  /// the UI so money formatting stays in one place.
  final double? lastActivityAmount;
  final bool lastActivityIsCharge;

  static const dueSoonAfterDays = 15;
  static const overdueAfterDays = 30;

  /// Credit ceiling. Crossing it warns but never blocks — the shopkeeper
  /// decides, not the app.
  static const creditCeiling = 500.0;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  int get ageInDays {
    final since = oldestChargeAt;
    if (since == null || balance <= 0) return 0;
    return DateTime.now().difference(since).inDays;
  }

  UtangStatus get status {
    if (balance <= 0) return UtangStatus.current;
    final age = ageInDays;
    if (age >= overdueAfterDays) return UtangStatus.overdue;
    if (age >= dueSoonAfterDays) return UtangStatus.dueSoon;
    return UtangStatus.current;
  }

  String get ageLabel {
    if (balance <= 0) return 'Settled';
    final age = ageInDays;
    if (age <= 0) return 'Since today';
    if (age == 1) return '1 day old';
    return '$age days old';
  }

  Customer copyWith({
    double? balance,
    DateTime? oldestChargeAt,
    DateTime? lastActivityAt,
    double? lastActivityAmount,
    bool? lastActivityIsCharge,
  }) =>
      Customer(
        id: id,
        name: name,
        createdAt: createdAt,
        balance: balance ?? this.balance,
        oldestChargeAt: oldestChargeAt ?? this.oldestChargeAt,
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
        lastActivityAmount: lastActivityAmount ?? this.lastActivityAmount,
        lastActivityIsCharge: lastActivityIsCharge ?? this.lastActivityIsCharge,
      );

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        id: m['id'],
        name: m['name'],
        createdAt: m['created_at'],
      );
}

class UtangEntry {
  const UtangEntry({
    this.id,
    required this.customerId,
    this.saleId,
    required this.createdAt,
    required this.amount,
    required this.kind,
    this.method,
    this.note,
  });

  final int? id;
  final int customerId;
  final int? saleId;
  final String createdAt;

  /// Positive for a charge, negative for a payment.
  final double amount;

  /// 'charge' or 'payment'.
  final String kind;
  final String? method;
  final String? note;

  bool get isCharge => kind == 'charge';
  DateTime get createdAtDate => DateTime.parse(createdAt);

  factory UtangEntry.fromMap(Map<String, dynamic> m) => UtangEntry(
        id: m['id'],
        customerId: m['customer_id'],
        saleId: m['sale_id'],
        createdAt: m['created_at'],
        amount: (m['amount'] as num).toDouble(),
        kind: m['kind'],
        method: m['method'],
        note: m['note'],
      );
}
