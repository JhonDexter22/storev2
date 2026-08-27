import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';

class RestockScreen extends StatefulWidget {
  const RestockScreen({super.key});

  @override
  State<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends State<RestockScreen> {
  final ProductService _productService = ProductService();
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final products = await _productService.getLowStockProducts();
    if (!mounted) return;
    setState(() {
      _products = products;
      _loading = false;
    });
  }

  List<Product> get _critical => _products.where((p) => p.stock <= 0).toList();
  List<Product> get _low => _products.where((p) => p.stock > 0).toList();

  int _suggested(Product p) {
    final s = p.minStock * 2 - p.stock;
    return s < p.minStock ? p.minStock : s;
  }

  void _openUpdateSheet(Product product) {
    int addQty = _suggested(product);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final newStock = product.stock + addQty;
          return Container(
            padding: EdgeInsets.fromLTRB(
              AppSpace.sheetPad,
              14,
              AppSpace.sheetPad,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
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
                    decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(product.name, style: AppText.sectionTitle().copyWith(fontSize: 18)),
                const SizedBox(height: 2),
                Text('Minimum stock: ${product.minStock}', style: AppText.caption()),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: _stockTile('Current stock', '${product.stock}', AppColors.ink)),
                    const SizedBox(width: 10),
                    Expanded(child: _stockTile('New stock', '$newStock', AppColors.primary, tint: true)),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Add quantity', style: AppText.body()),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _stepBtn(Icons.remove_rounded, () {
                      if (addQty > 1) setSheet(() => addQty--);
                    }),
                    Expanded(
                      child: Center(
                        child: Text('$addQty', style: AppText.largeFigure().copyWith(fontSize: 30)),
                      ),
                    ),
                    _stepBtn(Icons.add_rounded, () => setSheet(() => addQty++)),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                    ),
                    onPressed: () async {
                      await _productService.updateStock(product.id!, newStock);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    },
                    child: Text('Update inventory', style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Icon(icon, color: AppColors.ink, size: 20),
      ),
    );
  }

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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 16, AppSpace.screenH, 32),
                  children: [
                    Text('Restock center', style: AppText.screenTitle()),
                    const SizedBox(height: 4),
                    Text(
                      _products.isEmpty
                          ? 'All products are sufficiently stocked'
                          : '${_products.length} product${_products.length == 1 ? '' : 's'} need attention',
                      style: AppText.body(),
                    ),
                    const SizedBox(height: AppSpace.gapBlock),
                    if (_critical.isNotEmpty) ...[
                      _groupHeading('Critical', AppColors.danger),
                      const SizedBox(height: 10),
                      for (final p in _critical) ...[
                        _criticalCard(p),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: AppSpace.gapSection),
                    ],
                    if (_low.isNotEmpty) ...[
                      _groupHeading('Low stock', AppColors.warning),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: AppColors.hairline),
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
                      ),
                    ],
                    if (_products.isEmpty) _emptyState(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _groupHeading(String label, Color dot) {
    return Row(
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: AppText.sectionTitle()),
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
              const SizedBox(width: 48, height: 48, child: PhotoPlaceholder(borderRadius: 12)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: AppText.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(p.category, style: AppText.caption()),
                  ],
                ),
              ),
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
                _ruleStat('Current', '${p.stock}'),
                _ruleStat('Minimum', '${p.minStock}'),
                _ruleStat('Suggested', '+${_suggested(p)}'),
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
              child: Text('Restock', style: AppText.chip(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: AppText.cardTitle()),
          const SizedBox(height: 2),
          Text(label, style: AppText.caption()),
        ],
      ),
    );
  }

  Widget _lowRow(Product p) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openUpdateSheet(p),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const SizedBox(width: 40, height: 40, child: PhotoPlaceholder(borderRadius: 10)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: AppText.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${p.stock} left · min ${p.minStock}', style: AppText.caption()),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: AppColors.warningFill, borderRadius: BorderRadius.circular(999)),
                child: Text('Restock', style: AppText.chip(color: AppColors.warningText)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.successFill, borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 30),
          ),
          const SizedBox(height: 14),
          Text('Nothing needs restocking', style: AppText.cardTitle()),
        ],
      ),
    );
  }
}
