import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design_tokens.dart';
import '../models/customer.dart';
import '../services/utang_service.dart';

/// One customer's book: the running balance, every charge and payment,
/// and the things done from here — remind, take a payment, call, edit.
///
/// Actions that change the ledger are handed back to the caller through
/// [onRecordPayment] / [onRemind] / [onEdit], which own the flows already.
/// Completes with true if anything changed.
Future<bool?> showCustomerLedger(
  BuildContext context,
  Customer c, {
  required Future<bool> Function() onRecordPayment,
  required Future<bool> Function() onRemind,
  required Future<bool> Function() onEdit,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LedgerSheet(
      customer: c,
      onRecordPayment: onRecordPayment,
      onRemind: onRemind,
      onEdit: onEdit,
    ),
  );
}

class _LedgerSheet extends StatefulWidget {
  const _LedgerSheet({
    required this.customer,
    required this.onRecordPayment,
    required this.onRemind,
    required this.onEdit,
  });

  final Customer customer;
  final Future<bool> Function() onRecordPayment;
  final Future<bool> Function() onRemind;
  final Future<bool> Function() onEdit;

  @override
  State<_LedgerSheet> createState() => _LedgerSheetState();
}

class _LedgerSheetState extends State<_LedgerSheet> {
  final UtangService _utang = UtangService();
  late Customer _c = widget.customer;
  List<UtangEntry> _entries = [];
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _utang.getEntries(_c.id!);
    final fresh = await _utang.getCustomer(_c.id!);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      if (fresh != null) _c = fresh;
      _loading = false;
    });
  }

  Future<void> _run(Future<bool> Function() action) async {
    final changed = await action();
    if (!mounted) return;
    if (changed) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _call() async {
    final uri = Uri(scheme: 'tel', path: _c.phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      // No dialler on this device; the number is on screen to type.
    }
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _when(DateTime d) {
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final t = TimeOfDay.fromDateTime(d).format(context);
    return sameDay ? 'Today · $t' : '${d.day} ${_months[d.month - 1]} · $t';
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final owing = c.balance > 0;
    final status = c.status;
    final tone = switch (status) {
      UtangStatus.overdue => AppColors.dangerText,
      UtangStatus.dueSoon => AppColors.warningText,
      UtangStatus.current => AppColors.successText,
    };
    final fill = switch (status) {
      UtangStatus.overdue => AppColors.dangerFill,
      UtangStatus.dueSoon => AppColors.warningFill,
      UtangStatus.current => AppColors.successFill,
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
            ),
            // ── Header ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.sheetPad, 18, AppSpace.sheetPad, 12),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(c.initials, style: AppText.statFigure(color: tone, size: 17)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sectionTitle()),
                        const SizedBox(height: 2),
                        Text(
                          c.hasPhone ? c.phone! : 'No number on file',
                          style: AppText.caption(color: c.hasPhone ? AppColors.body : AppColors.faint),
                        ),
                      ],
                    ),
                  ),
                  if (c.hasPhone)
                    IconButton(
                      tooltip: 'Call',
                      onPressed: _call,
                      icon: const Icon(Icons.call_outlined, color: AppColors.primary),
                    ),
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: () => _run(widget.onEdit),
                    icon: const Icon(Icons.edit_outlined, color: AppColors.body),
                  ),
                ],
              ),
            ),
            // ── Balance ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sheetPad),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.cardPad),
                decoration: BoxDecoration(
                  color: owing ? fill : AppColors.canvas,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(owing ? 'OWES' : 'SETTLED', style: AppText.overline(color: owing ? tone : AppColors.muted)),
                          const SizedBox(height: 2),
                          Text(formatPeso(c.balance), style: AppText.largeFigure(color: owing ? tone : AppColors.ink)),
                          const SizedBox(height: 2),
                          Text(
                            owing
                                ? '${c.ageLabel}${c.lastRemindedAt != null ? ' · reminded ${_when(c.lastRemindedAt!)}' : ''}'
                                : 'Nothing outstanding',
                            style: AppText.caption(color: owing ? tone : AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // ── Ledger ─────────────────────────────────────────────────
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    )
                  : _entries.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('No charges or payments yet.', style: AppText.body()),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(AppSpace.sheetPad, 0, AppSpace.sheetPad, 8),
                          itemCount: _entries.length,
                          separatorBuilder: (_, __) => const Divider(color: AppColors.divider, height: 1),
                          itemBuilder: (_, i) => _entryRow(_entries[i]),
                        ),
            ),
            // ── Actions ────────────────────────────────────────────────
            if (owing)
              Padding(
                padding: EdgeInsets.fromLTRB(AppSpace.sheetPad, 8, AppSpace.sheetPad,
                    16 + MediaQuery.paddingOf(context).bottom),
                child: Row(
                  children: [
                    Expanded(
                      child: _action(Icons.notifications_none_rounded, 'Remind', () => _run(widget.onRemind)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _action(Icons.payments_outlined, 'Record payment', () => _run(widget.onRecordPayment),
                          primary: true),
                    ),
                  ],
                ),
              )
            else
              SizedBox(height: 16 + MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }

  Widget _entryRow(UtangEntry e) {
    final charge = e.isCharge;
    final detail = charge
        ? (e.note?.isNotEmpty == true ? e.note! : (e.saleId != null ? 'Sale on tab' : 'Charge'))
        : 'Paid by ${e.method ?? 'cash'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: charge ? AppColors.warningFill : AppColors.successFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              charge ? Icons.add_shopping_cart_rounded : Icons.check_rounded,
              size: 17,
              color: charge ? AppColors.warningText : AppColors.successText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
                const SizedBox(height: 2),
                Text(_when(e.createdAtDate), style: AppText.caption()),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${charge ? '+' : '−'}${formatPeso(e.amount.abs())}',
            style: AppText.cardTitle(color: charge ? AppColors.ink : AppColors.successText),
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap, {bool primary = false}) {
    final fg = primary ? Colors.white : AppColors.ink;
    return Material(
      color: primary ? AppColors.primary : AppColors.canvas,
      borderRadius: BorderRadius.circular(AppRadius.cta),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.cta),
        onTap: onTap,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.cta),
            border: Border.all(color: primary ? AppColors.primary : AppColors.hairline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 7),
              Flexible(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.chip(color: fg).copyWith(fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
