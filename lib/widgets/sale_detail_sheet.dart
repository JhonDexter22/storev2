import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/design_tokens.dart';
import '../models/sale_model.dart';
import '../screens/returns_screen.dart';
import '../services/printer_service.dart';
import '../services/receipt_document.dart';
import '../services/settings_service.dart';

/// A receipt, opened from a list of sales: every line, how it was paid, who
/// rang it up, and the three things a shopkeeper does with an old receipt —
/// print it again, send it to the customer, or take something back.
///
/// Returns true when a return was recorded, so the caller can reload.
Future<bool?> showSaleDetail(BuildContext context, Sale sale) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SaleDetailSheet(sale: sale),
  );
}

class _SaleDetailSheet extends StatefulWidget {
  const _SaleDetailSheet({required this.sale});

  final Sale sale;

  @override
  State<_SaleDetailSheet> createState() => _SaleDetailSheetState();
}

class _SaleDetailSheetState extends State<_SaleDetailSheet> {
  bool _printing = false;

  Sale get sale => widget.sale;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _when(BuildContext context) {
    final d = sale.createdAtDate;
    final now = DateTime.now();
    final t = TimeOfDay.fromDateTime(d).format(context);
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    if (sameDay) return 'Today · $t';
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) {
      return 'Yesterday · $t';
    }
    return '${d.day} ${_months[d.month - 1]} · $t';
  }

  IconData get _payIcon {
    final types = SettingsService.instance.paymentTypes;
    for (final t in types) {
      if (t.name.toLowerCase() == sale.paymentMethod.toLowerCase()) return t.icon;
    }
    return Icons.swap_horiz_rounded;
  }

  List<ReceiptBlock> _blocks() => ReceiptDocument.sale(
        storeName: SettingsService.instance.storeName,
        reference: sale.reference,
        time: sale.createdAtDate,
        cashier: sale.cashier,
        items: [
          for (final i in sale.items)
            ReceiptLineItem(name: i.name, qty: i.qty, unitPrice: i.unitPrice, lineTotal: i.lineTotal),
        ],
        subtotal: sale.subtotal,
        total: sale.total,
        method: sale.paymentMethod,
        discountLabel: sale.discountReason,
        discountAmount: sale.discount,
        cashReceived: sale.cashReceived,
        change: sale.changeAmount,
      );

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    final result = await PrinterService.instance.printDocument(_blocks());
    if (!mounted) return;
    setState(() => _printing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: result.ok ? AppColors.success : AppColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text(result.message, style: const TextStyle(color: Colors.white)),
    ));
  }

  Future<void> _share() => SharePlus.instance.share(
        ShareParams(
          text: ReceiptDocument.asText(_blocks()),
          subject: '${SettingsService.instance.storeName} · ${sale.reference}',
        ),
      );

  Future<void> _returnItems() async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ReturnDetailScreen(sale: sale, startAsVoid: false)),
    );
    if (done == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final hasPrinter = PrinterService.instance.hasPrinter;
    final items = sale.items;

    return Container(
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
          // ── Header ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.sheetPad, 18, AppSpace.sheetPad, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_payIcon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatPeso(sale.total), style: AppText.largeFigure().copyWith(fontSize: 24)),
                      const SizedBox(height: 2),
                      Text(
                        '${sale.paymentMethod} · ${_when(context)}'
                        '${sale.cashier.isNotEmpty ? ' · ${sale.cashier}' : ''}',
                        style: AppText.caption(color: AppColors.body),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Text(sale.reference, style: AppText.mono(color: AppColors.body, size: 10.5)),
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),

          // ── Lines ────────────────────────────────────────────────────────
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(AppSpace.sheetPad, 12, AppSpace.sheetPad, 12),
              children: [
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('${sale.itemCount} item${sale.itemCount == 1 ? '' : 's'}',
                        style: AppText.body()),
                  ),
                for (final i in items) _line(i),
                const SizedBox(height: 8),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 10),
                if (sale.discount > 0) ...[
                  _total('Subtotal', formatPeso(sale.subtotal)),
                  _total(
                    sale.discountReason.isEmpty ? 'Discount' : sale.discountReason,
                    '−${formatPeso(sale.discount)}',
                    color: AppColors.successText,
                  ),
                ],
                _total('Total', formatPeso(sale.total), strong: true),
                if (sale.cashReceived > 0) ...[
                  const SizedBox(height: 6),
                  _total('Cash received', formatPeso(sale.cashReceived), muted: true),
                  _total('Change', formatPeso(sale.changeAmount), muted: true),
                ],
              ],
            ),
          ),

          // ── Actions ──────────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.sheetPad, 6, AppSpace.sheetPad,
                16 + MediaQuery.paddingOf(context).bottom),
            child: Row(
              children: [
                if (hasPrinter) ...[
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.print_outlined,
                      label: _printing ? 'Printing…' : 'Reprint',
                      onTap: _printing ? null : _print,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _ActionButton(icon: Icons.ios_share_rounded, label: 'Share', onTap: _share),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.assignment_return_outlined,
                    label: 'Return',
                    onTap: _returnItems,
                    tone: AppColors.dangerText,
                    fill: AppColors.dangerFill,
                    border: AppColors.dangerBorder,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(SaleItem i) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 30),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text('${i.qty}×',
                style: AppText.chip(color: AppColors.body)
                    .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.name, style: AppText.cardTitle(), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (i.qty > 1)
                  Text('@ ${formatPeso(i.unitPrice)} each', style: AppText.caption()),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(formatPeso(i.lineTotal), style: AppText.cardTitle()),
        ],
      ),
    );
  }

  Widget _total(String label, String value, {bool strong = false, bool muted = false, Color? color}) {
    final style = strong
        ? AppText.sectionTitle()
        : muted
            ? AppText.caption()
            : AppText.body(color: color ?? AppColors.body);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value,
              style: (strong ? AppText.statFigure(size: 18) : style.copyWith(color: color))
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone = AppColors.ink,
    this.fill = AppColors.canvas,
    this.border = AppColors.hairline,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color tone;
  final Color fill;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(AppRadius.input),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.input),
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: onTap == null ? AppColors.faint : tone),
              const SizedBox(width: 7),
              Text(label, style: AppText.chip(color: onTap == null ? AppColors.faint : tone)),
            ],
          ),
        ),
      ),
    );
  }
}
