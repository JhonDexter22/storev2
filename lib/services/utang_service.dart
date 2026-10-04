import '../database/database_helper.dart';
import 'settings_service.dart';
import '../models/customer.dart';

/// Charged vs collected over a period, for the Utang block in Reports.
class UtangFlows {
  const UtangFlows({
    required this.charged,
    required this.collected,
    required this.outstanding,
    required this.overdue,
    required this.customerCount,
    this.returned = 0,
  });

  final double charged;
  final double collected;
  final double outstanding;
  final double overdue;
  final int customerCount;

  /// Goods from tab sales brought back: off the book, though not collected.
  final double returned;

  /// Positive when the book grew over the period. Returns count against it:
  /// without them a sale charged and returned the same day read as the book
  /// growing by its amount, while the balance had not moved.
  double get net => charged - collected - returned;
}

class UtangService {
  final dbHelper = DatabaseHelper.instance;

  Future<int> addCustomer(String name, {String? phone, double? creditLimit}) async {
    final db = await dbHelper.database;
    return db.insert('customers', {
      'name': name.trim(),
      'created_at': DateTime.now().toIso8601String(),
      'phone': _cleanPhone(phone),
      'credit_limit': creditLimit,
    });
  }

  /// [creditLimit] null puts the customer back on the store's default.
  Future<void> updateCustomer(int id, {required String name, String? phone, double? creditLimit}) async {
    final db = await dbHelper.database;
    await db.update(
      'customers',
      {'name': name.trim(), 'phone': _cleanPhone(phone), 'credit_limit': creditLimit},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Digits and a leading plus only; empty becomes null so "no number"
  /// has one spelling.
  static String? _cleanPhone(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<void> markReminded(int id) async {
    final db = await dbHelper.database;
    await db.update(
      'customers',
      {'last_reminded_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Payments taken today, across every customer — the figure that answers
  /// "did the reminders work?".
  Future<({double amount, int count})> collectedToday() async {
    final db = await dbHelper.database;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).toIso8601String();
    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM(-amount),0) AS v, COUNT(*) AS n FROM utang_entries "
      "WHERE kind = 'payment' AND created_at >= ?",
      [start],
    );
    return (
      amount: (rows.first['v'] as num).toDouble(),
      count: (rows.first['n'] as num).toInt(),
    );
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
      lastActivityIsReturn: last?.isReturn ?? false,
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

  /// Utang paid back in cash from [since] on — money that lands in the
  /// drawer without being a sale.
  Future<double> cashCollectedSince(DateTime since) async {
    final db = await dbHelper.database;
    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM(-amount),0) AS v FROM utang_entries "
      "WHERE kind = 'payment' AND method = 'Cash' AND created_at >= ?",
      [since.toIso8601String()],
    );
    return (rows.first['v'] as num).toDouble();
  }

  /// Returns the entry's id, so the screen can offer Undo.
  Future<int> recordPayment({
    required int customerId,
    required double amount,
    required String method,
  }) async {
    final db = await dbHelper.database;
    return db.insert('utang_entries', {
      'customer_id': customerId,
      'created_at': DateTime.now().toIso8601String(),
      // Payments are stored negative so a balance is just the sum.
      'amount': -amount,
      'kind': 'payment',
      'method': method,
    });
  }

  /// Takes back a payment recorded by mistake. Payments only: a charge
  /// belongs to a sale, and is undone by returning the sale.
  Future<void> deletePayment(int entryId) async {
    final db = await dbHelper.database;
    await db.delete('utang_entries', where: "id = ? AND kind = 'payment'", whereArgs: [entryId]);
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
    final returned = await db.rawQuery(
      "SELECT COALESCE(SUM(-amount),0) AS v FROM utang_entries "
      "WHERE kind = 'return' AND created_at >= ?",
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
      returned: (returned.first['v'] as num).toDouble(),
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

/// The limit that applies to [c]: their own, or the store's default. Zero
/// means none. Crossing it warns but never blocks — the shopkeeper decides,
/// not the app.
///
/// Was one fixed ₱500 for everyone, in the code: a regular who always
/// carries ₱1,500 showed "Over limit" on every sale, until the warning meant
/// nothing.
double creditLimitFor(Customer c) => c.creditLimit ?? SettingsService.instance.creditLimit;

bool isOverLimit(Customer c, {double balance = -1}) {
  final limit = creditLimitFor(c);
  return limit > 0 && (balance < 0 ? c.balance : balance) > limit + 0.005;
}
