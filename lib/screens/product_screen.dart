import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/design_tokens.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/settings_service.dart';
import 'barcode_scanner_screen.dart';

enum _View { grid, list }

enum _Sort { name, stockAsc, priceDesc }

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, this.newProductSku});

  /// When set, the add-product sheet opens on first frame with this SKU
  /// pre-filled — the path from an unknown barcode in the scanner.
  final String? newProductSku;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final ProductService _productService = ProductService();
  final ImagePicker _picker = ImagePicker();

  List<Product> _products = [];
  String _search = '';
  String _category = 'All';
  _View _view = _View.grid;
  _Sort _sort = _Sort.name;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.dark,
      statusBarColor: Colors.transparent,
    ));
    _load().then((_) {
      final sku = widget.newProductSku;
      if (sku != null && mounted) _showProductSheet(presetSku: sku);
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final products = await _productService.getAllProducts();
    if (!mounted) return;
    setState(() {
      _products = products;
      _loading = false;
    });
  }

  // ── Derived data ─────────────────────────────────────────────────────────
  List<String> get _categories {
    final cats = _products.map((p) => p.category).toSet().toList()..sort();
    return ['All', ...cats];
  }

  List<Product> get _filtered {
    final q = _search.toLowerCase();
    final list = _products.where((p) {
      final matchQ = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          (p.sku ?? '').toLowerCase().contains(q);
      final matchCat = _category == 'All' || p.category == _category;
      return matchQ && matchCat;
    }).toList();

    switch (_sort) {
      case _Sort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _Sort.stockAsc:
        list.sort((a, b) => a.stock.compareTo(b.stock));
      case _Sort.priceDesc:
        list.sort((a, b) => b.price.compareTo(a.price));
    }
    return list;
  }

  int get _totalUnits => _products.fold(0, (s, p) => s + p.stock);
  int get _lowCount => _products.where((p) => p.stock > 0 && p.stock <= p.minStock).length;
  int get _outCount => _products.where((p) => p.stock <= 0).length;

  String get _sortLabel => switch (_sort) {
        _Sort.name => 'Name A–Z',
        _Sort.stockAsc => 'Stock: low first',
        _Sort.priceDesc => 'Price: high first',
      };

  void _cycleSort() {
    setState(() {
      _sort = switch (_sort) {
        _Sort.name => _Sort.stockAsc,
        _Sort.stockAsc => _Sort.priceDesc,
        _Sort.priceDesc => _Sort.name,
      };
    });
  }

  Future<String?> _pickImage() async {
    final xFile = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 600);
    return xFile?.path;
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _titleRow(),
            const SizedBox(height: 14),
            _searchRow(),
            const SizedBox(height: 14),
            _statRow(),
            const SizedBox(height: 14),
            _categoryChips(),
            _resultRow(filtered.length),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : filtered.isEmpty
                      ? _emptyState()
                      : (_view == _View.grid ? _gridBody(filtered) : _listBody(filtered)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titleRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 16, AppSpace.screenH, 0),
      child: Row(
        children: [
          Expanded(child: Text('Products', style: AppText.screenTitle())),
          GestureDetector(
            onTap: () => _showProductSheet(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.iconBtn),
                boxShadow: AppShadows.primaryCta,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, color: Colors.white, size: 17),
                  const SizedBox(width: 5),
                  Text('Add', style: AppText.chip(color: Colors.white).copyWith(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.screenH),
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
          _viewToggle(),
        ],
      ),
    );
  }

  /// Segmented control with an ink fill on the active side.
  Widget _viewToggle() {
    Widget half(_View v, IconData icon) {
      final active = _view == v;
      return GestureDetector(
        onTap: () => setState(() => _view = v),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active ? AppColors.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.iconBtn - 1),
          ),
          child: Icon(icon, size: 18, color: active ? Colors.white : AppColors.body),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          half(_View.grid, Icons.grid_view_rounded),
          half(_View.list, Icons.view_list_rounded),
        ],
      ),
    );
  }

  /// One ruled row: products | units | low | out, dividers between.
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
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.screenH),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          cell('${_products.length}', 'Products', AppColors.ink),
          rule(),
          cell('$_totalUnits', 'Units', AppColors.ink),
          rule(),
          cell('$_lowCount', 'Low', _lowCount > 0 ? AppColors.warningText : AppColors.ink),
          rule(),
          cell('$_outCount', 'Out', _outCount > 0 ? AppColors.dangerText : AppColors.ink),
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

  Widget _resultRow(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 14, AppSpace.screenH, 10),
      child: Row(
        children: [
          Text('$count ${count == 1 ? 'result' : 'results'}', style: AppText.body()),
          const Spacer(),
          GestureDetector(
            onTap: _cycleSort,
            child: Row(
              children: [
                Text(_sortLabel, style: AppText.chip(color: AppColors.primary)),
                const SizedBox(width: 3),
                const Icon(Icons.unfold_more_rounded, size: 15, color: AppColors.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridBody(List<Product> items) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 0, AppSpace.screenH, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpace.gapGrid,
        crossAxisSpacing: AppSpace.gapGrid,
        childAspectRatio: 0.72,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _gridCard(items[i]),
    );
  }

  Widget _gridCard(Product p) {
    return GestureDetector(
      onTap: () => _showProductSheet(product: p),
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
            SizedBox(height: 78, width: double.infinity, child: _thumb(p, radius: 12)),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
            ),
            const SizedBox(height: 2),
            Text(p.category, style: AppText.caption()),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(formatPeso(p.price),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
                ),
                const SizedBox(width: 6),
                StatusPill(
                  label: StockStatus.label(p.stock, p.minStock),
                  fg: StockStatus.text(p.stock, p.minStock),
                  bg: StockStatus.fill(p.stock, p.minStock),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _listBody(List<Product> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 0, AppSpace.screenH, 32),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _listRow(items[i]),
    );
  }

  /// 46px thumbnail, name, semantic dot + category + stock, price, chevron.
  Widget _listRow(Product p) {
    return GestureDetector(
      onTap: () => _showProductSheet(product: p),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.hairline),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            SizedBox(width: 46, height: 46, child: _thumb(p, radius: 11)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: StockStatus.dot(p.stock, p.minStock),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('${p.category} · ${p.stock} in stock',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(formatPeso(p.price), style: AppText.cardTitle()),
            const Icon(Icons.chevron_right_rounded, color: AppColors.faint, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _thumb(Product p, {required double radius}) {
    final path = p.imagePath;
    if (path == null || path.isEmpty) return PhotoPlaceholder(borderRadius: radius);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => PhotoPlaceholder(borderRadius: radius),
      ),
    );
  }

  Widget _emptyState() {
    final filtering = _search.isNotEmpty || _category != 'All';
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
              child: Icon(filtering ? Icons.search_off_rounded : Icons.inventory_2_outlined,
                  color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 14),
            Text(filtering ? 'No products found' : 'No products yet',
                style: AppText.cardTitle().copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              filtering ? 'Try a different search or category' : 'Add your first product to start selling',
              textAlign: TextAlign.center,
              style: AppText.caption(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Add / edit sheet ─────────────────────────────────────────────────────
  void _showProductSheet({Product? product, String? presetSku}) {
    final isEdit = product != null;
    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final priceCtrl = TextEditingController(text: isEdit ? product.price.toStringAsFixed(2) : '');
    final skuCtrl = TextEditingController(text: presetSku ?? product?.sku ?? '');
    final categoryCtrl = TextEditingController(text: product?.category ?? '');
    final formKey = GlobalKey<FormState>();

    String? imagePath = product?.imagePath;
    int stock = product?.stock ?? 0;
    // A new product starts at the store's configured default minimum.
    int minStock = product?.minStock ?? SettingsService.instance.defaultMinStock;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final lowNotice = stock <= minStock;
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.92,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 14),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.sheetPad, 16, AppSpace.sheetPad, 14),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.canvas,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: AppColors.hairline),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.body, size: 15),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isEdit ? 'Edit product' : 'New product',
                                style: AppText.sectionTitle().copyWith(fontSize: 18)),
                            if (isEdit)
                              Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: AppText.caption()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppColors.divider, height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      AppSpace.sheetPad,
                      18,
                      AppSpace.sheetPad,
                      MediaQuery.of(ctx).viewInsets.bottom + 28,
                    ),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionLabel('Product information'),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () async {
                              final path = await _pickImage();
                              if (path != null) setSheet(() => imagePath = path);
                            },
                            child: Container(
                              width: double.infinity,
                              height: 104,
                              decoration: BoxDecoration(
                                color: AppColors.canvas,
                                borderRadius: BorderRadius.circular(AppRadius.input),
                                border: Border.all(color: AppColors.hairline),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: imagePath != null && imagePath!.isNotEmpty
                                  ? Image.file(File(imagePath!), fit: BoxFit.cover)
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.add_photo_alternate_outlined,
                                            color: AppColors.faint, size: 26),
                                        const SizedBox(height: 6),
                                        Text('Add a photo', style: AppText.caption()),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _fieldLabel('Product name'),
                          _field(nameCtrl, hint: 'e.g. SkyFlakes',
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                          const SizedBox(height: 14),
                          _fieldLabel('SKU / barcode'),
                          Row(
                            children: [
                              Expanded(child: _field(skuCtrl, hint: 'Optional')),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: () async {
                                  final result = await Navigator.push<ScannerResult>(
                                    ctx,
                                    MaterialPageRoute(builder: (_) => const SimpleBarcodeScannerScreen()),
                                  );
                                  if (result is ScanCapture) setSheet(() => skuCtrl.text = result.code);
                                },
                                child: Container(
                                  width: 52,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: AppColors.ink,
                                    borderRadius: BorderRadius.circular(AppRadius.input),
                                  ),
                                  child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 20),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _fieldLabel('Category'),
                          _field(categoryCtrl, hint: 'e.g. Biscuits',
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),

                          const SizedBox(height: 20),
                          const Divider(color: AppColors.divider, height: 1),
                          const SizedBox(height: 18),
                          _sectionLabel('Pricing'),
                          const SizedBox(height: 10),
                          _fieldLabel('Selling price'),
                          _field(priceCtrl,
                              hint: '0.00',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              prefixText: '₱ ',
                              validator: (v) =>
                                  (double.tryParse(v ?? '') == null) ? 'Enter a price' : null),

                          const SizedBox(height: 20),
                          const Divider(color: AppColors.divider, height: 1),
                          const SizedBox(height: 18),
                          _sectionLabel('Inventory'),
                          const SizedBox(height: 10),
                          _stepperRow('Current stock', stock, (v) => setSheet(() => stock = v)),
                          const SizedBox(height: 10),
                          _stepperRow('Minimum stock', minStock, (v) => setSheet(() => minStock = v)),
                          if (lowNotice) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warningFill,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.warningBorder),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      size: 16, color: AppColors.warningText),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Stock is at or below the minimum — this product will show in Restock.',
                                      style: AppText.caption(color: AppColors.warningText),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 20),
                          const Divider(color: AppColors.divider, height: 1),
                          const SizedBox(height: 18),
                          _sectionLabel('Actions'),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppRadius.cta)),
                              ),
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                final p = Product(
                                  id: product?.id,
                                  name: nameCtrl.text.trim(),
                                  stock: stock,
                                  minStock: minStock,
                                  category: categoryCtrl.text.trim(),
                                  createdAt: product?.createdAt ?? DateTime.now().toIso8601String(),
                                  price: double.tryParse(priceCtrl.text) ?? 0,
                                  sku: skuCtrl.text.trim().isEmpty ? null : skuCtrl.text.trim(),
                                  imagePath: imagePath,
                                );
                                if (isEdit) {
                                  await _productService.updateProduct(p);
                                } else {
                                  await _productService.insertProduct(p);
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                                _load();
                              },
                              child: Text(isEdit ? 'Save changes' : 'Save product',
                                  style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
                            ),
                          ),
                          if (isEdit) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                  side: const BorderSide(color: AppColors.dangerBorder),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadius.cta)),
                                ),
                                onPressed: () => _confirmDelete(ctx, product),
                                child: Text('Delete product',
                                    style: AppText.chip(color: AppColors.danger).copyWith(fontSize: 15)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext sheetCtx, Product product) async {
    final confirmed = await showDialog<bool>(
      context: sheetCtx,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete this product?', style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: Text(
          '"${product.name}" will be removed from the catalog. Past sales that included it are not affected.',
          style: AppText.body(),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: AppText.chip(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _productService.deleteProduct(product.id!);
    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
    _load();
  }

  // ── Sheet helpers ────────────────────────────────────────────────────────
  Widget _sectionLabel(String text) =>
      Text(text.toUpperCase(), style: AppText.overline(color: AppColors.muted));

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: AppText.body()),
      );

  Widget _field(
    TextEditingController ctrl, {
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? prefixText,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: AppText.body(color: AppColors.ink).copyWith(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.body(color: AppColors.faint).copyWith(fontSize: 14),
        prefixText: prefixText,
        prefixStyle: AppText.body(color: AppColors.body).copyWith(fontSize: 14),
        filled: true,
        fillColor: AppColors.canvas,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
      validator: validator,
    );
  }

  Widget _stepperRow(String label, int value, ValueChanged<int> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body()),
          QtyStepper(
            value: value,
            figureSize: 18,
            onDecrement: () {
              if (value > 0) onChanged(value - 1);
            },
            onIncrement: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}
