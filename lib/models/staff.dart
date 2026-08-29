/// Someone who can be signed in to the till.
///
/// The roster and PINs are hardcoded for now — the handoff calls this a
/// prototype stand-in and says to replace it with real auth before shipping.
class Staff {
  const Staff({
    required this.name,
    required this.role,
    required this.pin,
    this.isManager = false,
  });

  final String name;
  final String role;
  final String pin;

  /// Managers may authorise a shift close.
  final bool isManager;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    // A single-word name has one initial — "MA" for May reads as a truncation,
    // not an initial.
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static const roster = [
    Staff(name: 'May', role: 'Cashier', pin: '1111'),
    Staff(name: 'Ronel', role: 'Cashier', pin: '2222'),
    Staff(name: 'Nena', role: 'Manager', pin: '2468', isManager: true),
  ];

  static Staff? byName(String name) {
    for (final s in roster) {
      if (s.name == name) return s;
    }
    return null;
  }
}
