import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../database/database_helper.dart';
import '../services/export_service.dart';
import '../services/restore_service.dart';
import '../services/settings_service.dart';
import '../widgets/restore_preview_sheet.dart';

class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  final _settings = SettingsService.instance;
  final _export = ExportService();
  final _restore = RestoreService();
  bool _exporting = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmClearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear all data?', style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: Text(
          'This permanently deletes every product and sale on this device. This cannot be undone.',
          style: AppText.body(),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete everything', style: AppText.chip(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper.instance.clearAllData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Text('All data cleared', style: TextStyle(color: Colors.white)),
      ));
    }
  }

  Future<void> _editMinStock() async {
    final ctrl = TextEditingController(text: '${_settings.defaultMinStock}');
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Default minimum stock', style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: AppText.body(color: AppColors.ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.canvas,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text) ?? _settings.defaultMinStock),
            child: Text('Save', style: AppText.chip(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (result != null) await _settings.setDefaultMinStock(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
          padding: Breakpoints.pagePadding(context, constraints.maxWidth),
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.body, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Text('Settings', style: AppText.screenTitle().copyWith(fontSize: 22)),
              ],
            ),
            const SizedBox(height: AppSpace.gapBlock),
            _identityCard(),
            const SizedBox(height: AppSpace.gapBlock),
            _overline('Sales'),
            const SizedBox(height: 8),
            _group([
              _toggleRow('Print receipt', 'Automatically print after checkout',
                  _settings.printReceipt, _settings.setPrintReceipt),
              _toggleRow('Scan sound', 'Beep when the scanner reads a code',
                  _settings.scanSound, _settings.setScanSound),
              _navRow('Payment methods', 'Cash, GCash, Card', () {}),
            ]),
            const SizedBox(height: AppSpace.gapSection),
            _overline('Inventory'),
            const SizedBox(height: 8),
            _group([
              _toggleRow('Low stock alerts', 'Flag products at or below minimum',
                  _settings.lowStockAlerts, _settings.setLowStockAlerts),
              _navRow('Default minimum stock', '${_settings.defaultMinStock} units', _editMinStock),
            ]),
            const SizedBox(height: AppSpace.gapSection),
            _overline('Data'),
            const SizedBox(height: 8),
            _group([
              // Was "Automatic backup / Backing up every night", which nothing
              // did. Telling a shopkeeper their data is safe when it is not is
              // worse than an off switch, so this is a reminder — which is what
              // it can honestly deliver without a server behind it.
              _toggleRow(
                'Remind me to back up',
                _settings.autoBackup
                    ? 'Nudges you when the last export is over a week old'
                    : 'No reminders — export when you remember',
                _settings.autoBackup,
                _settings.setAutoBackup,
              ),
              _navRow(
                _exporting ? 'Exporting…' : 'Export a backup',
                'Last export: ${_lastBackupLabel()}',
                _exporting ? null : _exportBackup,
              ),
              _navRow(
                _restoring ? 'Restoring…' : 'Restore from a backup',
                'Replaces everything on this device',
                _restoring ? null : _restoreBackup,
              ),
              _navRow('Clear all data', 'Delete every product and sale', _confirmClearData, danger: true),
            ]),
            const SizedBox(height: AppSpace.gapBlock),
            Center(child: Text('Sari-Sari POS · v1.0.0', style: AppText.caption())),
          ],
        ),
        ),
      ),
    );
  }

  /// Writes every table to CSV and hands the files to the share sheet.
  ///
  /// Share rather than "saved to Downloads": the point is to get the data off
  /// this phone, and a file that never leaves it is not a backup.
  Future<void> _exportBackup() async {
    setState(() => _exporting = true);
    try {
      final dir = await getTemporaryDirectory();
      final paths = await _export.writeTo(dir);
      if (!mounted) return;

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [for (final path in paths) XFile(path)],
          subject: '${_settings.storeName} backup',
          text: 'Backup from ${_settings.storeName}, '
              '${paths.length} files.',
        ),
      );
      if (!mounted) return;

      // Backing out of the share sheet is not a backup. Stamping it anyway
      // would silence the reminder and tell the shopkeeper their data is off
      // the phone when it never left. Android does not always confirm which
      // app received the files, so anything short of an explicit dismissal
      // counts — the failure to avoid is the false reassurance.
      if (result.status == ShareResultStatus.dismissed) {
        _toast('Backup cancelled — nothing was sent');
        return;
      }

      await _settings.markBackedUp();
      if (!mounted) return;
      setState(() {});
      _toast('Backed up ${paths.length} files');
    } catch (e) {
      if (!mounted) return;
      // Worth surfacing rather than swallowing: a backup that silently did
      // nothing is the failure that matters here.
      _toast('Could not export: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Reads a backup folder back in, after showing exactly what it will do.
  ///
  /// The current data is exported first. A restore aimed at the wrong folder
  /// is the one mistake here that cannot be undone by hand, so there is always
  /// a copy of what was replaced.
  Future<void> _restoreBackup() async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
      dialogTitle: 'Pick the CSV files from a backup folder',
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;

    setState(() => _restoring = true);
    try {
      final files = <String, String>{};
      for (final file in picked.files) {
        final bytes = file.bytes;
        if (bytes == null) continue;
        files[file.name] = utf8.decode(bytes, allowMalformed: true);
      }

      final preview = await _restore.inspect(files);
      final current = await _restore.currentRowCounts();
      if (!mounted) return;

      final confirmed = await RestorePreviewSheet.show(
        context,
        preview: preview,
        current: current,
      );
      if (!confirmed || !mounted) return;

      // Silent safety net, reported afterwards so it is not just invisible.
      final snapshot = await _export.writeTo(await getApplicationDocumentsDirectory());
      await _restore.restore(files);
      if (!mounted) return;

      setState(() {});
      _toast('Restored ${preview.totalRows} rows. '
          'A copy of the old data is in ${p.basename(p.dirname(snapshot.first))}.');
    } catch (e) {
      if (!mounted) return;
      _toast('Could not restore: $e');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text(message, style: const TextStyle(color: Colors.white)),
    ));
  }

  String _lastBackupLabel() {
    final raw = _settings.lastBackup;
    if (raw == null) return 'never';
    final d = DateTime.tryParse(raw);
    if (d == null) return 'never';
    return '${d.day}/${d.month}/${d.year}';
  }

  Widget _identityCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_settings.storeName, style: AppText.cardTitle().copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text('${_settings.terminal} · Cashier ${_settings.cashier}',
                    style: AppText.caption()),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Edit', style: AppText.chip(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _overline(String text) => Text(text.toUpperCase(), style: AppText.overline(color: AppColors.muted));

  Widget _group(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1) const Padding(padding: EdgeInsets.only(left: 16), child: Divider(color: AppColors.divider, height: 1)),
          ],
        ],
      ),
    );
  }

  Widget _toggleRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardTitle()),
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.caption()),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _navRow(String title, String subtitle, VoidCallback? onTap, {bool danger = false}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.cardTitle(color: danger ? AppColors.danger : AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppText.caption()),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: danger ? AppColors.danger : AppColors.faint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
