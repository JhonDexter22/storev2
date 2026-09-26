import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import 'settings_service.dart';

/// Decides whether the app opens on the setup steps or straight to the till.
class FirstRun {
  FirstRun._();

  /// Tables that mean a store is already in use.
  static const _inUse = ['products', 'sales', 'shifts', 'customers'];

  /// True for a brand-new install that has not been set up yet.
  ///
  /// A store that already has data was being run before setup existed, and
  /// walking its owner through "welcome" would be both pointless and alarming
  /// — so it is marked done here, once, and never asked again.
  static Future<bool> needed({
    SettingsService? settings,
    DatabaseHelper? dbHelper,
  }) async {
    final s = settings ?? SettingsService.instance;
    if (s.setupDone) return false;

    final db = await (dbHelper ?? DatabaseHelper.instance).database;
    for (final table in _inUse) {
      final n = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
          0;
      if (n > 0) {
        await s.markSetupDone();
        return false;
      }
    }
    return true;
  }
}
