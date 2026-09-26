import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/tr.dart';
import 'export_service.dart';
import 'settings_service.dart';

/// Writes a backup and hands it to the share sheet.
///
/// The one way a backup leaves the phone, whether it starts from Settings,
/// Reports or the reminder on Home — three copies of this had already begun
/// to drift in what they stamped and when.
///
/// Returns the file name once it has gone somewhere, or null if the person
/// backed out of the share sheet. Throws if the backup could not be written
/// or did not read back the same.
Future<String?> shareBackup({
  ExportService? export,
  SettingsService? settings,
}) async {
  final s = settings ?? SettingsService.instance;
  final path = await (export ?? ExportService())
      .writeArchive(await getTemporaryDirectory());

  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path)],
      subject: tr('{store} backup', {'store': s.storeName}),
      text: tr('Backup from {store}. Keep this file — restoring needs it.',
          {'store': s.storeName}),
    ),
  );

  // Backing out of the share sheet is not a backup. Stamping it anyway would
  // silence the reminder and tell the shopkeeper their data is off the phone
  // when it never left. Android does not always confirm which app received
  // the file, so anything short of an explicit dismissal counts — the failure
  // to avoid is the false reassurance.
  if (result.status == ShareResultStatus.dismissed) return null;

  await s.markBackedUp();
  return p.basename(path);
}
