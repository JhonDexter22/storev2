import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/customer.dart';
import '../models/refund_model.dart';
import '../services/sales_service.dart';
import '../services/utang_service.dart';

/// Reports — what sells, what pays, which category carries the period.
/// Every figure on this screen is scoped to the selected range.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final SalesService _sales = SalesService();
  final UtangService _utangService = UtangService();

  int _days = 1;
  bool _loading = true;

  PeriodStats? _stats;

  /// The revenue card always shows the last seven days, whatever range is
  /// selected — it is a 7-bar chart by spec, not a picture of the range.
  List<double> _week = [];
  List<BreakdownRow> _top = [];
  List<BreakdownRow> _payment = [];
  List<BreakdownRow> _categories = [];
  List<Refund> _refunds = [];
  UtangFlows? _utang;
  List<Customer> _topBalances = [];

  /// A blue ramp, deliberately not the semantic palette — green/amber/red stay
  /// reserved for stock and variance meaning.
  static const _series = [
    AppColors.primary,
    Color(0xFF6B8AF0),
    Color(0xFFA2B6F7),
    Color(0xFFD7DDF5),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await _sales.getPeriodStats(_days);
    final week = _days == 7 ? stats : await _sales.getPeriodStats(7);
    final top = await _sales.topProducts(_days);
    final payment = await _sales.paymentMix(_days);
    final categories = await _sales.categoryMix(_days);
    final refunds = await _sales.getRefunds(_days);
    final utang = await _utangService.getFlows(_days);
    final topBalances = await _utangService.topBalances();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _week = week.dailyRevenue;
      _top = top;
      _utang = utang;
      _topBalances = topBalances;
      _payment = payment;
      _categories = categories;
      _refunds = refunds;
      _loading = false;
    });
  }

  double get _refundTotal => _refunds.fold(0, (s, r) => s + r.amount);
  double get _netRevenue => (_stats?.revenue ?? 0) - _refundTotal;

  String get _rangeLabel => switch (_days) {
        1 => 'Today',
        7 => 'Last 7 days',
        _ => 'Last 30 days',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: Breakpoints.isTablet(context) ? _tabletBody() : _phoneBody(),
              ),
      ),
    );
  }

  Widget _phoneBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 12, AppSpace.screenH, 32),
      children: [
        _header(),
        const SizedBox(height: AppSpace.gapBlock),
        _rangeChips(),
        const SizedBox(height: AppSpace.gapSection),
        _revenueCard(),
        const SizedBox(height: AppSpace.gapBlock),
        _section('Top products'),
        _topProducts(),
        const SizedBox(height: AppSpace.gapBlock),
        _section('Payment mix'),
        _paymentMix(),
        const SizedBox(height: AppSpace.gapBlock),
        _section('Returns'),
        _returns(),
        const SizedBox(height: AppSpace.gapBlock),
        _section('Utang'),
        _utangBlock(),
        const SizedBox(height: AppSpace.gapBlock),
        _section('By category'),
        _byCategory(),
      ],
    );
  }

  /// Tablet: revenue card at 1.5fr beside the stat tiles and payment mix, then
  /// the two leaderboards side by side, so the week, what sells and how people
  /// pay are all readable at once.
  Widget _tabletBody() {
    final s = _stats!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      children: [
        _header(),
        const SizedBox(height: AppSpace.gapSection),
        _rangeChips(),
        const SizedBox(height: AppSpace.gapSection),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _revenueCard()),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _statTile('Transactions', '${s.transactions}')),
                        const SizedBox(width: 10),
                        Expanded(child: _statTile('Avg sale', formatPeso(s.avgSale))),
                        const SizedBox(width: 10),
                        Expanded(child: _statTile('Items', '${s.itemsSold}')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _section('Payment mix'),
                    _paymentMix(),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.gapBlock),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('Top products'),
                  _topProducts(),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('By category'),
                  _byCategory(),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.gapBlock),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('Returns'),
                  _returns(),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section('Utang'),
                  _utangBlock(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption()),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.statFigure(size: 19)),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reports', style: AppText.screenTitle().copyWith(fontSize: 22)),
              Text(_rangeLabel, style: AppText.caption()),
            ],
          ),
        ),
        GestureDetector(
          onTap: _exportNotAvailable,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.file_download_outlined, size: 15, color: AppColors.primary),
                const SizedBox(width: 5),
                Text('Export', style: AppText.chip(color: AppColors.primary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _exportNotAvailable() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: const Text('CSV export is not wired up yet', style: TextStyle(color: Colors.white)),
    ));
  }

  Widget _rangeChips() {
    Widget chip(int days, String label) {
      final selected = _days == days;
      return GestureDetector(
        onTap: () {
          setState(() => _days = days);
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: selected ? AppColors.ink : AppColors.hairline),
          ),
          child: Text(label, style: AppText.chip(color: selected ? Colors.white : AppColors.body)),
        ),
      );
    }

    return Row(
      children: [
        chip(1, 'Today'),
        const SizedBox(width: AppSpace.gapChip),
        chip(7, '7 days'),
        const SizedBox(width: AppSpace.gapChip),
        chip(30, '30 days'),
      ],
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title, style: AppText.sectionTitle()),
      );

  Widget _revenueCard() {
    final s = _stats!;
    final up = s.deltaPct >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.sheetPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.hero),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('REVENUE', style: AppText.overline()),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(formatPeso(s.revenue),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.heroFigure()),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: StatusPill(
                  label: '${up ? '+' : ''}${(s.deltaPct * 100).toStringAsFixed(0)}%',
                  fg: up ? AppColors.successText : AppColors.dangerText,
                  bg: up ? AppColors.successFill : AppColors.dangerFill,
                  dot: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _BarChart(values: _week),
          const SizedBox(height: 8),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _footStat('Transactions', '${s.transactions}'),
              _footStat('Avg sale', formatPeso(s.avgSale)),
              _footStat('Items', '${s.itemsSold}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footStat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
            const SizedBox(height: 2),
            Text(label, style: AppText.caption()),
          ],
        ),
      );

  Widget _emptyCard(String message) => _card(
        padding: const EdgeInsets.all(20),
        child: Center(child: Text(message, textAlign: TextAlign.center, style: AppText.body())),
      );

  Widget _topProducts() {
    if (_top.isEmpty) return _emptyCard('No sales in this range yet');
    final max = _top.first.value;
    return _card(
      child: Column(
        children: [
          for (int i = 0; i < _top.length; i++) ...[
            _barRow(
              label: _top[i].label,
              amount: _top[i].value,
              fraction: max <= 0 ? 0 : _top[i].value / max,
              trailing: '${_top[i].units} sold',
              color: AppColors.primary,
            ),
            if (i != _top.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _utangBlock() {
    final u = _utang;
    if (u == null) return const SizedBox.shrink();
    if (u.outstanding <= 0 && u.charged <= 0 && u.collected <= 0) {
      return _emptyCard(
        'Nothing on credit.\nCharge a sale to a customer from checkout to start the book.',
      );
    }

    // Both bars share one scale so their lengths are comparable.
    final scale = [u.charged, u.collected].reduce((a, b) => a > b ? a : b);
    final grew = u.net > 0;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            // The Outstanding column carries an extra caption line, so without
            // this the two headings sit at different heights.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Outstanding', style: AppText.caption()),
                    const SizedBox(height: 2),
                    Text(formatPeso(u.outstanding),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.statFigure(size: 20)),
                    const SizedBox(height: 2),
                    Text(
                      '${u.customerCount} customer${u.customerCount == 1 ? '' : 's'}',
                      style: AppText.caption(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overdue', style: AppText.caption()),
                    const SizedBox(height: 2),
                    Text(formatPeso(u.overdue),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.statFigure(
                            color: u.overdue > 0 ? AppColors.dangerText : AppColors.ink,
                            size: 20)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 12),
          _flowBar('Charged', u.charged, scale, AppColors.warning),
          const SizedBox(height: 10),
          _flowBar('Collected', u.collected, scale, AppColors.success),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  grew
                      ? 'Book grew by ${formatPeso(u.net.abs())}'
                      : (u.net == 0
                          ? 'Book unchanged'
                          : 'Book shrank by ${formatPeso(u.net.abs())}'),
                  style: AppText.caption(
                      color: grew ? AppColors.warningText : AppColors.successText),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(creditShareLine(u),
                    textAlign: TextAlign.right, style: AppText.caption()),
              ),
            ],
          ),
          if (_topBalances.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: 10),
            for (int i = 0; i < _topBalances.length; i++) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(_topBalances[i].name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
                  ),
                  Text(_statusWord(_topBalances[i].status), style: AppText.caption()),
                  const SizedBox(width: 10),
                  Text(formatPeso(_topBalances[i].balance), style: AppText.cardTitle()),
                ],
              ),
              if (i != _topBalances.length - 1) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  static String _statusWord(UtangStatus s) => switch (s) {
        UtangStatus.overdue => 'Overdue',
        UtangStatus.dueSoon => 'Due soon',
        UtangStatus.current => 'Current',
      };

  Widget _flowBar(String label, double value, double scale, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppText.body())),
            Text(formatPeso(value), style: AppText.cardTitle()),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: scale <= 0 ? 0 : (value / scale).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _byCategory() {
    if (_categories.isEmpty) return _emptyCard('No sales in this range yet');
    final total = _categories.fold<double>(0, (s, c) => s + c.value);
    final max = _categories.first.value;
    return _card(
      child: Column(
        children: [
          for (int i = 0; i < _categories.length; i++) ...[
            _barRow(
              label: _categories[i].label,
              amount: _categories[i].value,
              fraction: max <= 0 ? 0 : _categories[i].value / max,
              trailing: total <= 0
                  ? '0%'
                  : '${(_categories[i].value / total * 100).toStringAsFixed(0)}%',
              color: _series[i % _series.length],
            ),
            if (i != _categories.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _barRow({
    required String label,
    required double amount,
    required double fraction,
    required String trailing,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
            ),
            const SizedBox(width: 8),
            Text(formatPeso(amount), style: AppText.cardTitle()),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: fraction.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(trailing, style: AppText.caption()),
          ],
        ),
      ],
    );
  }

  Widget _paymentMix() {
    if (_payment.isEmpty) return _emptyCard('No payments in this range yet');
    final total = _payment.fold<double>(0, (s, p) => s + p.value);
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (int i = 0; i < _payment.length; i++)
                    Expanded(
                      flex: total <= 0 ? 1 : (_payment[i].value / total * 1000).round().clamp(1, 1000),
                      child: Container(color: _series[i % _series.length]),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < _payment.length; i++) ...[
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _series[i % _series.length],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_payment[i].label, style: AppText.cardTitle())),
                Text(formatPeso(_payment[i].value), style: AppText.body()),
                const SizedBox(width: 10),
                SizedBox(
                  width: 42,
                  child: Text(
                    total <= 0 ? '0%' : '${(_payment[i].value / total * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: AppText.caption(),
                  ),
                ),
              ],
            ),
            if (i != _payment.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  /// Refunds ÷ revenue. A tiny non-zero ratio reads "under 0.1%" rather than
  /// rounding down to a false 0.0%.
  String _refundRateLine() {
    final revenue = _stats?.revenue ?? 0;
    if (revenue <= 0 || _refundTotal <= 0) return 'No refunds in this range';
    final pct = _refundTotal / revenue * 100;
    if (pct < 0.1) return 'Under 0.1% of revenue';
    return '${pct.toStringAsFixed(1)}% of revenue';
  }

  Widget _returns() {
    if (_refunds.isEmpty) {
      return _emptyCard(
        'No returns in this range.\nReturns are recorded from More → Returns & voids.',
      );
    }
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Refunded', style: AppText.caption()),
                    const SizedBox(height: 2),
                    Text('-${formatPeso(_refundTotal)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.statFigure(color: AppColors.dangerText, size: 20)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recorded', style: AppText.caption()),
                    const SizedBox(height: 2),
                    Text('${_refunds.length}', style: AppText.statFigure(size: 20)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Net revenue', style: AppText.caption()),
                    const SizedBox(height: 2),
                    Text(formatPeso(_netRevenue),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.statFigure(size: 20)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_refundRateLine(), style: AppText.caption()),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          // Not capped: the rows must sum to the header total.
          for (int i = 0; i < _refunds.length; i++) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(_refunds[i].saleReference, style: AppText.cardTitle()),
                          if (_refunds[i].isVoid) ...[
                            const SizedBox(width: 6),
                            const StatusPill(
                              label: 'Void',
                              fg: AppColors.dangerText,
                              bg: AppColors.dangerFill,
                              dot: false,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${_refunds[i].reason} · ${_refunds[i].method}', style: AppText.caption()),
                    ],
                  ),
                ),
                Text('-${formatPeso(_refunds[i].amount)}',
                    style: AppText.cardTitle(color: AppColors.dangerText)),
              ],
            ),
            if (i != _refunds.length - 1) const Divider(color: AppColors.divider, height: 18),
          ],
        ],
      ),
    );
  }
}

extension _UtangBlock on _ReportsScreenState {
  /// Share of revenue put on credit for this range. This is **charged ÷
  /// revenue** — outstanding is a running balance and does not belong in a
  /// period ratio.
  String creditShareLine(UtangFlows u) {
    final revenue = _stats?.revenue ?? 0;
    if (revenue <= 0 || u.charged <= 0) return 'Nothing put on credit';
    final pct = u.charged / revenue * 100;
    if (pct < 0.1) return 'Under 0.1% of revenue on credit';
    return '${pct.toStringAsFixed(1)}% of revenue on credit';
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    if (values.isEmpty) return const SizedBox(height: 96);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final now = DateTime.now();
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          final h = maxVal <= 0 ? 0.0 : (values[i] / maxVal) * 60;
          final isLast = i == values.length - 1;
          final dayIdx = (now.weekday - 1 - (values.length - 1 - i)) % 7;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: h < 4 ? 4 : h,
                    decoration: BoxDecoration(
                      color: isLast ? AppColors.primary : const Color(0xFFD7DDF5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
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
}
