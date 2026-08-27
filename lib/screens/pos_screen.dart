import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/cart_line.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import 'barcode_scanner_screen.dart';
import 'checkout_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final ProductService _productService = ProductService();

  List<Product> _products = [];
  bool _loading = true;
  String _search = '';
  String _category = 'All';
  final Map<int, int> _cart = {}; // productId -> qty

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final products = await _productService.getAllProducts();
    setState(() {
      _products = products;
      _loading = false;
    });
  }

  List<String> get _categories {
    final cats = _products.map((p) => p.category).toSet().toList()..sort();
    return ['All', ...cats];
  }

  List<Product> get _filtered => _products.where((p) {
        final q = _search.toLowerCase();
        final matchQ = q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            (p.sku ?? '').toLowerCase().contains(q);
        final matchCat = _category == 'All' || p.category == _category;
        return matchQ && matchCat;
      }).toList();

  List<CartLine> get _cartLines => _cart.entries
      .map((e) {
        final product = _products.firstWhere(
          (p) => p.id == e.key,
          orElse: () => Product(name: '', stock: 0, minStock: 0, category: '', createdAt: ''),
        );
        return CartLine(product: product, qty: e.value);
      })
      .where((l) => l.product.id != null)
      .toList();

  int get _cartCount => _cart.values.fold(0, (a, b) => a + b);
  double get _cartTotal => _cartLines.fold(0, (s, l) => s + l.lineTotal);

  void _addToCart(Product product) {
    if (product.id == null || product.stock <= 0) return;
    final inCart = _cart[product.id] ?? 0;
    if (inCart >= product.stock) return;
    setState(() => _cart[product.id!] = inCart + 1);
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const SimpleBarcodeScannerScreen()),
    );
    if (code == null || !mounted) return;
    final match = await _productService.findBySku(code);
    if (match == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text('No product matches code "$code"', style: const TextStyle(color: Colors.white)),
      ));
      return;
    }
    _addToCart(match);
  }

  Future<void> _openCheckout() async {
    final lines = _cartLines;
    if (lines.isEmpty) return;
    final completed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CheckoutScreen(lines: lines)),
    );
    if (completed == true) {
      setState(_cart.clear);
      _load();
    }
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
            _searchRow(),
            const SizedBox(height: 12),
            _categoryChips(),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _grid(),
            ),
          ],
        ),
      ),
      floatingActionButton: _cartCount > 0 ? _floatingCart() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 16, AppSpace.screenH, 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sari-Sari Store', style: AppText.cardTitle()),
                const SizedBox(height: 1),
                Text('Cashier · May', style: AppText.caption()),
              ],
            ),
          ),
          const StatusPill(label: 'Synced', fg: AppColors.successText, bg: AppColors.successFill),
        ],
      ),
    );
  }

  Widget _searchRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 10, AppSpace.screenH, 0),
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
                onChanged: (v) => setState(() => _search = v),
                style: AppText.body(color: AppColors.ink),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: 'Search products',
                  hintStyle: AppText.body(color: AppColors.faint),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted, size: 20),
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
              decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.input)),
              child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChips() {
    final cats = _categories;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.screenH),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.gapChip),
        itemBuilder: (_, i) {
          final c = cats[i];
          final selected = c == _category;
          return GestureDetector(
            onTap: () => setState(() => _category = c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.ink : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(color: selected ? AppColors.ink : AppColors.hairline),
              ),
              child: Text(c, style: AppText.chip(color: selected ? Colors.white : AppColors.body)),
            ),
          );
        },
      ),
    );
  }

  Widget _grid() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text('No products found', style: AppText.body()),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 10, AppSpace.screenH, 140),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpace.gapGrid,
        crossAxisSpacing: AppSpace.gapGrid,
        childAspectRatio: 0.72,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _ProductCard(
        product: items[i],
        qtyInCart: _cart[items[i].id] ?? 0,
        onTap: () => _addToCart(items[i]),
      ),
    );
  }

  Widget _floatingCart() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.screenH),
      child: GestureDetector(
        onTap: _openCheckout,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(AppRadius.hero),
            boxShadow: AppShadows.floatingCart,
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 24),
                  Positioned(
                    top: -6,
                    right: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(999)),
                      child: Text('$_cartCount', style: AppText.chip(color: Colors.white)),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$_cartCount item${_cartCount == 1 ? '' : 's'}',
                        style: AppText.caption(color: AppColors.faint)),
                    Text(formatPeso(_cartTotal),
                        style: AppText.screenTitle(color: Colors.white).copyWith(fontSize: 21)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(14)),
                child: Text('Checkout', style: AppText.chip(color: Colors.white).copyWith(fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.qtyInCart, required this.onTap});

  final Product product;
  final int qtyInCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stock <= 0;
    return GestureDetector(
      onTap: outOfStock ? null : onTap,
      child: Opacity(
        opacity: outOfStock ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.cardPad),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(height: 78, width: double.infinity, child: const PhotoPlaceholder()),
                  if (qtyInCart > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: Text('$qtyInCart',
                            style: AppText.chip(color: Colors.white).copyWith(fontSize: 11)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle(),
                ),
              ),
              const SizedBox(height: 2),
              Text(product.category, style: AppText.caption()),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatPeso(product.price),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.cardTitle(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatusPill(
                    label: StockStatus.label(product.stock, product.minStock),
                    fg: StockStatus.text(product.stock, product.minStock),
                    bg: StockStatus.fill(product.stock, product.minStock),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
