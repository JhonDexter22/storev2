import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/shift_model.dart';
import '../services/sales_service.dart';
import '../services/settings_service.dart';
import '../services/shift_service.dart';
import '../widgets/pin_sheet.dart';

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
  final SalesService _sales = SalesService();
  final ShiftService _shifts = ShiftService();

  /// ₱1,000 down to ₱1. Notes first, then coins.
  static const _denominations = [1000, 500, 200, 100, 50, 20, 10, 5, 1];

  /// ₱50 and up circulate as notes; ₱20 and below are coins (the ₱20 note was
  /// replaced by a coin in 2019).
  static const _notesFrom = 50;

  final Map<int, int> _counts = {};
  bool _loading = true;
  double _cashSales = 0;
  double _totalSales = 0;
  int _saleCount = 0;
  DateTime _openedAt = DateTime.now();
  Shift? _closed;

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
    final cash = await _sales.cashSalesToday();
    final shiftSales = await _shifts.currentShiftSales();
    if (!mounted) return;
    setState(() {
      _cashSales = cash;
      _totalSales = shiftSales.total;
      _saleCount = shiftSales.count;
      _openedAt = shiftSales.openedAt;
      _loading = false;
    });
  }

  double get _expected => _openingFloat + _cashSales;
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
    if (_variance.abs() < 0.005) return 'Drawer balances';
    return _variance < 0 ? 'Short' : 'Over';
  }

  /// Fills a drawer that balances exactly, greedily from the largest note.
  void _countExact() {
    var remaining = _expected.round();
    final next = <int, int>{};
    for (final d in _denominations) {
      final n = remaining ~/ d;
      if (n > 0) {
        next[d] = n;
        remaining -= n * d;
      }
    }
    setState(() {
      _counts
        ..clear()
        ..addAll(next);
    });
  }

  Future<void> _closeShift() async {
    final passed = await PinSheet.show(context, expectedPin: PinSheet.managerPin);
    if (!passed || !mounted) return;

    final shift = await _shifts.closeShift(
      cashier: _cashier,
      terminal: _terminal,
      openingFloat: _openingFloat,
      cashSales: _cashSales,
      counted: _counted,
      denominations: Map.of(_counts)..removeWhere((_, v) => v == 0),
      totalSales: _totalSales,
      saleCount: _saleCount,
      openedAt: _openedAt,
    );
    if (!mounted) return;
    setState(() => _closed = shift);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.canvas,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    if (_closed != null) return _closedView(_closed!);

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
                  Text('Count the drawer', style: AppText.sectionTitle()),
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
                Text('Cash count', style: AppText.screenTitle().copyWith(fontSize: 20)),
                Text('$_terminal · $_cashier', style: AppText.caption()),
              ],
            ),
          ),
          GestureDetector(
            onTap: _countExact,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text('Count exact', style: AppText.chip(color: AppColors.primary)),
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
          _row('Opening float', formatPeso(_openingFloat)),
          const SizedBox(height: 8),
          _row('Cash sales', formatPeso(_cashSales)),
          const SizedBox(height: 10),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Expected in drawer', style: AppText.sectionTitle()),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body()),
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
                Text('₱$value',
                    style: AppText.cardTitle(color: zero ? AppColors.faint : AppColors.ink)),
                Text(value >= _notesFrom ? 'note' : 'coin',
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
                  if (count > 0) setState(() => _counts[value] = count - 1);
                },
                onIncrement: () => setState(() => _counts[value] = count + 1),
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
              Text('Counted', style: AppText.body()),
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
                'Count the drawer to see the variance.',
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
              child: Text('Close shift', style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
            ),
          ),
          const SizedBox(height: 6),
          Text('Requires a manager PIN', style: AppText.caption()),
        ],
      ),
    );
  }

  Widget _closedView(Shift shift) {
    final color = shift.variance.abs() < 0.005
        ? AppColors.success
        : (shift.variance < 0 ? AppColors.danger : AppColors.primary);
    final fill = shift.variance.abs() < 0.005
        ? AppColors.successFill
        : (shift.variance < 0 ? AppColors.dangerFill : AppColors.primaryTint);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 32, AppSpace.screenH, 24),
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, color: color, size: 44),
              ),
              const SizedBox(height: 18),
              Text('Shift closed', style: AppText.sectionTitle().copyWith(fontSize: 19)),
              const SizedBox(height: 4),
              Text('${shift.terminal} · ${shift.cashier}', style: AppText.caption()),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.cardPad),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  children: [
                    _row('Opening float', formatPeso(shift.openingFloat)),
                    const SizedBox(height: 8),
                    _row('Cash sales', formatPeso(shift.cashSales)),
                    const SizedBox(height: 8),
                    _row('Expected', formatPeso(shift.expected)),
                    const SizedBox(height: 8),
                    _row('Counted', formatPeso(shift.counted)),
                    const SizedBox(height: 10),
                    const Divider(color: AppColors.divider, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Variance', style: AppText.body()),
                        Flexible(
                          child: Text(
                            '${shift.variance > 0 ? '+' : ''}${formatPeso(shift.variance)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.largeFigure(color: color).copyWith(fontSize: 30),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => setState(() => _closed = null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.body,
                    side: const BorderSide(color: AppColors.hairline),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                  ),
                  child: Text('Recount drawer', style: AppText.chip(color: AppColors.body).copyWith(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                  ),
                  child: Text('Done', style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
