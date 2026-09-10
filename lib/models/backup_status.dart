/// How the till header describes where this store's data actually is.
///
/// It replaced a green "Synced" pill, which was simply untrue: nothing syncs
/// anywhere, there is no server and no account. Telling a shopkeeper their
/// data is safe somewhere else when it exists only on this phone is the most
/// expensive lie the app could tell — they would find out when the phone did.
///
/// The slot now carries the one fact that is both true and worth acting on:
/// how long ago they last got a backup off the phone.
enum BackupLevel {
  /// Never backed up, or the last attempt was cancelled.
  none,

  /// Backed up recently enough.
  fresh,

  /// Old enough to be worth another export.
  stale,
}

class BackupStatus {
  const BackupStatus(this.label, this.level);

  final String label;
  final BackupLevel level;

  /// A week is the line: longer than that and a lost phone costs a month of
  /// takings rather than a few days of them.
  static const staleAfter = Duration(days: 7);

  static BackupStatus from(DateTime? lastBackup, {DateTime? now}) {
    if (lastBackup == null) return const BackupStatus('No backup', BackupLevel.none);

    final at = now ?? DateTime.now();
    // A backup stamped in the future is a clock that was wrong, not a backup
    // from tomorrow; treat it as just done rather than showing "-3d".
    final days = at.difference(lastBackup).inDays;
    if (days <= 0) return const BackupStatus('Backed up', BackupLevel.fresh);
    return BackupStatus(
      'Backup · ${days}d',
      days >= staleAfter.inDays ? BackupLevel.stale : BackupLevel.fresh,
    );
  }
}
