import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design_tokens.dart';
import '../models/customer.dart';
import '../services/settings_service.dart';
import '../services/utang_service.dart';

/// A polite nudge, ready to send. The message is drafted for the shopkeeper
/// and stays editable; it goes by SMS when a number is on file, or through
/// the share sheet (Messenger, Viber) when it is not.
///
/// Returns true when a message was handed to another app, so the caller
/// can reload the "reminded" marker.
Future<bool?> showRemindSheet(BuildContext context, Customer c) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RemindSheet(customer: c),
  );
}

/// The draft. Short, warm, and in the mix of English and Tagalog a sari-sari
/// text actually uses; the shopkeeper can change any of it before sending.
String reminderDraft(Customer c) {
  final store = SettingsService.instance.storeName;
  final since = c.oldestChargeAt;
  final sinceText = since == null ? '' : ' (since ${_day(since)})';
  // The whole name: "Aling Nena" is how she is addressed, and a first-word
  // split would greet her as "Aling".
  return 'Hi ${c.name.trim()}! Friendly reminder from $store: your balance is '
      '${formatPeso(c.balance)}$sinceText. Pwede po bang mabayaran kapag maluwag na? '
      'Salamat po!';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';

class _RemindSheet extends StatefulWidget {
  const _RemindSheet({required this.customer});

  final Customer customer;

  @override
  State<_RemindSheet> createState() => _RemindSheetState();
}

class _RemindSheetState extends State<_RemindSheet> {
  late final TextEditingController _ctrl = TextEditingController(text: reminderDraft(widget.customer));

  Customer get c => widget.customer;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _sent() async {
    await UtangService().markReminded(c.id!);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _sms() async {
    final uri = Uri(scheme: 'sms', path: c.phone, queryParameters: {'body': _ctrl.text});
    try {
      final ok = await launchUrl(uri);
      if (!ok) throw Exception('no handler');
      await _sent();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not open your messages app — try Share instead'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _share() async {
    await SharePlus.instance.share(ShareParams(text: _ctrl.text));
    await _sent();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _ctrl.text));
    HapticFeedback.lightImpact();
    await _sent();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: EdgeInsets.fromLTRB(AppSpace.sheetPad, 14, AppSpace.sheetPad,
            20 + MediaQuery.paddingOf(context).bottom),
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
                decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Remind ${c.name}', style: AppText.sectionTitle().copyWith(fontSize: 18)),
            const SizedBox(height: 2),
            Text(
              '${formatPeso(c.balance)} · ${c.ageLabel}'
              '${c.hasPhone ? ' · ${c.phone}' : ' · no number on file'}',
              style: AppText.caption(),
            ),
            if (c.remindedToday) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: AppColors.warningFill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warningBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 15, color: AppColors.warningText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Already reminded today.', style: AppText.caption(color: AppColors.warningText)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(color: AppColors.hairline),
              ),
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                minLines: 3,
                style: AppText.body(color: AppColors.ink).copyWith(height: 1.45),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text('You can edit the message before sending.', style: AppText.caption(color: AppColors.faint)),
            const SizedBox(height: 16),
            Row(
              children: [
                if (c.hasPhone) ...[
                  Expanded(
                    child: _Btn(icon: Icons.sms_outlined, label: 'Send SMS', onTap: _sms, primary: true),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _Btn(
                    icon: Icons.ios_share_rounded,
                    label: c.hasPhone ? 'Share' : 'Send via Messenger…',
                    onTap: _share,
                    primary: !c.hasPhone,
                  ),
                ),
                const SizedBox(width: 8),
                _Btn(icon: Icons.copy_rounded, label: '', onTap: _copy, tooltip: 'Copy message'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, required this.onTap, this.primary = false, this.tooltip});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppColors.ink;
    final btn = Material(
      color: primary ? AppColors.primary : AppColors.canvas,
      borderRadius: BorderRadius.circular(AppRadius.cta),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.cta),
        onTap: onTap,
        child: Container(
          height: 50,
          padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 15 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.cta),
            border: Border.all(color: primary ? AppColors.primary : AppColors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 7),
                Flexible(
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.chip(color: fg).copyWith(fontSize: 14)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
