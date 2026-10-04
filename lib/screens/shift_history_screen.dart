import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/shift_model.dart';
import '../services/printer_service.dart';
import '../services/receipt_document.dart';
import '../services/settings_service.dart';
import '../services/shift_summary.dart';
import '../widgets/day_close_view.dart';
import '../services/shift_service.dart';
import '../l10n/tr.dart';

/// Closed days — find a short drawer without opening a report.
class ShiftHistoryScreen extends StatefulWidget {
  const ShiftHistoryScreen({super.key});

  @override
  State<ShiftHistoryScreen> createState() => _ShiftHistoryScreenState();
}

enum _Outcome { all, short, over }

class _ShiftHistoryScreenState extends State<ShiftHistoryScreen> {
  final ShiftService _shifts = ShiftService();
  static const _page = 20;

  List<Shift> _list = [];
  bool _loading = true;
  bool _hasMore = false;
  int _totalCloses = 0;
  _Outcome _outcome = _Outcome.all;
  ({double sales, double short, int shortDays, double over, int overDays}) _month =
      (sales: 0, short: 0, shortDays: 0, over: 0, overDays: 0);

  /// Null for everyone.
  String? _cashier;
  List<String> _cashiers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _outcomeKey => switch (_outcome) {
        _Outcome.all => null,
        _Outcome.short => 'short',
        _Outcome.over => 'over',
      };

  Future<void> _load() async {
    final shifts = await _shifts.getShifts(limit: _page, outcome: _outcomeKey, cashier: _cashier);
    final total = await _shifts.closeCount();
    final month = await _shifts.totalsOver(30, cashier: _cashier);
    final cashiers = await _shifts.closingCashiers();
    if (!mounted) return;
    setState(() {
      _cashiers = cashiers;
      _list = shifts;
      _hasMore = shifts.length == _page;
      _totalCloses = total;
      _month = month;
      _loading = false;
    });
  }

  Future<void> _loadOlder() async {
    final more = await _shifts.getShifts(
        limit: _page, offset: _list.length, outcome: _outcomeKey, cashier: _cashier);
    if (!mounted) return;
    setState(() {
      _list = [..._list, ...more];
      _hasMore = more.length == _page;
    });
  }

  void _setOutcome(_Outcome o) {
    if (o == _outcome) return;
    setState(() => _outcome = o);
    _load();
  }

  void _setCashier(String? c) {
    if (c == _cashier) return;
    setState(() => _cashier = c);
    _load();
  }

  static Color _varianceColor(double v) {
    if (v.abs() < 0.005) return AppColors.success;
    return v < 0 ? AppColors.danger : AppColors.primary;
  }

  static Color _varianceFill(double v) {
    if (v.abs() < 0.005) return AppColors.successFill;
    return v < 0 ? AppColors.dangerFill : AppColors.primaryTint;
  }

  static String _varianceWord(double v) {
    if (v.abs() < 0.005) return tr('Balanced');
    return v < 0 ? tr('Short') : tr('Over');
  }

  String _dateLabel(DateTime d) => trDay(d);
  String _weekday(DateTime d) => trWeekday(d.weekday);

  /// A day opens at the previous close, so its window can cross midnight.
  /// "9:00 PM – 9:00 PM" read as no time at all; the opening day is named
  /// when it is not the closing day.
  String _hours(Shift s) {
    final open = s.openedAtDate;
    final close = s.closedAtDate;
    String fmt(DateTime d) => TimeOfDay.fromDateTime(d).format(context);
    if (open == null) return fmt(close);
    final sameDay = open.year == close.year && open.month == close.month && open.day == close.day;
    return sameDay
        ? '${fmt(open)} – ${fmt(close)}'
        : '${trDay(open)} ${fmt(open)} – ${fmt(close)}';
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
                  : _totalCloses == 0
                      ? _empty()
                      : LayoutBuilder(
                          builder: (context, constraints) => ListView(
                          padding: Breakpoints.pagePadding(
                              context, constraints.maxWidth, top: 6),
                          children: [
                            _statTiles(),
                            const SizedBox(height: AppSpace.gapSection),
                            _outcomeChips(),
                            const SizedBox(height: AppSpace.gapSection),
                            if (_list.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: Text(
                                    _outcome == _Outcome.short
                                        ? tr('No short drawers')
                                        : tr('No drawers over'),
                                    style: AppText.body(),
                                  ),
                                ),
                              ),
                            for (final s in _list) ...[
                              _shiftCard(s),
                              const SizedBox(height: 10),
                            ],
                            if (_hasMore)
                              SizedBox(
                                height: 46,
                                child: OutlinedButton(
                                  onPressed: _loadOlder,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.body,
                                    side: const BorderSide(color: AppColors.hairline),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(AppRadius.cta)),
                                  ),
                                  child: Text(tr('Show older'), style: AppText.chip(color: AppColors.body)),
                                ),
                              ),
                          ],
                        ),
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
                Text(tr('Closed days'), style: AppText.screenTitle().copyWith(fontSize: 20)),
                Text(
                  _loading
                      ? tr('Loading…')
                      // Every close, not just the page on screen.
                      : trCount(_totalCloses, '{n} close recorded', '{n} closes recorded'),
                  style: AppText.caption(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Over the last 30 days, and saying so: these used to add up whichever
  /// twenty closes were loaded, under no period at all.
  Widget _statTiles() {
    final m = _month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('LAST 30 DAYS'), style: AppText.overline(color: AppColors.muted)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _tile(tr('Sales'), formatPeso(m.sales), AppColors.ink, AppColors.surface)),
            const SizedBox(width: 8),
            Expanded(
              child: _tile(
                trCount(m.shortDays, 'Short · {n} day', 'Short · {n} days'),
                formatPeso(m.short),
                m.short > 0 ? AppColors.danger : AppColors.ink,
                m.short > 0 ? AppColors.dangerFill : AppColors.surface,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _tile(
                trCount(m.overDays, 'Over · {n} day', 'Over · {n} days'),
                formatPeso(m.over),
                m.over > 0 ? AppColors.primary : AppColors.ink,
                m.over > 0 ? AppColors.primaryTint : AppColors.surface,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _outcomeChips() {
    Widget chip(_Outcome o, String label) {
      final selected = _outcome == o;
      return GestureDetector(
        onTap: () => _setOutcome(o),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          margin: const EdgeInsets.only(right: AppSpace.gapChip),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: selected ? AppColors.ink : AppColors.hairline),
          ),
          child: Text(label, style: AppText.chip(color: selected ? Colors.white : AppColors.body)),
        ),
      );
    }

    Widget person(String? name) {
      final selected = _cashier == name;
      return GestureDetector(
        onTap: () => _setCashier(name),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          margin: const EdgeInsets.only(right: AppSpace.gapChip),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryTint : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: selected ? AppColors.primary : AppColors.hairline),
          ),
          child: Text(name ?? tr('Everyone'),
              style: AppText.chip(color: selected ? AppColors.primary : AppColors.body)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip(_Outcome.all, tr('All')),
              chip(_Outcome.short, tr('Short')),
              chip(_Outcome.over, tr('Over')),
            ],
          ),
        ),
        // Who closes short, when more than one person closes: a pattern the
        // owner otherwise had to spot card by card.
        if (_cashiers.length > 1) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                person(null),
                for (final c in _cashiers) person(c),
              ],
            ),
          ),
        ],
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
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption()),
          const SizedBox(height: 4),
          // Three to a row now, so a large figure shrinks rather than clips.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: AppText.statFigure(color: color, size: 18)),
          ),
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
                              trCount(s.saleCount, '{total} · {n} sale', '{total} · {n} sales', {'total': formatPeso(s.totalSales)}),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(),
                            ),
                          ),
                          Text(tr('View count'), style: AppText.chip(color: AppColors.primary)),
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
                Text(tr('Sales'), style: AppText.body()),
                Text(trCount(s.saleCount, '{total} · {n} sale', '{total} · {n} sales', {'total': formatPeso(s.totalSales)}),
                    style: AppText.cardTitle()),
              ],
            ),
            const SizedBox(height: 16),
            Text(tr('THE DRAWER AS COUNTED'), style: AppText.overline(color: AppColors.muted)),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (denoms.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(tr('No denominations recorded for this close.'),
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
                    _detailRow(tr('Opening float'), formatPeso(s.openingFloat)),
                    const SizedBox(height: 8),
                    _detailRow(tr('Cash sales'), formatPeso(s.cashSales)),
                    const SizedBox(height: 8),
                    if (s.utangCash > 0) ...[
                      _detailRow(tr('Utang paid in cash'), formatPeso(s.utangCash)),
                      const SizedBox(height: 8),
                    ],
                    _detailRow(tr('Expected'), formatPeso(s.expected)),
                    const SizedBox(height: 8),
                    _detailRow(tr('Counted'), formatPeso(s.counted)),
                    const SizedBox(height: 10),
                    const Divider(color: AppColors.divider, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(tr('Variance'), style: AppText.body()),
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
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openReport(s);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                icon: const Icon(Icons.summarize_outlined, size: 16),
                label: Text(tr('Full day report'), style: AppText.chip(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _printSummary(s);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.body,
                  side: const BorderSide(color: AppColors.hairline),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                icon: const Icon(Icons.print_outlined, size: 16),
                label: Text(tr('Print this summary'), style: AppText.chip(color: AppColors.body)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The same end-of-day report the close shows, for any shift in history:
  /// sales, payment mix, top sellers and the drawer, with Send and Print.
  Future<void> _openReport(Shift s) async {
    final summary = await ShiftSummaryService().forShift(s);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => DayCloseView(
          summary: summary,
          title: tr('Day report'),
          onDone: () => Navigator.pop(ctx),
        ),
      ),
    );
  }

  /// Prints the cash count, for the shopkeeper to sign and keep.
  ///
  /// The same slip the drawer was counted against, on paper, so a variance can
  /// be queried the next morning without unlocking the phone.
  Future<void> _printSummary(Shift s) async {
    final result = await PrinterService.instance.printDocument(
      ReceiptDocument.shift(s,
          storeName: SettingsService.instance.storeName),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: result.ok ? AppColors.success : AppColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text(result.message, style: const TextStyle(color: Colors.white)),
    ));
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
            Text(tr('No days closed yet'), style: AppText.cardTitle().copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Text(tr('Close the day from Cash count and it will show up here.'),
                textAlign: TextAlign.center, style: AppText.caption()),
          ],
        ),
      ),
    );
  }
}
