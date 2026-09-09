import 'package:flutter/material.dart';

/// How a payment type behaves at the till.
///
/// Only two of them need special handling; everything else is just a name
/// recorded against the sale, which is what makes adding your own cheap.
enum PaymentKind {
  /// Takes cash, works out change. There is always exactly one of these.
  cash,

  /// Puts the sale on a customer's tab instead of taking money now.
  utang,

  /// Money arrives some other way — GCash, a card, a bank transfer. The app
  /// records which, and has nothing further to do.
  plain,
}

/// A way a customer can pay.
class PaymentType {
  const PaymentType({
    required this.name,
    required this.kind,
    this.builtIn = true,
  });

  final String name;
  final PaymentKind kind;

  /// Built-in types can be switched off; ones the shopkeeper added can be
  /// deleted outright.
  final bool builtIn;

  /// Cash is not optional. A till that cannot take cash is not a till, and an
  /// off switch here would be a foot-gun rather than a setting.
  bool get canBeDisabled => kind != PaymentKind.cash;

  IconData get icon => switch (kind) {
        PaymentKind.cash => Icons.payments_outlined,
        PaymentKind.utang => Icons.account_balance_wallet_outlined,
        PaymentKind.plain => switch (name.toLowerCase()) {
            'gcash' => Icons.qr_code_2_rounded,
            'maya' => Icons.qr_code_2_rounded,
            'card' => Icons.credit_card_rounded,
            _ => Icons.swap_horiz_rounded,
          },
      };

  /// The types every install starts with — the four that were hardcoded at
  /// checkout before this was configurable.
  static const builtInTypes = [
    PaymentType(name: 'Cash', kind: PaymentKind.cash),
    PaymentType(name: 'GCash', kind: PaymentKind.plain),
    PaymentType(name: 'Card', kind: PaymentKind.plain),
    PaymentType(name: 'Utang', kind: PaymentKind.utang),
  ];

  @override
  bool operator ==(Object other) =>
      other is PaymentType && other.name == name && other.kind == kind;

  @override
  int get hashCode => Object.hash(name, kind);
}
