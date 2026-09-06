import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../services/restore_service.dart';

/// Shows what a backup holds and what it would replace, before anything runs.
///
/// A restore is the most destructive thing in the app, so it is the one place
/// that states both halves of the trade plainly: these rows arrive, those rows
/// go. Returns true only if the person confirms.
class RestorePreviewSheet extends StatelessWidget {
  const RestorePreviewSheet({
    super.key,
    required this.preview,
    required this.current,
  });

  final RestorePreview preview;

  /// What is on the device now, table to row count.
  final Map<String, int> current;

  static Future<bool> show(
    BuildContext context, {
    required RestorePreview preview,
    required Map<String, int> current,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RestorePreviewSheet(preview: preview, current: current),
    );
    return ok ?? false;
  }

  int get _currentTotal => current.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final rows = preview.rowCounts.entries.where((e) => e.value > 0).toList();
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.sheetPad,
        14,
        AppSpace.sheetPad,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Restore this backup?',
              style: AppText.sectionTitle().copyWith(fontSize: 18)),
          const SizedBox(height: 2),
          Text(
            preview.isValid
                ? '${preview.totalRows} rows across ${rows.length} tables.'
                : 'This does not look like a store backup.',
            style: AppText.caption(),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (preview.isValid) ...[
                    _counts(rows),
                    const SizedBox(height: 14),
                    _replaceWarning(),
                  ],
                  for (final message in preview.errors) ...[
                    const SizedBox(height: 8),
                    _note(message, AppColors.dangerText, AppColors.dangerFill,
                        AppColors.dangerBorder, Icons.error_outline_rounded),
                  ],
                  for (final message in preview.warnings) ...[
                    const SizedBox(height: 8),
                    _note(message, AppColors.warningText, AppColors.warningFill,
                        AppColors.warningBorder, Icons.info_outline_rounded),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (preview.isValid)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                child: Text('Replace everything',
                    style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(preview.isValid ? 'Cancel' : 'Close',
                  style: AppText.chip(color: AppColors.body)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _counts(List<MapEntry<String, int>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                      child: Text(_label(rows[i].key), style: AppText.body())),
                  Text('${rows[i].value}', style: AppText.cardTitle()),
                ],
              ),
            ),
            if (i != rows.length - 1)
              const Divider(color: AppColors.divider, height: 1),
          ],
        ],
      ),
    );
  }

  /// States what is being given up, in the same units as what is arriving.
  Widget _replaceWarning() {
    final message = _currentTotal == 0
        ? 'There is nothing on this device yet, so nothing will be lost.'
        : 'The $_currentTotal rows currently on this device will be deleted '
            'first. Staff and their PINs are not touched.';
    return _note(message, AppColors.dangerText, AppColors.dangerFill,
        AppColors.dangerBorder, Icons.warning_amber_rounded);
  }

  Widget _note(String message, Color fg, Color bg, Color border, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: AppText.caption(color: fg))),
        ],
      ),
    );
  }

  static String _label(String table) => switch (table) {
        'products' => 'Products',
        'sales' => 'Sales',
        'sale_items' => 'Sale lines',
        'refunds' => 'Refunds',
        'refund_items' => 'Refund lines',
        'shifts' => 'Shifts',
        'customers' => 'Utang customers',
        'utang_entries' => 'Utang entries',
        _ => table,
      };
}
