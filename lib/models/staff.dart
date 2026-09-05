/// Someone who can be signed in to the till.
///
/// Deliberately has no PIN field. The PIN lives as a salted hash in the
/// `staff` table and never leaves [StaffService] — a model that carried it
/// would put it back into every widget that renders a name.
class Staff {
  const Staff({
    this.id,
    required this.name,
    required this.role,
    this.isManager = false,
    this.active = true,
  });

  final int? id;
  final String name;
  final String role;

  /// Managers may authorise a shift close.
  final bool isManager;

  /// Former staff are kept rather than deleted, so past shifts and sales still
  /// name a real person.
  final bool active;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    // A single-word name has one initial — "MA" for May reads as a truncation,
    // not an initial.
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory Staff.fromMap(Map<String, dynamic> map) => Staff(
        id: map['id'] as int?,
        name: map['name'] as String,
        role: map['role'] as String,
        isManager: (map['is_manager'] as int? ?? 0) == 1,
        active: (map['active'] as int? ?? 1) == 1,
      );
}
