import 'package:flutter/services.dart';

import 'error_log.dart';
import 'settings_service.dart';

/// What the cashier hears and feels when the scanner reads a code.
///
/// Without it a scan was silent and still, so the only way to know it had
/// worked was to look up from the product to the screen — which is exactly
/// what a scanner is meant to spare you.
///
/// The vibration always plays, like the app's other haptics. The beep follows
/// the "Scan sound" switch in Settings, which until now was connected to
/// nothing at all.
class ScanFeedback {
  ScanFeedback._();

  static const channel = MethodChannel('ph.jhedev.basepoint/beep');

  /// A code that matched a product, or any code read in capture mode.
  static Future<void> found() => _play(ok: true);

  /// A code the store does not know.
  static Future<void> unknown() => _play(ok: false);

  static Future<void> _play({required bool ok}) async {
    try {
      await (ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact());
      if (!SettingsService.instance.scanSound) return;
      bool played;
      try {
        played = await channel.invokeMethod<bool>('beep', {'ok': ok}) ?? false;
      } on MissingPluginException {
        // No tone channel on this platform (iOS, desktop): the system click
        // is the next best thing.
        played = false;
      }
      if (!played) await SystemSound.play(SystemSoundType.click);
    } catch (e, st) {
      // Feedback is a nicety; a failure must never interrupt a scan.
      ErrorLog.caught(e, st, 'scan sound');
    }
  }
}
