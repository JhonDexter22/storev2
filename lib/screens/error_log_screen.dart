import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_info.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/tr.dart';
import '../services/error_log.dart';
import '../services/settings_service.dart';

/// What has gone wrong on this phone, newest first.
///
/// Meant to be read by whoever looks after the app, standing at the counter
/// or from a shared file afterwards. The entries themselves stay in English:
/// they are for fixing, and a translated stack trace helps nobody.
class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({super.key, this.log});

  /// Injectable for tests.
  final ErrorLog? log;

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  late final ErrorLog _log = widget.log ?? ErrorLog.instance;

  @override
  void initState() {
    super.initState();
    // Opening the log is looking at it: the bell on Home stops counting
    // these as new.
    SettingsService.instance.markErrorsSeen();
  }

  /// Entries opened to show their full message and stack.
  final _open = <ErrorEntry>{};

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text(message, style: const TextStyle(color: Colors.white)),
    ));
  }

  /// The screen this is being sent from, for the report's header.
  String _deviceLine() {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    return 'Screen ${size.width.round()}×${size.height.round()} dp · '
        'pixel ratio ${mq.devicePixelRatio.toStringAsFixed(2)} · '
        'text ${mq.textScaler.scale(1).toStringAsFixed(2)}× · '
        'language ${SettingsService.instance.language.name}';
  }

  /// As a text file rather than message text: a long log is cut short by
  /// most chat apps, and a file keeps its line breaks.
  Future<void> _share() async {
    try {
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final file = File(p.join(dir.path,
          'basepoint-errors-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}.txt'));
      await file.writeAsString(_log.toReport(device: _deviceLine()));
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        subject: '${AppInfo.name} error log',
      ));
    } catch (e, st) {
      ErrorLog.caught(e, st, 'sharing the error log');
      if (mounted) _toast(tr('Could not share: {error}', {'error': e}));
    }
  }

  Future<void> _confirmClear() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Clear the error log?'),
            style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: Text(
          tr('Share it first if someone is looking into a problem — once cleared, it is gone.'),
          style: AppText.body(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancel'), style: AppText.chip(color: AppColors.body)),
          ),
          // The dialog says to share first; now it can.
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'share'),
            child: Text(tr('Share first'), style: AppText.chip(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'clear'),
            child: Text(tr('Clear'), style: AppText.chip(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (choice == 'share') await _share();
    if (choice == 'clear') await _log.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: _log,
          builder: (context, _) {
            final entries = _log.entries;
            return LayoutBuilder(
              builder: (context, constraints) => ListView.builder(
                padding: Breakpoints.pagePadding(
                  context,
                  constraints.maxWidth,
                  top: 12,
                  bottom: 32 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount: 2 + (entries.isEmpty ? 1 : entries.length),
                itemBuilder: (context, i) {
                  if (i == 0) return _header(entries.isNotEmpty);
                  if (i == 1) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 14),
                      child: Text(
                        tr('Kept on this phone only. If something goes wrong, share this with whoever looks after the app.'),
                        style: AppText.caption(),
                      ),
                    );
                  }
                  if (entries.isEmpty) return _empty();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _entry(entries[i - 2]),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(bool hasEntries) {
    Widget button(IconData icon, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Icon(icon, color: AppColors.body, size: 18),
            ),
          ),
        );

    return Row(
      children: [
        button(Icons.arrow_back_ios_new_rounded, tr('Back'), () => Navigator.pop(context)),
        const SizedBox(width: 12),
        Expanded(child: Text(tr('Error log'), style: AppText.screenTitle().copyWith(fontSize: 22))),
        if (hasEntries) ...[
          button(Icons.ios_share_rounded, tr('Share'), _share),
          const SizedBox(width: 8),
          button(Icons.delete_outline_rounded, tr('Clear'), _confirmClear),
        ],
      ],
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 28),
          const SizedBox(height: 10),
          Text(tr('Nothing has gone wrong'), style: AppText.cardTitle()),
        ],
      ),
    );
  }

  Widget _entry(ErrorEntry e) {
    final open = _open.contains(e);
    final (label, fg, bg) = switch (e.kind) {
      'flutter' => (tr('Screen'), AppColors.dangerText, AppColors.dangerFill),
      'uncaught' => (tr('Unhandled'), AppColors.dangerText, AppColors.dangerFill),
      _ => (tr('Handled'), AppColors.warningText, AppColors.warningFill),
    };
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => setState(() => open ? _open.remove(e) : _open.add(e)),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(label, style: AppText.chip(color: fg).copyWith(fontSize: 10.5)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.where.isEmpty ? '—' : e.where,
                      style: AppText.caption(color: AppColors.body),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (e.count > 1)
                    Text('×${e.count}', style: AppText.chip(color: AppColors.body)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                e.message,
                style: AppText.body(color: AppColors.ink),
                maxLines: open ? null : 3,
                overflow: open ? null : TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '${trWhen(context, e.at)} · v${e.version}',
                style: AppText.caption(),
              ),
              if (open && e.stack.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(e.stack, style: AppText.mono(size: 10)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
