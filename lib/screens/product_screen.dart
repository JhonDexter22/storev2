import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:storev2/database/database_helper.dart';

import '../models/product_model.dart';
import '../services/product_service.dart';
import 'barcode_scanner_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {


  final ProductService _productService = ProductService();
  final ImagePicker _picker = ImagePicker();


  // ── Design Tokens ──────────────────────────────────────────────────────
  static const Color _white       = Color(0xFFFFFFFF);
  static const Color _bg          = Color(0xFFF4F6FB);
  static const Color _cardBg      = Color(0xFFFFFFFF);
  static const Color _ink         = Color(0xFF0D0F1A);
  static const Color _inkMid      = Color(0xFF5A5F7A);
  static const Color _inkLight    = Color(0xFFB0B5CC);
  static const Color _border      = Color(0xFFE8EBF5);
  static const Color _accent      = Color(0xFF2563EB);
  static const Color _accentLight = Color(0xFFEEF3FF);
  static const Color _success     = Color(0xFF16A34A);
  static const Color _successBg   = Color(0xFFECFDF5);
  static const Color _warning     = Color(0xFFD97706);
  static const Color _warningBg   = Color(0xFFFFFBEB);
  static const Color _danger      = Color(0xFFDC2626);
  static const Color _dangerBg    = Color(0xFFFEF2F2);
  static const Color _navBg       = Color(0xFFFFFFFF);

  List<Product> _products       = [];
  String  _searchQuery          = '';
  String  _selectedCategory     = 'All';
  bool    _loading              = true;
  int     _currentNavIndex      = 0;

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

  // ── Data ────────────────────────────────────────────────────────────────
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
    return ['All', ...cats];
  }

  List<Product> get _filtered => _products.where((p) {
        final q        = _searchQuery.toLowerCase();
        final matchQ   = p.name.toLowerCase().contains(q) ||
                         p.category.toLowerCase().contains(q) ||
                         (p.sku ?? '').toLowerCase().contains(q);
        final matchCat = _selectedCategory == 'All' ||
                         p.category == _selectedCategory;
        return matchQ && matchCat;
      }).toList();

  int    get _totalItems    => _products.fold(0, (s, p) => s + p.stock);
  int    get _lowStockCount => _products.where((p) => p.stock <= p.minStock).length;

  // ── Stock dot color ─────────────────────────────────────────────────────
  Color _dotColor(Product p) {
    if (p.stock == 0)              return _danger;
    if (p.stock <= p.minStock)     return _warning;
    return _success;
  }

  // ── Image picker ─────────────────────────────────────────────────────────
  Future<String?> _pickImage() async {
    final xFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 600,
    );
    return xFile?.path;
  }

  // ── Bottom Sheet ─────────────────────────────────────────────────────────
  void _showProductSheet({Product? product}) {
    final isEdit        = product != null;
    final nameCtrl      = TextEditingController(text: isEdit ? product!.name        : '');
    final priceCtrl     = TextEditingController(text: isEdit ? product!.price.toStringAsFixed(2) : '');
    final skuCtrl       = TextEditingController(text: isEdit ? (product!.sku ?? '') : '');
    final minStockCtrl  = TextEditingController(text: isEdit ? product!.minStock.toString() : '');
    final categoryCtrl = TextEditingController(text: isEdit ? product!.category : '',);
    final formKey       = GlobalKey<FormState>();

    // Mutable state inside the sheet
    String? pickedImagePath = isEdit ? product!.imagePath : null;
  
    int     stockCount      = isEdit ? product!.stock      : 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.92,
            decoration: const BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                // Drag handle
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

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: _bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _border),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: _inkMid, size: 15),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        isEdit ? 'Edit Product' : 'Add New Product',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: _border, height: 1),

                // Form body
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      24, 24, 24,
                      MediaQuery.of(context).viewInsets.bottom + 32,
                    ),
                    child: Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          // ── Product image picker ────────────────────────
                          GestureDetector(
                            onTap: () async {
                              final path = await _pickImage();
                              if (path != null) {
                                setSheet(() => pickedImagePath = path);
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              height: 140,
                              decoration: BoxDecoration(
                                color: _bg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _border,
                                  width: 1.5,
                                  style: BorderStyle.solid,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: pickedImagePath != null
                                  ? Stack(fit: StackFit.expand, children: [
                                      Image.file(
                                        File(pickedImagePath!),
                                        fit: BoxFit.cover,
                                      ),
                                      Positioned(
                                        bottom: 8, right: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: _ink.withOpacity(0.7),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Text('Change',
                                              style: TextStyle(
                                                  color: _white,
                                                  fontSize: 11,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                        ),
                                      ),
                                    ])
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: const [
                                        Icon(Icons.camera_alt_outlined,
                                            color: _inkLight, size: 32),
                                        SizedBox(height: 8),
                                        Text('Product Image',
                                            style: TextStyle(
                                                color: _inkLight,
                                                fontSize: 13,
                                                fontWeight:
                                                    FontWeight.w500)),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 14),

                         
                        // ── Scan Barcode button ─────────────────────────
SizedBox(
  width: double.infinity,
  height: 46,
  child: OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: _accent,
      side: const BorderSide(color: _accent, width: 1.5),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
    ),
    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
    label: const Text(
      'Scan Barcode',
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    ),
    onPressed: () async {
  // 1. Open the scanner
  final String? scannedBarcode = await Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => const SimpleBarcodeScannerScreen()),
  );

  // 2. Kapag may na-scan na...
  if (scannedBarcode != null && context.mounted) {
    
    // 3. I-map ang data base sa mga columns ng DatabaseHelper mo!
 final Map<String, dynamic> newProduct = {
      'sku': scannedBarcode, // Dito papasok ang na-scan na barcode
      'name': nameCtrl.text.isEmpty ? 'New Product' : nameCtrl.text,
      'category': categoryCtrl.text.isEmpty ? 'Uncategorized' : categoryCtrl.text,
      // Gumamit tayo ng tryParse para hindi mag-crash kapag may maling na-type
      'price': double.tryParse(priceCtrl.text) ?? 0.0, 
      'stock': stockCount, // Hindi na kailangan i-parse dahil integer na ito agad sa stepper mo!
      'min_stock': int.tryParse(minStockCtrl.text) ?? 0, 
      'created_at': DateTime.now().toIso8601String(), 
      'image_path': '', 
    };

    try {
      // 4. I-save agad sa SQLite
      await DatabaseHelper.instance.insertProduct(newProduct);

      if (!context.mounted) return;

      // 5. Success Message!
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          content: Text('Saved! Barcode $scannedBarcode added as SKU.'),
        ),
      );

      // Optional: I-clear ang text fields pagkatapos ma-save
      // nameController.clear();
      _loadProducts();
      // ... at iba pa
      Navigator.pop(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')),
      );
    }
  }
},
  ),
),
                          const SizedBox(height: 20),

                          // ── Product Name ────────────────────────────────
                          _sheetLabel('Product Name'),
                          const SizedBox(height: 6),
                          _sheetField(
                            ctrl: nameCtrl,
                            hint: 'e.g. Hansel',
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: 14),

                          // ── Category dropdown ───────────────────────────
                         _sheetLabel('Category'),
const SizedBox(height: 6),
_sheetField(
  ctrl: categoryCtrl,
  hint: 'e.g. Biscuits',
  validator: (v) =>
      (v == null || v.trim().isEmpty)
          ? 'Required'
          : null,
),
                          const SizedBox(height: 14),

                          // ── Unit Price ──────────────────────────────────
                          _sheetLabel('Unit Price'),
                          const SizedBox(height: 6),
                          _sheetField(
                            ctrl: priceCtrl,
                            hint: '0.00',
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            prefix: const Text('\₱  ',
                                style: TextStyle(
                                    color: _inkMid,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15)),
                          ),
                          const SizedBox(height: 14),

                          // ── Initial Stock stepper ───────────────────────
                          _sheetLabel(
                              isEdit ? 'Current Stock' : 'Initial Stock'),
                          const SizedBox(height: 6),
                          _stockStepper(
                            value: stockCount,
                            onDecrement: () {
                              if (stockCount > 0) {
                                setSheet(() => stockCount--);
                              }
                            },
                            onIncrement: () =>
                                setSheet(() => stockCount++),
                          ),
                          const SizedBox(height: 14),

                          // ── Min Stock ───────────────────────────────────
                          _sheetLabel('Min Stock Alert'),
                          const SizedBox(height: 6),
                          _sheetField(
                            ctrl: minStockCtrl,
                            hint: '5',
                            keyboardType: TextInputType.number,
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: 14),

                       
                        
                          const SizedBox(height: 28),

                          // ── Save button ─────────────────────────────────
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: _white,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                if (formKey.currentState!.validate()) {
                                  final p = Product(
                                    id: isEdit ? product!.id : null,
                                    name: nameCtrl.text.trim(),
                                    stock: stockCount,
                                    minStock: int.tryParse(
                                            minStockCtrl.text) ??
                                        0,
                                    category: categoryCtrl.text.trim().isEmpty
                                        ? 'General'
                                       : categoryCtrl.text.trim(),
                                    createdAt: isEdit
                                        ? product!.createdAt
                                        : DateTime.now()
                                            .toIso8601String(),
                                    price: double.tryParse(
                                            priceCtrl.text) ??
                                        0.0,
                                    sku: skuCtrl.text.trim().isEmpty
                                        ? null
                                        : skuCtrl.text.trim(),
                                    imagePath: pickedImagePath,
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
                                isEdit
                                    ? 'Save Changes'
                                    : 'Save Product',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),

                          // ── Delete (edit only) ──────────────────────────
                          if (isEdit) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: _danger,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    side: const BorderSide(
                                        color: _border),
                                  ),
                                ),
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await _productService
                                      .deleteProduct(product!.id!);
                                  _loadProducts();
                                },
                                child: const Text('Delete Product',
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
          );
        },
      ),
    );
  }

  // ── Sheet helpers ───────────────────────────────────────────────────────
  Widget _sheetLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: _ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _sheetField({
    required TextEditingController ctrl,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? prefix,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: const TextStyle(
          color: _ink, fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: _inkLight, fontSize: 14),
        prefix: prefix,
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
      validator: validator,
    );
  }

  Widget _categoryDropdown({
    required String value,
    required List<String> categories,
    required void Function(String?) onChanged,
  }) {
    // If the current value is not in the list, fall back gracefully.
    final items = categories.isEmpty ? ['General'] : categories;
    final safeValue = items.contains(value) ? value : items.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          style: const TextStyle(
              color: _ink, fontSize: 15, fontWeight: FontWeight.w500),
          dropdownColor: _white,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.expand_more_rounded, color: _inkMid),
          items: items
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _stockStepper({
    required int value,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$value',
              style: const TextStyle(
                color: _ink,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _stepBtn(Icons.remove_rounded, onDecrement),
          Container(
              width: 1, height: 20, color: _border,
              margin: const EdgeInsets.symmetric(horizontal: 8)),
          _stepBtn(Icons.add_rounded, onIncrement),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _border),
          ),
          child: Icon(icon, color: _ink, size: 16),
        ),
      );

  // ── Product Card ─────────────────────────────────────────────────────────
  Widget _productCard(Product product) {
    final dot     = _dotColor(product);
    final isLow   = product.stock <= product.minStock;

    return Dismissible(
      key: Key(product.id.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 28),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _dangerBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _danger.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.delete_outline_rounded, color: _danger, size: 22),
            SizedBox(height: 4),
            Text('Remove',
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(children: [
            const Icon(Icons.check_circle_outline, color: _white, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text('\"₱${deleted.name}\" removed',
                  style: const TextStyle(color: _white, fontSize: 14)),
            ),
          ]),
          action: SnackBarAction(
            label: 'Undo',
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
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isLow ? _danger.withOpacity(0.2) : _border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Thumbnail
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: _border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (product.imagePath != null &&
                          product.imagePath!.isNotEmpty)
                      ? Image.file(
                          File(product.imagePath!),
                          fit: BoxFit.cover,
                        )
                      : Icon(
                          Icons.inventory_2_outlined,
                          color: isLow ? _danger : _accent,
                          size: 22,
                        ),
                ),
                const SizedBox(width: 14),

                // Name + category
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
                      const SizedBox(height: 3),
                      Text(
                        product.category,
                        style: const TextStyle(
                          color: _inkMid,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (product.price > 0) ...[
                        const SizedBox(height: 2),
                       
                      ],
                    ],
                  ),
                ),

                // Stock count + dot
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                 Row(
  children: [
    Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: dot,
        shape: BoxShape.circle,
      ),
    ),
    const SizedBox(width: 8),
    Text(
      '${product.stock}',
      style: TextStyle(
        color: isLow ? _danger : _ink,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
  ],
),

const SizedBox(height: 6),

Text(
  '₱${product.price.toStringAsFixed(2)}',
  style: const TextStyle(
    color: _ink,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  ),
),
                    const SizedBox(height: 2),
                  
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Stat card ────────────────────────────────────────────────────────────
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [

            // ── Header ───────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Good day 👋',
                            style: TextStyle(
                              color: _inkMid,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'My Inventory',
                            style: TextStyle(
                              color: _ink,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _loadProducts,
                      child: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(13),
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
                            color: _inkMid, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Stat cards ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    _statCard('${_products.length}', 'Products',
                        Icons.widgets_rounded, _accent, _accentLight),
                    const SizedBox(width: 10),
                    _statCard('$_totalItems', 'Total Units',
                        Icons.inventory_rounded, _warning, _warningBg),
                    const SizedBox(width: 10),
                    _statCard('$_lowStockCount', 'Low Stock',
                        Icons.warning_rounded, _danger, _dangerBg),
                  ],
                ),
              ),
            ),

            // ── Search ────────────────────────────────────────────────────
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
                    hintText: 'Search inventory…',
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
                                setState(() => _searchQuery = ''),
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
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: _border, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: _accent, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),

            // ── Category chips ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 50,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
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
                            horizontal: 16, vertical: 10),
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
                                  ),
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

            // ── List header ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
                child: Row(
                  children: [
                    Text(
                      '${filtered.length} ${filtered.length == 1 ? 'result' : 'results'}',
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
                              '$_lowStockCount low stock',
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

            // ── Product list ───────────────────────────────────────────────
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
                        child: const Icon(Icons.search_off_rounded,
                            color: _accent, size: 32),
                      ),
                      const SizedBox(height: 16),
                      const Text('No products found',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          )),
                      const SizedBox(height: 6),
                      const Text('Try a different search or category',
                          style: TextStyle(color: _inkMid, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                // Extra bottom padding so last card clears the bottom nav bar
                padding:
                    const EdgeInsets.fromLTRB(24, 0, 24, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _productCard(filtered[i]),
                    childCount: filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),

      // ── FAB ──────────────────────────────────────────────────────────────
      floatingActionButton: Padding(
  padding: const EdgeInsets.only(
    right: 8,
    bottom: 12,
  ),
  child: Container(
    height: 48,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: _accent.withOpacity(0.35),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: FloatingActionButton.extended(
      onPressed: () => _showProductSheet(),
      backgroundColor: _accent,
      foregroundColor: _white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      icon: const Icon(Icons.add_rounded, size: 20),
      label: const Text(
        'Add Product',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          letterSpacing: 0.2,
        ),
      ),
    ),
  ),
),
    floatingActionButtonLocation:
    FloatingActionButtonLocation.endFloat,

      // ── Bottom Navigation Bar ─────────────────────────────────────────────
   
    );
  }

  Widget _navItem(
      int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final selected = _currentNavIndex == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _currentNavIndex = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? activeIcon : inactiveIcon,
              color: selected ? _accent : _inkLight,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: selected ? _accent : _inkLight,
                fontSize: 10,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}