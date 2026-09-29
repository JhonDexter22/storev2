import 'package:flutter_test/flutter_test.dart';

import 'package:storev2/models/backup_status.dart';
import 'package:storev2/models/product_model.dart';
import 'package:storev2/models/store_alerts.dart';
import 'package:storev2/services/error_log.dart';

void main() {
  Product p(int stock, {int min = 5}) => Product(
        name: 'P$stock',
        stock: stock,
        minStock: min,
        category: 'Snacks',
        createdAt: '2026-09-01',
        price: 10,
      );

  final fresh = BackupStatus.from(DateTime.now());
  final never = BackupStatus.from(null);

  StoreAlerts alerts({
    List<Product>? products,
    ({int count, double amount}) overdue = (count: 0, amount: 0.0),
    BackupStatus? backup,
    bool remind = true,
    bool hasData = true,
    bool lowStockAlerts = true,
    int newErrors = 0,
  }) =>
      StoreAlerts.from(
        products: products ?? [p(40)],
        overdueUtang: overdue,
        backup: backup ?? fresh,
        remindBackup: remind,
        storeHasData: hasData,
        lowStockAlerts: lowStockAlerts,
        newErrors: newErrors,
      );

  test('a healthy store has nothing to say', () {
    final a = alerts();
    expect(a.isEmpty, isTrue);
    expect(a.hasUrgent, isFalse);
  });

  test('out of stock is urgent; running low is listed but is not', () {
    final a = alerts(products: [p(0), p(3), p(40)]);
    expect(a.items.map((i) => (i.kind, i.count, i.urgent)), [
      (AlertKind.outOfStock, 1, true),
      (AlertKind.lowStock, 1, false),
    ]);
  });

  test('switching off low-stock alerts drops running low, not out of stock', () {
    final a = alerts(products: [p(0), p(3)], lowStockAlerts: false);
    expect(a.items.map((i) => i.kind), [AlertKind.outOfStock]);
  });

  test('overdue utang carries its count and amount', () {
    final a = alerts(overdue: (count: 2, amount: 730.0));
    final item = a.items.single;
    expect(item.kind, AlertKind.overdueUtang);
    expect((item.count, item.amount), (2, 730.0));
    expect(a.hasUrgent, isTrue);
  });

  test('a backup is due only with reminders on and something to lose', () {
    expect(alerts(backup: never).items.single.kind, AlertKind.backupDue);
    expect(alerts(backup: never, remind: false).isEmpty, isTrue);
    expect(alerts(backup: never, hasData: false).isEmpty, isTrue);
    expect(alerts(backup: fresh).isEmpty, isTrue);
  });

  test('new errors are urgent', () {
    final a = alerts(newErrors: 3);
    expect(a.items.single.count, 3);
    expect(a.hasUrgent, isTrue);
  });

  group('errors since last looked at', () {
    final log = ErrorLog.instance;
    setUp(log.resetForTests);
    tearDown(log.resetForTests);

    test('all of them when the log was never opened', () {
      ErrorLog.caught('a', null, 'x');
      ErrorLog.caught('b', null, 'y');
      expect(log.newerThan(null), 2);
    });

    test('only those after it was opened — including one that happened again',
        () {
      final seen = DateTime(2026, 9, 28, 12);
      log.record(kind: 'caught', error: 'old', where: 'x', now: seen.subtract(const Duration(hours: 1)));
      log.record(kind: 'caught', error: 'repeats', where: 'y', now: seen.subtract(const Duration(hours: 2)));
      log.record(kind: 'caught', error: 'repeats', where: 'y', now: seen.add(const Duration(minutes: 5)));
      log.record(kind: 'caught', error: 'new', where: 'z', now: seen.add(const Duration(minutes: 9)));
      expect(log.newerThan(seen), 2);
    });
  });
}
