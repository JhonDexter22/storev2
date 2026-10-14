import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product_model.dart';
import 'error_log.dart';

/// The sale being rung up right now. The POS screen is rebuilt on every tab
/// change, and Android may close the app while it sits in the background, so
/// the cart lives here and in preferences rather than in screen state. In
/// screen state a trip to Products, or a phone call, emptied it.
class OpenSale {
  OpenSale._();

  static final OpenSale instance = OpenSale._();

  static const _key = 'open_sale';

  /// productId → qty. A negative id is a quick item, described in [quick].
  final Map<int, int> lines = {};

  /// Quick items in the cart, by their negative id. Kept after a line is
  /// removed (Undo can bring it back) and dropped once the sale is done.
  final Map<int, Product> quick = {};

  int _nextQuickId = -1;

  /// A fresh id for a quick item, distinct within this sale.
  int takeQuickId() => _nextQuickId--;

  bool _loaded = false;

  /// Nothing is written until the saved sale has been read back, or an empty
  /// till on startup would overwrite it.
  bool _ready = false;

  /// What was last written, so an unchanged cart is not written again.
  String? _saved;

  /// Reads back a sale left open when the app was closed. Once per run: after
  /// that, [lines] is the truth.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      _saved = raw;
      // Anything rung up while this was loading is newer; keep it.
      if (raw != null && lines.isEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final q = (m['quick'] as Map<String, dynamic>?) ?? const {};
        for (final e in (m['lines'] as Map<String, dynamic>).entries) {
          final id = int.parse(e.key);
          final qty = (e.value as num).toInt();
          if (Product.isQuickId(id)) {
            final item = q[e.key] as Map<String, dynamic>?;
            if (item == null) continue;
            quick[id] = Product.quick(
              id: id,
              name: item['name'] as String,
              price: (item['price'] as num).toDouble(),
            );
          }
          lines[id] = qty;
        }
        _nextQuickId = quick.keys.fold(0, math.min) - 1;
      }
    } catch (e, st) {
      // A corrupt entry is not worth failing the till over; start empty.
      ErrorLog.caught(e, st, 'open sale: loading');
      lines.clear();
      quick.clear();
    }
    _ready = true;
  }

  /// Writes the sale out if it changed since the last write. Cheap enough to
  /// call after every redraw of the till.
  void save() {
    if (!_ready) return;
    final raw = lines.isEmpty
        ? null
        : jsonEncode({
            'lines': {for (final e in lines.entries) '${e.key}': e.value},
            'quick': {
              for (final e in quick.entries)
                if (lines.containsKey(e.key)) '${e.key}': {'name': e.value.name, 'price': e.value.price},
            },
          });
    if (raw == _saved) return;
    _saved = raw;
    unawaited(_write(raw));
  }

  /// Drops the sale. For when the store's data is replaced: its product ids
  /// may now belong to other products, or to none.
  Future<void> clear() async {
    lines.clear();
    quick.clear();
    _nextQuickId = -1;
    // Nothing left to read back, even if the till has not opened yet.
    _loaded = true;
    _ready = true;
    _saved = null;
    await _write(null);
  }

  Future<void> _write(String? raw) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (raw == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, raw);
      }
    } catch (e, st) {
      // The sale still works for this session; only the restart copy is lost.
      ErrorLog.caught(e, st, 'open sale: saving');
    }
  }

  /// Test hook: as on a fresh start.
  @visibleForTesting
  void reset() {
    lines.clear();
    quick.clear();
    _nextQuickId = -1;
    _loaded = false;
    _ready = false;
    _saved = null;
  }
}
