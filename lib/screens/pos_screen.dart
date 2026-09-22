import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import '../models/backup_status.dart';
import '../core/responsive.dart';
import '../models/cart_line.dart';
import '../models/product_model.dart';
import '../models/sale_model.dart';
import '../services/held_sales.dart';
import '../services/product_service.dart';
import '../services/sales_service.dart';
import '../services/settings_service.dart';
import '../widgets/cart_bar.dart';
import '../widgets/fly_to_cart.dart';
import '../widgets/product_card.dart';
import '../widgets/product_thumb.dart';
import 'barcode_scanner_screen.dart';
import 'checkout_screen.dart';
import 'product_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with TickerProviderStateMixin {
  final ProductService _productService = ProductService();
  final SalesService _salesService = SalesService();

  List<Product> _products = [];
  bool _loading = true;
  String _search = '';
  String _category = 'All';
  final Map<int, int> _cart = {}; // productId -> qty

  // ── Speed ────────────────────────────────────────────────────────────────
  /// A pseudo-category of the products sold most this fortnight. Most of a
  /// store's sales are the same twenty items; this puts them one tap away.
  static const _kPopular = 'Popular';

  /// Product ids in sold-most-first order, empty until there is history.
  List<int> _frequentIds = const [];

  /// The sale before this one, for "repeat last sale".
  Sale? _lastSale;
  bool _pickedDefaultCategory = false;

  // ── Add-to-cart choreography ─────────────────────────────────────────────
  // A tapped product flies from the card into the bar's bag icon, and the
  // bar only counts it once it lands. [_cart] is the truth the whole time;
  // the bar shows [_cart] minus whatever is still in the air.
  final CartBarController _bar = CartBarController();
  final List<FlyToCart> _flights = [];
  int _inFlightCount = 0;
  double _inFlightTotal = 0;

  /// Where the last product tap landed, so the flight starts under the thumb.
  Offset? _lastTapAt;

  int get _shownCount => (_cartCount - _inFlightCount).clamp(0, _cartCount);
  double get _shownTotal => (_cartTotal - _inFlightTotal).clamp(0, _cartTotal);

  @override
  void initState() {
    super.initState();
    HeldSales.instance.addListener(_onHeldChanged);
    HeldSales.instance.load();
    _load();
  }

  @override
  void dispose() {
    HeldSales.instance.removeListener(_onHeldChanged);
    for (final f in _flights) {
      f.cancel();
    }
    super.dispose();
  }

  void _onHeldChanged() {
    if (mounted) setState(() {});
  }

  /// Bring every airborne chip down immediately. Called whenever the cart
  /// changes by some route other than a card tap, so the bar never shows a
  /// figure that the in-flight arithmetic cannot account for.
  void _settleFlights() {
    if (_flights.isEmpty) return;
    for (final f in _flights) {
      f.cancel();
    }
    _flights.clear();
    _inFlightCount = 0;
    _inFlightTotal = 0;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final products = await _productService.getAllProducts();
    final frequent = await _salesService.frequentProductIds(14, limit: 12);
    final recent = await _salesService.getRecentSales(limit: 1);
    if (!mounted) return;
    setState(() {
      _products = products;
      // Only ids that still exist and can be sold earn a place.
      _frequentIds = [
        for (final id in frequent)
          if (products.any((p) => p.id == id)) id,
      ];
      _lastSale = recent.isEmpty ? null : recent.first;
      _loading = false;
      // Open on Popular once there is enough history for it to be useful;
      // a store with three products sold is better served by All.
      if (!_pickedDefaultCategory) {
        _pickedDefaultCategory = true;
        if (_frequentIds.length >= 6) _category = _kPopular;
      }
    });
  }

  List<String> get _categories {
    final cats = _products.map((p) => p.category).toSet().toList()..sort();
    return [if (_frequentIds.isNotEmpty) _kPopular, 'All', ...cats];
  }

  List<Product> get _filtered {
    final q = _search.toLowerCase();
    // A search reaches the whole catalog whatever chip is selected: the
    // cashier typing a name has already said which product they want.
    if (_category == _kPopular && q.isEmpty) {
      return [
        for (final id in _frequentIds) _products.firstWhere((p) => p.id == id),
      ];
    }
    return _products.where((p) {
      final matchQ = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          (p.sku ?? '').toLowerCase().contains(q);
      final matchCat = q.isNotEmpty || _category == 'All' || _category == _kPopular || p.category == _category;
      return matchQ && matchCat;
    }).toList();
  }

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

  /// Adds [qty] of [product], capped at what is on the shelf.
  void _addToCart(Product product, {int qty = 1}) {
    if (product.id == null || product.stock <= 0 || qty <= 0) return;
    final inCart = _cart[product.id] ?? 0;
    if (inCart >= product.stock) {
      // Nothing more to give: a firm buzz says "no" without a dialog.
      HapticFeedback.heavyImpact();
      return;
    }
    final added = (product.stock - inCart).clamp(0, qty);
    HapticFeedback.selectionClick();
    setState(() => _cart[product.id!] = inCart + added);
    _fly(product, qty: added);
  }

  /// Send [product] from the tapped card to the bag. Falls back to landing
  /// on the spot when there is nothing to fly to (tablet cart column, or a
  /// scanner add with no tap position).
  void _fly(Product product, {int qty = 1}) {
    final from = _lastTapAt;
    final to = _bar.bagCenter();
    if (from == null || to == null) {
      _bar.bump();
      return;
    }
    final value = product.price * qty;
    _inFlightCount += qty;
    _inFlightTotal += value;
    late final FlyToCart flight;
    flight = FlyToCart.launch(
      context: context,
      vsync: this,
      product: product,
      from: from,
      to: to,
      qty: qty,
      onLand: () {
        if (!mounted) return;
        _flights.remove(flight);
        setState(() {
          _inFlightCount = (_inFlightCount - qty).clamp(0, _inFlightCount);
          _inFlightTotal = (_inFlightTotal - value).clamp(0, _inFlightTotal);
        });
        HapticFeedback.lightImpact();
        _bar.bump();
      },
    );
    _flights.add(flight);
  }

  /// Long-press: how many? A keypad for the bulk buys — a dozen eggs, six
  /// sachets — that would otherwise be a dozen taps.
  void _showQtySheet(Product product) {
    if (product.id == null || product.stock <= 0) return;
    HapticFeedback.mediumImpact();
    final inCart = _cart[product.id] ?? 0;
    final room = product.stock - inCart;
    if (room <= 0) {
      HapticFeedback.heavyImpact();
      return;
    }
    final ctrl = TextEditingController();
    int qty = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final capped = qty.clamp(0, room);
          final overRoom = qty > room;

          void confirm() {
            if (capped <= 0) return;
            Navigator.pop(ctx);
            _addToCart(product, qty: capped);
          }

          Widget quick(int n) => Expanded(
                child: GestureDetector(
                  onTap: () {
                    ctrl.text = '$n';
                    setSheet(() => qty = n);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: qty == n ? AppColors.ink : AppColors.canvas,
                      borderRadius: BorderRadius.circular(AppRadius.iconBtn),
                      border: Border.all(color: qty == n ? AppColors.ink : AppColors.hairline),
                    ),
                    child: Text('$n', style: AppText.chip(color: qty == n ? Colors.white : AppColors.ink)),
                  ),
                ),
              );

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Container(
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ProductThumb(product: product, size: 44, radius: 11),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.sectionTitle()),
                            const SizedBox(height: 2),
                            Text(
                              '${formatPeso(product.price)} each · $room available'
                              '${inCart > 0 ? ' · $inCart in cart' : ''}',
                              style: AppText.caption(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.canvas,
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      border: Border.all(color: overRoom ? AppColors.danger : AppColors.hairline),
                    ),
                    child: TextField(
                      controller: ctrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      style: AppText.largeFigure(),
                      onChanged: (v) => setSheet(() => qty = int.tryParse(v) ?? 0),
                      onSubmitted: (_) => confirm(),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        hintText: '0',
                        hintStyle: AppText.largeFigure(color: AppColors.faint),
                      ),
                    ),
                  ),
                  if (overRoom) ...[
                    const SizedBox(height: 6),
                    Text('Only $room left — adding $capped',
                        style: AppText.caption(color: AppColors.dangerText)),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      quick(2),
                      const SizedBox(width: 8),
                      quick(3),
                      const SizedBox(width: 8),
                      quick(6),
                      const SizedBox(width: 8),
                      quick(12),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: capped > 0 ? confirm : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.disabledFill,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.cta)),
                      ),
                      child: Text(
                        capped > 0 ? 'Add $capped · ${formatPeso(product.price * capped)}' : 'Add to sale',
                        style: AppText.chip(color: Colors.white).copyWith(fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Repeat / hold ────────────────────────────────────────────────────────
  /// Puts the last sale's lines back in the cart, as far as stock allows.
  void _repeatLastSale() {
    final sale = _lastSale;
    if (sale == null || sale.items.isEmpty) return;
    _settleFlights();
    var skipped = 0;
    setState(() {
      for (final item in sale.items) {
        final product = _products.where((p) => p.id == item.productId).firstOrNull;
        if (product == null || product.stock <= 0) {
          skipped++;
          continue;
        }
        final have = _cart[product.id] ?? 0;
        final add = (product.stock - have).clamp(0, item.qty);
        if (add <= 0) {
          skipped++;
          continue;
        }
        _cart[product.id!] = have + add;
      }
    });
    HapticFeedback.lightImpact();
    _bar.bump();
    if (skipped > 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(_snack('$skipped item${skipped == 1 ? '' : 's'} skipped — out of stock'));
    }
  }

  /// Sets the running sale aside so the next customer can be served.
  Future<void> _holdSale() async {
    if (_cart.isEmpty) return;
    _settleFlights();
    final label = _cartLines.take(2).map((l) => l.qty > 1 ? '${l.product.name} ×${l.qty}' : l.product.name).join(', ');
    final more = _cartLines.length - 2;
    await HeldSales.instance.hold(_cart, label: more > 0 ? '$label +$more more' : label);
    if (!mounted) return;
    setState(_cart.clear);
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(_snack('Sale held — tap Held to bring it back'));
  }

  /// Brings a held sale back. A running sale is held in its place rather
  /// than merged or lost: the two customers' baskets stay separate.
  Future<void> _resumeHeld(HeldSale held) async {
    _settleFlights();
    if (_cart.isNotEmpty) await _holdSale();
    await HeldSales.instance.remove(held.id);
    if (!mounted) return;
    setState(() {
      _cart.clear();
      held.lines.forEach((id, qty) {
        final product = _products.where((p) => p.id == id).firstOrNull;
        if (product == null || product.stock <= 0) return;
        _cart[id] = qty.clamp(1, product.stock);
      });
    });
    HapticFeedback.lightImpact();
    _bar.bump();
  }

  void _showHeldSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ListenableBuilder(
        listenable: HeldSales.instance,
        builder: (ctx, _) {
          final held = HeldSales.instance.sales;
          if (held.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted) Navigator.pop(ctx);
            });
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
                Text('Held sales', style: AppText.sectionTitle().copyWith(fontSize: 18)),
                const SizedBox(height: 2),
                Text('Tap one to bring it back to the register.', style: AppText.caption()),
                const SizedBox(height: 12),
                for (final h in held) _heldRow(ctx, h),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _heldRow(BuildContext sheetCtx, HeldSale h) {
    final t = TimeOfDay.fromDateTime(h.heldAt).format(context);
    final total = h.lines.entries.fold<double>(0, (sum, e) {
      final p = _products.where((p) => p.id == e.key).firstOrNull;
      return sum + (p?.price ?? 0) * e.value;
    });
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadius.input),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.input),
          onTap: () {
            Navigator.pop(sheetCtx);
            _resumeHeld(h);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                const Icon(Icons.pause_circle_outline_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.label.isEmpty ? '${h.itemCount} items' : h.label,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
                      const SizedBox(height: 2),
                      Text('${h.itemCount} item${h.itemCount == 1 ? '' : 's'} · held $t', style: AppText.caption()),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(formatPeso(total), style: AppText.cardTitle()),
                IconButton(
                  tooltip: 'Discard',
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                  onPressed: () => HeldSales.instance.remove(h.id),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Look and placement come from the app theme: Scaffold floats it above
  /// the cart bar on its own.
  SnackBar _snack(String text) => SnackBar(content: Text(text), duration: const Duration(seconds: 3));

  /// Decrement a line; at zero the line leaves the cart entirely.
  void _decrementLine(int productId) {
    _settleFlights();
    final qty = _cart[productId] ?? 0;
    if (qty <= 1) {
      setState(() => _cart.remove(productId));
    } else {
      setState(() => _cart[productId] = qty - 1);
    }
  }

  void _incrementLine(int productId) {
    _settleFlights();
    final product = _products.firstWhere((p) => p.id == productId);
    final qty = _cart[productId] ?? 0;
    if (qty >= product.stock) return;
    setState(() => _cart[productId] = qty + 1);
  }

  Future<void> _scan() async {
    // On a tablet the scanner floats over the POS as a dialog, so the cart
    // column stays visible beside the running sale instead of being replaced.
    ScannerResult? result;
    if (Breakpoints.isTablet(context)) {
      result = await showDialog<ScannerResult>(
        context: context,
        barrierColor: AppColors.ink.withValues(alpha: 0.55),
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.hero),
            child: const SizedBox(
              width: 470,
              height: 640,
              child: SimpleBarcodeScannerScreen.forSale(),
            ),
          ),
        ),
      );
    } else {
      result = await Navigator.push<ScannerResult>(
        context,
        MaterialPageRoute(builder: (_) => const SimpleBarcodeScannerScreen.forSale()),
      );
    }
    if (result is! ScanSale || !mounted) return;
    // A mutable local is not promoted inside a closure, so bind it here.
    final scanned = result;

    if (scanned.added.isNotEmpty) {
      _settleFlights();
      setState(() {
        scanned.added.forEach((id, qty) {
          _cart.update(id, (v) => v + qty, ifAbsent: () => qty);
        });
      });
      // No card was tapped, so there is nowhere to fly from; just land.
      HapticFeedback.lightImpact();
      _bar.bump();
    }

    // "Add as new product" on an unknown code hands us the SKU to pre-fill.
    final sku = scanned.newProductSku;
    if (sku != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductsScreen(newProductSku: sku)),
      );
      if (mounted) _load();
    }
  }

  Future<void> _openCheckout() async {
    final lines = _cartLines;
    if (lines.isEmpty) return;
    final outcome = await Navigator.push<CheckoutOutcome>(
      context,
      MaterialPageRoute(builder: (_) => CheckoutScreen(lines: lines)),
    );
    if (outcome == null || !mounted) return;
    _settleFlights();
    setState(_cart.clear);
    if (outcome == CheckoutOutcome.completed) _load();
  }

  /// The cart bar's body opens the line editor; its Checkout button goes
  /// straight to payment.
  void _openCartSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final lines = _cartLines;
          if (lines.isEmpty) {
            // Last line was just removed — close rather than show an empty sheet.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (ctx.mounted) Navigator.pop(ctx);
            });
          }
          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            padding: const EdgeInsets.fromLTRB(AppSpace.sheetPad, 14, AppSpace.sheetPad, 20),
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
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text('Current sale', style: AppText.sectionTitle().copyWith(fontSize: 18)),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _holdSale();
                      },
                      child: Row(
                        children: [
                          const Icon(Icons.pause_rounded, size: 16, color: AppColors.primary),
                          const SizedBox(width: 2),
                          Text('Hold', style: AppText.chip(color: AppColors.primary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () {
                        _settleFlights();
                        setState(_cart.clear);
                        Navigator.pop(ctx);
                      },
                      child: Text('Clear all', style: AppText.chip(color: AppColors.danger)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Swipe a line to remove it', style: AppText.caption(color: AppColors.faint)),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const Divider(color: AppColors.divider, height: 18),
                    itemBuilder: (_, i) {
                      final line = lines[i];
                      final id = line.product.id!;
                      return _swipeToRemove(
                        key: ValueKey('sheet-$id'),
                        onRemove: () {
                          _settleFlights();
                          setState(() => _cart.remove(id));
                          setSheet(() {});
                        },
                        child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.product.name,
                                    style: AppText.cardTitle(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 2),
                                Text(
                                  '${formatPeso(line.product.price)} · ${formatPeso(line.lineTotal)}',
                                  style: AppText.caption(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          QtyStepper(
                            value: line.qty,
                            figureSize: 17,
                            canIncrement: line.qty < line.product.stock,
                            decrementIcon:
                                line.qty <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
                            onDecrement: () {
                              _decrementLine(id);
                              setSheet(() {});
                            },
                            onIncrement: () {
                              _incrementLine(id);
                              setSheet(() {});
                            },
                          ),
                        ],
                      ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: AppText.sectionTitle()),
                    Text(formatPeso(_cartTotal), style: AppText.largeFigure().copyWith(fontSize: 22)),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openCheckout();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                    ),
                    child: Text('Checkout', style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
            _searchRow(),
            _quickRow(),
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
      floatingActionButton: _floatingCart(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// Tablet: the checkout sheet becomes a persistent right-hand cart column,
  /// so nav, products and cart are all visible with no screen change.
  Widget _tabletLayout() {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  _header(),
                  _searchRow(),
                  _quickRow(),
                  const SizedBox(height: 12),
                  _categoryChips(),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(color: AppColors.primary))
                        : _grid(columns: 4, bottomPadding: 24),
                  ),
                ],
              ),
            ),
            SizedBox(width: 360, child: _cartColumn()),
          ],
        ),
      ),
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
                Text(SettingsService.instance.storeName, style: AppText.cardTitle()),
                const SizedBox(height: 1),
                Text('Cashier · ${SettingsService.instance.cashier}', style: AppText.caption()),
              ],
            ),
          ),
          // Was a green "Synced" pill. Nothing syncs — there is no server and
          // no account — so it now carries the one fact in this slot that is
          // true and worth acting on: how old the last backup is.
          _backupPill(),
        ],
      ),
    );
  }

  Widget _backupPill() {
    final raw = SettingsService.instance.lastBackup;
    final status = BackupStatus.from(raw == null ? null : DateTime.tryParse(raw));
    return switch (status.level) {
      BackupLevel.fresh => StatusPill(
          label: status.label,
          fg: AppColors.successText,
          bg: AppColors.successFill),
      BackupLevel.stale => StatusPill(
          label: status.label,
          fg: AppColors.warningText,
          bg: AppColors.warningFill),
      BackupLevel.none => StatusPill(
          label: status.label,
          fg: AppColors.warningText,
          bg: AppColors.warningFill),
    };
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

  /// Persistent cart pane. Lines carry their own compact steppers, so quantity
  /// changes never need a sheet.
  Widget _cartColumn() {
    final lines = _cartLines;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.dividerStrong)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text('Current sale',
                      style: AppText.sectionTitle().copyWith(fontSize: 17)),
                ),
                if (HeldSales.instance.count > 0) ...[
                  _QuickPill(
                    icon: Icons.pause_circle_outline_rounded,
                    label: 'Held',
                    badge: HeldSales.instance.count,
                    onTap: _showHeldSheet,
                    tint: true,
                    dense: true,
                  ),
                  const SizedBox(width: 12),
                ],
                if (lines.isNotEmpty) ...[
                  GestureDetector(
                    onTap: _holdSale,
                    child: Text('Hold', style: AppText.chip(color: AppColors.primary)),
                  ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: () {
                      _settleFlights();
                      setState(_cart.clear);
                    },
                    child: Text('Clear', style: AppText.chip(color: AppColors.danger)),
                  ),
                ],
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.canvas,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.shopping_bag_outlined,
                                color: AppColors.muted, size: 24),
                          ),
                          const SizedBox(height: 12),
                          Text('No items yet', style: AppText.cardTitle()),
                          const SizedBox(height: 4),
                          Text('Tap a product to add it, or hold to choose a quantity.',
                              textAlign: TextAlign.center, style: AppText.caption()),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: lines.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: AppColors.divider, height: 1),
                    itemBuilder: (_, i) => _swipeToRemove(
                      key: ValueKey('col-${lines[i].product.id}'),
                      onRemove: () {
                        _settleFlights();
                        setState(() => _cart.remove(lines[i].product.id!));
                      },
                      child: _cartLineRow(lines[i]),
                    ),
                  ),
          ),
          if (lines.isNotEmpty) _cartFooter(),
        ],
      ),
    );
  }

  Widget _cartLineRow(CartLine line) {
    final id = line.product.id!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.product.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
                const SizedBox(height: 2),
                Text(formatPeso(line.product.price), style: AppText.caption()),
              ],
            ),
          ),
          const SizedBox(width: 8),
          QtyStepper(
            value: line.qty,
            compact: true,
            figureSize: 15,
            canIncrement: line.qty < line.product.stock,
            decrementIcon: line.qty <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded,
            onDecrement: () => _decrementLine(id),
            onIncrement: () => _incrementLine(id),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(formatPeso(line.lineTotal),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.cardTitle()),
          ),
        ],
      ),
    );
  }

  Widget _cartFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal', style: AppText.body()),
              Text(formatPeso(_cartTotal), style: AppText.cardTitle()),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items', style: AppText.body()),
              Text('$_cartCount', style: AppText.cardTitle()),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: AppText.sectionTitle()),
              Flexible(
                child: Text(formatPeso(_cartTotal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.largeFigure().copyWith(fontSize: 22)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _openCheckout,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.cta)),
              ),
              child: Text('Charge · ${formatPeso(_cartTotal)}',
                  style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  /// "Repeat last sale" while the cart is empty, and the held-sales chip
  /// whenever there is something held. Collapses to nothing otherwise, so
  /// the grid keeps its height on a store with no history.
  Widget _quickRow() {
    final last = _lastSale;
    final canRepeat = _cart.isEmpty && last != null && last.items.isNotEmpty && !_loading;
    final heldCount = HeldSales.instance.count;
    if (!canRepeat && heldCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 10, AppSpace.screenH, 0),
      child: Row(
        children: [
          if (canRepeat)
            Expanded(
              child: _QuickPill(
                icon: Icons.replay_rounded,
                label: 'Repeat last sale',
                detail: last.summary(),
                onTap: _repeatLastSale,
              ),
            ),
          if (canRepeat && heldCount > 0) const SizedBox(width: 8),
          if (heldCount > 0)
            _QuickPill(
              icon: Icons.pause_circle_outline_rounded,
              label: 'Held',
              badge: heldCount,
              onTap: _showHeldSheet,
              tint: true,
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c == _kPopular) ...[
                    Icon(Icons.bolt_rounded, size: 15, color: selected ? Colors.white : AppColors.primary),
                    const SizedBox(width: 3),
                  ],
                  Text(c, style: AppText.chip(color: selected ? Colors.white : AppColors.body)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _grid({int columns = 2, double bottomPadding = 140}) {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text('No products found', style: AppText.body()),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(AppSpace.screenH, 10, AppSpace.screenH, bottomPadding),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: AppSpace.gapGrid,
        crossAxisSpacing: AppSpace.gapGrid,
        childAspectRatio: ProductCard.aspectRatio,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => Listener(
        // Remember where the finger went down so the flight to the bag can
        // start from under it rather than from the card's corner.
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => _lastTapAt = e.position,
        child: ProductCard(
          product: items[i],
          qtyInCart: _cart[items[i].id] ?? 0,
          dimWhenOut: true,
          onTap: items[i].stock <= 0 ? null : () => _addToCart(items[i]),
          onLongPress: items[i].stock <= 0 ? null : () => _showQtySheet(items[i]),
        ),
      ),
    );
  }

  /// A line that can be swiped away. The red backdrop and the bin make the
  /// gesture discoverable the first time; after that it is just faster than
  /// stepping the quantity down.
  Widget _swipeToRemove({required Key key, required VoidCallback onRemove, required Widget child}) {
    return Dismissible(
      key: key,
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        HapticFeedback.lightImpact();
        onRemove();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        color: AppColors.dangerFill,
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.dangerText, size: 22),
      ),
      child: child,
    );
  }

  Widget _floatingCart() {
    return CartBar(
      controller: _bar,
      count: _shownCount,
      total: _shownTotal,
      onTap: _openCartSheet,
      onCheckout: _openCheckout,
    );
  }
}

/// A slim action above the chips: repeat the last sale, or open held sales.
class _QuickPill extends StatelessWidget {
  const _QuickPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.badge,
    this.tint = false,
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final int? badge;
  final VoidCallback onTap;
  final bool tint;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = tint ? AppColors.primary : AppColors.ink;
    return Material(
      color: tint ? AppColors.primaryTint : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: onTap,
        child: Container(
          height: dense ? 32 : 38,
          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: tint ? Colors.transparent : AppColors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 6),
              // With a detail the pill sits in an Expanded, so both texts
              // can give way; without one it sizes to its content.
              if (detail != null)
                Flexible(
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.chip(color: fg)),
                )
              else
                Text(label, style: AppText.chip(color: fg)),
              if (detail != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(detail!,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption()),
                ),
              ],
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text('$badge', style: AppText.chip(color: Colors.white).copyWith(fontSize: 11)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
