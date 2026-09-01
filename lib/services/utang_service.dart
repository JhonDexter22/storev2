import '../database/database_helper.dart';
import '../models/customer.dart';

/// Charged vs collected over a period, for the Utang block in Reports.
class UtangFlows {
  const UtangFlows({
    required this.charged,
    required this.collected,
    required this.outstanding,
    required this.overdue,
    required this.customerCount,
  });

  final double charged;
  final double collected;
  final double outstanding;
  final double overdue;
  final int customerCount;

  /// Positive when the book grew over the period.
  double get net => charged - collected;
}

class UtangService {
  final dbHelper = DatabaseHelper.instance;

  Future<int> addCustomer(String name) async {
    final db = await dbHelper.database;
    return db.insert('customers', {
      'name': name.trim(),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Every customer with their balance, the age of the currently-outstanding
  /// balance, and their last activity. Sorted by age of debt — the overdue
  /// balance should be the first thing read, not the alphabetically first name.
  Future<List<Customer>> getCustomers() async {
    final db = await dbHelper.database;
    final rows = await db.query('customers', orderBy: 'name ASC');
    final entries = await db.query('utang_entries', orderBy: 'created_at ASC');

    final byCustomer = <int, List<UtangEntry>>{};
    for (final r in entries) {
      final e = UtangEntry.fromMap(r);
      byCustomer.putIfAbsent(e.customerId, () => []).add(e);
    }

    final result = <Customer>[];
    for (final r in rows) {
      final base = Customer.fromMap(r);
      final list = byCustomer[base.id] ?? const <UtangEntry>[];
      result.add(_withLedger(base, list));
    }

    result.sort((a, b) {
      // Settled customers sink below anyone who owes.
      if ((a.balance > 0) != (b.balance > 0)) return a.balance > 0 ? -1 : 1;
      final byAge = b.ageInDays.compareTo(a.ageInDays);
      if (byAge != 0) return byAge;
      return b.balance.compareTo(a.balance);
    });
    return result;
  }

  Future<Customer?> getCustomer(int id) async {
    final db = await dbHelper.database;
    final rows = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final entries = await db.query('utang_entries',
        where: 'customer_id = ?', whereArgs: [id], orderBy: 'created_at ASC');
    return _withLedger(
      Customer.fromMap(rows.first),
      entries.map((e) => UtangEntry.fromMap(e)).toList(),
    );
  }

  /// Walks the ledger to find the balance and, crucially, when the *current*
  /// balance started: the first charge after the last time the running total
  /// reached zero. Ageing from the first-ever charge would mark a customer who
  /// pays regularly as permanently overdue.
  Customer _withLedger(Customer base, List<UtangEntry> entries) {
    double running = 0;
    DateTime? oldest;
    for (final e in entries) {
      final was = running;
      running += e.amount;
      if (was <= 0.005 && running > 0.005) {
        oldest = e.createdAtDate;
      }
      if (running <= 0.005) oldest = null;
    }

    final last = entries.isEmpty ? null : entries.last;

    return base.copyWith(
      balance: running < 0.005 ? 0 : running,
      oldestChargeAt: oldest,
      lastActivityAt: last?.createdAtDate,
      lastActivityAmount: last?.amount.abs(),
      lastActivityIsCharge: last?.isCharge ?? false,
    );
  }

  Future<List<UtangEntry>> getEntries(int customerId) async {
    final db = await dbHelper.database;
    final rows = await db.query('utang_entries',
        where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'id DESC');
    return rows.map((m) => UtangEntry.fromMap(m)).toList();
  }

  Future<void> charge({
    required int customerId,
    required double amount,
    int? saleId,
    String? note,
  }) async {
    final db = await dbHelper.database;
    await db.insert('utang_entries', {
      'customer_id': customerId,
      'sale_id': saleId,
      'created_at': DateTime.now().toIso8601String(),
      'amount': amount,
      'kind': 'charge',
      'note': note,
    });
  }

  Future<void> recordPayment({
    required int customerId,
    required double amount,
    required String method,
  }) async {
    final db = await dbHelper.database;
    await db.insert('utang_entries', {
      'customer_id': customerId,
      'created_at': DateTime.now().toIso8601String(),
      // Payments are stored negative so a balance is just the sum.
      'amount': -amount,
      'kind': 'payment',
      'method': method,
    });
  }

  /// Period-scoped flows plus the running book totals.
  Future<UtangFlows> getFlows(int days) async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1))
        .toIso8601String();

    final charged = await db.rawQuery(
      "SELECT COALESCE(SUM(amount),0) AS v FROM utang_entries "
      "WHERE kind = 'charge' AND created_at >= ?",
      [start],
    );
    final collected = await db.rawQuery(
      "SELECT COALESCE(SUM(-amount),0) AS v FROM utang_entries "
      "WHERE kind = 'payment' AND created_at >= ?",
      [start],
    );

    final customers = await getCustomers();
    final owing = customers.where((c) => c.balance > 0).toList();

    return UtangFlows(
      charged: (charged.first['v'] as num).toDouble(),
      collected: (collected.first['v'] as num).toDouble(),
      outstanding: owing.fold(0, (s, c) => s + c.balance),
      overdue: owing
          .where((c) => c.status == UtangStatus.overdue)
          .fold(0, (s, c) => s + c.balance),
      customerCount: owing.length,
    );
  }

  /// The largest balances, for the Reports block.
  Future<List<Customer>> topBalances({int limit = 3}) async {
    final customers = await getCustomers();
    final owing = customers.where((c) => c.balance > 0).toList()
      ..sort((a, b) => b.balance.compareTo(a.balance));
    return owing.take(limit).toList();
  }
}
