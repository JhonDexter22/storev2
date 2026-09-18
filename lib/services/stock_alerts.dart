import 'package:flutter/foundation.dart';

import 'product_service.dart';

/// Counts that the navigation chrome shows as badges.
///
/// [ProductService] is a plain query layer with no change notification, so
/// rather than thread callbacks through every screen that touches stock, the
/// shell calls [refresh] at the moments a count could have gone stale: on
/// boot, on every tab change, and when the app comes back to the foreground.
/// One indexed query each time; cheap enough to run on every tap.
class StockAlerts {
  StockAlerts._();

  static final StockAlerts instance = StockAlerts._();

  /// Products at or under their minimum, including the ones at zero.
  final ValueNotifier<int> needsRestock = ValueNotifier<int>(0);

  /// Products with nothing on the shelf.
  final ValueNotifier<int> outOfStock = ValueNotifier<int>(0);

  ProductService _service = ProductService();

  /// Test hook.
  @visibleForTesting
  set service(ProductService s) => _service = s;

  Future<void> refresh() async {
    try {
      final low = await _service.getLowStockProducts();
      needsRestock.value = low.length;
      outOfStock.value = low.where((p) => p.stock <= 0).length;
    } catch (_) {
      // A badge is decoration; a failed count must never surface as an error.
    }
  }
}
