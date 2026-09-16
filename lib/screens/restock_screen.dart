import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../widgets/product_thumb.dart';

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

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await _productService.getAllProducts();
    if (!mounted) return;
    setState(() {
      _all = all;
      _products = all.where((p) => p.stock <= p.minStock).toList();
      _loading = false;
    });
  }

  List<Product> get _critical => _products.where((p) => p.stock <= 0).toList();
  List<Product> get _low => _products.where((p) => p.stock > 0).toList();

  /// Enough to land at twice the minimum, and never less than the minimum
  /// itself — one order that keeps the product off this screen for a while.
  int _suggested(Product p) {
    final s = p.minStock * 2 - p.stock;
    return s < p.minStock ? p.minStock : s;
  }

  int get _suggestedTotal => _products.fold(0, (s, p) => s + _suggested(p));

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

  /// Stock against the healthy level (twice the minimum), 0..1.
  double _fill(Product p) {
    final healthy = p.minStock * 2;
    if (healthy <= 0) return 1;
    return (p.stock / healthy).clamp(0.0, 1.0);
  }

  // ── Update sheet ─────────────────────────────────────────────────────────
  void _openUpdateSheet(Product product) {
    final suggested = _suggested(product);
    final qtyCtrl = TextEditingController(text: '$suggested');
    int addQty = suggested;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void setQty(int v) {
            addQty = v.clamp(0, 99999);
            qtyCtrl.text = '$addQty';
            qtyCtrl.selection = TextSelection.collapsed(offset: qtyCtrl.text.length);
            setSheet(() {});
          }

          final newStock = product.stock + addQty;
          final canSave = addQty > 0;

          return Container(
            padding: EdgeInsets.fromLTRB(
              AppSpace.sheetPad,
              14,
              AppSpace.sheetPad,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ProductThumb(product: product, size: 48, radius: 12),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.sectionTitle().copyWith(fontSize: 18)),
                            const SizedBox(height: 2),
                            Text('${product.category} · min ${product.minStock}',
                                style: AppText.caption()),
                          ],
                        ),
                      ),
                      StatusPill(
                        label: StockStatus.label(product.stock, product.minStock),
                        fg: StockStatus.text(product.stock, product.minStock),
                        bg: StockStatus.fill(product.stock, product.minStock),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(child: _stockTile('Current stock', '${product.stock}', AppColors.ink)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.faint),
                      ),
                      Expanded(
                          child: _stockTile('After restock', '$newStock', AppColors.primary,
                              tint: true)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text('Add quantity', style: AppText.body()),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Row(
                      children: [
                        _stepBtn(Icons.remove_rounded, addQty > 0 ? () => setQty(addQty - 1) : null),
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(5),
                            ],
                            style: AppText.largeFigure().copyWith(fontSize: 30),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isCollapsed: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 6),
                            ),
                            onChanged: (v) => setSheet(() => addQty = int.tryParse(v) ?? 0),
                          ),
                        ),
                        _stepBtn(Icons.add_rounded, () => setQty(addQty + 1)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Sari-sari deliveries come by the pack and the dozen; typing
                  // 24 one tap at a time is the thing this row exists to skip.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _quickChip('Suggested +$suggested', addQty == suggested,
                          () => setQty(suggested)),
                      for (final n in const [5, 10, 12, 24])
                        _quickChip('+$n', false, () => setQty(addQty + n)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.disabledFill,
                        disabledForegroundColor: AppColors.muted,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.cta)),
                      ),
                      onPressed: !canSave
                          ? null
                          : () async {
                              // Relative, so a sale rung while this sheet was
                              // open is not overwritten by a stale total.
                              await _productService.addStock(product.id!, addQty);
                              if (ctx.mounted) Navigator.pop(ctx);
                              _load();
                            },
                      child: Text(
                        canSave ? 'Add $addQty to stock' : 'Enter a quantity',
                        style: AppText.chip(color: canSave ? Colors.white : AppColors.muted)
                            .copyWith(fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(qtyCtrl.dispose);
  }

  Widget _stockTile(String label, String value, Color color, {bool tint = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint ? AppColors.primaryTint : AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.input),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption()),
          const SizedBox(height: 4),
          Text(value, style: AppText.largeFigure(color: color).copyWith(fontSize: 22)),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback? onTap) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Icon(icon, color: enabled ? AppColors.ink : AppColors.faint, size: 20),
      ),
    );
  }

  Widget _quickChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: selected ? AppColors.ink : AppColors.hairline),
        ),
        child: Text(label, style: AppText.chip(color: selected ? Colors.white : AppColors.body)),
      ),
    );
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
                onRefresh: _load,
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
        Text('Restock center', style: AppText.screenTitle()),
        const SizedBox(height: 4),
        Text(
          n == 0
              ? 'Every product is above its minimum'
              : n == 1
                  ? '1 product needs attention'
                  : '$n products need attention',
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
          cell('${_critical.length}', 'Out of stock',
              _critical.isEmpty ? AppColors.ink : AppColors.dangerText),
          rule(),
          cell('${_low.length}', 'Running low',
              _low.isEmpty ? AppColors.ink : AppColors.warningText),
          rule(),
          cell('+$_suggestedTotal', 'Units to order', AppColors.primary),
        ],
      ),
    );
  }

  Widget _lowStockCard() {
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
          for (int i = 0; i < _low.length; i++) ...[
            _lowRow(_low[i]),
            if (i != _low.length - 1) const Divider(color: AppColors.divider, height: 1),
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
            _groupHeading('Closest to minimum', AppColors.success, _watch.length),
            const SizedBox(height: 10),
            _watchCard(),
          ],
        ] else ...[
          const SizedBox(height: AppSpace.gapSection),
          _statRow(),
          const SizedBox(height: AppSpace.gapBlock),
          if (_critical.isNotEmpty) ...[
            _groupHeading('Critical', AppColors.danger, _critical.length),
            const SizedBox(height: 10),
            for (final p in _critical) ...[
              _criticalCard(p),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: AppSpace.gapSection),
          ],
          if (_low.isNotEmpty) ...[
            _groupHeading('Low stock', AppColors.warning, _low.length),
            const SizedBox(height: 10),
            _lowStockCard(),
          ],
        ],
      ],
    );
  }

  /// Tablet: the two urgencies sit side by side rather than stacked, so a
  /// long list of low stock no longer buries the out-of-stock cards that
  /// actually cost a sale. Critical takes the wider column because its cards
  /// carry the stat rule and the restock button.
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
            _groupHeading('Closest to minimum', AppColors.success, _watch.length),
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
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _groupHeading('Critical', AppColors.danger, _critical.length),
                  const SizedBox(height: 10),
                  if (_critical.isEmpty)
                    _columnEmpty('Nothing is out of stock')
                  else
                    for (final p in _critical) ...[
                      _criticalCard(p),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _groupHeading('Low stock', AppColors.warning, _low.length),
                  const SizedBox(height: 10),
                  if (_low.isEmpty)
                    _columnEmpty('Nothing is running low')
                  else
                    _lowStockCard(),
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

  Widget _criticalCard(Product p) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.dangerBorder),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProductThumb(product: p, size: 48, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: AppText.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(p.category, style: AppText.caption()),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const StatusPill(label: 'Out of stock', fg: AppColors.dangerText, bg: AppColors.dangerFill),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.divider), bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                _ruleStat('Current', '${p.stock}', AppColors.dangerText),
                _ruleStat('Minimum', '${p.minStock}', AppColors.ink),
                _ruleStat('Suggested', '+${_suggested(p)}', AppColors.primary),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () => _openUpdateSheet(p),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Restock now', style: AppText.chip(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppText.statFigure(color: color, size: 16)),
          const SizedBox(height: 2),
          Text(label, style: AppText.caption()),
        ],
      ),
    );
  }

  /// Thumbnail, name, a thin bar of stock against the healthy level (twice
  /// the minimum), and a restock button.
  Widget _lowRow(Product p) {
    final fill = _fill(p);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openUpdateSheet(p),
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
                    Row(
                      children: [
                        Text('${p.stock} left', style: AppText.caption(color: AppColors.warningText)),
                        Text(' · min ${p.minStock}', style: AppText.caption()),
                      ],
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
                  color: AppColors.warningFill,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.warningBorder),
                ),
                child: Text('+${_suggested(p)}', style: AppText.chip(color: AppColors.warningText)),
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
                Text(noProducts ? 'No products yet' : 'Nothing needs restocking',
                    style: AppText.cardTitle()),
                const SizedBox(height: 2),
                Text(
                  noProducts
                      ? 'Add products in the Products tab and set a minimum stock for each.'
                      : 'All ${_all.length} products are above their minimum.',
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
        onTap: () => _openUpdateSheet(p),
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
                        Text('${p.stock} left', style: AppText.caption(color: AppColors.successText)),
                        Text(' · min ${p.minStock}', style: AppText.caption()),
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
              Text('+$headroom above min', style: AppText.caption()),
            ],
          ),
        ),
      ),
    );
  }
}
