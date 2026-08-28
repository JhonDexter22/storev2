import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/shift_model.dart';
import '../services/shift_service.dart';

/// Shift history — find a short drawer without opening a report.
class ShiftHistoryScreen extends StatefulWidget {
  const ShiftHistoryScreen({super.key});

  @override
  State<ShiftHistoryScreen> createState() => _ShiftHistoryScreenState();
}

class _ShiftHistoryScreenState extends State<ShiftHistoryScreen> {
  final ShiftService _shifts = ShiftService();
  List<Shift> _list = [];
  bool _loading = true;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shifts = await _shifts.getShifts();
    if (!mounted) return;
    setState(() {
      _list = shifts;
      _loading = false;
    });
  }

  double get _totalSales => _list.fold(0, (s, x) => s + x.totalSales);
  double get _netVariance => _list.fold(0, (s, x) => s + x.variance);

  static Color _varianceColor(double v) {
    if (v.abs() < 0.005) return AppColors.success;
    return v < 0 ? AppColors.danger : AppColors.primary;
  }

  static Color _varianceFill(double v) {
    if (v.abs() < 0.005) return AppColors.successFill;
    return v < 0 ? AppColors.dangerFill : AppColors.primaryTint;
  }

  static String _varianceWord(double v) {
    if (v.abs() < 0.005) return 'Exact';
    return v < 0 ? 'Short' : 'Over';
  }

  String _dateLabel(DateTime d) => '${d.day} ${_months[d.month - 1]}';
  String _weekday(DateTime d) => _weekdays[d.weekday - 1];

  String _hours(Shift s) {
    final open = s.openedAtDate;
    final close = s.closedAtDate;
    String fmt(DateTime d) => TimeOfDay.fromDateTime(d).format(context);
    if (open == null) return fmt(close);
    return '${fmt(open)} – ${fmt(close)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _list.isEmpty
                      ? _empty()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 6, AppSpace.screenH, 32),
                          children: [
                            _statTiles(),
                            const SizedBox(height: AppSpace.gapBlock),
                            for (final s in _list) ...[
                              _shiftCard(s),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 12, AppSpace.screenH, 12),
      child: Row(
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
                Text('Shift history', style: AppText.screenTitle().copyWith(fontSize: 20)),
                Text(
                  _loading
                      ? 'Loading…'
                      : '${_list.length} close${_list.length == 1 ? '' : 's'} recorded',
                  style: AppText.caption(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTiles() {
    return Row(
      children: [
        Expanded(child: _tile('Sales', formatPeso(_totalSales), AppColors.ink, AppColors.surface)),
        const SizedBox(width: 10),
        Expanded(
          child: _tile(
            'Net variance',
            '${_netVariance > 0 ? '+' : ''}${formatPeso(_netVariance)}',
            _varianceColor(_netVariance),
            _netVariance.abs() < 0.005 ? AppColors.surface : _varianceFill(_netVariance),
          ),
        ),
      ],
    );
  }

  Widget _tile(String label, String value, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: bg,
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
              style: AppText.statFigure(color: color, size: 20)),
        ],
      ),
    );
  }

  Widget _shiftCard(Shift s) {
    final color = _varianceColor(s.variance);
    return GestureDetector(
      onTap: () => _openDetail(s),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.hairline),
          boxShadow: AppShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Semantic bar: the drawer outcome readable before any text.
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.cardPad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${_dateLabel(s.closedAtDate)} · ${_weekday(s.closedAtDate)}',
                                    style: AppText.cardTitle()),
                                const SizedBox(height: 2),
                                Text('${s.cashier} · ${_hours(s)}', style: AppText.caption()),
                              ],
                            ),
                          ),
                          StatusPill(
                            label:
                                '${_varianceWord(s.variance)}${s.variance.abs() < 0.005 ? '' : ' ${formatPeso(s.variance.abs())}'}',
                            fg: color,
                            bg: _varianceFill(s.variance),
                            dot: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Divider(color: AppColors.divider, height: 1),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${formatPeso(s.totalSales)} · ${s.saleCount} sale${s.saleCount == 1 ? '' : 's'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(),
                            ),
                          ),
                          Text('View count', style: AppText.chip(color: AppColors.primary)),
                          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(Shift s) {
    final color = _varianceColor(s.variance);
    final denoms = s.denominations.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        padding: EdgeInsets.fromLTRB(
          AppSpace.sheetPad, 14, AppSpace.sheetPad, 20 + MediaQuery.of(ctx).padding.bottom),
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
                decoration:
                    BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('${_dateLabel(s.closedAtDate)} · ${_weekday(s.closedAtDate)}',
                style: AppText.sectionTitle().copyWith(fontSize: 18)),
            const SizedBox(height: 2),
            Text('${s.cashier} · ${s.terminal} · ${_hours(s)}', style: AppText.caption()),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Sales', style: AppText.body()),
                Text('${formatPeso(s.totalSales)} · ${s.saleCount} sale${s.saleCount == 1 ? '' : 's'}',
                    style: AppText.cardTitle()),
              ],
            ),
            const SizedBox(height: 16),
            Text('THE DRAWER AS COUNTED', style: AppText.overline(color: AppColors.muted)),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (denoms.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('No denominations recorded for this close.',
                            style: AppText.caption()),
                      ),
                    // Stored per denomination, so this always sums to counted.
                    for (final d in denoms)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            SizedBox(width: 76, child: Text('₱${d.key}', style: AppText.body())),
                            Expanded(child: Text('×${d.value}', style: AppText.caption())),
                            Text(formatPeso(d.key * d.value), style: AppText.body()),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    const Divider(color: AppColors.divider, height: 1),
                    const SizedBox(height: 10),
                    _detailRow('Opening float', formatPeso(s.openingFloat)),
                    const SizedBox(height: 8),
                    _detailRow('Cash sales', formatPeso(s.cashSales)),
                    const SizedBox(height: 8),
                    _detailRow('Expected', formatPeso(s.expected)),
                    const SizedBox(height: 8),
                    _detailRow('Counted', formatPeso(s.counted)),
                    const SizedBox(height: 10),
                    const Divider(color: AppColors.divider, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Variance', style: AppText.body()),
                        Text('${s.variance > 0 ? '+' : ''}${formatPeso(s.variance)}',
                            style: AppText.largeFigure(color: color).copyWith(fontSize: 24)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.ink,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    content: const Text('Receipt printing is not wired up yet',
                        style: TextStyle(color: Colors.white)),
                  ));
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.body,
                  side: const BorderSide(color: AppColors.hairline),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                icon: const Icon(Icons.print_outlined, size: 16),
                label: Text('Print this summary', style: AppText.chip(color: AppColors.body)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body()),
          Text(value, style: AppText.cardTitle()),
        ],
      );

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration:
                  BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.history_rounded, color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 14),
            Text('No shifts closed yet', style: AppText.cardTitle().copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Text('Close a drawer from Cash count and it will show up here.',
                textAlign: TextAlign.center, style: AppText.caption()),
          ],
        ),
      ),
    );
  }
}
