import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen>
    with TickerProviderStateMixin {
  final ProductService _productService = ProductService();

  // ── Design Tokens ─────────────────────────────────────────────────────
  static const Color _white        = Color(0xFFFFFFFF);
  static const Color _bg           = Color(0xFFF7F8FC);
  static const Color _cardBg       = Color(0xFFFFFFFF);
  static const Color _ink          = Color(0xFF0D0F1A);
  static const Color _inkMid       = Color(0xFF5A5F7A);
  static const Color _inkLight     = Color(0xFFB0B5CC);
  static const Color _border       = Color(0xFFEAECF5);
  static const Color _accent       = Color(0xFF2563EB);
  static const Color _accentLight  = Color(0xFFEEF3FF);
  static const Color _success      = Color(0xFF16A34A);
  static const Color _successBg    = Color(0xFFECFDF5);
  static const Color _warning      = Color(0xFFD97706);
  static const Color _warningBg    = Color(0xFFFFFBEB);
  static const Color _danger       = Color(0xFFDC2626);
  static const Color _dangerBg     = Color(0xFFFEF2F2);

  List<Product> _products   = [];
  String  _searchQuery      = "";
  String  _selectedCategory = "All";
  bool    _loading          = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.light,
      statusBarIconBrightness: Brightness.dark,
      statusBarColor: Colors.transparent,
    ));
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final products = await _productService.getAllProducts();
    setState(() {
      _products = products;
      _loading  = false;
    });
  }

  List<String> get _categories {
    final cats = _products.map((p) => p.category).toSet().toList()..sort();
    return ["All", ...cats];
  }

  List<Product> get _filtered => _products.where((p) {
        final matchName = p.name.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchCat  = _selectedCategory == "All" || p.category == _selectedCategory;
        return matchName && matchCat;
      }).toList();

  int get _totalItems    => _products.fold(0, (s, p) => s + p.stock);
  int get _lowStockCount => _products.where((p) => p.stock <= p.minStock).length;

  // ── Form field ────────────────────────────────────────────────────────
  Widget _formField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool isNumber = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _inkMid,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: ctrl,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            style: const TextStyle(
                color: _ink, fontSize: 15, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _inkLight, fontSize: 14),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: Icon(icon, color: _accent, size: 18),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              filled: true,
              fillColor: _bg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _accent, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _danger, width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _danger, width: 1.5),
              ),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? "This field is required" : null,
          ),
        ],
      ),
    );
  }

  // ── Bottom Sheet ──────────────────────────────────────────────────────
  void _showProductSheet({Product? product}) {
    final isEdit       = product != null;
    final nameCtrl     = TextEditingController(text: isEdit ? product!.name : "");
    final stockCtrl    = TextEditingController(text: isEdit ? product!.stock.toString() : "");
    final minStockCtrl = TextEditingController(text: isEdit ? product!.minStock.toString() : "");
    final catCtrl      = TextEditingController(text: isEdit ? product!.category : "");
    final formKey      = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: _border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: _accentLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isEdit ? Icons.edit_rounded : Icons.add_rounded,
                      color: _accent, size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit ? "Edit Product" : "New Product",
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          isEdit
                              ? "Update product details"
                              : "Add to your inventory",
                          style: const TextStyle(
                              color: _inkMid, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _border),
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: _inkMid, size: 17),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: _border, height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24, 24, 24,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    children: [
                      _formField(nameCtrl, "PRODUCT NAME",
                          Icons.inventory_2_outlined,
                          hint: "e.g. Pancit Canton"),
                      _formField(catCtrl, "CATEGORY",
                          Icons.label_outline_rounded,
                          hint: "e.g. Noodles"),
                      Row(
                        children: [
                          Expanded(
                            child: _formField(
                                stockCtrl, "CURRENT STOCK",
                                Icons.layers_rounded,
                                isNumber: true, hint: "0"),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _formField(
                                minStockCtrl, "MIN STOCK",
                                Icons.warning_amber_rounded,
                                isNumber: true, hint: "0"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: _white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            if (formKey.currentState!.validate()) {
                              final p = Product(
                                id: isEdit ? product!.id : null,
                                name: nameCtrl.text.trim(),
                                stock: int.parse(stockCtrl.text),
                                minStock: int.parse(minStockCtrl.text),
                                category: catCtrl.text.trim(),
                                createdAt: isEdit
                                    ? product!.createdAt
                                    : DateTime.now().toIso8601String(),
                              );
                              if (isEdit) {
                                await _productService.updateProduct(p);
                              } else {
                                await _productService.insertProduct(p);
                              }
                              if (mounted) Navigator.pop(context);
                              _loadProducts();
                            }
                          },
                          child: Text(
                            isEdit ? "Save Changes" : "Add to Inventory",
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                      if (isEdit) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: _danger,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(color: _border),
                              ),
                            ),
                            onPressed: () async {
                              Navigator.pop(context);
                              await _productService
                                  .deleteProduct(product!.id!);
                              _loadProducts();
                            },
                            child: const Text("Delete Product",
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15)),
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
      ),
    );
  }

  // ── Product Card ──────────────────────────────────────────────────────
  Widget _productCard(Product product, int index) {
    final isLow  = product.stock <= product.minStock;
    final double pct = product.minStock == 0
        ? 1.0
        : (product.stock / (product.minStock * 4)).clamp(0.0, 1.0);

    return Dismissible(
      key: Key(product.id.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 28),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _dangerBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _danger.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.delete_outline_rounded, color: _danger, size: 22),
            SizedBox(height: 4),
            Text("Remove",
                style: TextStyle(
                    color: _danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      onDismissed: (_) async {
        final deleted = product;
        await _productService.deleteProduct(product.id!);
        _loadProducts();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: _ink,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          content: Row(children: [
            const Icon(Icons.check_circle_outline,
                color: _white, size: 16),
            const SizedBox(width: 10),
            Text("\"${deleted.name}\" removed",
                style: const TextStyle(color: _white, fontSize: 14)),
          ]),
          action: SnackBarAction(
            label: "Undo",
            textColor: const Color(0xFF93C5FD),
            onPressed: () async {
              await _productService.insertProduct(deleted);
              _loadProducts();
            },
          ),
        ));
      },
      child: GestureDetector(
        onTap: () => _showProductSheet(product: product),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isLow ? _danger.withOpacity(0.25) : _border,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: isLow ? _dangerBg : _accentLight,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.inventory_2_rounded,
                        color: isLow ? _danger : _accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _bg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _border),
                            ),
                            child: Text(
                              product.category,
                              style: const TextStyle(
                                color: _inkMid,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
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
                        Text(
                          "${product.stock}",
                          style: TextStyle(
                            color: isLow ? _danger : _ink,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            height: 1,
                          ),
                        ),
                        const Text(
                          "units",
                          style: TextStyle(
                              color: _inkLight,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Stack(children: [
                          Container(height: 5, color: _bg),
                          FractionallySizedBox(
                            widthFactor: pct,
                            child: Container(
                              height: 5,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                gradient: LinearGradient(
                                  colors: isLow
                                      ? [_danger, _danger.withOpacity(0.4)]
                                      : [_accent, const Color(0xFF60A5FA)],
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isLow ? _dangerBg : _successBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isLow
                              ? _danger.withOpacity(0.2)
                              : _success.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLow
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_rounded,
                            size: 11,
                            color: isLow ? _danger : _success,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isLow ? "Low Stock" : "In Stock",
                            style: TextStyle(
                              color: isLow ? _danger : _success,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Stat Card ──────────────────────────────────────────────────────────
  Widget _statCard(
    String value,
    String label,
    IconData icon,
    Color color,
    Color bgColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: const TextStyle(
                color: _inkLight,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [

            // ── Header ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Good day 👋",
                            style: TextStyle(
                              color: _inkMid,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            "My Inventory",
                            style: TextStyle(
                              color: _ink,
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadProducts,
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.refresh_rounded,
                            color: _inkMid, size: 19),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Stat cards ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    _statCard("${_products.length}", "Products",
                        Icons.widgets_rounded, _accent, _accentLight),
                    const SizedBox(width: 10),
                    _statCard("$_totalItems", "Total Units",
                        Icons.inventory_rounded, _warning, _warningBg),
                    const SizedBox(width: 10),
                    _statCard("$_lowStockCount", "Low Stock",
                        Icons.warning_rounded, _danger, _dangerBg),
                  ],
                ),
              ),
            ),

            // ── Search ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(
                      color: _ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    hintText: "Search by name or category…",
                    hintStyle: const TextStyle(
                        color: _inkLight,
                        fontSize: 14,
                        fontWeight: FontWeight.w400),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 16, right: 12),
                      child: Icon(Icons.search_rounded,
                          color: _inkMid, size: 20),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 0, minHeight: 0),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () =>
                                setState(() => _searchQuery = ""),
                            child: const Padding(
                              padding: EdgeInsets.only(right: 16),
                              child: Icon(Icons.cancel_rounded,
                                  color: _inkLight, size: 18),
                            ),
                          )
                        : null,
                    suffixIconConstraints:
                        const BoxConstraints(minWidth: 0, minHeight: 0),
                    filled: true,
                    fillColor: _cardBg,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 16),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: _border, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: _accent, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),

            // ── Category chips ────────────────────────────────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 50,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final cat      = _categories[i];
                    final selected = cat == _selectedCategory;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedCategory = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? _accent : _cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: selected ? _accent : _border,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: _accent.withOpacity(0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  )
                                ]
                              : [],
                        ),
                        child: Text(
                          cat,
                          style: TextStyle(
                            color: selected ? _white : _inkMid,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── List header ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(24, 22, 24, 12),
                child: Row(
                  children: [
                    Text(
                      "${filtered.length} ${filtered.length == 1 ? 'result' : 'results'}",
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (_lowStockCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _dangerBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _danger.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: _danger, size: 12),
                            const SizedBox(width: 5),
                            Text(
                              "$_lowStockCount low stock",
                              style: const TextStyle(
                                color: _danger,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Product list ──────────────────────────────────────────
            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                      color: _accent, strokeWidth: 2),
                ),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          color: _accentLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                            Icons.search_off_rounded,
                            color: _accent, size: 32),
                      ),
                      const SizedBox(height: 16),
                      const Text("No products found",
                          style: TextStyle(
                            color: _ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          )),
                      const SizedBox(height: 6),
                      const Text(
                          "Try a different search or category",
                          style: TextStyle(
                              color: _inkMid, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(24, 0, 24, 120),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _productCard(filtered[i], i),
                    childCount: filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),

      // ── FAB ──────────────────────────────────────────────────────────
      floatingActionButton: Container(
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _accent.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _showProductSheet(),
          backgroundColor: _accent,
          foregroundColor: _white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text(
            "Add Product",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}