import 'backup_status.dart';
import 'product_model.dart';

/// Something on the bell's list.
enum AlertKind { outOfStock, lowStock, overdueUtang, backupDue, newErrors }

class StoreAlert {
  const StoreAlert(this.kind, {this.count = 0, this.amount = 0, this.urgent = true});

  final AlertKind kind;

  /// Products, customers or errors, depending on [kind].
  final int count;

  /// Money owed, for overdue utang.
  final double amount;

  /// Whether it lights the bell's dot. Everything listed is worth a look, but
  /// only these need acting on: a dot that is always on stops meaning anything.
  final bool urgent;
}

/// What the bell on Home knows about.
///
/// The bell was a picture with a red dot painted on permanently — telling the
/// shopkeeper something needed them when nothing did. These are the things
/// that actually can.
class StoreAlerts {
  const StoreAlerts(this.items);

  final List<StoreAlert> items;

  bool get isEmpty => items.isEmpty;

  /// Whether the dot shows.
  bool get hasUrgent => items.any((a) => a.urgent);

  static StoreAlerts from({
    required List<Product> products,
    required ({int count, double amount}) overdueUtang,
    required BackupStatus backup,
    required bool remindBackup,
    required bool storeHasData,
    required bool lowStockAlerts,
    required int newErrors,
  }) {
    final out = products.where((p) => p.stock <= 0).length;
    final low = products.where((p) => p.stock > 0 && p.stock <= p.minStock).length;
    return StoreAlerts([
      if (out > 0) StoreAlert(AlertKind.outOfStock, count: out),
      // Listed, but not urgent: a store nearly always has something running
      // low, and Restock already carries that count on its tab.
      if (lowStockAlerts && low > 0)
        StoreAlert(AlertKind.lowStock, count: low, urgent: false),
      if (overdueUtang.count > 0)
        StoreAlert(AlertKind.overdueUtang,
            count: overdueUtang.count, amount: overdueUtang.amount),
      // Only when reminders are on and there is something to lose — the same
      // rule as the backup card on Home.
      if (remindBackup && storeHasData && backup.level != BackupLevel.fresh)
        const StoreAlert(AlertKind.backupDue),
      if (newErrors > 0) StoreAlert(AlertKind.newErrors, count: newErrors),
    ]);
  }
}
