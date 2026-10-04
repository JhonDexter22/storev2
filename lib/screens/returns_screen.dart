import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/payment_type.dart';
import '../models/refund_model.dart';
import '../models/sale_model.dart';
import '../services/sales_service.dart';
import '../services/settings_service.dart';
import '../services/staff_service.dart';
import '../widgets/change_pin_flow.dart';
import '../l10n/tr.dart';

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
  static const _page = 20;

  List<Sale> _recent = [];
  Map<int, double> _refunded = const {};
  String _search = '';
  bool _hasMore = false;
  bool _loading = true;

  /// Tablet only: the sale whose return is being built in the right pane.
  Sale? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Only the last twenty used to be reachable, with no way to look further
  /// back: a customer returning yesterday's item after a busy day could not
  /// be found. Now searchable, and paged.
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    final sales = await _sales.findSales(query: _search, limit: _page);
    final refunded = await _sales.refundedBySale(sales.map((s) => s.id!));
    if (!mounted) return;
    setState(() {
      _recent = sales;
      _refunded = refunded;
      _hasMore = sales.length == _page;
      _loading = false;
    });
  }

  Future<void> _loadOlder() async {
    final more = await _sales.findSales(query: _search, limit: _page, offset: _recent.length);
    final refunded = await _sales.refundedBySale(more.map((s) => s.id!));
    if (!mounted) return;
    setState(() {
      _recent = [..._recent, ...more];
      _refunded = {..._refunded, ...refunded};
      _hasMore = more.length == _page;
    });
  }

  /// Fully returned, partly returned, or neither.
  ({bool all, bool some}) _returnState(Sale sale) {
    final r = _refunded[sale.id] ?? 0;
    return (all: r >= sale.total - 0.005 && r > 0, some: r > 0.005);
  }

  Widget _searchField() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.hairline),
      ),
      child: TextField(
        onChanged: (v) {
          _search = v;
          _load(quiet: true);
        },
        style: AppText.body(color: AppColors.ink),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          hintText: tr('Search receipt number or item'),
          hintStyle: AppText.body(color: AppColors.faint),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted, size: 20),
          prefixIconConstraints: const BoxConstraints(minWidth: 42),
        ),
      ),
    );
  }

  Widget _olderButton() => SizedBox(
        height: 46,
        child: OutlinedButton(
          onPressed: _loadOlder,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.body,
            side: const BorderSide(color: AppColors.hairline),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
          ),
          child: Text(tr('Show older'), style: AppText.chip(color: AppColors.body)),
        ),
      );

  Widget _noMatch() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text(tr('No sales match'), style: AppText.body())),
      );

  Widget _returnPill(Sale sale) {
    final state = _returnState(sale);
    if (!state.some) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: StatusPill(
        label: state.all ? tr('Returned') : tr('Partly returned'),
        fg: AppColors.body,
        bg: AppColors.divider,
        dot: false,
      ),
    );
  }

  Future<void> _open(Sale sale, {required bool startAsVoid}) async {
    final done = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ReturnDetailScreen(sale: sale, startAsVoid: startAsVoid)),
    );
    if (done == true) _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    if (Breakpoints.isTablet(context)) return _tabletLayout();

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
                  : _recent.isEmpty && _search.isEmpty
                      ? _empty()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 6, AppSpace.screenH, 32),
                          children: [
                            _searchField(),
                            const SizedBox(height: AppSpace.gapSection),
                            _note(),
                            const SizedBox(height: AppSpace.gapSection),
                            if (_recent.isEmpty) _noMatch(),
                            for (final sale in _recent) ...[
                              _saleCard(sale),
                              const SizedBox(height: 10),
                            ],
                            if (_hasMore) _olderButton(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tablet: a selectable column of the day's sales beside the return being
  /// built, so the sale never leaves the screen.
  Widget _tabletLayout() {
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
                  : _recent.isEmpty && _search.isEmpty
                      ? _empty()
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 340, child: _salesColumn()),
                            Expanded(
                              child: _selected == null
                                  ? _pickPrompt()
                                  : ReturnDetailScreen(
                                      key: ValueKey(_selected!.id),
                                      sale: _selected!,
                                      startAsVoid: false,
                                      embedded: true,
                                      onDone: () {
                                        setState(() => _selected = null);
                                        _load(quiet: true);
                                      },
                                    ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _salesColumn() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.dividerStrong)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          _searchField(),
          const SizedBox(height: AppSpace.gapSection),
          _note(),
          const SizedBox(height: AppSpace.gapSection),
          if (_recent.isEmpty) _noMatch(),
          for (final sale in _recent) ...[
            _selectableSaleRow(sale),
            const SizedBox(height: 8),
          ],
          if (_hasMore) _olderButton(),
        ],
      ),
    );
  }

  Widget _selectableSaleRow(Sale sale) {
    final selected = _selected?.id == sale.id;
    final t = TimeOfDay.fromDateTime(sale.createdAtDate);
    return GestureDetector(
      onTap: () => setState(() => _selected = sale),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTint : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sale.summary(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
                  const SizedBox(height: 2),
                  Text(
                    '${t.format(context)} · ${trCount(sale.itemCount, '{n} item', '{n} items')} · ${sale.paymentMethod} · ${sale.shortRef}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatPeso(sale.total), style: AppText.cardTitle()),
                _returnPill(sale),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: AppColors.primaryTint, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.receipt_long_outlined,
                  color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 14),
            Text(tr('Pick a sale to return'),
                style: AppText.cardTitle().copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Text(tr('Choose one on the left and build the refund here.'),
                textAlign: TextAlign.center, style: AppText.caption()),
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
                Text(tr('Returns & voids'), style: AppText.screenTitle().copyWith(fontSize: 20)),
                Text(tr('Recent sales'), style: AppText.caption()),
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
              tr('A void is a full return, so both leave the same trail in Reports.'),
              style: AppText.caption(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// One tap opens the return; "Void all" is inside. Every card used to
  /// carry its own red Void button — a list of them, each one mis-tap from
  /// voiding the wrong sale.
  Widget _saleCard(Sale sale) {
    final t = TimeOfDay.fromDateTime(sale.createdAtDate);
    final state = _returnState(sale);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => _open(sale, startAsVoid: false),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.cardPad),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sale.summary(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.cardTitle(color: state.all ? AppColors.muted : AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(
                      '${t.format(context)} · ${trCount(sale.itemCount, '{n} item', '{n} items')} · ${tr(sale.paymentMethod)} · ${sale.shortRef}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatPeso(sale.total), style: AppText.cardTitle()),
                  _returnPill(sale),
                ],
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, color: AppColors.faint, size: 20),
            ],
          ),
        ),
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
            Text(tr('No sales to return'), style: AppText.cardTitle().copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Text(tr('Completed sales show up here so you can reverse them.'),
                textAlign: TextAlign.center, style: AppText.caption()),
          ],
        ),
      ),
    );
  }
}

// ── Return detail ──────────────────────────────────────────────────────────

class ReturnDetailScreen extends StatefulWidget {
  const ReturnDetailScreen({
    super.key,
    required this.sale,
    required this.startAsVoid,
    this.embedded = false,
    this.onDone,
  });

  final Sale sale;
  final bool startAsVoid;

  /// When true this lives inside the tablet pane rather than its own route, so
  /// it must not pop the navigator or draw a back button.
  final bool embedded;
  final VoidCallback? onDone;

  @override
  State<ReturnDetailScreen> createState() => _ReturnDetailScreenState();
}

class _ReturnDetailScreenState extends State<ReturnDetailScreen> {
  final SalesService _sales = SalesService();

  static const _reasons = ['Damaged', 'Wrong item', 'Expired', 'Changed mind'];

  /// The sale went on a customer's tab, so it was never paid for.
  bool get _onTab => widget.sale.paymentMethod == PaymentType.utangName;

  /// Refund routes follow the same configuration as checkout: a store that
  /// does not take GCash should not be offering a GCash refund. Store credit
  /// is added because it is a refund route rather than a payment type.
  ///
  /// A tab sale has one route: off the tab. Money cannot go back for goods
  /// that were never paid for.
  List<String> get _methods => _onTab
      ? [PaymentType.utangName]
      : [
          for (final t in SettingsService.instance.paymentTypes)
            if (t.kind != PaymentKind.utang) t.name,
          'Store credit',
        ];

  /// How the sale was paid, where that is still a way to refund — not Cash
  /// for everything, which took a GCash sale's refund out of the drawer.
  late String _method =
      _methods.contains(widget.sale.paymentMethod) ? widget.sale.paymentMethod : _methods.first;

  /// What a refund route is called on screen.
  static String _methodLabel(String m) =>
      m == PaymentType.utangName ? tr('Take off their tab') : tr(m);

  List<ReturnableLine> _lines = [];
  final Map<int, int> _selected = {}; // productId -> qty
  String _reason = _reasons.first;
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
        // Net of the line's share of any discount, so the figure on screen
        // is the figure that will be refunded.
        return s + l.item.netUnitPrice * qty;
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
        title: Text(isVoid ? tr('Void this whole sale?') : tr('Confirm this return?'),
            style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: Text(
          _onTab
              ? tr('{amount} will come off the customer\'s tab, recorded against {ref}. No money changes hands.',
                  {'ref': widget.sale.reference, 'amount': formatPeso(_refundDue)})
              : isVoid
                  ? tr('Every line on {ref} will be reversed and {amount} refunded by {method}.', {'ref': widget.sale.reference, 'amount': formatPeso(_refundDue), 'method': tr(_method)})
                  : tr('{amount} will be refunded by {method} and recorded against {ref}.', {'ref': widget.sale.reference, 'amount': formatPeso(_refundDue), 'method': tr(_method)}),
          style: AppText.body(),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Keep the sale'), style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isVoid ? tr('Void sale') : tr('Confirm return'),
                style: AppText.chip(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Cash out of the drawer needs a manager, as closing the day does: ring
    // up, take the money, void, keep it, is the classic way a till leaks.
    if (_method == PaymentType.cashName) {
      final approved = await authoriseAsManager(
        context,
        staff: StaffService(),
        hint: tr('Enter the manager PIN to refund cash.'),
        confirmLabel: tr('Continue'),
      );
      if (!approved || !mounted) return;
    }

    setState(() => _saving = true);
    final refund = await _sales.recordRefund(
      cashier: SettingsService.instance.cashier,
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded,
                                size: 40, color: AppColors.muted),
                            const SizedBox(height: 12),
                            Text(
                                tr('Every line on this sale has already been returned.'),
                                textAlign: TextAlign.center,
                                style: AppText.body()),
                            const SizedBox(height: 20),
                            // Was a message in an empty screen whose only way
                            // out was the back arrow in the corner.
                            SizedBox(
                              height: 46,
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.body,
                                  side: const BorderSide(
                                      color: AppColors.hairline),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          AppRadius.cta)),
                                ),
                                child: Text(tr('Back to recent sales'),
                                    style: AppText.chip(color: AppColors.body)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 6, AppSpace.screenH, 24),
                      children: [
                        _linesCard(),
                        const SizedBox(height: AppSpace.gapSection),
                        Text(tr('Reason'), style: AppText.sectionTitle()),
                        const SizedBox(height: 10),
                        _chips(_reasons, _reason, (v) => setState(() => _reason = v)),
                        const SizedBox(height: AppSpace.gapSection),
                        Text(tr('Refund method'), style: AppText.sectionTitle()),
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
          // Embedded in the tablet pane there is nothing to go back to.
          if (!widget.embedded) ...[
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
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppColors.body, size: 16),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Return items'), style: AppText.sectionTitle().copyWith(fontSize: 18)),
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
                child: Text(_isWholeSale ? tr('Clear') : tr('Void all'), style: AppText.chip(color: AppColors.body)),
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
                      ? tr('Already returned')
                      : tr('{price} · {n} of {total} returnable', {'price': formatPeso(line.item.netUnitPrice), 'n': line.returnable, 'total': line.item.qty}),
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
            // Reasons and methods are stored in English; only the label is
            // translated.
            child: Text(_methods.contains(o) ? _methodLabel(o) : tr(o),
                style: AppText.chip(color: selected ? Colors.white : AppColors.body)),
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
                Text(tr('Return to stock'), style: AppText.cardTitle()),
                const SizedBox(height: 2),
                // The caption states the consequence either way.
                Text(
                  _returnToStock
                      ? tr('Units go back on the shelf and count as sellable again.')
                      : tr('Units are written off — stock stays as it is.'),
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
              tr('Every line is selected — this will be recorded as a full void.'),
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
              Text(tr('Refund due'), style: AppText.body()),
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
                  : Text(tr('Review refund'), style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
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
              Text(refund.isVoid ? tr('Sale voided') : tr('Return recorded'),
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
                            Text(formatPeso(l.item.netUnitPrice * (_selected[l.item.productId] ?? 0)),
                                style: AppText.body()),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    const Divider(color: AppColors.divider, height: 1),
                    const SizedBox(height: 10),
                    _resultRow(tr('Reason'), refund.reason),
                    const SizedBox(height: 8),
                    _resultRow(tr('Refund method'), _methodLabel(refund.method)),
                    const SizedBox(height: 8),
                    _resultRow(tr('Stock effect'), refund.restocked ? tr('Returned to stock') : tr('Written off')),
                    const SizedBox(height: 10),
                    const Divider(color: AppColors.divider, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(tr('Refunded'), style: AppText.body()),
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
                  onPressed: () => widget.embedded
                      ? widget.onDone?.call()
                      : Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                  ),
                  child: Text(tr('Done'), style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
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
