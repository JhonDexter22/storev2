import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../services/sales_service.dart';
import '../l10n/tr.dart';

/// Who gave what away, and why.
///
/// The reason is mandatory at the till; this is where that requirement earns
/// its keep. Grouped first so an outlier stands out, then listed one by one so
/// a specific discount can be matched against a receipt.
class DiscountAudit extends StatelessWidget {
  const DiscountAudit({
    super.key,
    required this.discounts,
    required this.byReason,
    required this.byCashier,
  });

  final List<DiscountRecord> discounts;
  final List<BreakdownRow> byReason;
  final List<BreakdownRow> byCashier;

  @override
  Widget build(BuildContext context) {
    final total = discounts.fold<double>(0, (a, d) => a + d.amount);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(tr('Given away'), style: AppText.body())),
              Text('-${formatPeso(total)}',
                  style: AppText.cardTitle(color: AppColors.warningText)),
            ],
          ),
          const SizedBox(height: 14),
          _breakdown(tr('By reason'), byReason),
          // Only worth the space once more than one person has given one;
          // with a single cashier it just restates the total.
          if (byCashier.length > 1) ...[
            const SizedBox(height: 14),
            _breakdown(tr('By cashier'), byCashier),
          ],
          const SizedBox(height: 14),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          Text(tr('Each discount'), style: AppText.overline()),
          const SizedBox(height: 8),
          for (int i = 0; i < discounts.length; i++) ...[
            _row(context, discounts[i]),
            if (i != discounts.length - 1) ...[
              const SizedBox(height: 8),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _breakdown(String title, List<BreakdownRow> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final max = rows.first.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.overline()),
        const SizedBox(height: 8),
        for (int i = 0; i < rows.length; i++) ...[
          _bar(rows[i], max),
          if (i != rows.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _bar(BreakdownRow row, double max) {
    final sales = trCount(row.units, '{n} sale', '{n} sales');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(row.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle()),
            ),
            const SizedBox(width: 8),
            Text(formatPeso(row.value), style: AppText.cardTitle()),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: max <= 0 ? 0 : (row.value / max).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: AppColors.divider,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.warning),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(sales, style: AppText.caption()),
          ],
        ),
      ],
    );
  }

  Widget _row(BuildContext context, DiscountRecord d) {
    final time = TimeOfDay.fromDateTime(d.at).format(context);
    // Sales taken before cashiers were recorded say so, rather than being
    // pinned on whoever happens to be signed in now.
    final who = d.cashier.isEmpty ? tr('cashier not recorded') : d.cashier;
    final reason = d.reason.isEmpty ? tr('No reason given') : d.reason;
    final percent = (d.share * 100).toStringAsFixed(0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reason,
                  style: AppText.cardTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${d.reference} · $time · $who',
                  style: AppText.caption(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('-${formatPeso(d.amount)}',
                style: AppText.cardTitle(color: AppColors.warningText)),
            const SizedBox(height: 2),
            Text(tr('{pct}% of {amount}', {'pct': percent, 'amount': formatPeso(d.subtotal)}),
                style: AppText.caption()),
          ],
        ),
      ],
    );
  }
}
