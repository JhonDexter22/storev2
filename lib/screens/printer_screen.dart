import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../services/escpos.dart';
import '../services/printer_service.dart';
import '../services/settings_service.dart';

/// Choosing the thermal printer, and proving it works.
///
/// Pairing itself happens in Android's own Bluetooth settings, where the PIN
/// prompt belongs — this screen only picks from printers already paired, so
/// the app never scans and needs no location permission.
class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  final _settings = SettingsService.instance;
  final _printer = PrinterService.instance;

  List<PrinterDevice> _devices = const [];
  bool _loading = true;
  bool _testing = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _problem = null;
    });
    final t = _printer.transport;
    List<PrinterDevice> found = const [];
    String? problem;
    try {
      if (!await t.isSupported) {
        problem = 'This device cannot print to a Bluetooth printer.';
      } else if (!await t.hasPermission) {
        // The check also raises Android's permission dialog, so the honest
        // instruction is to allow it and come back rather than to retry now.
        problem = 'Allow Bluetooth access, then tap Refresh.';
      } else if (!await t.isBluetoothOn) {
        problem = 'Bluetooth is off. Switch it on, then tap Refresh.';
      } else {
        found = await t.paired();
      }
    } catch (e) {
      problem = 'Could not read the paired printers.';
    }
    if (!mounted) return;
    setState(() {
      _devices = found;
      _problem = problem;
      _loading = false;
    });
  }

  Future<void> _choose(PrinterDevice d) async {
    await _settings.setPrinter(d.address, name: d.label);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _forget() async {
    await _settings.setPrinter(null);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final result = await _printer.printTestPage();
    if (!mounted) return;
    setState(() => _testing = false);
    _toast(result.message, good: result.ok);
  }

  void _toast(String message, {bool good = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: good ? AppColors.success : AppColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text(message, style: const TextStyle(color: Colors.white)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _settings.printerAddress;
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
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColors.body, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Receipt printer',
                        style: AppText.screenTitle().copyWith(fontSize: 22)),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.body, size: 20),
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                chosen == null
                    ? 'No printer chosen. Receipts can still be shared as text.'
                    : 'Printing to ${_settings.printerName}',
                style: AppText.body(),
              ),
              const SizedBox(height: AppSpace.gapBlock),
              _overline('Paper width'),
              const SizedBox(height: 8),
              _paperChoice(),
              const SizedBox(height: AppSpace.gapSection),
              _overline('Paired printers'),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_problem != null)
                _message(_problem!)
              else if (_devices.isEmpty)
                _message('Nothing paired yet. Pair the printer in your '
                    "phone's Bluetooth settings, then tap Refresh.")
              else
                _deviceList(chosen),
              const SizedBox(height: AppSpace.gapSection),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: chosen == null || _testing ? null : _test,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.disabledFill,
                    disabledForegroundColor: AppColors.faint,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.cta)),
                  ),
                  icon: Icon(
                      _testing ? Icons.hourglass_top_rounded : Icons.print_outlined,
                      size: 18),
                  label: Text(_testing ? 'Printing…' : 'Print a test receipt',
                      style: AppText.chip(color: Colors.white)
                          .copyWith(fontSize: 15)),
                ),
              ),
              if (chosen != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: TextButton(
                    onPressed: _forget,
                    child: Text('Forget this printer',
                        style: AppText.chip(color: AppColors.dangerText)),
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.gapSection),
              _note(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overline(String text) => Text(text.toUpperCase(),
      style: AppText.caption().copyWith(letterSpacing: 1.1));

  Widget _paperChoice() {
    return Row(
      children: [
        for (final w in PaperWidth.values) ...[
          Expanded(
            child: GestureDetector(
              onTap: () async {
                await _settings.setPaperWidth(w);
                if (mounted) setState(() {});
              },
              child: Container(
                height: 58,
                decoration: BoxDecoration(
                  color: _settings.paperWidth == w
                      ? AppColors.primaryTint
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  border: Border.all(
                    color: _settings.paperWidth == w
                        ? AppColors.primary
                        : AppColors.hairline,
                    width: _settings.paperWidth == w ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(w.label,
                        style: AppText.cardTitle(
                            color: _settings.paperWidth == w
                                ? AppColors.primary
                                : AppColors.ink)),
                    Text('${w.cols} characters', style: AppText.caption()),
                  ],
                ),
              ),
            ),
          ),
          if (w != PaperWidth.values.last) const SizedBox(width: 10),
        ],
      ],
    );
  }

  Widget _deviceList(String? chosen) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < _devices.length; i++) ...[
            ListTile(
              onTap: () => _choose(_devices[i]),
              leading: Icon(
                _devices[i].address == chosen
                    ? Icons.check_circle_rounded
                    : Icons.print_outlined,
                color: _devices[i].address == chosen
                    ? AppColors.success
                    : AppColors.muted,
                size: 22,
              ),
              title: Text(_devices[i].label, style: AppText.cardTitle()),
              subtitle: Text(_devices[i].address, style: AppText.caption()),
            ),
            if (i != _devices.length - 1)
              const Divider(color: AppColors.divider, height: 1),
          ],
        ],
      ),
    );
  }

  Widget _message(String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Text(text, style: AppText.body()),
      );

  Widget _note() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Works with Bluetooth thermal printers that speak ESC/POS — '
                'nearly all of them do. The peso sign prints as "P": no '
                'thermal printer has a ₱ character.',
                style: AppText.caption(),
              ),
            ),
          ],
        ),
      );
}
