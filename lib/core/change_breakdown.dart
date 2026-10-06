/// One kind of bill or coin in a handful of change, and how many of it.
class ChangePiece {
  const ChangePiece(this.centavos, this.count);

  final int centavos;
  final int count;

  double get value => centavos / 100;

  /// ₱20 circulates as both a bill and a coin; it is counted with the bills,
  /// which is what most drawers still hold.
  bool get isBill => centavos >= 2000;
}

/// Philippine money in circulation, largest first, in centavos. No ₱2 (gone
/// since the 1990s) and no 10¢ (the 2017 series dropped it).
const _denominations = [
  100000, 50000, 20000, 10000, 5000, 2000, // bills (and the ₱20 coin)
  1000, 500, 100, // coins
  25, 5, 1, // centavo coins
];

/// The fewest bills and coins that make [change]: ₱67 → ₱50, ₱10, ₱5, ₱1 ×2.
///
/// A hint for the cashier, not an instruction — a drawer out of ₱5 coins
/// just hands five ₱1s. Empty for nothing owed.
List<ChangePiece> changeBreakdown(double change) {
  var left = (change * 100).round();
  final out = <ChangePiece>[];
  for (final d in _denominations) {
    if (left < d) continue;
    out.add(ChangePiece(d, left ~/ d));
    left %= d;
  }
  return out;
}
