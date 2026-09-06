import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted, iterated hashing for till PINs.
///
/// What this buys and what it does not, plainly: a four-digit PIN has ten
/// thousand possibilities, so anyone holding the database file can try all of
/// them. Iterating the hash makes that take minutes instead of milliseconds,
/// and the per-person salt means the ten thousand have to be tried again for
/// each staff member — but it is not a password, and no amount of hashing
/// makes it one.
///
/// What it does buy is the thing that actually matters here: the PIN is no
/// longer sitting in the source, in the APK, or in a column anyone with a
/// file browser can read. A cashier cannot look up the manager's code. The
/// defence against someone standing at the till guessing is the attempt
/// lockout in [StaffService], not this.
class PinHasher {
  PinHasher._();

  /// Chosen so a verify costs tens of milliseconds on a low-end Android phone:
  /// unnoticeable when a cashier signs in a few times a day, and enough to
  /// make ten thousand guesses per account a slow job rather than an instant
  /// one. Stored per row so this can be raised later without stranding the
  /// PINs hashed at the old count.
  static const iterations = 20000;

  static final _random = Random.secure();

  /// 16 bytes, base64. Long enough that two people who pick the same PIN do
  /// not end up with the same hash.
  static String newSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  /// Iterated HMAC-SHA256, keyed with the salt. Each round hashes the previous
  /// digest, so the work cannot be skipped.
  static String hash(String pin, String salt, {int iterations = iterations}) {
    final hmac = Hmac(sha256, base64Decode(salt));
    var digest = hmac.convert(utf8.encode(pin)).bytes;
    for (var i = 1; i < iterations; i++) {
      digest = hmac.convert(digest).bytes;
    }
    return base64Encode(digest);
  }

  /// Compares in constant time. The timing of a PIN check is not a realistic
  /// way in here, but a comparison that returns early on the first wrong byte
  /// is the kind of thing that gets copied somewhere it does matter.
  static bool matches(
    String pin,
    String salt,
    String expectedHash, {
    int iterations = iterations,
  }) {
    final actual = utf8.encode(hash(pin, salt, iterations: iterations));
    final expected = utf8.encode(expectedHash);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// A PIN the keypad can actually produce: exactly four digits.
  static bool isWellFormed(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);
}
