import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import '../l10n/tr.dart';
import '../models/product_model.dart';
import '../services/error_log.dart';
import '../services/product_service.dart';
import '../services/stock_alerts.dart';
import '../widgets/product_thumb.dart';
import 'barcode_scanner_screen.dart';

/// Back from the market, or a delivery at the door: every item on one
/// screen, a number each, one Save. Restocking used to be a sheet per
/// product — open, type, save, close — fifteen times over.
///
/// Opens with the restock list. Anything else bought is a search or a scan
/// away. Boxes start empty, with the suggestion greyed inside: pre-filled,
/// a product that was not bought would get stock it never had unless
/// someone remembered to clear it. "Fill in suggested" is there for the day
/// the list was bought exactly.
///
/// Pops with productId → units added, or null when nothing was saved.
class StockInScreen extends StatefulWidget {
  const StockInScreen({super.key, required this.products});

  /// The rows it opens with, most urgent first.
  final List<Product> products;

  @override
  State<StockInScreen> createState() => _StockInScreenState();
}

class _StockInScreenState extends State<StockInScreen> {
  final _service = ProductService();
  late final List<Product> _rows = [...widget.products];
  final Map<int, int> _amounts = {};
  final Map<int, TextEditingController> _ctrls = {};
  final _searchCtrl = TextEditingController();
  List<Product> _catalog = const [];
  String _search = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final all = await _service.getAllProducts();
    if (mounted) setState(() => _catalog = all);
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _searchCtrl.dispose();
    super.dispose();
  }

  TextEditingController _ctrl(Product p) => _ctrls.putIfAbsent(p.id!, TextEditingController.new);

  int get _units => _amounts.values.fold(0, (a, b) => a + b);

  /// Sets the units for [p]; zero takes it out of the save.
  void _set(Product p, int n, {bool fromField = false}) {
    final v = n < 0 ? 0 : n;
    setState(() {
      if (v == 0) {
        _amounts.remove(p.id);
      } else {
        _amounts[p.id!] = v;
      }
    });
    // Typing already put the figure in the box; rewriting it would move
    // the cursor under the cashier's thumb.
    if (!fromField) _ctrl(p).text = v == 0 ? '' : '$v';
  }

  bool get _canFill => _rows.any((p) => (_amounts[p.id] ?? 0) == 0);

  void _fillSuggested() {
    for (final p in _rows) {
      if ((_amounts[p.id] ?? 0) == 0) _set(p, suggestedRestock(p));
    }
    HapticFeedback.selectionClick();
  }

  /// Puts [p] on the list (at the top, where it can be seen) if it is not
  /// there yet. [bump] adds one unit — a scan is one item in the hand.
  void _addRow(Product p, {bool bump = false}) {
    setState(() {
      if (!_rows.any((r) => r.id == p.id)) _rows.insert(0, p);
      _search = '';
    });
    _searchCtrl.clear();
    if (bump) _set(p, (_amounts[p.id] ?? 0) + 1);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _scan() async {
    final result = await Navigator.push<ScannerResult>(
      context,
      MaterialPageRoute(builder: (_) => const SimpleBarcodeScannerScreen()),
    );
    if (result is! ScanCapture || !mounted) return;
    final p = await _service.findBySku(result.code);
    if (!mounted) return;
    if (p == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('No product matches this code'))));
      return;
    }
    _addRow(p, bump: true);
  }

  Future<void> _save() async {
    if (_amounts.isEmpty || _saving) return;
    setState(() => _saving = true);
    final deltas = Map.of(_amounts);
    try {
      await _service.addStockBatch(deltas);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, deltas);
    } catch (e, st) {
      ErrorLog.caught(e, st, 'stock in: saving');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Could not save. Nothing was added — try again.'))));
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Discard changes?'), style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: Text(tr('What you entered will not be saved.'), style: AppText.body()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Keep editing'), style: AppText.chip(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Discard'), style: AppText.chip(color: AppColors.danger)),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _leave() async {
    if (_amounts.isEmpty || await _confirmDiscard()) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _amounts.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  _header(),
                  _searchRow(),
                  Expanded(child: _search.trim().isEmpty ? _list() : _matches()),
                  _saveBar(),
                ],
              ),
            ),
          ),
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
            onTap: _leave,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.body, size: 16, semanticLabel: tr('Back')),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Stock in'), style: AppText.sectionTitle().copyWith(fontSize: 18)),
                Text(tr('Type what came in. Empty rows are skipped.'),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 4, AppSpace.screenH, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(color: AppColors.hairline),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                style: AppText.body(color: AppColors.ink),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: tr('Add another product'),
                  hintStyle: AppText.body(color: AppColors.faint),
                  prefixIcon: const Icon(Icons.add_rounded, color: AppColors.muted, size: 20),
                  prefixIconConstraints: const BoxConstraints(minWidth: 42),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _scan,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.input)),
              child: Icon(Icons.qr_code_scanner_rounded,
                  color: Colors.white, size: 20, semanticLabel: tr('Scan barcode')),
            ),
          ),
        ],
      ),
    );
  }

  /// Catalog products matching the search that are not on the list yet.
  Widget _matches() {
    final q = _search.trim().toLowerCase();
    final found = _catalog
        .where((p) =>
            !_rows.any((r) => r.id == p.id) &&
            (p.name.toLowerCase().contains(q) || (p.sku ?? '').toLowerCase().contains(q)))
        .take(20)
        .toList();
    if (found.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _rows.any((r) => r.name.toLowerCase().contains(q))
              ? tr('Already on the list below.')
              : tr('No products found'),
          textAlign: TextAlign.center,
          style: AppText.body(),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 4, AppSpace.screenH, 16),
      itemCount: found.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final p = found[i];
        return Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.input),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.input),
            onTap: () => _addRow(p),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ProductThumb(product: p, size: 36, radius: 9),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
                  ),
                  Text(tr('{n} left', {'n': p.stock}), style: AppText.caption()),
                  const SizedBox(width: 8),
                  const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _list() {
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(tr('Search or scan to add what came in.'),
              textAlign: TextAlign.center, style: AppText.body()),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 0, AppSpace.screenH, 16),
      children: [
        if (_canFill)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _fillSuggested,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
              icon: const Icon(Icons.lightbulb_outline_rounded, size: 17),
              label: Text(tr('Fill in suggested amounts'), style: AppText.chip(color: AppColors.primary)),
            ),
          ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < _rows.length; i++) ...[
                _row(_rows[i]),
                if (i != _rows.length - 1) const Divider(color: AppColors.divider, height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(Product p) {
    final n = _amounts[p.id] ?? 0;
    final tone = p.stock <= 0
        ? AppColors.dangerText
        : p.stock <= p.minStock
            ? AppColors.warningText
            : AppColors.muted;
    return Container(
      color: n > 0 ? AppColors.primaryTint.withValues(alpha: 0.5) : null,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        children: [
          ProductThumb(product: p, size: 40, radius: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: tr('{n} left', {'n': p.stock}), style: AppText.caption(color: tone)),
                    // Where this lands, once something is typed.
                    if (n > 0)
                      TextSpan(
                        text: ' → ${p.stock + n}',
                        style: AppText.caption(color: AppColors.primary),
                      ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          QtyStepper(
            value: n,
            compact: true,
            onDecrement: () => _set(p, n - 1),
            onIncrement: () => _set(p, n + 1),
            field: TextField(
              controller: _ctrl(p),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: AppText.statFigure(size: 16),
              onChanged: (v) => _set(p, int.tryParse(v) ?? 0, fromField: true),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                // The suggestion, greyed: one glance says what the list asked
                // for, without it counting until it is typed or filled in.
                hintText: '${suggestedRestock(p)}',
                hintStyle: AppText.statFigure(size: 16, color: AppColors.faint),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveBar() {
    final products = _amounts.length;
    final units = _units;
    return Container(
      padding: EdgeInsets.fromLTRB(
          AppSpace.screenH, 12, AppSpace.screenH, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: products > 0 && !_saving ? _save : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.disabledFill,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(
                  products == 0
                      ? tr('Enter an amount')
                      : trCount(products, 'Add {units} to {n} product', 'Add {units} to {n} products',
                          {'units': units}),
                  style: AppText.chip(color: products > 0 ? Colors.white : AppColors.muted)
                      .copyWith(fontSize: 15),
                ),
        ),
      ),
    );
  }
}
