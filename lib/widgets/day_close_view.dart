import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/design_tokens.dart';
import '../services/printer_service.dart';
import '../services/receipt_document.dart';
import '../services/settings_service.dart';
import '../services/shift_summary.dart';

/// The end-of-day report on screen: what the owner would ask about if they
/// were standing at the counter, then the ways to hand it to them when they
/// are not. Used after a close, and for any past shift from history.
class DayCloseView extends StatefulWidget {
  const DayCloseView({
    super.key,
    required this.summary,
    required this.onDone,
    this.onRecount,
    this.title = 'Day closed',
  });

  final ShiftSummary summary;
  final VoidCallback onDone;

  /// Only offered right after a close, while the drawer is still open.
  final VoidCallback? onRecount;
  final String title;

  @override
  State<DayCloseView> createState() => _DayCloseViewState();
}

class _DayCloseViewState extends State<DayCloseView> {
  bool _printing = false;

  ShiftSummary get sum => widget.summary;

  List<ReceiptBlock> _blocks() =>
      ReceiptDocument.dayClose(sum, storeName: SettingsService.instance.storeName);

  Future<void> _share() => SharePlus.instance.share(
        ShareParams(
          text: ReceiptDocument.asText(_blocks()),
          subject: '${SettingsService.instance.storeName} · End of day',
        ),
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

  @override
  Widget build(BuildContext context) {
    final shift = sum.shift;
    final variance = shift?.variance ?? 0;
    final balanced = variance.abs() < 0.005;
    final tone = balanced
        ? AppColors.success
        : variance < 0
            ? AppColors.danger
            : AppColors.primary;
    final fill = balanced
        ? AppColors.successFill
        : variance < 0
            ? AppColors.dangerFill
            : AppColors.primaryTint;
    final hasPrinter = PrinterService.instance.hasPrinter;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 28, AppSpace.screenH, 16),
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                      child: Icon(Icons.check_rounded, color: tone, size: 38),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(child: Text(widget.title, style: AppText.sectionTitle().copyWith(fontSize: 19))),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      '${_clock(sum.from)} – ${_clock(sum.to)}'
                      '${shift != null ? ' · ${shift.cashier}' : ''}',
                      style: AppText.caption(),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // ── Headline ───────────────────────────────────────────
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SALES', style: AppText.overline(color: AppColors.muted)),
                        const SizedBox(height: 4),
                        Text(formatPeso(sum.revenue), style: AppText.heroFigure()),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _stat('${sum.transactions}', sum.transactions == 1 ? 'sale' : 'sales'),
                            _rule(),
                            _stat('${sum.items}', 'items'),
                            _rule(),
                            _stat(formatPeso(sum.averageSale), 'avg sale'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Payment mix ────────────────────────────────────────
                  if (sum.byMethod.isNotEmpty) ...[
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PAID BY', style: AppText.overline(color: AppColors.muted)),
                          const SizedBox(height: 8),
                          for (final m in sum.byMethod) ...[
                            _row('${m.label} · ${m.units}', formatPeso(m.value)),
                            _bar(sum.revenue == 0 ? 0 : m.value / sum.revenue,
                                m.label.toLowerCase() == 'utang' ? AppColors.warning : AppColors.primary),
                            const SizedBox(height: 8),
                          ],
                          if (sum.utangCharged > 0)
                            Text(
                              '${formatPeso(sum.utangCharged)} of this is on tab — owed, not in the drawer.',
                              style: AppText.caption(color: AppColors.warningText),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Top products ───────────────────────────────────────
                  if (sum.topProducts.isNotEmpty) ...[
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TOP SELLERS', style: AppText.overline(color: AppColors.muted)),
                          const SizedBox(height: 6),
                          for (final t in sum.topProducts)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  Container(
                                    constraints: const BoxConstraints(minWidth: 32),
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.canvas,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text('${t.units}×', style: AppText.chip(color: AppColors.body)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(t.label,
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
                                  ),
                                  Text(formatPeso(t.value), style: AppText.cardTitle()),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Given away / handed back ───────────────────────────
                  if (sum.discounts > 0 || sum.refunds > 0) ...[
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('OUT', style: AppText.overline(color: AppColors.muted)),
                          const SizedBox(height: 8),
                          if (sum.discounts > 0)
                            _row('Discounts given', '−${formatPeso(sum.discounts)}', color: AppColors.warningText),
                          if (sum.refunds > 0)
                            _row('Refunds · ${sum.refundCount}', '−${formatPeso(sum.refunds)}',
                                color: AppColors.dangerText),
                          const SizedBox(height: 6),
                          const Divider(color: AppColors.divider, height: 1),
                          const SizedBox(height: 8),
                          _row('Net sales', formatPeso(sum.net), strong: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Cash drawer ────────────────────────────────────────
                  if (shift != null)
                    _card(
                      tint: fill,
                      border: tone.withValues(alpha: 0.25),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CASH DRAWER', style: AppText.overline(color: tone)),
                          const SizedBox(height: 8),
                          _row('Opening float', formatPeso(shift.openingFloat)),
                          _row('Cash sales', formatPeso(shift.cashSales)),
                          _row('Expected', formatPeso(shift.expected)),
                          _row('Counted', formatPeso(shift.counted)),
                          const SizedBox(height: 6),
                          Divider(color: tone.withValues(alpha: 0.2), height: 1),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(balanced ? 'Balanced' : (variance < 0 ? 'Short' : 'Over'),
                                  style: AppText.cardTitle(color: tone)),
                              Text(
                                '${variance > 0 ? '+' : ''}${formatPeso(variance)}',
                                style: AppText.largeFigure(color: tone).copyWith(fontSize: 26),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // ── Actions ─────────────────────────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(AppSpace.screenH, 12, AppSpace.screenH,
                  16 + MediaQuery.paddingOf(context).bottom),
              decoration: const BoxDecoration(
                color: AppColors.canvas,
                border: Border(top: BorderSide(color: AppColors.hairline)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _action(Icons.ios_share_rounded, 'Send to owner', _share, primary: true),
                      ),
                      if (hasPrinter) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: _action(Icons.print_outlined, _printing ? 'Printing…' : 'Print',
                              _printing ? null : _print),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (widget.onRecount != null) ...[
                        Expanded(child: _action(Icons.replay_rounded, 'Recount', widget.onRecount)),
                        const SizedBox(width: 8),
                      ],
                      Expanded(child: _action(Icons.check_rounded, 'Done', widget.onDone)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child, Color? tint, Color? border}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: tint ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: border ?? AppColors.hairline),
      ),
      child: child,
    );
  }

  Widget _stat(String value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: AppText.statFigure(size: 17))),
            Text(label, style: AppText.caption()),
          ],
        ),
      );

  Widget _rule() => Container(width: 1, height: 28, color: AppColors.divider, margin: const EdgeInsets.only(right: 12));

  Widget _row(String label, String value, {bool strong = false, Color? color}) {
    final style = strong ? AppText.cardTitle() : AppText.body(color: color ?? AppColors.body);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(value,
              style: (strong ? AppText.statFigure(size: 16) : style)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _bar(double fraction, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(
          children: [
            Container(color: AppColors.divider),
            FractionallySizedBox(widthFactor: fraction.clamp(0, 1), child: Container(color: color)),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap, {bool primary = false}) {
    final fg = primary ? Colors.white : (onTap == null ? AppColors.faint : AppColors.ink);
    return Material(
      color: primary ? AppColors.primary : AppColors.surface,
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
              Text(label, style: AppText.chip(color: fg).copyWith(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }
}
