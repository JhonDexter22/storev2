import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/shift_model.dart';
import '../services/settings_service.dart';
import '../services/shift_service.dart';
import '../services/staff_service.dart';
import '../services/shift_summary.dart';
import '../widgets/change_pin_flow.dart';
import '../widgets/day_close_view.dart';
import '../l10n/tr.dart';

/// Cash count / end of day — reconcile the drawer and close the shift.
///
/// Counted total, variance and variance colour all derive from the
/// denomination counts; there is no separately-entered total to disagree with.
class CashCountScreen extends StatefulWidget {
  const CashCountScreen({super.key});

  @override
  State<CashCountScreen> createState() => _CashCountScreenState();
}

class _CashCountScreenState extends State<CashCountScreen> {
  final ShiftService _shifts = ShiftService();
  final StaffService _staff = StaffService();

  /// ₱1,000 down to ₱1. Notes first, then coins.
  static const _denominations = [1000, 500, 200, 100, 50, 20, 10, 5, 1];

  /// ₱50 and up circulate as notes; ₱20 and below are coins (the ₱20 note was
  /// replaced by a coin in 2019).
  static const _notesFrom = 50;

  final Map<int, int> _counts = {};

  /// One field per denomination, kept in step with + and −.
  late final Map<int, TextEditingController> _fields = {
    for (final d in _denominations) d: TextEditingController(),
  };

  void _setCount(int value, int count) {
    setState(() => _counts[value] = count);
    final text = count == 0 ? '' : '$count';
    final field = _fields[value]!;
    if (field.text != text) {
      field.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }
  bool _loading = true;
  double _cashSales = 0;

  /// Utang paid back in cash since the last close: in the drawer, though
  /// not a sale.
  double _utangCash = 0;
  double _totalSales = 0;
  int _saleCount = 0;
  DateTime _openedAt = DateTime.now();
  Shift? _closed;
  ShiftSummary? _summary;

  final _settings = SettingsService.instance;
  String get _cashier => _settings.cashier;
  String get _terminal => _settings.terminal;
  double get _openingFloat => _settings.openingFloat;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final drawer = await _shifts.drawerNow();
    final shiftSales = await _shifts.currentShiftSales();
    if (!mounted) return;
    setState(() {
      _cashSales = drawer.cashSales;
      _utangCash = drawer.utangCash;
      _totalSales = shiftSales.total;
      _saleCount = shiftSales.count;
      _openedAt = shiftSales.openedAt;
      _loading = false;
    });
  }

  /// "9:00 PM" for a day opened today, "Yesterday, 9:00 PM" otherwise — the
  /// last close can be days back.
  String get _sinceLabel {
    final now = DateTime.now();
    final clock = TimeOfDay.fromDateTime(_openedAt).format(context);
    final today = _openedAt.year == now.year && _openedAt.month == now.month && _openedAt.day == now.day;
    return today ? clock : '${trRelativeDay(_openedAt)}, $clock';
  }

  double get _expected => _openingFloat + _cashSales + _utangCash;
  double get _counted =>
      _counts.entries.fold<double>(0, (s, e) => s + e.key * e.value);
  double get _variance => _counted - _expected;
  bool get _countingStarted => _counts.values.any((v) => v > 0);

  Color get _varianceColor {
    if (_variance.abs() < 0.005) return AppColors.success;
    return _variance < 0 ? AppColors.danger : AppColors.primary;
  }

  Color get _varianceFill {
    if (_variance.abs() < 0.005) return AppColors.successFill;
    return _variance < 0 ? AppColors.dangerFill : AppColors.primaryTint;
  }

  String get _varianceLabel {
    if (_variance.abs() < 0.005) return tr('Balanced');
    return _variance < 0 ? tr('Short') : tr('Over');
  }

  Future<void> _closeShift() async {
    final passed = await authoriseAsManager(
      context,
      staff: _staff,
      hint: tr('Enter the manager PIN to close the day.'),
      confirmLabel: tr('Confirm close'),
    );
    if (!passed || !mounted) return;

    final shift = await _shifts.closeShift(
      cashier: _cashier,
      terminal: _terminal,
      openingFloat: _openingFloat,
      cashSales: _cashSales,
      utangCash: _utangCash,
      counted: _counted,
      denominations: Map.of(_counts)..removeWhere((_, v) => v == 0),
      totalSales: _totalSales,
      saleCount: _saleCount,
      openedAt: _openedAt,
    );
    // The full report for the owner: sales, payment mix, top sellers, and
    // the drawer that was just counted.
    final summary = await ShiftSummaryService().forShift(shift);
    if (!mounted) return;
    setState(() {
      _closed = shift;
      _summary = summary;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.canvas,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_closed != null && _summary != null) {
      return DayCloseView(
        summary: _summary!,
        onDone: () => Navigator.pop(context, true),
        // Reopens the day rather than starting a second close of it: the
        // close just made is taken back, and the count stays as it was.
        onRecount: () async {
          await _shifts.undoClose(_closed!);
          await _load();
          if (!mounted) return;
          setState(() {
            _closed = null;
            _summary = null;
          });
        },
      );
    }
    if (Breakpoints.isTablet(context)) return _tabletLayout();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 6, AppSpace.screenH, 24),
                children: [
                  _expectedBlock(),
                  const SizedBox(height: AppSpace.gapBlock),
                  Text(tr('Count the drawer'), style: AppText.sectionTitle()),
                  const SizedBox(height: 10),
                  _denominationList(),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  /// Tablet: denominations in two columns so the whole drawer fits without
  /// scrolling, with reconciliation pinned right where the numbers settle.
  Widget _tabletLayout() {
    final half = (_denominations.length / 2).ceil();
    final left = _denominations.take(half).toList();
    final right = _denominations.skip(half).toList();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: Row(
                // Stretch so the pinned column's surface runs the full height
                // rather than stopping under its content.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 6, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Count the drawer'), style: AppText.sectionTitle()),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _denominationCard(left)),
                              const SizedBox(width: 12),
                              Expanded(child: _denominationCard(right)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 344, child: _reconciliationColumn()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _denominationCard(List<int> values) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < values.length; i++) ...[
            _denominationRow(values[i]),
            if (i != values.length - 1) const Divider(color: AppColors.divider, height: 1),
          ],
        ],
      ),
    );
  }

  Widget _reconciliationColumn() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.dividerStrong)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _expectedBlock(),
            const SizedBox(height: AppSpace.gapSection),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('Counted'), style: AppText.body()),
                Flexible(
                  child: Text(formatPeso(_counted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.largeFigure().copyWith(fontSize: 22)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!_countingStarted)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Text(tr('Count the drawer to see the variance.'),
                    textAlign: TextAlign.center, style: AppText.caption()),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _varianceFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _varianceColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_varianceLabel, style: AppText.body(color: _varianceColor)),
                    Text('${_variance > 0 ? '+' : ''}${formatPeso(_variance)}',
                        style: AppText.cardTitle(color: _varianceColor).copyWith(fontSize: 15)),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _countingStarted ? _closeShift : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.disabledFill,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: AppColors.faint,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                child: Text(tr('Close day'),
                    style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
              ),
            ),
            const SizedBox(height: 6),
            Text(tr('Requires a manager PIN'),
                textAlign: TextAlign.center, style: AppText.caption()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 12, AppSpace.screenH, 8),
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
                // The name Home's card, More and this screen's own button use.
                Text(tr('Close day'), style: AppText.screenTitle().copyWith(fontSize: 20)),
                // Which day is being closed, as Home's card puts it; the
                // terminal is on the record and the receipt.
                Text(tr('Since {since} · {name}', {'since': _sinceLabel, 'name': _cashier}),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _expectedBlock() {
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          _row(tr('Opening float'), formatPeso(_openingFloat)),
          const SizedBox(height: 8),
          _row(tr('Cash sales'), formatPeso(_cashSales)),
          if (_utangCash > 0) ...[
            const SizedBox(height: 8),
            _row(tr('Utang paid in cash'), formatPeso(_utangCash)),
          ],
          const SizedBox(height: 10),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('Expected in drawer'), style: AppText.sectionTitle()),
              Flexible(
                child: Text(formatPeso(_expected),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.largeFigure().copyWith(fontSize: 21)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Row(
        children: [
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body()),
          ),
          const SizedBox(width: 8),
          Text(value, style: AppText.cardTitle()),
        ],
      );

  Widget _denominationList() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < _denominations.length; i++) ...[
            _denominationRow(_denominations[i]),
            if (i != _denominations.length - 1)
              const Divider(color: AppColors.divider, height: 1),
          ],
        ],
      ),
    );
  }

  Widget _denominationRow(int value) {
    final count = _counts[value] ?? 0;
    final subtotal = value * count;
    // Zero rows sit back in faint so a counted row reads first.
    final zero = count == 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "₱1,000", as every other figure in the app writes it.
                Text(formatPeso(value).replaceAll('.00', ''),
                    style: AppText.cardTitle(color: zero ? AppColors.faint : AppColors.ink)),
                Text(value >= _notesFrom ? tr('note') : tr('coin'),
                    style: AppText.caption(color: AppColors.faint)),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: QtyStepper(
                value: count,
                compact: true,
                figureSize: 16,
                onDecrement: () {
                  if (count > 0) _setCount(value, count - 1);
                },
                onIncrement: () => _setCount(value, count + 1),
                field: TextField(
                  key: ValueKey('count-$value'),
                  controller: _fields[value],
                  keyboardType: TextInputType.number,
                  textInputAction:
                      value == _denominations.last ? TextInputAction.done : TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  textAlign: TextAlign.center,
                  style: AppText.statFigure(size: 16),
                  onChanged: (v) => setState(() => _counts[value] = int.tryParse(v) ?? 0),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '0',
                    hintStyle: AppText.statFigure(size: 16, color: AppColors.faint),
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.hairline)),
                    enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.hairline)),
                    focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 84,
            child: Text(
              formatPeso(subtotal),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(color: zero ? AppColors.faint : AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screenH,
        12,
        AppSpace.screenH,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('Counted'), style: AppText.body()),
              Flexible(
                child: Text(formatPeso(_counted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.largeFigure().copyWith(fontSize: 22)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Variance appears the moment counting starts, not at the end.
          if (!_countingStarted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Text(
                tr('Count the drawer to see the variance.'),
                textAlign: TextAlign.center,
                style: AppText.caption(),
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _varianceFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _varianceColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_varianceLabel, style: AppText.body(color: _varianceColor)),
                  Text(
                    '${_variance > 0 ? '+' : ''}${formatPeso(_variance)}',
                    style: AppText.cardTitle(color: _varianceColor).copyWith(fontSize: 15),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _countingStarted ? _closeShift : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.disabledFill,
                foregroundColor: Colors.white,
                disabledForegroundColor: AppColors.faint,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
              ),
              child: Text(tr('Close day'), style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
            ),
          ),
          const SizedBox(height: 6),
          Text(tr('Requires a manager PIN'), style: AppText.caption()),
        ],
      ),
    );
  }
}
