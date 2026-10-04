import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/product_model.dart';
import '../services/error_log.dart';
import '../services/product_service.dart';
import '../services/settings_service.dart';
import '../services/stock_alerts.dart';
import '../widgets/add_stock_sheet.dart';
import '../widgets/product_thumb.dart';
import '../l10n/tr.dart';

class RestockScreen extends StatefulWidget {
  const RestockScreen({super.key});

  @override
  State<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends State<RestockScreen> {
  final ProductService _productService = ProductService();
  List<Product> _all = [];
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [quiet] keeps the list on screen while it reloads — after a restock or
  /// a pull to refresh, a spinner in its place was a flash of nothing.
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    final all = await _productService.getAllProducts();
    if (!mounted) return;
    setState(() {
      _all = all;
      _products = all.where((p) => p.stock <= p.minStock).toList()..sort(byRestockUrgency);
      _loading = false;
    });
  }


  List<Product> get _critical => _products.where((p) => p.stock <= 0).toList();
  List<Product> get _low => _products.where((p) => p.stock > 0).toList();

  /// The shared rule, so Home and Products offer the same figure.
  int _suggested(Product p) => suggestedRestock(p);

  /// The list, as a message to take to the palengke or send to a supplier.
  Future<void> _shareList() async {
    final text = restockListText(
      store: SettingsService.instance.storeName,
      date: DateTime.now(),
      items: _products,
      suggested: _suggested,
    );
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (e, st) {
      ErrorLog.caught(e, st, 'share restock list');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr('Could not share: {error}', {'error': e})),
      ));
    }
  }

  /// Healthy products nearest their minimum — what will land on this screen
  /// next. Ordered by headroom in units, then by how full the bar is.
  List<Product> get _watch {
    final list = _all.where((p) => p.stock > p.minStock).toList()
      ..sort((a, b) {
        final byUnits = (a.stock - a.minStock).compareTo(b.stock - b.minStock);
        if (byUnits != 0) return byUnits;
        return _fill(a).compareTo(_fill(b));
      });
    return list.take(5).toList();
  }

  double _fill(Product p) => restockFill(p);

  /// The shared add-stock sheet, with this product's suggestion one tap away.
  Future<void> _restock(Product p) async {
    final added = await showAddStockSheet(context, p, suggested: _suggested(p));
    if (added == null || !mounted) return;
    await _load(quiet: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
            tr('Added {n} · {name} now {after}', {'n': added, 'name': p.name, 'after': p.stock + added}),
            style: AppText.body(color: Colors.white)),
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        // Sit above the raised Sell button rather than under it.
        margin: EdgeInsets.fromLTRB(AppSpace.screenH, 0, AppSpace.screenH,
            12 + MediaQuery.paddingOf(context).bottom),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.input)),
        action: undoAddedStock(p.id!, added, onUndone: () => _load(quiet: true)),
      ));
  }

  // ── Build ────────────────────────────────────────────────────────────────
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
                onRefresh: () => _load(quiet: true),
                child: Breakpoints.isTablet(context) ? _tabletBody() : _phoneBody(),
              ),
      ),
    );
  }

  Widget _header() {
    final n = _products.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Restock center'), style: AppText.screenTitle()),
        const SizedBox(height: 4),
        Text(
          n == 0
              ? tr('Every product is above its minimum')
              : n == 1
                  ? tr('1 product needs attention')
                  : tr('{n} products need attention', {'n': n}),
          style: AppText.body(),
        ),
      ],
    );
  }

  /// One ruled row, the same shape as the Products screen's stat card.
  Widget _statRow() {
    Widget cell(String value, String label, Color color) => Expanded(
          child: Column(
            children: [
              Text(value, style: AppText.statFigure(color: color, size: 19)),
              const SizedBox(height: 2),
              Text(label, style: AppText.caption()),
            ],
          ),
        );

    Widget rule() => Container(width: 1, height: 30, color: AppColors.divider);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          cell('${_critical.length}', tr('Out of stock'),
              _critical.isEmpty ? AppColors.ink : AppColors.dangerText),
          rule(),
          cell('${_low.length}', tr('Running low'),
              _low.isEmpty ? AppColors.ink : AppColors.warningText),
          rule(),
          // Was "+404 Units to order": sachets, cans and bottles added
          // together, a number nobody could act on. Now the way to the list.
          Expanded(
            child: Semantics(
              button: true,
              label: tr('Share shopping list'),
              child: GestureDetector(
                onTap: _products.isEmpty ? null : _shareList,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${_products.length}',
                            style: AppText.statFigure(color: AppColors.primary, size: 19)),
                        const SizedBox(width: 4),
                        const Icon(Icons.ios_share_rounded, size: 15, color: AppColors.primary),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(tr('Shopping list'), style: AppText.caption(color: AppColors.primary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Out of stock and running low share one compact row; the out-of-stock
  /// ones were full cards of about 200px each, so a dozen of them pushed
  /// everything running low several screens down.
  Widget _needCard(List<Product> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _needRow(items[i]),
            if (i != items.length - 1) const Divider(color: AppColors.divider, height: 1),
          ],
        ],
      ),
    );
  }

  Widget _phoneBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 16, AppSpace.screenH, 32),
      children: [
        _header(),
        if (_products.isEmpty) ...[
          const SizedBox(height: AppSpace.gapSection),
          _allClearCard(),
          if (_watch.isNotEmpty) ...[
            const SizedBox(height: AppSpace.gapBlock),
            _groupHeading(tr('Closest to minimum'), AppColors.success, _watch.length),
            const SizedBox(height: 10),
            _watchCard(),
          ],
        ] else ...[
          const SizedBox(height: AppSpace.gapSection),
          _statRow(),
          const SizedBox(height: AppSpace.gapBlock),
          if (_critical.isNotEmpty) ...[
            _groupHeading(tr('Critical'), AppColors.danger, _critical.length),
            const SizedBox(height: 10),
            _needCard(_critical),
            const SizedBox(height: AppSpace.gapBlock),
          ],
          if (_low.isNotEmpty) ...[
            _groupHeading(tr('Low stock'), AppColors.warning, _low.length),
            const SizedBox(height: 10),
            _needCard(_low),
          ],
        ],
      ],
    );
  }

  /// Tablet: the two urgencies sit side by side rather than stacked, so a
  /// long list of low stock no longer buries the out-of-stock rows that
  /// actually cost a sale. Both use the same compact row, so the columns
  /// split evenly.
  Widget _tabletBody() {
    if (_products.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          _header(),
          const SizedBox(height: AppSpace.gapSection),
          _allClearCard(),
          if (_watch.isNotEmpty) ...[
            const SizedBox(height: AppSpace.gapBlock),
            _groupHeading(tr('Closest to minimum'), AppColors.success, _watch.length),
            const SizedBox(height: 10),
            _watchCard(),
          ],
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        _header(),
        const SizedBox(height: AppSpace.gapSection),
        _statRow(),
        const SizedBox(height: AppSpace.gapBlock),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _groupHeading(tr('Critical'), AppColors.danger, _critical.length),
                  const SizedBox(height: 10),
                  if (_critical.isEmpty)
                    _columnEmpty(tr('Nothing is out of stock'))
                  else
                    _needCard(_critical),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _groupHeading(tr('Low stock'), AppColors.warning, _low.length),
                  const SizedBox(height: 10),
                  if (_low.isEmpty)
                    _columnEmpty(tr('Nothing is running low'))
                  else
                    _needCard(_low),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Either column can be empty while the other has work in it, so each says
  /// so in place instead of collapsing and pulling the layout sideways.
  Widget _columnEmpty(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(message, style: AppText.body()),
    );
  }

  Widget _groupHeading(String label, Color dot, int count) {
    return Row(
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: AppText.sectionTitle()),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Text('$count', style: AppText.chip(color: AppColors.body)),
        ),
      ],
    );
  }

  /// Thumbnail, name, a thin bar of stock against the healthy level (twice
  /// the minimum), and the suggested order. Red when out, amber when low.
  Widget _needRow(Product p) {
    final fill = _fill(p);
    final out = p.stock <= 0;
    final text = out ? AppColors.dangerText : AppColors.warningText;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _restock(p),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              ProductThumb(product: p, size: 44, radius: 11),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: AppText.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    // One line that trims, not a Row that overflows: the
                    // column is narrow beside the suggestion pill, and the
                    // Filipino runs longer.
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: tr('{n} left', {'n': p.stock}),
                            style: AppText.caption(color: text)),
                        TextSpan(
                            text: ' · ${tr('min {n}', {'n': p.minStock})}',
                            style: AppText.caption()),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        height: 4,
                        child: LinearProgressIndicator(
                          value: fill,
                          backgroundColor: AppColors.divider,
                          valueColor: const AlwaysStoppedAnimation(AppColors.warning),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: out ? AppColors.dangerFill : AppColors.warningFill,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: out ? AppColors.dangerBorder : AppColors.warningBorder),
                ),
                child: Text('+${_suggested(p)}', style: AppText.chip(color: text)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Nothing is low: a compact card instead of a lone icon in a blank
  /// screen. With no products at all it says so, since the fix is different.
  Widget _allClearCard() {
    final noProducts = _all.isEmpty;
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: noProducts ? AppColors.surface : AppColors.successFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: noProducts ? AppColors.hairline : const Color(0xFFD1FAE0)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: noProducts ? AppColors.primaryTint : AppColors.surface,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              noProducts ? Icons.inventory_2_outlined : Icons.check_circle_rounded,
              color: noProducts ? AppColors.primary : AppColors.success,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(noProducts ? tr('No products yet') : tr('Nothing needs restocking'),
                    style: AppText.cardTitle()),
                const SizedBox(height: 2),
                Text(
                  noProducts
                      ? tr('Add products in the Products tab and set a minimum stock for each.')
                      : tr('All {n} products are above their minimum.', {'n': _all.length}),
                  style: AppText.caption(color: noProducts ? AppColors.muted : AppColors.successText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The next products to run low, so the screen still says something useful
  /// on a good day — and lets you restock ahead of the alert.
  Widget _watchCard() {
    final items = _watch;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _watchRow(items[i]),
            if (i != items.length - 1) const Divider(color: AppColors.divider, height: 1),
          ],
        ],
      ),
    );
  }

  Widget _watchRow(Product p) {
    final headroom = p.stock - p.minStock;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _restock(p),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ProductThumb(product: p, size: 44, radius: 11),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: AppText.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(tr('{n} left', {'n': p.stock}), style: AppText.caption(color: AppColors.successText)),
                        Text(' · ${tr('min {n}', {'n': p.minStock})}', style: AppText.caption()),
                      ],
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        height: 4,
                        child: LinearProgressIndicator(
                          value: _fill(p),
                          backgroundColor: AppColors.divider,
                          valueColor: const AlwaysStoppedAnimation(AppColors.success),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(tr('+{n} above min', {'n': headroom}), style: AppText.caption()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The restock list as a message: by category, out of stock first within
/// each, with the suggested amount. Plain text, so it reads the same in
/// Messenger, SMS or a notes app.
String restockListText({
  required String store,
  required DateTime date,
  required List<Product> items,
  required int Function(Product) suggested,
}) {
  final byCategory = <String, List<Product>>{};
  for (final p in items) {
    byCategory.putIfAbsent(p.category.trim(), () => []).add(p);
  }
  final categories = byCategory.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  final out = StringBuffer('$store · ${tr('Restock list')} · ${trDay(date)}');
  for (final c in categories) {
    final list = byCategory[c]!..sort(byRestockUrgency);
    out.write('\n\n${c.toUpperCase()}');
    for (final p in list) {
      out.write('\n${p.name} — ${suggested(p)}');
      if (p.stock <= 0) out.write(' (${tr('out')})');
    }
  }
  return out.toString();
}
