import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_info.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../database/database_helper.dart';
import '../services/backup_share.dart';
import '../services/demo_data.dart';
import '../services/export_service.dart';
import 'error_log_screen.dart';
import 'payment_types_screen.dart';
import 'printer_screen.dart';
import '../services/restore_service.dart';
import '../services/settings_service.dart';
import '../services/staff_service.dart';
import '../services/stock_alerts.dart';
import '../widgets/restore_flow.dart';
import '../l10n/tr.dart';
import '../widgets/language_switch.dart';
import '../services/error_log.dart';

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

  /// Progress of a demo load, or null when none is running.
  double? _demoProgress;

  /// Fills the store with a year of trading, for trying the app on a real
  /// phone. Developer-only — the row is absent from release builds — so its
  /// text is left in English.
  Future<void> _loadDemoYear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Load a demo year?', style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: Text(
          'Replaces every product, sale, return, closed day and utang record '
          'on this device with a year of made-up trading: '
          '${DemoData.productCount} products and about 20,000 sales. '
          'Staff and settings are kept. For testing only.',
          style: AppText.body(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'), style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Replace with demo', style: AppText.chip(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _demoProgress = 0);
    final watch = Stopwatch()..start();
    try {
      final roster = await StaffService().roster();
      await DemoData().loadYear(
        cashiers: [for (final s in roster) s.name],
        onProgress: (p) {
          if (mounted) setState(() => _demoProgress = p);
        },
      );
      await _settings.markSetupDone();
      await StockAlerts.instance.refresh();
      if (!mounted) return;
      _toast('Demo year loaded in ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
    } catch (e, st) {
      ErrorLog.caught(e, st, 'demo year');
      if (mounted) _toast('Could not load the demo: $e');
    } finally {
      if (mounted) setState(() => _demoProgress = null);
    }
  }

  Future<void> _confirmClearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Clear all data?'), style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: Text(
          tr('This permanently deletes every product, sale, return, closed day and utang record on this device. Staff and settings are kept. This cannot be undone.'),
          style: AppText.body(),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'), style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Delete everything'), style: AppText.chip(color: AppColors.danger)),
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
        content: Text(tr('All data cleared'), style: TextStyle(color: Colors.white)),
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
        title: Text(tr('Default minimum stock'), style: AppText.sectionTitle().copyWith(fontSize: 17)),
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
            child: Text(tr('Cancel'), style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(ctrl.text) ?? _settings.defaultMinStock),
            child: Text(tr('Save'), style: AppText.chip(color: AppColors.primary)),
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
                Text(tr('Settings'), style: AppText.screenTitle().copyWith(fontSize: 22)),
              ],
            ),
            const SizedBox(height: AppSpace.gapBlock),
            _identityCard(),
            const SizedBox(height: AppSpace.gapBlock),
            _overline(tr('Language')),
            const SizedBox(height: 8),
            _group([
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('App language'), style: AppText.cardTitle()),
                          const SizedBox(height: 2),
                          Text(tr('Receipts and reports you send stay in English'),
                              style: AppText.caption()),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    const LanguageSwitch(),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: AppSpace.gapBlock),
            _overline(tr('Sales')),
            const SizedBox(height: 8),
            _group([
              _toggleRow(
                tr('Print receipt'),
                // Was a flat "Automatically print after checkout", which was
                // not true until a printer was chosen. It now says which of
                // the two it is.
                _settings.printerAddress == null
                    ? tr('Automatically after checkout — needs a printer')
                    : tr('Automatically after checkout'),
                _settings.printReceipt,
                (v) async {
                  await _settings.setPrintReceipt(v);
                  if (mounted) setState(() {});
                },
              ),
              _navRow(
                tr('Receipt printer'),
                _settings.printerAddress == null
                    ? tr('None chosen')
                    : '${_settings.printerName} · ${_settings.paperWidth.label}',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PrinterScreen()),
                ).then((_) {
                  if (mounted) setState(() {});
                }),
              ),
              _toggleRow(tr('Scan sound'), tr('Beep when the scanner reads a code'),
                  _settings.scanSound, _settings.setScanSound),
              _navRow(
                tr('Payment types'),
                // A live summary rather than a fixed string: the old one read
                // "Cash, GCash, Card" and had never mentioned Utang.
                _settings.paymentTypes.map((t) => t.name).join(', '),
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaymentTypesScreen()),
                ).then((_) {
                  if (mounted) setState(() {});
                }),
              ),
              _navRow(
                tr('Opening cash'),
                tr('{amount} in the drawer at the start of each day',
                    {'amount': formatPeso(_settings.openingFloat)}),
                _editOpeningFloat,
              ),
            ]),
            const SizedBox(height: AppSpace.gapSection),
            _overline(tr('Inventory')),
            const SizedBox(height: 8),
            _group([
              // Was "Flag products at or below minimum" and read by nothing. It now
              // decides whether running-low products appear under the bell on Home.
              _toggleRow(tr('Low stock alerts'), tr('List running-low products under the bell on Home'),
                  _settings.lowStockAlerts, _settings.setLowStockAlerts),
              _navRow(tr('Default minimum stock'), tr('{n} units', {'n': _settings.defaultMinStock}), _editMinStock),
            ]),
            const SizedBox(height: AppSpace.gapSection),
            _overline(tr('Data')),
            const SizedBox(height: 8),
            _group([
              // Was "Automatic backup / Backing up every night", which nothing
              // did. Telling a shopkeeper their data is safe when it is not is
              // worse than an off switch, so this is a reminder — which is what
              // it can honestly deliver without a server behind it.
              _toggleRow(
                tr('Remind me to back up'),
                _settings.autoBackup
                    ? tr('Nudges you when the last export is over a week old')
                    : tr('No reminders — export when you remember'),
                _settings.autoBackup,
                _settings.setAutoBackup,
              ),
              _navRow(
                _exporting ? tr('Exporting…') : tr('Export a backup'),
                tr('Last export: {when}', {'when': _lastBackupLabel()}),
                _exporting ? null : _exportBackup,
              ),
              _navRow(
                _restoring ? tr('Restoring…') : tr('Restore from a backup'),
                tr('Replaces everything on this device'),
                _restoring ? null : _restoreBackup,
              ),
              _navRow(
                tr('Error log'),
                _errorLogSummary(),
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ErrorLogScreen()),
                ).then((_) {
                  if (mounted) setState(() {});
                }),
              ),
              _navRow(tr('Clear all data'), tr('Products, sales and utang — all of it'), _confirmClearData, danger: true),
            ]),
            // Never in a release build: this replaces the store's data.
            if (!kReleaseMode) ...[
              const SizedBox(height: AppSpace.gapSection),
              _overline('Developer'),
              const SizedBox(height: 8),
              _group([
                _navRow(
                  _demoProgress == null
                      ? 'Load a demo year'
                      : 'Loading… ${(_demoProgress! * 100).round()}%',
                  '${DemoData.productCount} products, a year of sales — for testing speed',
                  _demoProgress == null ? _loadDemoYear : null,
                  danger: true,
                ),
              ]),
            ],
            const SizedBox(height: AppSpace.gapBlock),
            Center(child: Text('${AppInfo.name} · v${AppInfo.version}', style: AppText.caption())),
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
      final file = await shareBackup(export: _export, settings: _settings);
      if (!mounted) return;
      if (file == null) {
        _toast(tr('Backup cancelled — nothing was sent'));
        return;
      }
      setState(() {});
      _toast(tr('Backed up to {file}', {'file': file}));
    } catch (e, st) {
      ErrorLog.caught(e, st, 'backup from Settings');
      if (!mounted) return;
      // Worth surfacing rather than swallowing: a backup that silently did
      // nothing is the failure that matters here.
      _toast(tr('Could not export: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Reads a backup back in, after showing exactly what it will do.
  Future<void> _restoreBackup() async {
    setState(() => _restoring = true);
    try {
      final done =
          await runRestoreFlow(context, restore: _restore, export: _export);
      if (done == null || !mounted) return;
      setState(() {});
      _toast(tr('Restored {n} rows. A copy of the old data is in {folder}.',
          {'n': done.rows, 'folder': done.snapshotFolder}));
    } catch (e, st) {
      ErrorLog.caught(e, st, 'restore from Settings');
      if (!mounted) return;
      _toast(tr('Could not restore: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// The change the drawer opens with — what closing the day counts from.
  Future<void> _editOpeningFloat() async {
    final v = _settings.openingFloat;
    final ctrl = TextEditingController(
        text: v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(2));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Opening cash'), style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppText.body(color: AppColors.ink),
          decoration: InputDecoration(
            prefixText: '₱ ',
            filled: true,
            fillColor: AppColors.canvas,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancel'), style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () {
              final parsed = double.tryParse(ctrl.text.replaceAll(',', '').trim());
              Navigator.pop(ctx, parsed == null || parsed < 0 ? null : parsed);
            },
            child: Text(tr('Save'), style: AppText.chip(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _settings.setOpeningFloat(result);
    if (mounted) setState(() {});
  }

  /// The name printed at the top of every receipt.
  Future<void> _editStoreName() async {
    final ctrl = TextEditingController(text: _settings.storeName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Store name'), style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 40,
          style: AppText.body(color: AppColors.ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.canvas,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancel'), style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(tr('Save'), style: AppText.chip(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _settings.setStoreName(result);
    if (mounted) setState(() {});
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text(message, style: const TextStyle(color: Colors.white)),
    ));
  }

  String _errorLogSummary() {
    final log = ErrorLog.instance;
    if (log.count == 0) return tr('Nothing has gone wrong');
    return tr('{n} recorded · last {when}',
        {'n': log.count, 'when': trWhen(context, log.entries.first.lastAt ?? log.entries.first.at)});
  }

  String _lastBackupLabel() {
    final raw = _settings.lastBackup;
    if (raw == null) return tr('never');
    final d = DateTime.tryParse(raw);
    if (d == null) return tr('never');
    return '${d.day}/${d.month}/${d.year}';
  }

  Widget _identityCard() {
    return GestureDetector(
      onTap: _editStoreName,
      behavior: HitTestBehavior.opaque,
      child: Container(
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
                Text(tr('{terminal} · Cashier {name}', {'terminal': _settings.terminal, 'name': _settings.cashier}),
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
            child: Text(tr('Edit'), style: AppText.chip(color: AppColors.primary)),
          ),
        ],
      ),
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
