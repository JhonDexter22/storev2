import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../l10n/tr.dart';
import '../services/sales_service.dart';
import '../services/settings_service.dart';

/// Daily revenue as bars, newest on the right and highlighted.
///
/// One widget for Home and Reports. Each used to draw its own copy, and both
/// showed seven days whatever range was picked; fixed once here, it stays
/// fixed in both.
///
/// Up to seven bars carry a day letter each. More than that — the 30-day
/// range — become thin bars with the first date and "Today" at the ends,
/// since thirty letters would not fit. [caption] sits above, for when the
/// chart is context rather than the period itself (seven days under Today).
class SalesBarChart extends StatelessWidget {
  const SalesBarChart({super.key, required this.values, this.caption});

  final List<double> values;
  final String? caption;

  static const _past = Color(0xFFD7DDF5);

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox(height: 96);
    final month = values.length > 7;
    final maxVal = values.reduce((a, b) => a > b ? a : b).clamp(1, double.infinity);
    final now = DateTime.now();

    Widget bar(int i) {
      final h = (values[i] / maxVal) * 60;
      return Container(
        height: h < 4 ? 4 : h,
        decoration: BoxDecoration(
          color: i == values.length - 1 ? AppColors.primary : _past,
          borderRadius: BorderRadius.circular(month ? 2 : 4),
        ),
      );
    }

    final Widget chart;
    if (month) {
      final first = now.subtract(Duration(days: values.length - 1));
      chart = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: bar(i),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(trDay(first), style: AppText.caption()),
              const Spacer(),
              Text(tr('Today'), style: AppText.caption()),
            ],
          ),
        ],
      );
    } else {
      // Monday first. Lunes, Martes, Miyerkules, Huwebes, Biyernes, Sabado,
      // Linggo.
      final days = SettingsService.instance.language == AppLanguage.fil
          ? const ['L', 'M', 'M', 'H', 'B', 'S', 'L']
          : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      chart = SizedBox(
        height: 96,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(values.length, (i) {
            final dayIdx = (now.weekday - 1 - (values.length - 1 - i)) % 7;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    bar(i),
                    const SizedBox(height: 6),
                    Text(days[(dayIdx + 7) % 7], style: AppText.caption()),
                  ],
                ),
              ),
            );
          }),
        ),
      );
    }

    if (caption == null) return chart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption!, style: AppText.caption()),
        const SizedBox(height: 4),
        chart,
      ],
    );
  }
}

/// "+12% vs yesterday" — or nothing, when the period before had no sales.
/// With nothing to compare against it used to read +100% on a store's first
/// day, and it never said what it was compared with.
class PeriodComparison extends StatelessWidget {
  const PeriodComparison({super.key, required this.stats, required this.days});

  final PeriodStats stats;

  /// 1, 7 or 30.
  final int days;

  @override
  Widget build(BuildContext context) {
    if (stats.previousRevenue <= 0) return const SizedBox.shrink();
    final up = stats.deltaPct >= 0;
    final pct = '${up ? '+' : ''}${(stats.deltaPct * 100).toStringAsFixed(0)}%';
    return StatusPill(
      label: switch (days) {
        1 => tr('{pct} vs yesterday', {'pct': pct}),
        7 => tr('{pct} vs previous 7 days', {'pct': pct}),
        _ => tr('{pct} vs previous 30 days', {'pct': pct}),
      },
      fg: up ? AppColors.successText : AppColors.dangerText,
      bg: up ? AppColors.successFill : AppColors.dangerFill,
      dot: false,
    );
  }
}
