import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/refund_model.dart';
import '../models/sale_model.dart';
import '../services/sales_service.dart';

/// Returns & voids — reverse part or all of a completed sale.
///
/// A void is a full return, so both paths leave the same trail.
class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  final SalesService _sales = SalesService();
  List<Sale> _recent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sales = await _sales.getRecentSales(limit: 20);
    if (!mounted) return;
    setState(() {
      _recent = sales;
      _loading = false;
    });
  }

  Future<void> _open(Sale sale, {required bool startAsVoid}) async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _ReturnDetailScreen(sale: sale, startAsVoid: startAsVoid)),
    );
    if (done == true) _load();
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
                  : _recent.isEmpty
                      ? _empty()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 6, AppSpace.screenH, 32),
                          children: [
                            _note(),
                            const SizedBox(height: AppSpace.gapSection),
                            for (final sale in _recent) ...[
                              _saleCard(sale),
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
                Text('Returns & voids', style: AppText.screenTitle().copyWith(fontSize: 20)),
                Text('Recent sales', style: AppText.caption()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _note() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'A void is a full return, so both leave the same trail in Reports.',
              style: AppText.caption(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _saleCard(Sale sale) {
    final t = TimeOfDay.fromDateTime(sale.createdAtDate);
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sale.reference, style: AppText.cardTitle()),
                    const SizedBox(height: 2),
                    Text(
                      '${t.format(context)} · ${sale.itemCount} item${sale.itemCount == 1 ? '' : 's'} · ${sale.paymentMethod}',
                      style: AppText.caption(),
                    ),
                  ],
                ),
              ),
              Text(formatPeso(sale.total), style: AppText.cardTitle()),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => _open(sale, startAsVoid: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryTint,
                      foregroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Return items', style: AppText.chip(color: AppColors.primary)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton(
                    onPressed: () => _open(sale, startAsVoid: true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.dangerBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Void whole sale', style: AppText.chip(color: AppColors.danger)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
              decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.receipt_long_outlined, color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 14),
            Text('No sales to return', style: AppText.cardTitle().copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Text('Completed sales show up here so you can reverse them.',
                textAlign: TextAlign.center, style: AppText.caption()),
          ],
        ),
      ),
    );
  }
}

// ── Return detail ──────────────────────────────────────────────────────────

class _ReturnDetailScreen extends StatefulWidget {
  const _ReturnDetailScreen({required this.sale, required this.startAsVoid});

  final Sale sale;
  final bool startAsVoid;

  @override
  State<_ReturnDetailScreen> createState() => _ReturnDetailScreenState();
}

class _ReturnDetailScreenState extends State<_ReturnDetailScreen> {
  final SalesService _sales = SalesService();

  static const _reasons = ['Damaged', 'Wrong item', 'Expired', 'Changed mind'];
  static const _methods = ['Cash', 'GCash', 'Store credit'];

  List<ReturnableLine> _lines = [];
  final Map<int, int> _selected = {}; // productId -> qty
  String _reason = _reasons.first;
  String _method = _methods.first;
  bool _returnToStock = true;
  bool _loading = true;
  bool _saving = false;
  Refund? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lines = await _sales.getReturnableLines(widget.sale.id!);
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _loading = false;
      if (widget.startAsVoid) _selectAll();
    });
  }

  void _selectAll() {
    _selected.clear();
    for (final l in _lines) {
      if (l.returnable > 0) _selected[l.item.productId] = l.returnable;
    }
  }

  double get _refundDue => _lines.fold<double>(0, (s, l) {
        final qty = _selected[l.item.productId] ?? 0;
        return s + l.item.unitPrice * qty;
      });

  bool get _anySelected => _selected.values.any((v) => v > 0);

  /// Every returnable unit selected — this stops being a partial return and
  /// gets recorded as a full void.
  bool get _isWholeSale {
    final returnable = _lines.where((l) => l.returnable > 0).toList();
    if (returnable.isEmpty) return false;
    return returnable.every((l) => (_selected[l.item.productId] ?? 0) == l.returnable);
  }

  bool get _nothingLeft => _lines.every((l) => l.returnable <= 0);

  Future<void> _review() async {
    final isVoid = _isWholeSale;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isVoid ? 'Void this whole sale?' : 'Confirm this return?',
            style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: Text(
          isVoid
              ? 'Every line on ${widget.sale.reference} will be reversed and ${formatPeso(_refundDue)} refunded by $_method.'
              : '${formatPeso(_refundDue)} will be refunded by $_method and recorded against ${widget.sale.reference}.',
          style: AppText.body(),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep the sale', style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isVoid ? 'Void sale' : 'Confirm return',
                style: AppText.chip(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final refund = await _sales.recordRefund(
      sale: widget.sale,
      lines: Map.of(_selected),
      reason: _reason,
      method: _method,
      restock: _returnToStock,
      isVoid: isVoid,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _result = refund;
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
    if (_result != null) return _resultView(_result!);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _nothingLeft
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text('Every line on this sale has already been returned.',
                            textAlign: TextAlign.center, style: AppText.body()),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 6, AppSpace.screenH, 24),
                      children: [
                        _linesCard(),
                        const SizedBox(height: AppSpace.gapSection),
                        Text('Reason', style: AppText.sectionTitle()),
                        const SizedBox(height: 10),
                        _chips(_reasons, _reason, (v) => setState(() => _reason = v)),
                        const SizedBox(height: AppSpace.gapSection),
                        Text('Refund method', style: AppText.sectionTitle()),
                        const SizedBox(height: 10),
                        _chips(_methods, _method, (v) => setState(() => _method = v)),
                        const SizedBox(height: AppSpace.gapSection),
                        _restockToggle(),
                        if (_isWholeSale) ...[
                          const SizedBox(height: 10),
                          _voidNotice(),
                        ],
                      ],
                    ),
            ),
            if (!_nothingLeft) _footer(),
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
                Text('Return items', style: AppText.sectionTitle().copyWith(fontSize: 18)),
                Text(widget.sale.reference, style: AppText.caption()),
              ],
            ),
          ),
          if (!_nothingLeft)
            GestureDetector(
              onTap: () => setState(() {
                if (_isWholeSale) {
                  _selected.clear();
                } else {
                  _selectAll();
                }
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Text(_isWholeSale ? 'Clear' : 'Void all', style: AppText.chip(color: AppColors.body)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _linesCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < _lines.length; i++) ...[
            _lineRow(_lines[i]),
            if (i != _lines.length - 1) const Divider(color: AppColors.divider, height: 1),
          ],
        ],
      ),
    );
  }

  Widget _lineRow(ReturnableLine line) {
    final qty = _selected[line.item.productId] ?? 0;
    final exhausted = line.returnable <= 0;
    return Container(
      // Selected rows tint so what is being returned reads at a glance.
      color: qty > 0 ? const Color(0xFFF8F9FD) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.cardTitle(color: exhausted ? AppColors.faint : AppColors.ink)),
                const SizedBox(height: 2),
                Text(
                  exhausted
                      ? 'Already returned'
                      : '${formatPeso(line.item.unitPrice)} · ${line.returnable} of ${line.item.qty} returnable',
                  style: AppText.caption(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!exhausted)
            QtyStepper(
              value: qty,
              compact: true,
              figureSize: 16,
              // Capped at what is actually left on the line.
              canIncrement: qty < line.returnable,
              onDecrement: () {
                if (qty > 0) {
                  setState(() {
                    if (qty - 1 == 0) {
                      _selected.remove(line.item.productId);
                    } else {
                      _selected[line.item.productId] = qty - 1;
                    }
                  });
                }
              },
              onIncrement: () => setState(() => _selected[line.item.productId] = qty + 1),
            ),
        ],
      ),
    );
  }

  Widget _chips(List<String> options, String selectedValue, ValueChanged<String> onPick) {
    return Wrap(
      spacing: AppSpace.gapChip,
      runSpacing: AppSpace.gapChip,
      children: options.map((o) {
        final selected = o == selectedValue;
        return GestureDetector(
          onTap: () => onPick(o),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? AppColors.ink : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: selected ? AppColors.ink : AppColors.hairline),
            ),
            child: Text(o, style: AppText.chip(color: selected ? Colors.white : AppColors.body)),
          ),
        );
      }).toList(),
    );
  }

  Widget _restockToggle() {
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Return to stock', style: AppText.cardTitle()),
                const SizedBox(height: 2),
                // The caption states the consequence either way.
                Text(
                  _returnToStock
                      ? 'Units go back on the shelf and count as sellable again.'
                      : 'Units are written off — stock stays as it is.',
                  style: AppText.caption(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppSwitch(value: _returnToStock, onChanged: (v) => setState(() => _returnToStock = v)),
        ],
      ),
    );
  }

  Widget _voidNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dangerBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.dangerText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Every line is selected — this will be recorded as a full void.',
              style: AppText.caption(color: AppColors.dangerText),
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
              Text('Refund due', style: AppText.body()),
              Flexible(
                child: Text(formatPeso(_refundDue),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.largeFigure(color: AppColors.dangerText).copyWith(fontSize: 28)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _anySelected && !_saving ? _review : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.disabledFill,
                foregroundColor: Colors.white,
                disabledForegroundColor: AppColors.faint,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Review refund', style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultView(Refund refund) {
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
                decoration: const BoxDecoration(color: AppColors.successFill, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: AppColors.success, size: 44),
              ),
              const SizedBox(height: 18),
              Text(refund.isVoid ? 'Sale voided' : 'Return recorded',
                  style: AppText.sectionTitle().copyWith(fontSize: 19)),
              const SizedBox(height: 4),
              Text(refund.saleReference, style: AppText.caption()),
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
                    for (final l in _lines)
                      if ((_selected[l.item.productId] ?? 0) > 0) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text('${_selected[l.item.productId]} × ${l.item.name}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body()),
                            ),
                            Text(formatPeso(l.item.unitPrice * (_selected[l.item.productId] ?? 0)),
                                style: AppText.body()),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    const Divider(color: AppColors.divider, height: 1),
                    const SizedBox(height: 10),
                    _resultRow('Reason', refund.reason),
                    const SizedBox(height: 8),
                    _resultRow('Refund method', refund.method),
                    const SizedBox(height: 8),
                    _resultRow('Stock effect', refund.restocked ? 'Returned to stock' : 'Written off'),
                    const SizedBox(height: 10),
                    const Divider(color: AppColors.divider, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Refunded', style: AppText.body()),
                        Flexible(
                          child: Text(formatPeso(refund.amount),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.largeFigure(color: AppColors.dangerText).copyWith(fontSize: 28)),
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
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
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

  Widget _resultRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body()),
          Text(value, style: AppText.cardTitle()),
        ],
      );
}
