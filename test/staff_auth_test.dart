import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:storev2/database/database_helper.dart';
import 'package:storev2/services/pin_hasher.dart';
import 'package:storev2/services/staff_service.dart';

void main() {
  final staff = StaffService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseHelper.testDatabasePath = inMemoryDatabasePath;
  });

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    // Not covered by clearAllData, on purpose — see DatabaseHelper. Cleared
    // here so every test starts from the seeding path.
    await db.delete('staff');
  });

  Future<int> idOf(String name) async => (await staff.byName(name))!.id!;

  Future<Map<String, Object?>> rowOf(String name) async {
    final db = await DatabaseHelper.instance.database;
    return (await db.query('staff', where: 'name = ?', whereArgs: [name])).first;
  }

  /// Burns through the allowance so the next wrong PIN trips the lockout.
  Future<void> failTimes(int id, int times) async {
    for (var i = 0; i < times; i++) {
      await staff.verifyPin(id, '0000');
    }
  }

  group('PinHasher', () {
    test('the same PIN and salt always produce the same hash', () {
      const salt = 'c2FsdHNhbHRzYWx0c2ExMg==';
      expect(PinHasher.hash('1234', salt), PinHasher.hash('1234', salt));
    });

    test('two people with the same PIN do not share a hash', () {
      final a = PinHasher.hash('1234', PinHasher.newSalt());
      final b = PinHasher.hash('1234', PinHasher.newSalt());
      expect(a, isNot(b), reason: 'the salt is what makes these differ');
    });

    test('matches accepts the right PIN and refuses the rest', () {
      final salt = PinHasher.newSalt();
      final hash = PinHasher.hash('1234', salt);
      expect(PinHasher.matches('1234', salt, hash), isTrue);
      expect(PinHasher.matches('1235', salt, hash), isFalse);
      expect(PinHasher.matches('', salt, hash), isFalse);
    });

    test('a hash under a different salt does not verify', () {
      final hash = PinHasher.hash('1234', PinHasher.newSalt());
      expect(PinHasher.matches('1234', PinHasher.newSalt(), hash), isFalse);
    });

    test('salts are random', () {
      final salts = List.generate(20, (_) => PinHasher.newSalt()).toSet();
      expect(salts.length, 20);
    });

    test('only four digits is a well-formed PIN', () {
      expect(PinHasher.isWellFormed('0000'), isTrue);
      expect(PinHasher.isWellFormed('123'), isFalse);
      expect(PinHasher.isWellFormed('12345'), isFalse);
      expect(PinHasher.isWellFormed('12a4'), isFalse);
      expect(PinHasher.isWellFormed(''), isFalse);
    });
  });

  group('seeding', () {
    test('an empty table is filled on first read', () async {
      final roster = await staff.roster();
      expect(roster.map((s) => s.name), ['May', 'Ronel', 'Nena']);
      expect(roster.last.isManager, isTrue, reason: 'managers sort last');
    });

    test('reading twice does not duplicate anyone', () async {
      await staff.roster();
      final second = await staff.roster();
      expect(second.length, StaffService.seedRoster.length);
    });

    test('no PIN is stored in the clear', () async {
      await staff.roster();
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('staff');

      // The property under test is that reading a row does not hand you the
      // PIN. Checked as equality, not containment: the salt and hash are
      // random base64, and a substring search over them reports a leak the
      // first time four digits happen to line up.
      for (final row in rows) {
        for (final entry in row.entries) {
          for (final person in StaffService.seedRoster) {
            expect('${entry.value}', isNot(person.pin),
                reason: '${row['name']}.${entry.key} holds a PIN verbatim');
          }
        }
      }

      // And nothing outside the two credential columns may carry one at all,
      // which is where a stray copy would realistically end up.
      for (final row in rows) {
        for (final entry in row.entries) {
          if (entry.key == 'pin_hash' || entry.key == 'pin_salt') continue;
          for (final person in StaffService.seedRoster) {
            expect('${entry.value}'.contains(person.pin), isFalse,
                reason: '${row['name']}.${entry.key} contains ${person.pin}');
          }
        }
      }

      expect(rows.first['pin_hash'], isNotEmpty);
      expect(rows.first['pin_salt'], isNotEmpty);
    });

    test('the iteration count is recorded per row', () async {
      await staff.roster();
      expect((await rowOf('May'))['pin_iterations'], PinHasher.iterations);
    });
  });

  group('verifyPin', () {
    test('the right PIN is accepted and names who was let in', () async {
      final result = await staff.verifyPin(await idOf('May'), '1111');
      expect(result, isA<PinAccepted>());
      expect((result as PinAccepted).staff.name, 'May');
    });

    test('another person\'s PIN does not open this account', () async {
      final result = await staff.verifyPin(await idOf('May'), '2222');
      expect(result, isA<PinRejected>());
    });

    test('each wrong try counts down the allowance', () async {
      final id = await idOf('May');
      for (var used = 1; used < StaffService.maxAttempts; used++) {
        final result = await staff.verifyPin(id, '0000');
        expect((result as PinRejected).attemptsRemaining,
            StaffService.maxAttempts - used);
      }
    });

    test('the allowance runs out into a lockout', () async {
      final id = await idOf('May');
      await failTimes(id, StaffService.maxAttempts - 1);
      final result = await staff.verifyPin(id, '0000');
      expect(result, isA<PinLockedOut>());
      expect((result as PinLockedOut).remaining, StaffService.lockoutDuration);
    });

    test('a locked account refuses even the correct PIN', () async {
      final id = await idOf('May');
      await failTimes(id, StaffService.maxAttempts);
      // This is what makes the lockout worth having: guessing cannot be
      // resumed by happening to land on the right code.
      expect(await staff.verifyPin(id, '1111'), isA<PinLockedOut>());
    });

    test('the lockout lets go when it expires', () async {
      final id = await idOf('May');
      await failTimes(id, StaffService.maxAttempts);

      final db = await DatabaseHelper.instance.database;
      await db.update(
        'staff',
        {'locked_until': DateTime.now().subtract(const Duration(seconds: 1)).toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );

      expect(await staff.verifyPin(id, '1111'), isA<PinAccepted>());
    });

    test('a correct PIN clears the failures behind it', () async {
      final id = await idOf('May');
      await failTimes(id, 3);
      expect(await staff.verifyPin(id, '1111'), isA<PinAccepted>());

      // Back to a full allowance, so three slips last week cannot combine with
      // two today into a lockout.
      final next = await staff.verifyPin(id, '0000');
      expect((next as PinRejected).attemptsRemaining, StaffService.maxAttempts - 1);
    });

    test('an unknown id is rejected, not accepted by accident', () async {
      await staff.roster();
      expect(await staff.verifyPin(99999, '1111'), isA<PinRejected>());
    });
  });

  group('verifyManagerPin', () {
    test('a manager PIN authorises', () async {
      expect(await staff.verifyManagerPin('2468'), isA<PinAccepted>());
    });

    test('a cashier PIN does not', () async {
      // May's code is valid for signing May in, and useless for a close.
      expect(await staff.verifyManagerPin('1111'), isA<PinRejected>());
    });

    test('wrong tries count against the manager and end in a lockout', () async {
      for (var i = 0; i < StaffService.maxAttempts - 1; i++) {
        expect(await staff.verifyManagerPin('0000'), isA<PinRejected>());
      }
      expect(await staff.verifyManagerPin('0000'), isA<PinLockedOut>());
      // And the untargeted door is not an easier one than the targeted door.
      expect(await staff.verifyManagerPin('2468'), isA<PinLockedOut>());
    });

    test('with no managers left nothing is authorised', () async {
      final db = await DatabaseHelper.instance.database;
      await staff.roster();
      await db.update('staff', {'active': 0}, where: 'is_manager = 1');
      expect(await staff.verifyManagerPin('2468'), isA<PinRejected>());
    });
  });

  group('addStaff', () {
    test('a new cashier can sign in with their PIN', () async {
      final id = await staff.addStaff(name: 'Ana', role: 'Cashier', pin: '4321');
      expect(await staff.verifyPin(id, '4321'), isA<PinAccepted>());
      expect(await staff.verifyPin(id, '1234'), isA<PinRejected>());
    });

    test('the new PIN is not stored in the clear either', () async {
      await staff.addStaff(name: 'Ana', role: 'Cashier', pin: '4321');
      final dump = (await rowOf('Ana')).values.map((v) => '$v').join('|');
      expect(dump.contains('4321'), isFalse);
    });

    test('the name is trimmed and has to be there', () async {
      final id = await staff.addStaff(name: '  Ana  ', role: 'Cashier', pin: '4321');
      expect((await staff.byName('Ana'))?.id, id);
      expect(
        () => staff.addStaff(name: '   ', role: 'Cashier', pin: '4321'),
        throwsA(isA<StaffValidationException>()),
      );
    });

    test('the PIN has to be four digits', () async {
      for (final bad in ['123', '12345', 'abcd', '']) {
        expect(
          () => staff.addStaff(name: 'Ana$bad', role: 'Cashier', pin: bad),
          throwsA(isA<StaffValidationException>()),
          reason: '"$bad" should be refused',
        );
      }
    });

    test('a duplicate name is refused', () async {
      await staff.addStaff(name: 'Ana', role: 'Cashier', pin: '4321');
      expect(
        () => staff.addStaff(name: 'Ana', role: 'Cashier', pin: '1111'),
        throwsA(isA<StaffValidationException>()),
      );
    });

    test('a new manager can authorise a close', () async {
      await staff.addStaff(name: 'Ana', role: 'Manager', pin: '4321', isManager: true);
      expect(await staff.verifyManagerPin('4321'), isA<PinAccepted>());
    });
  });

  group('setPin', () {
    test('the old PIN stops working and the new one starts', () async {
      final id = await idOf('May');
      await staff.setPin(id, '9876');
      expect(await staff.verifyPin(id, '1111'), isA<PinRejected>());
      expect(await staff.verifyPin(id, '9876'), isA<PinAccepted>());
    });

    test('it re-salts rather than reusing the old salt', () async {
      await staff.roster();
      final before = await rowOf('May');
      await staff.setPin(before['id'] as int, '9876');
      expect((await rowOf('May'))['pin_salt'], isNot(before['pin_salt']));
    });

    test('it lifts a lockout', () async {
      final id = await idOf('May');
      await failTimes(id, StaffService.maxAttempts);
      await staff.setPin(id, '9876');
      expect(await staff.verifyPin(id, '9876'), isA<PinAccepted>());
    });

    test('a malformed PIN is refused', () async {
      final id = await idOf('May');
      expect(() => staff.setPin(id, '12'), throwsA(isA<StaffValidationException>()));
    });
  });

  group('the starting codes', () {
    test('a fresh seed flags everyone as still on a starting PIN', () async {
      final roster = await staff.roster();
      expect(roster.every((s) => s.onStartingPin), isTrue);
      expect((await staff.onStartingPin()).length, StaffService.seedRoster.length);
    });

    test('changing a PIN clears the flag for that person only', () async {
      final id = await idOf('May');
      await staff.setPin(id, '9876');

      expect((await staff.byName('May'))!.onStartingPin, isFalse);
      expect((await staff.onStartingPin()).map((s) => s.name),
          ['Nena', 'Ronel'], reason: 'managers first, so the urgent one leads');
    });

    test('someone added later is not on a starting code', () async {
      await staff.addStaff(name: 'Ana', role: 'Cashier', pin: '4321');
      expect((await staff.byName('Ana'))!.onStartingPin, isFalse);
      expect((await staff.onStartingPin()).map((s) => s.name), isNot(contains('Ana')));
    });

    test('the warning empties once every code has been rotated', () async {
      for (final person in await staff.roster()) {
        await staff.setPin(person.id!, '9876');
      }
      expect(await staff.onStartingPin(), isEmpty);
    });

    test('a former staff member does not keep the warning alive', () async {
      await staff.addStaff(name: 'Ana', role: 'Manager', pin: '4321', isManager: true);
      for (final name in ['May', 'Ronel', 'Nena']) {
        await staff.deactivate(await idOf(name));
      }
      expect(await staff.onStartingPin(), isEmpty);
    });
  });

  group('verifyPinOrManager', () {
    test("the person's own PIN opens it", () async {
      final id = await idOf('May');
      expect(await staff.verifyPinOrManager(id, '1111'), isA<PinAccepted>());
    });

    test('a manager PIN opens it too, for a forgotten code', () async {
      final id = await idOf('May');
      expect(await staff.verifyPinOrManager(id, '2468'), isA<PinAccepted>());
    });

    test("another cashier's PIN opens nothing", () async {
      final id = await idOf('May');
      // Ronel is neither May nor a manager, so his code is no help here.
      expect(await staff.verifyPinOrManager(id, '2222'), isA<PinRejected>());
    });

    test('a wrong code counts against both doors at once', () async {
      final id = await idOf('May');
      final result = await staff.verifyPinOrManager(id, '0000');
      expect((result as PinRejected).attemptsRemaining,
          StaffService.maxAttempts - 1);

      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('staff', columns: ['name', 'failed_attempts']);
      final failures = {for (final r in rows) r['name']: r['failed_attempts']};
      // Otherwise this screen would be a way to guess a manager code without
      // the manager door ever counting the tries.
      expect(failures['May'], 1);
      expect(failures['Nena'], 1);
      expect(failures['Ronel'], 0, reason: 'uninvolved staff are untouched');
    });

    test('the count reported is the closer of the two doors', () async {
      final id = await idOf('May');
      await failTimes(id, 2);
      final result = await staff.verifyPinOrManager(id, '0000');
      // May is now at 3 failures and the manager at 1, so the honest number
      // left is May's.
      expect((result as PinRejected).attemptsRemaining,
          StaffService.maxAttempts - 3);
    });
  });

  group('deactivate', () {
    test('a former cashier drops off the list but is not deleted', () async {
      final id = await idOf('Ronel');
      await staff.deactivate(id);

      expect((await staff.roster()).map((s) => s.name), isNot(contains('Ronel')));
      // Kept, so a shift already closed under this name still points at a
      // real person.
      expect((await staff.roster(includeInactive: true)).map((s) => s.name),
          contains('Ronel'));
    });

    test('the last manager cannot be removed', () async {
      final id = await idOf('Nena');
      expect(
        () => staff.deactivate(id),
        throwsA(isA<StaffValidationException>()),
      );
    });

    test('a manager can go once there is another', () async {
      await staff.addStaff(name: 'Ana', role: 'Manager', pin: '4321', isManager: true);
      await staff.deactivate(await idOf('Nena'));
      expect((await staff.roster()).map((s) => s.name), isNot(contains('Nena')));
    });
  });
}
