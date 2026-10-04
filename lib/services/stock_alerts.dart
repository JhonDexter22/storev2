import 'package:flutter/foundation.dart';

import '../models/product_model.dart';
import 'product_service.dart';
import 'error_log.dart';

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
    } catch (e, st) {
      // A badge is decoration; a failed count must never surface as an error
      // on screen — but a database that cannot count is worth knowing about.
      ErrorLog.caught(e, st, 'stock badges');
    }
  }
}

/// Stock against the healthy level (twice the minimum), 0..1.
double restockFill(Product p) {
  final healthy = p.minStock * 2;
  if (healthy <= 0) return 1;
  return (p.stock / healthy).clamp(0.0, 1.0);
}

/// Most urgent first — the order Restock lists in, and Home's "Needs
/// attention" with it, so the two never disagree about what comes first.
/// Everything out is at zero, so there the higher minimum — the faster
/// seller — leads. Running low is ordered by how near empty it is.
int byRestockUrgency(Product a, Product b) {
  final int order;
  if (a.stock <= 0 && b.stock <= 0) {
    order = b.minStock.compareTo(a.minStock);
  } else {
    order = restockFill(a).compareTo(restockFill(b));
  }
  return order != 0 ? order : a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// How many to order: enough to land at twice the minimum, and never less
/// than the minimum itself — one order that keeps the product off Restock
/// for a while. Restock, Home and Products all offer this same figure.
int suggestedRestock(Product p) {
  final s = p.minStock * 2 - p.stock;
  return s < p.minStock ? p.minStock : s;
}
