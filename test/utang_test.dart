import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/models/customer.dart';
import 'package:storev2/services/utang_service.dart';

void main() {
  final service = UtangService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Each suite gets its own in-memory store; sharing one file makes
    // suites clobber each other when they run in parallel.
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('utang_entries');
    await db.delete('customers');
  });

  /// Writes an entry at a specific time — the service always stamps "now", and
  /// the ageing rules need backdated history to be testable.
  Future<void> entryAt(int customerId, double amount, String kind, DateTime at) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert('utang_entries', {
      'customer_id': customerId,
      'created_at': at.toIso8601String(),
      'amount': amount,
      'kind': kind,
    });
  }

  test('balance is charges minus payments', () async {
    final id = await service.addCustomer('Aling Nena');
    await service.charge(customerId: id, amount: 120);
    await service.charge(customerId: id, amount: 80);
    await service.recordPayment(customerId: id, amount: 50, method: 'Cash');

    final c = await service.getCustomer(id);
    expect(c!.balance, closeTo(150, 0.001));
  });

  test('a fully settled customer has no balance and no age', () async {
    final id = await service.addCustomer('Mang Tonyo');
    await entryAt(id, 200, 'charge', DateTime.now().subtract(const Duration(days: 90)));
    await service.recordPayment(customerId: id, amount: 200, method: 'Cash');

    final c = await service.getCustomer(id);
    expect(c!.balance, 0);
    expect(c.ageInDays, 0);
    expect(c.status, UtangStatus.current);
  });

  test('ageing restarts after a customer settles', () async {
    final id = await service.addCustomer('Regular payer');
    // An old debt, fully paid off...
    await entryAt(id, 300, 'charge', DateTime.now().subtract(const Duration(days: 120)));
    await entryAt(id, -300, 'payment', DateTime.now().subtract(const Duration(days: 110)));
    // ...then a fresh charge from two days ago.
    await entryAt(id, 40, 'charge', DateTime.now().subtract(const Duration(days: 2)));

    final c = await service.getCustomer(id);
    expect(c!.balance, closeTo(40, 0.001));
    // Ageing from the first-ever charge would call this 120 days overdue.
    expect(c.ageInDays, lessThanOrEqualTo(3));
    expect(c.status, UtangStatus.current);
  });

  test('an old unsettled balance reads as overdue', () async {
    final id = await service.addCustomer('Slow payer');
    await entryAt(id, 250, 'charge', DateTime.now().subtract(const Duration(days: 45)));

    final c = await service.getCustomer(id);
    expect(c!.status, UtangStatus.overdue);
    expect(c.ageInDays, greaterThanOrEqualTo(Customer.overdueAfterDays));
  });

  test('the ledger sorts by age of debt, not alphabetically', () async {
    final anna = await service.addCustomer('Anna');
    final zeno = await service.addCustomer('Zeno');
    await entryAt(anna, 50, 'charge', DateTime.now().subtract(const Duration(days: 1)));
    await entryAt(zeno, 50, 'charge', DateTime.now().subtract(const Duration(days: 60)));

    final list = await service.getCustomers();
    expect(list.first.name, 'Zeno', reason: 'the oldest debt should be read first');
  });

  test('settled customers sink below anyone still owing', () async {
    final owing = await service.addCustomer('Owes money');
    final settled = await service.addCustomer('All square');
    await entryAt(owing, 20, 'charge', DateTime.now());
    await entryAt(settled, 500, 'charge', DateTime.now().subtract(const Duration(days: 200)));
    await entryAt(settled, -500, 'payment', DateTime.now().subtract(const Duration(days: 199)));

    final list = await service.getCustomers();
    expect(list.first.name, 'Owes money');
    expect(list.last.name, 'All square');
  });

  test('period flows report charged and collected separately', () async {
    final id = await service.addCustomer('Flow test');
    await service.charge(customerId: id, amount: 300);
    await service.recordPayment(customerId: id, amount: 100, method: 'Cash');

    final flows = await service.getFlows(1);
    expect(flows.charged, closeTo(300, 0.001));
    expect(flows.collected, closeTo(100, 0.001));
    expect(flows.net, closeTo(200, 0.001), reason: 'the book grew by 200');
    expect(flows.outstanding, closeTo(200, 0.001));
    expect(flows.customerCount, 1);
  });

  test('flows exclude entries outside the range', () async {
    final id = await service.addCustomer('Old activity');
    await entryAt(id, 900, 'charge', DateTime.now().subtract(const Duration(days: 10)));

    final today = await service.getFlows(1);
    expect(today.charged, 0, reason: 'a 10-day-old charge is not in today');
    // Outstanding is a running balance, not a period figure, so it still counts.
    expect(today.outstanding, closeTo(900, 0.001));
  });
}
