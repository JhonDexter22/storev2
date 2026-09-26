import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/design_tokens.dart';
import '../services/product_image_store.dart';
import '../core/responsive.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/settings_service.dart';
import '../services/stock_alerts.dart';
import '../widgets/add_stock_sheet.dart';
import '../widgets/product_card.dart';
import '../widgets/product_thumb.dart';
import '../widgets/skeleton.dart';
import 'barcode_scanner_screen.dart';
import '../l10n/tr.dart';

enum _View { grid, list }

enum _Sort { name, stockAsc, priceDesc, recent }

/// What the chip row narrows the catalog to. Stock states and categories
/// share one row and one selection: "Low" is a filter the same way
/// "Biscuit" is, and the two would rarely be combined on a phone anyway.
sealed class _Filter {
  const _Filter();
}

class _AllFilter extends _Filter {
  const _AllFilter();
}

class _LowFilter extends _Filter {
  const _LowFilter();
}

class _OutFilter extends _Filter {
  const _OutFilter();
}

class _CategoryFilter extends _Filter {
  const _CategoryFilter(this.name);
  final String name;

  @override
  bool operator ==(Object other) => other is _CategoryFilter && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, this.newProductSku, this.onRestock});

  /// When set, the add-product sheet opens on first frame with this SKU
  /// pre-filled — the path from an unknown barcode in the scanner.
  final String? newProductSku;

  /// Jumps to the Restock tab. Null when the screen is pushed from the More
  /// hub, in which case the low-stock banner filters in place instead.
  final VoidCallback? onRestock;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final ProductService _productService = ProductService();
  final ImagePicker _picker = ImagePicker();
  final ProductImageStore _images = ProductImageStore();

  List<Product> _products = [];
  String _search = '';
  _Filter _filter = const _AllFilter();
  _View _view = SettingsService.instance.productsGridView ? _View.grid : _View.list;
  _Sort _sort = _Sort.name;
  bool _loading = true;

  final TextEditingController _searchCtrl = TextEditingController();

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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_products.isEmpty) setState(() => _loading = true);
    final products = await _productService.getAllProducts();
    if (!mounted) return;
    setState(() {
      _products = products;
      _loading = false;
    });
    // The nav badges read the same numbers; keep them honest after an edit.
    StockAlerts.instance.refresh();
  }

  // ── Derived data ─────────────────────────────────────────────────────────
  List<String> get _categories {
    final cats = _products.map((p) => p.category).toSet().toList()..sort();
    return cats;
  }

  bool _isLow(Product p) => p.stock > 0 && p.stock <= p.minStock;
  bool _isOut(Product p) => p.stock <= 0;

  List<Product> get _filtered {
    final q = _search.toLowerCase();
    final list = _products.where((p) {
      final matchQ = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.category.toLowerCase().contains(q) ||
          (p.sku ?? '').toLowerCase().contains(q);
      final matchF = switch (_filter) {
        _AllFilter() => true,
        _LowFilter() => _isLow(p),
        _OutFilter() => _isOut(p),
        _CategoryFilter(name: final n) => p.category == n,
      };
      return matchQ && matchF;
    }).toList();

    switch (_sort) {
      case _Sort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _Sort.stockAsc:
        list.sort((a, b) => a.stock.compareTo(b.stock));
      case _Sort.priceDesc:
        list.sort((a, b) => b.price.compareTo(a.price));
      case _Sort.recent:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  int get _totalUnits => _products.fold(0, (s, p) => s + p.stock);
  double get _inventoryValue => _products.fold(0, (s, p) => s + p.stock * p.price);
  int get _lowCount => _products.where(_isLow).length;
  int get _outCount => _products.where(_isOut).length;
  int _categoryCount(String c) => _products.where((p) => p.category == c).length;

  bool get _narrowed => _search.isNotEmpty || _filter is! _AllFilter;

  /// Camera or gallery, then squared and kept. Returns null if the
  /// shopkeeper backed out.
  Future<String?> _pickImage(ImageSource source) async {
    XFile? xFile;
    try {
      xFile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
        preferredCameraDevice: CameraDevice.rear,
      );
    } catch (_) {
      // No camera, or permission refused: say so rather than surface a
      // platform error; the gallery route is one tap away.
      if (source == ImageSource.camera && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(_snack(tr('Camera is not available — choose from your gallery instead')));
      }
      return null;
    }
    if (xFile == null) return null;
    // The picker's own file lives in the cache directory, which Android is
    // free to empty. Square it and copy it somewhere durable before the
    // path is saved.
    return _images.keepSquared(xFile.path);
  }

  /// Where should the photo come from? Camera leads: the product is on the
  /// shelf in front of the person adding it. Returns '' for "remove".
  Future<String?> _choosePhoto({bool hasPhoto = false}) async {
    final choice = await showModalBottomSheet<_PhotoChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Widget row(IconData icon, String label, _PhotoChoice value,
            {Color color = AppColors.ink, Color iconBg = AppColors.canvas}) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(ctx, value),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(11)),
                      child: Icon(icon, size: 19, color: color),
                    ),
                    const SizedBox(width: 12),
                    Text(label, style: AppText.cardTitle(color: color).copyWith(fontSize: 14.5)),
                  ],
                ),
              ),
            ),
          );
        }

        return Container(
          padding: EdgeInsets.fromLTRB(AppSpace.sheetPad, 14, AppSpace.sheetPad,
              12 + MediaQuery.paddingOf(ctx).bottom),
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
                  decoration:
                      BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text(hasPhoto ? tr('Change photo') : tr('Add a photo'),
                  style: AppText.sectionTitle().copyWith(fontSize: 17)),
              const SizedBox(height: 6),
              row(Icons.photo_camera_outlined, tr('Take photo'), _PhotoChoice.camera,
                  color: AppColors.primary, iconBg: AppColors.primaryTint),
              row(Icons.photo_library_outlined, tr('Choose from gallery'), _PhotoChoice.gallery),
              if (hasPhoto)
                row(Icons.delete_outline_rounded, tr('Remove photo'), _PhotoChoice.remove,
                    color: AppColors.danger, iconBg: AppColors.dangerFill),
            ],
          ),
        );
      },
    );
    return switch (choice) {
      null => null,
      _PhotoChoice.camera => _pickImage(ImageSource.camera),
      _PhotoChoice.gallery => _pickImage(ImageSource.gallery),
      _PhotoChoice.remove => '',
    };
  }

  /// Straight to the camera and straight back to the list — cataloguing a
  /// shelf of 200 items should not mean 200 trips through the edit sheet.
  Future<void> _snapPhoto(Product p) async {
    final path = await _pickImage(ImageSource.camera);
    if (path == null || !mounted) return;
    final old = p.imagePath;
    await _productService.updateProduct(Product(
      id: p.id,
      name: p.name,
      stock: p.stock,
      minStock: p.minStock,
      category: p.category,
      createdAt: p.createdAt,
      price: p.price,
      sku: p.sku,
      imagePath: path,
    ));
    if (old != null && old != path) _images.discard(old);
    HapticFeedback.lightImpact();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(_snack(tr('Photo saved · {name}', {'name': p.name})));
  }

  void _setView(_View v) {
    setState(() => _view = v);
    SettingsService.instance.setProductsGridView(v == _View.grid);
  }

  /// Scan a barcode from the search bar: a known SKU opens that product, an
  /// unknown one opens the add sheet with the code already filled in.
  Future<void> _scanToFind() async {
    final result = await Navigator.push<ScannerResult>(
      context,
      MaterialPageRoute(builder: (_) => const SimpleBarcodeScannerScreen()),
    );
    if (result is! ScanCapture || !mounted) return;
    final match = await _productService.findBySku(result.code);
    if (!mounted) return;
    if (match != null) {
      _showProductSheet(product: match);
    } else {
      _showProductSheet(presetSku: result.code);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final bottomInset = MediaQuery.paddingOf(context).bottom + 32;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: _titleRow()),
              if (!_loading && _lowCount + _outCount > 0)
                SliverToBoxAdapter(child: _attentionBanner()),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedHeader(
                  height: _PinnedHeader.heightFor(showChips: _showChips),
                  child: _pinnedTools(),
                ),
              ),
              if (_narrowed && !_loading) SliverToBoxAdapter(child: _resultRow(filtered.length)),
              if (_loading)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(AppSpace.screenH, 4, AppSpace.screenH, bottomInset),
                  sliver: _skeletonList(),
                )
              else if (filtered.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: _emptyState())
              else if (_view == _View.grid)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(AppSpace.screenH, 4, AppSpace.screenH, bottomInset),
                  sliver: _gridBody(filtered),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(AppSpace.screenH, 4, AppSpace.screenH, bottomInset),
                  sliver: _listBody(filtered),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Chips earn their row once there is a second category or something to
  /// fix; a lone "All / Biscuit" pair is noise.
  bool get _showChips => _categories.length > 1 || _lowCount > 0 || _outCount > 0;

  Widget _titleRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 16, AppSpace.screenH, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Products'), style: AppText.screenTitle()),
                const SizedBox(height: 2),
                Text(
                  _loading
                      ? tr('Loading…')
                      : trCount(_totalUnits, '{n} unit · {value} on hand', '{n} units · {value} on hand', {'value': formatPeso(_inventoryValue)}),
                  style: AppText.caption(color: AppColors.body),
                ),
              ],
            ),
          ),
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
                  Text(tr('Add'), style: AppText.chip(color: Colors.white).copyWith(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "3 running low, 1 out" → Restock. The one thing an owner opening this
  /// screen most often needs to know, put where the eye lands first.
  Widget _attentionBanner() {
    final parts = <String>[
      if (_outCount > 0) tr('{n} out of stock', {'n': _outCount}),
      if (_lowCount > 0) tr('{n} running low', {'n': _lowCount}),
    ];
    final critical = _outCount > 0;
    final fg = critical ? AppColors.dangerText : AppColors.warningText;
    final bg = critical ? AppColors.dangerFill : AppColors.warningFill;
    final border = critical ? AppColors.dangerBorder : AppColors.warningBorder;
    final onRestock = widget.onRestock;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 0, AppSpace.screenH, 12),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.input),
          onTap: onRestock ??
              () => setState(() => _filter = critical ? const _OutFilter() : const _LowFilter()),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: border),
            ),
            child: Row(
              children: [
                Icon(critical ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                    size: 18, color: fg),
                const SizedBox(width: 8),
                Expanded(child: Text(parts.join(', '), style: AppText.chip(color: fg))),
                Text(onRestock != null ? tr('Restock') : tr('Show'), style: AppText.chip(color: fg)),
                Icon(Icons.chevron_right_rounded, size: 18, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Search + tools, then the filter chips. Pinned so neither scrolls away.
  Widget _pinnedTools() {
    return Container(
      color: AppColors.canvas,
      child: Column(
        children: [
          _searchRow(),
          if (_showChips) ...[
            const SizedBox(height: 10),
            _filterChips(),
          ],
          const SizedBox(height: 10),
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
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                style: AppText.body(color: AppColors.ink),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  hintText: tr('Search name or SKU'),
                  hintStyle: AppText.body(color: AppColors.faint),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted, size: 20),
                  prefixIconConstraints: const BoxConstraints(minWidth: 42),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          tooltip: tr('Clear'),
                          icon: const Icon(Icons.close_rounded, color: AppColors.muted, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _search = '');
                          },
                        )
                      : IconButton(
                          tooltip: tr('Scan barcode'),
                          icon: const Icon(Icons.qr_code_scanner_rounded,
                              color: AppColors.primary, size: 20),
                          onPressed: _scanToFind,
                        ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 44),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _toolsButton(),
        ],
      ),
    );
  }

  /// Sort + layout live behind one button; a dot marks a non-default sort so
  /// "why is Coke first?" has a visible answer.
  Widget _toolsButton() {
    final customised = _sort != _Sort.name;
    return Semantics(
      button: true,
      label: tr('Sort and layout'),
      child: GestureDetector(
        onTap: _showSortSheet,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.tune_rounded, size: 20, color: AppColors.body),
              if (customised)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChips() {
    final chips = <(_Filter, String, int, Color?, Color?)>[
      (const _AllFilter(), tr('All'), _products.length, null, null),
      if (_lowCount > 0)
        (const _LowFilter(), tr('Low'), _lowCount, AppColors.warningFill, AppColors.warningText),
      if (_outCount > 0)
        (const _OutFilter(), tr('Out'), _outCount, AppColors.dangerFill, AppColors.dangerText),
      if (_categories.length > 1)
        for (final c in _categories) (_CategoryFilter(c), c, _categoryCount(c), null, null),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.screenH),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.gapChip),
        itemBuilder: (_, i) {
          final (filter, label, count, tintBg, tintFg) = chips[i];
          final selected = filter == _filter;
          final bg = selected ? (tintFg ?? AppColors.ink) : (tintBg ?? AppColors.surface);
          final fg = selected ? Colors.white : (tintFg ?? AppColors.body);
          final border = selected ? bg : (tintBg != null ? Colors.transparent : AppColors.hairline);
          return GestureDetector(
            onTap: () => setState(() => _filter = selected ? const _AllFilter() : filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: AppText.chip(color: fg)),
                  const SizedBox(width: 5),
                  Text('$count',
                      style: AppText.chip(color: fg.withValues(alpha: selected ? 0.8 : 0.7))
                          .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _resultRow(int count) {
    final what = switch (_filter) {
      _AllFilter() => '',
      _LowFilter() => tr(' running low'),
      _OutFilter() => tr(' out of stock'),
      _CategoryFilter(name: final n) => tr(' in {category}', {'category': n}),
    };
    final forQ = _search.isNotEmpty ? tr(' for "{q}"', {'q': _search}) : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 2, AppSpace.screenH, 8),
      child: Row(
        children: [
          Expanded(
            child: Text('${trCount(count, '{n} result', '{n} results')}$what$forQ',
                style: AppText.body(), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          GestureDetector(
            onTap: () {
              _searchCtrl.clear();
              setState(() {
                _search = '';
                _filter = const _AllFilter();
              });
            },
            child: Text(tr('Clear'), style: AppText.chip(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ── Sort / layout sheet ──────────────────────────────────────────────────
  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget sortRow(_Sort s, String label, IconData icon) {
            final on = _sort == s;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() => _sort = s);
                  setSheet(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: on ? AppColors.primary : AppColors.muted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(label,
                            style: AppText.cardTitle(color: on ? AppColors.primary : AppColors.ink)
                                .copyWith(fontSize: 14.5)),
                      ),
                      if (on) const Icon(Icons.check_rounded, size: 20, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            );
          }

          Widget layoutHalf(_View v, IconData icon, String label) {
            final on = _view == v;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  _setView(v);
                  setSheet(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 42,
                  decoration: BoxDecoration(
                    color: on ? AppColors.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.iconBtn - 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: on ? Colors.white : AppColors.body),
                      const SizedBox(width: 7),
                      Text(label, style: AppText.chip(color: on ? Colors.white : AppColors.body)),
                    ],
                  ),
                ),
              ),
            );
          }

          return Container(
            padding: EdgeInsets.fromLTRB(AppSpace.sheetPad, 14, AppSpace.sheetPad,
                20 + MediaQuery.paddingOf(ctx).bottom),
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
                    decoration: BoxDecoration(
                        color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 18),
                _sectionLabel(tr('Sort by')),
                const SizedBox(height: 4),
                sortRow(_Sort.name, tr('Name A–Z'), Icons.sort_by_alpha_rounded),
                sortRow(_Sort.stockAsc, tr('Stock, low first'), Icons.trending_down_rounded),
                sortRow(_Sort.priceDesc, tr('Price, high first'), Icons.payments_outlined),
                sortRow(_Sort.recent, tr('Recently added'), Icons.schedule_rounded),
                const SizedBox(height: 16),
                _sectionLabel(tr('Layout')),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: Row(
                    children: [
                      layoutHalf(_View.list, Icons.view_list_rounded, tr('List')),
                      layoutHalf(_View.grid, Icons.grid_view_rounded, tr('Grid')),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Bodies ───────────────────────────────────────────────────────────────
  Widget _gridBody(List<Product> items) {
    // A 2-up grid stretches badly on a tablet, so widen the run instead.
    final columns = Breakpoints.isTablet(context) ? 4 : 2;
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: AppSpace.gapGrid,
        crossAxisSpacing: AppSpace.gapGrid,
        childAspectRatio: ProductCard.aspectRatio,
      ),
      delegate: SliverChildBuilderDelegate(
        (_, i) => ProductCard(
          product: items[i],
          onTap: () => _showProductSheet(product: items[i]),
          onLongPress: () => _showQuickActions(items[i]),
        ),
        childCount: items.length,
      ),
    );
  }

  Widget _listBody(List<Product> items) {
    return SliverList.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _listRow(items[i]),
    );
  }

  Widget _skeletonList() {
    return SliverList.separated(
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, __) => SkeletonCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const SkeletonBox(width: 46, height: 46, radius: 11),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 140, height: 12, emphasis: true),
                  SizedBox(height: 8),
                  SkeletonBox(width: 90, height: 10),
                  SizedBox(height: 10),
                  SkeletonBox(height: 4, radius: 2),
                ],
              ),
            ),
            const SizedBox(width: 16),
            const SkeletonBox(width: 28, height: 20, emphasis: true),
          ],
        ),
      ),
    );
  }

  /// Stock is the hero: a big figure on the right with its minimum under it,
  /// a thin bar so the ratio reads at a glance, and a tinted row plus an
  /// inline "+ Stock" when it needs attention. Swipe right for the same.
  Widget _listRow(Product p) {
    final low = _isLow(p);
    final out = _isOut(p);
    final attention = low || out;
    final tone = StockStatus.text(p.stock, p.minStock);
    final bg = attention ? StockStatus.fill(p.stock, p.minStock) : AppColors.surface;
    final border = out
        ? AppColors.dangerBorder
        : low
            ? AppColors.warningBorder
            : AppColors.hairline;
    // Full bar at twice the minimum: "comfortably stocked" is the ceiling,
    // not the biggest number in the catalog.
    final target = (p.minStock * 2).clamp(1, 1 << 30);
    final fraction = (p.stock / target).clamp(0.0, 1.0);

    final row = Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => _showProductSheet(product: p),
        onLongPress: () => _showQuickActions(p),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: border),
            boxShadow: attention ? null : AppShadows.card,
          ),
          child: Row(
            children: [
              ProductThumb(product: p, size: 46, radius: 11),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.cardTitle(color: attention ? tone : AppColors.ink)),
                    const SizedBox(height: 3),
                    Text('${p.category} · ${formatPeso(p.price)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption(color: attention ? tone : AppColors.muted)),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 4,
                        child: Stack(
                          children: [
                            Container(color: attention ? AppColors.surface : AppColors.divider),
                            FractionallySizedBox(
                              widthFactor: fraction,
                              child: Container(color: StockStatus.dot(p.stock, p.minStock)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${p.stock}',
                      style: AppText.statFigure(size: 19, color: attention ? tone : AppColors.ink)),
                  Text(tr('min {n}', {'n': p.minStock}),
                      style: AppText.caption(color: attention ? tone : AppColors.muted)),
                ],
              ),
              if (attention) ...[
                const SizedBox(width: 10),
                _AddStockPill(onTap: () => _showAddStockSheet(p)),
              ],
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('product-${p.id}'),
      direction: DismissDirection.startToEnd,
      // A swipe reveals the action but never removes the row.
      confirmDismiss: (_) async {
        _showAddStockSheet(p);
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 18),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_box_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(tr('Add stock'), style: AppText.chip(color: Colors.white)),
          ],
        ),
      ),
      child: row,
    );
  }

  Widget _emptyState() {
    final filtering = _narrowed;
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
            Text(filtering ? tr('No products found') : tr('No products yet'),
                style: AppText.cardTitle().copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              filtering ? tr('Try a different search or category') : tr('Add your first product to start selling'),
              textAlign: TextAlign.center,
              style: AppText.caption(),
            ),
            if (!filtering) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => _showProductSheet(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.iconBtn)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(tr('Add product'), style: AppText.chip(color: Colors.white)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Quick actions ────────────────────────────────────────────────────────
  /// Long-press menu: the three things done to a product ten times a day,
  /// without the full edit sheet in the way.
  void _showQuickActions(Product p) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        Widget action(IconData icon, String label, VoidCallback onTap,
            {Color color = AppColors.ink, Color iconBg = AppColors.canvas}) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(11)),
                      child: Icon(icon, size: 19, color: color),
                    ),
                    const SizedBox(width: 12),
                    Text(label, style: AppText.cardTitle(color: color).copyWith(fontSize: 14.5)),
                  ],
                ),
              ),
            ),
          );
        }

        return Container(
          padding: EdgeInsets.fromLTRB(AppSpace.sheetPad, 14, AppSpace.sheetPad,
              16 + MediaQuery.paddingOf(ctx).bottom),
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
                  decoration:
                      BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ProductThumb(product: p, size: 44, radius: 11),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sectionTitle()),
                        const SizedBox(height: 2),
                        Text(tr('{n} in stock · {price}', {'n': p.stock, 'price': formatPeso(p.price)}), style: AppText.caption()),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 6),
              action(Icons.add_box_outlined, tr('Add stock'), () => _showAddStockSheet(p),
                  color: AppColors.primary, iconBg: AppColors.primaryTint),
              action(Icons.edit_outlined, tr('Edit'), () => _showProductSheet(product: p)),
              action(
                Icons.photo_camera_outlined,
                (p.imagePath ?? '').isEmpty ? tr('Take photo') : tr('Retake photo'),
                () => _snapPhoto(p),
              ),
              action(Icons.copy_rounded, tr('Duplicate'), () => _showProductSheet(template: p)),
              action(Icons.delete_outline_rounded, tr('Delete'), () => _deleteWithUndo(p),
                  color: AppColors.danger, iconBg: AppColors.dangerFill),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddStockSheet(Product p) async {
    final added = await showAddStockSheet(context, p);
    if (added == null || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(_snack(tr('Added {n} · {name} now {after}', {'n': added, 'name': p.name, 'after': p.stock + added})));
  }

  /// Delete now, offer Undo for a few seconds. The row comes back with the
  /// same id, so sale history that points at it stays intact.
  Future<void> _deleteWithUndo(Product p) async {
    await _productService.deleteProduct(p.id!);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(_snack(
        tr('Deleted {name}', {'name': p.name}),
        action: SnackBarAction(
          label: tr('Undo'),
          textColor: AppColors.primary,
          onPressed: () async {
            await _productService.insertProduct(p);
            _load();
          },
        ),
      ));
  }

  /// One of the two buttons drawn inside the empty photo slot. Purely
  /// visual — the whole slot is the tap target.
  Widget _photoCta(IconData icon, String label, {bool primary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: primary ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: primary ? AppColors.primary : AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: primary ? Colors.white : AppColors.body),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.chip(color: primary ? Colors.white : AppColors.body)),
          ),
        ],
      ),
    );
  }

  SnackBar _snack(String text, {SnackBarAction? action}) {
    return SnackBar(
      content: Text(text, style: AppText.body(color: Colors.white)),
      backgroundColor: AppColors.ink,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      // Sit above the raised Sell button rather than under it.
      margin: EdgeInsets.fromLTRB(AppSpace.screenH, 0, AppSpace.screenH,
          12 + MediaQuery.paddingOf(context).bottom),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.input)),
      action: action,
    );
  }

  // ── Add / edit sheet ─────────────────────────────────────────────────────
  /// [product] edits in place; [template] seeds a new product from an
  /// existing one (Duplicate) — same name, price, category and photo, but no
  /// SKU (they are unique) and no stock (it has not been counted yet).
  void _showProductSheet({Product? product, Product? template, String? presetSku}) {
    final isEdit = product != null;
    final seed = product ?? template;
    final nameCtrl = TextEditingController(text: seed?.name ?? '');
    final priceCtrl = TextEditingController(text: seed != null ? seed.price.toStringAsFixed(2) : '');
    final skuCtrl = TextEditingController(text: presetSku ?? product?.sku ?? '');
    final categoryCtrl = TextEditingController(text: seed?.category ?? '');
    final formKey = GlobalKey<FormState>();

    String? imagePath = seed?.imagePath;
    int stock = product?.stock ?? 0;
    // A new product starts at the store's configured default minimum.
    int minStock = seed?.minStock ?? SettingsService.instance.defaultMinStock;

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
                            Text(isEdit ? tr('Edit product') : (template != null ? tr('Duplicate product') : tr('New product')),
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
                          _sectionLabel(tr('Product information')),
                          const SizedBox(height: 10),
                          Builder(builder: (_) {
                            final hasPhoto = imagePath != null && imagePath!.isNotEmpty;
                            return GestureDetector(
                              onTap: () async {
                                final path = await _choosePhoto(hasPhoto: hasPhoto);
                                if (path == null) return;
                                // '' means "remove"; the file itself is only
                                // discarded once the product is saved.
                                setSheet(() => imagePath = path.isEmpty ? null : path);
                              },
                              child: Container(
                                width: double.infinity,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: AppColors.canvas,
                                  borderRadius: BorderRadius.circular(AppRadius.input),
                                  border: Border.all(color: AppColors.hairline),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: hasPhoto
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.file(File(imagePath!), fit: BoxFit.cover),
                                          Positioned(
                                            right: 10,
                                            bottom: 10,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: AppColors.ink.withValues(alpha: 0.72),
                                                borderRadius: BorderRadius.circular(AppRadius.chip),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.photo_camera_outlined,
                                                      size: 14, color: Colors.white),
                                                  const SizedBox(width: 5),
                                                  Text(tr('Replace'), style: AppText.chip(color: Colors.white)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Flexible(child: _photoCta(Icons.photo_camera_outlined, tr('Take photo'), primary: true)),
                                          const SizedBox(width: 10),
                                          Flexible(child: _photoCta(Icons.photo_library_outlined, tr('Gallery'))),
                                        ],
                                      ),
                              ),
                            );
                          }),
                          const SizedBox(height: 14),
                          _fieldLabel(tr('Product name')),
                          _field(nameCtrl, hint: tr('e.g. SkyFlakes'),
                              validator: (v) => (v == null || v.trim().isEmpty) ? tr('Required') : null),
                          const SizedBox(height: 14),
                          _fieldLabel(tr('SKU / barcode')),
                          Row(
                            children: [
                              Expanded(child: _field(skuCtrl, hint: tr('Optional'))),
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
                          _fieldLabel(tr('Category')),
                          _field(categoryCtrl, hint: tr('e.g. Biscuits'),
                              validator: (v) => (v == null || v.trim().isEmpty) ? tr('Required') : null),

                          const SizedBox(height: 20),
                          const Divider(color: AppColors.divider, height: 1),
                          const SizedBox(height: 18),
                          _sectionLabel(tr('Pricing')),
                          const SizedBox(height: 10),
                          _fieldLabel(tr('Selling price')),
                          _field(priceCtrl,
                              hint: '0.00',
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              prefixText: '₱ ',
                              validator: (v) =>
                                  (double.tryParse(v ?? '') == null) ? tr('Enter a price') : null),

                          const SizedBox(height: 20),
                          const Divider(color: AppColors.divider, height: 1),
                          const SizedBox(height: 18),
                          _sectionLabel(tr('Inventory')),
                          const SizedBox(height: 10),
                          _stepperRow(tr('Current stock'), stock, (v) => setSheet(() => stock = v)),
                          const SizedBox(height: 10),
                          _stepperRow(tr('Minimum stock'), minStock, (v) => setSheet(() => minStock = v)),
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
                                      tr('Stock is at or below the minimum — this product will show in Restock.'),
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
                          _sectionLabel(tr('Actions')),
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
                                var photo = imagePath;
                                // A duplicate must not share the original's
                                // file, or deleting either would blank both.
                                if (template != null && photo != null && photo == template.imagePath) {
                                  photo = await _images.duplicate(photo);
                                }
                                final p = Product(
                                  id: product?.id,
                                  name: nameCtrl.text.trim(),
                                  stock: stock,
                                  minStock: minStock,
                                  category: categoryCtrl.text.trim(),
                                  createdAt: product?.createdAt ?? DateTime.now().toIso8601String(),
                                  price: double.tryParse(priceCtrl.text) ?? 0,
                                  sku: skuCtrl.text.trim().isEmpty ? null : skuCtrl.text.trim(),
                                  imagePath: photo,
                                );
                                if (isEdit) {
                                  await _productService.updateProduct(p);
                                  // The photo that was replaced or removed is
                                  // nobody's now.
                                  final old = product.imagePath;
                                  if (old != null && old != photo) _images.discard(old);
                                } else {
                                  await _productService.insertProduct(p);
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                                _load();
                              },
                              child: Text(isEdit ? tr('Save changes') : tr('Save product'),
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
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _deleteWithUndo(product);
                                },
                                child: Text(tr('Delete product'),
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
        children: [
          Expanded(child: Text(label, style: AppText.body())),
          const SizedBox(width: 8),
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

// ── Bits ───────────────────────────────────────────────────────────────────────
/// Fixed-height pinned block for the search row and chips.
class _PinnedHeader extends SliverPersistentHeaderDelegate {
  const _PinnedHeader({required this.height, required this.child});

  final double height;
  final Widget child;

  static double heightFor({required bool showChips}) => 46 + 10 + (showChips ? 36 + 10 : 0);

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_PinnedHeader old) => old.height != height || old.child != child;
}

/// Inline "+ Stock" on a low or out row: the row already knows what is
/// wrong, so it offers the fix.
class _AddStockPill extends StatelessWidget {
  const _AddStockPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr('Add stock'),
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(9, 8, 11, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 16, color: Colors.white),
                SizedBox(width: 2),
                Text(tr('Stock'),
                    style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _PhotoChoice { camera, gallery, remove }
