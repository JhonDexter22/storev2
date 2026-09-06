import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/staff.dart';
import 'pin_hasher.dart';

/// The outcome of a PIN check.
sealed class PinResult {
  const PinResult();
}

/// Correct PIN. [staff] is who was let in.
class PinAccepted extends PinResult {
  const PinAccepted(this.staff);
  final Staff staff;
}

/// Wrong PIN. [attemptsRemaining] is how many are left before a lockout.
class PinRejected extends PinResult {
  const PinRejected(this.attemptsRemaining);
  final int attemptsRemaining;
}

/// Too many wrong PINs. Nothing is checked until [remaining] has passed, so a
/// guess made during the lockout does not even get compared.
class PinLockedOut extends PinResult {
  const PinLockedOut(this.remaining);
  final Duration remaining;
}

/// Raised when a new PIN or name is not usable. The message is written to be
/// shown to the person typing.
class StaffValidationException implements Exception {
  const StaffValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Staff records and the PIN gate in front of them.
///
/// The only place a PIN is compared. Callers get a [PinResult] and never see a
/// hash, a salt, or the stored value.
class StaffService {
  StaffService({DatabaseHelper? dbHelper})
      : dbHelper = dbHelper ?? DatabaseHelper.instance;

  final DatabaseHelper dbHelper;

  /// Wrong PINs tolerated before the account is frozen for [lockoutDuration].
  /// Five is enough for a fat-fingered cashier and few enough that guessing
  /// ten thousand codes at the counter is not a plan.
  static const maxAttempts = 5;
  static const lockoutDuration = Duration(minutes: 1);

  /// The codes an install starts with. These are in the source, so they are
  /// public: they exist so a new till is usable on the first day, and the
  /// store is told to change them. Everything after the first launch is a
  /// hash in the database.
  static const seedRoster = [
    (name: 'May', role: 'Cashier', pin: '1111', isManager: false),
    (name: 'Ronel', role: 'Cashier', pin: '2222', isManager: false),
    (name: 'Nena', role: 'Manager', pin: '2468', isManager: true),
  ];

  /// Puts the starting roster in place the first time the table is read.
  ///
  /// This also covers the upgrade from v6, where the roster lived in source:
  /// without it, everyone who already had the app would open it to an empty
  /// sign-in list and no way to close a shift.
  Future<void> _ensureSeeded(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM staff'),
    );
    if (count != null && count > 0) return;

    final now = DateTime.now().toIso8601String();
    for (final person in seedRoster) {
      final salt = PinHasher.newSalt();
      await db.insert('staff', {
        'name': person.name,
        'role': person.role,
        'pin_salt': salt,
        'pin_hash': PinHasher.hash(person.pin, salt),
        'pin_iterations': PinHasher.iterations,
        'is_manager': person.isManager ? 1 : 0,
        'active': 1,
        'created_at': now,
        // These codes are printed in the source, so an install that still has
        // them is not protected by them. The flag is what the warning reads.
        'pin_is_default': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<Database> get _db async {
    final db = await dbHelper.database;
    await _ensureSeeded(db);
    return db;
  }

  /// Everyone who can be signed in, managers last so the pick list reads as
  /// the people who work the till first.
  Future<List<Staff>> roster({bool includeInactive = false}) async {
    final db = await _db;
    final rows = await db.query(
      'staff',
      where: includeInactive ? null : 'active = 1',
      orderBy: 'is_manager ASC, id ASC',
    );
    return rows.map(Staff.fromMap).toList();
  }

  Future<Staff?> byName(String name) async {
    final db = await _db;
    final rows = await db.query('staff', where: 'name = ?', whereArgs: [name], limit: 1);
    return rows.isEmpty ? null : Staff.fromMap(rows.first);
  }

  /// Checks [pin] against the stored hash for [staffId].
  ///
  /// A locked-out account short-circuits before any comparison, and a correct
  /// PIN clears the failure count so an earlier slip does not accumulate
  /// towards a lockout days later.
  Future<PinResult> verifyPin(int staffId, String pin) async {
    final db = await _db;
    final rows = await db.query('staff', where: 'id = ?', whereArgs: [staffId], limit: 1);
    if (rows.isEmpty) return const PinRejected(maxAttempts);
    final row = rows.first;

    final locked = _lockoutRemaining(row['locked_until'] as String?);
    if (locked != null) return PinLockedOut(locked);

    final ok = PinHasher.matches(
      pin,
      row['pin_salt'] as String,
      row['pin_hash'] as String,
      iterations: row['pin_iterations'] as int,
    );

    if (ok) {
      await db.update(
        'staff',
        {'failed_attempts': 0, 'locked_until': null},
        where: 'id = ?',
        whereArgs: [staffId],
      );
      return PinAccepted(Staff.fromMap(row));
    }

    final failures = (row['failed_attempts'] as int) + 1;
    if (failures >= maxAttempts) {
      final until = DateTime.now().add(lockoutDuration);
      await db.update(
        'staff',
        {'failed_attempts': 0, 'locked_until': until.toIso8601String()},
        where: 'id = ?',
        whereArgs: [staffId],
      );
      return PinLockedOut(lockoutDuration);
    }
    await db.update(
      'staff',
      {'failed_attempts': failures},
      where: 'id = ?',
      whereArgs: [staffId],
    );
    return PinRejected(maxAttempts - failures);
  }

  /// Authorises a manager-only action — closing a shift, adding staff.
  ///
  /// Unlike [verifyPin] this does not know who is being asked for, so it tries
  /// every manager. A wrong code counts against all of them, which is what
  /// stops the untargeted version being an easier door than the targeted one.
  Future<PinResult> verifyManagerPin(String pin) async {
    final db = await _db;
    final managers = await db.query('staff',
        where: 'is_manager = 1 AND active = 1', orderBy: 'id ASC');
    if (managers.isEmpty) {
      return const PinRejected(maxAttempts);
    }

    // Every manager locked out means the door is shut; report the shortest
    // wait so the message can say when to try again.
    Duration? shortestLock;
    var anyUnlocked = false;
    for (final row in managers) {
      final locked = _lockoutRemaining(row['locked_until'] as String?);
      if (locked != null) {
        if (shortestLock == null || locked < shortestLock) shortestLock = locked;
        continue;
      }
      anyUnlocked = true;
    }
    if (!anyUnlocked) return PinLockedOut(shortestLock!);

    for (final row in managers) {
      if (_lockoutRemaining(row['locked_until'] as String?) != null) continue;
      final result = await verifyPin(row['id'] as int, pin);
      if (result is PinAccepted) return result;
    }

    // Report the state of the manager closest to a lockout, so the warning
    // ("1 try left") is not more optimistic than the truth.
    final after = await db.query('staff',
        where: 'is_manager = 1 AND active = 1', orderBy: 'id ASC');
    var fewest = maxAttempts;
    for (final row in after) {
      if (_lockoutRemaining(row['locked_until'] as String?) != null) {
        return PinLockedOut(lockoutDuration);
      }
      final left = maxAttempts - (row['failed_attempts'] as int);
      if (left < fewest) fewest = left;
    }
    return PinRejected(fewest);
  }

  /// Null when not locked, otherwise how much of the lockout is left. An
  /// expired stamp is treated as unlocked rather than cleared here, so a
  /// read stays a read.
  Duration? _lockoutRemaining(String? lockedUntil) {
    if (lockedUntil == null) return null;
    final until = DateTime.tryParse(lockedUntil);
    if (until == null) return null;
    final left = until.difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  /// Adds a cashier. Throws [StaffValidationException] with a message meant
  /// for the person typing.
  Future<int> addStaff({
    required String name,
    required String role,
    required String pin,
    bool isManager = false,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const StaffValidationException('Enter a name.');
    }
    if (!PinHasher.isWellFormed(pin)) {
      throw const StaffValidationException('The PIN has to be four digits.');
    }
    if (await byName(trimmed) != null) {
      throw StaffValidationException('$trimmed is already on the roster.');
    }

    final db = await _db;
    final salt = PinHasher.newSalt();
    return db.insert('staff', {
      'name': trimmed,
      'role': role,
      'pin_salt': salt,
      'pin_hash': PinHasher.hash(pin, salt),
      'pin_iterations': PinHasher.iterations,
      'is_manager': isManager ? 1 : 0,
      'active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Replaces someone's PIN with a fresh salt, and clears any lockout.
  Future<void> setPin(int staffId, String pin) async {
    if (!PinHasher.isWellFormed(pin)) {
      throw const StaffValidationException('The PIN has to be four digits.');
    }
    final db = await _db;
    final salt = PinHasher.newSalt();
    await db.update(
      'staff',
      {
        'pin_salt': salt,
        'pin_hash': PinHasher.hash(pin, salt),
        'pin_iterations': PinHasher.iterations,
        'failed_attempts': 0,
        'locked_until': null,
        'pin_is_default': 0,
      },
      where: 'id = ?',
      whereArgs: [staffId],
    );
  }

  /// Anyone still using the code they were seeded with.
  ///
  /// Read from a flag rather than by testing the seed PIN against the hash:
  /// checking would burn attempts and, worse, would mean the app comparing
  /// against a known-public value every launch.
  Future<List<Staff>> onStartingPin() async {
    final db = await _db;
    final rows = await db.query('staff',
        where: 'active = 1 AND pin_is_default = 1', orderBy: 'is_manager DESC, id ASC');
    return rows.map(Staff.fromMap).toList();
  }

  /// Authorises changing [staffId]'s PIN: either their own current code, or
  /// any manager's.
  ///
  /// Both doors are needed. Someone who has forgotten their code needs a
  /// manager to reset it, and a manager should not have to know a cashier's
  /// code to help them.
  Future<PinResult> verifyPinOrManager(int staffId, String pin) async {
    final own = await verifyPin(staffId, pin);
    if (own is PinAccepted) return own;
    final manager = await verifyManagerPin(pin);
    if (manager is PinAccepted) return manager;
    // Report whichever door is closer to giving way, so the count shown is
    // never more generous than the truth.
    if (own is PinLockedOut && manager is PinLockedOut) return own;
    if (own is PinRejected && manager is PinRejected) {
      return PinRejected(
        own.attemptsRemaining < manager.attemptsRemaining
            ? own.attemptsRemaining
            : manager.attemptsRemaining,
      );
    }
    return own is PinRejected ? own : manager;
  }

  /// Takes someone off the till without deleting them, so shifts and sales
  /// already recorded against their name still point at a real person.
  ///
  /// Refuses to remove the last active manager: with none left, no shift could
  /// ever be closed again.
  Future<void> deactivate(int staffId) async {
    final db = await _db;
    final rows = await db.query('staff', where: 'id = ?', whereArgs: [staffId], limit: 1);
    if (rows.isEmpty) return;
    if ((rows.first['is_manager'] as int) == 1) {
      final managers = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM staff WHERE is_manager = 1 AND active = 1',
      ));
      if ((managers ?? 0) <= 1) {
        throw const StaffValidationException(
          'This is the only manager. Add another before removing this one.',
        );
      }
    }
    await db.update('staff', {'active': 0}, where: 'id = ?', whereArgs: [staffId]);
  }
}
