import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/tr.dart';
import '../services/export_service.dart';
import '../services/restore_service.dart';
import 'restore_preview_sheet.dart';

/// What a finished restore did, for the message afterwards.
class RestoreOutcome {
  const RestoreOutcome({
    required this.rows,
    required this.snapshotFolder,
    required this.hadSettings,
  });

  final int rows;

  /// Where the data that was replaced was saved first.
  final String snapshotFolder;

  /// Whether the store's name and settings came back too.
  final bool hadSettings;
}

/// Picks a backup, shows what it holds, and restores it once confirmed.
///
/// Shared by Settings and by first-run setup on a new phone, which is exactly
/// when a restore is most likely to be needed and least likely to be found.
///
/// Returns null if the person backed out at any point. Throws if the backup
/// could not be read or written.
///
/// The current data is exported first. A restore aimed at the wrong file is
/// the one mistake here that cannot be undone by hand, so there is always a
/// copy of what was replaced.
Future<RestoreOutcome?> runRestoreFlow(
  BuildContext context, {
  RestoreService? restore,
  ExportService? export,
}) async {
  final restorer = restore ?? RestoreService();
  final picked = await FilePicker.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    // Zip is what an export produces now; csv stays accepted so backups
    // taken by an earlier build still restore.
    allowedExtensions: ['zip', 'csv'],
    withData: true,
    dialogTitle: tr('Pick a backup file'),
  );
  if (picked == null || picked.files.isEmpty || !context.mounted) return null;

  final files = <String, String>{};
  final photos = <String, List<int>>{};
  Map<String, Object?>? settings;
  for (final file in picked.files) {
    final bytes = file.bytes;
    if (bytes == null) continue;
    if (file.name.toLowerCase().endsWith('.zip')) {
      files.addAll(RestoreService.readArchive(bytes));
      photos.addAll(RestoreService.readPhotos(bytes));
      settings ??= RestoreService.readSettings(bytes);
    } else {
      files[file.name] = utf8.decode(bytes, allowMalformed: true);
    }
  }

  final preview =
      await restorer.inspect(files, photos: photos, settings: settings);
  final current = await restorer.currentRowCounts();
  if (!context.mounted) return null;

  final confirmed = await RestorePreviewSheet.show(
    context,
    preview: preview,
    current: current,
  );
  if (!confirmed || !context.mounted) return null;

  // Silent safety net, reported afterwards so it is not just invisible.
  final snapshot = await (export ?? ExportService())
      .writeTo(await getApplicationDocumentsDirectory());
  await restorer.restore(files, photos: photos, settings: settings);

  return RestoreOutcome(
    rows: preview.totalRows,
    snapshotFolder: p.basename(p.dirname(snapshot.first)),
    hadSettings: settings != null,
  );
}
