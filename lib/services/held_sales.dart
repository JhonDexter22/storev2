import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A sale put aside at the counter — the customer went to fetch money, and
/// the next one is waiting. Lines are kept by product id so a later price
/// change on the product is picked up on resume, the way it would be if the
/// items were re-rung.
class HeldSale {
  const HeldSale({required this.id, required this.heldAt, required this.lines, this.label = ''});

  final String id;
  final DateTime heldAt;

  /// productId → qty.
  final Map<int, int> lines;

  /// First product or two, captured at hold time so the list can describe
  /// the sale without a product lookup.
  final String label;

  int get itemCount => lines.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'id': id,
        'heldAt': heldAt.toIso8601String(),
        'label': label,
        'lines': {for (final e in lines.entries) '${e.key}': e.value},
      };

  static HeldSale fromJson(Map<String, dynamic> m) => HeldSale(
        id: m['id'] as String,
        heldAt: DateTime.parse(m['heldAt'] as String),
        label: m['label'] as String? ?? '',
        lines: {
          for (final e in (m['lines'] as Map<String, dynamic>).entries)
            int.parse(e.key): (e.value as num).toInt(),
        },
      );
}

/// Held sales outlive the POS screen (which is rebuilt on every tab change)
/// and the app itself, so they live here and in preferences rather than in
/// screen state.
class HeldSales extends ChangeNotifier {
  HeldSales._();

  static final HeldSales instance = HeldSales._();

  static const _key = 'held_sales';

  List<HeldSale> _sales = const [];
  bool _loaded = false;

  List<HeldSale> get sales => _sales;
  int get count => _sales.length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _sales = [for (final m in list) HeldSale.fromJson(m as Map<String, dynamic>)];
      notifyListeners();
    } catch (_) {
      // A corrupt entry is not worth failing the till over; start empty.
      _sales = const [];
    }
  }

  Future<void> hold(Map<int, int> lines, {String label = ''}) async {
    if (lines.isEmpty) return;
    final sale = HeldSale(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      heldAt: DateTime.now(),
      lines: Map.of(lines),
      label: label,
    );
    _sales = [sale, ..._sales];
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _sales = [for (final s in _sales) if (s.id != id) s];
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode([for (final s in _sales) s.toJson()]));
    } catch (_) {
      // Held sales still work for this session; only the restart copy is lost.
    }
  }

  /// Test hook.
  @visibleForTesting
  void reset() {
    _sales = const [];
    _loaded = false;
  }
}
