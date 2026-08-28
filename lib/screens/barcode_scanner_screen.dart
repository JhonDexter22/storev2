import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/design_tokens.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';

/// What the scanner hands back when it closes.
///
/// [ScanCapture] is the plain "give me the raw code" result used by the product
/// editor. [ScanSale] is the POS result: everything added during a continuous
/// scan session, plus an optional unknown code the cashier chose to turn into a
/// new product.
sealed class ScannerResult {
  const ScannerResult();
}

class ScanCapture extends ScannerResult {
  const ScanCapture(this.code);
  final String code;
}

class ScanSale extends ScannerResult {
  const ScanSale({required this.added, this.newProductSku});

  /// productId -> quantity added during this scanning session.
  final Map<int, int> added;

  /// Set when the cashier hit "Add as new product" on an unknown code.
  final String? newProductSku;
}

enum _ScanState { scanning, found, unknown }

class SimpleBarcodeScannerScreen extends StatefulWidget {
  /// Capture mode — returns a [ScanCapture] with the first code read.
  const SimpleBarcodeScannerScreen({super.key}) : forSale = false;

  /// Sale mode — looks each code up, adds matches to the running sale without
  /// leaving the scanner, and returns a [ScanSale] when dismissed.
  const SimpleBarcodeScannerScreen.forSale({super.key}) : forSale = true;

  final bool forSale;

  @override
  State<SimpleBarcodeScannerScreen> createState() => _SimpleBarcodeScannerScreenState();
}

class _SimpleBarcodeScannerScreenState extends State<SimpleBarcodeScannerScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController cameraController = MobileScannerController();
  final ProductService _productService = ProductService();

  bool _torchOn = false;
  bool _busy = false;
  late final AnimationController _scanAnim;

  _ScanState _state = _ScanState.scanning;
  Product? _match;
  int _matchQty = 1;
  String? _unknownCode;

  final Map<int, int> _added = {};

  @override
  void initState() {
    super.initState();
    _scanAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanAnim.dispose();
    cameraController.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.pop(
      context,
      widget.forSale ? ScanSale(added: Map.of(_added)) : null,
    );
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    // Ignore frames while a sheet is up or a lookup is already running —
    // continuous scan means the camera keeps streaming, not that we re-handle
    // the same code dozens of times a second.
    if (_busy || _state != _ScanState.scanning) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty || barcodes.first.rawValue == null) return;
    final code = barcodes.first.rawValue!;

    if (!widget.forSale) {
      _busy = true;
      Navigator.pop(context, ScanCapture(code));
      return;
    }

    _busy = true;
    final product = await _productService.findBySku(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (product == null) {
        _state = _ScanState.unknown;
        _unknownCode = code;
      } else {
        _state = _ScanState.found;
        _match = product;
        _matchQty = 1;
      }
    });
  }

  void _resumeScanning() {
    setState(() {
      _state = _ScanState.scanning;
      _match = null;
      _unknownCode = null;
      _matchQty = 1;
    });
  }

  void _addToSale() {
    final p = _match;
    if (p?.id == null) return;
    _added.update(p!.id!, (v) => v + _matchQty, ifAbsent: () => _matchQty);
    _resumeScanning();
  }

  Future<void> _enterManually() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Enter code manually', style: AppText.sectionTitle()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: AppText.body(color: AppColors.ink),
          decoration: InputDecoration(
            hintText: 'Barcode / SKU',
            hintStyle: AppText.body(color: AppColors.faint),
            filled: true,
            fillColor: AppColors.canvas,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Look up', style: AppText.chip(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;

    if (!widget.forSale) {
      Navigator.pop(context, ScanCapture(code));
      return;
    }
    final product = await _productService.findBySku(code);
    if (!mounted) return;
    setState(() {
      if (product == null) {
        _state = _ScanState.unknown;
        _unknownCode = code;
      } else {
        _state = _ScanState.found;
        _match = product;
        _matchQty = 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: MobileScanner(controller: cameraController, onDetect: _onDetect),
                    ),
                    Positioned.fill(child: Container(color: _overlayColor())),
                    if (_state == _ScanState.scanning) _reticle(),
                    if (_state == _ScanState.found) _resultGlyph(Icons.check_rounded, AppColors.success),
                    if (_state == _ScanState.unknown) _resultGlyph(Icons.close_rounded, AppColors.danger),
                  ],
                ),
              ),
              if (_state == _ScanState.scanning) _scanningFooter(),
              if (_state == _ScanState.found) _matchSheet(),
              if (_state == _ScanState.unknown) _unknownSheet(),
            ],
          ),
        ),
      ),
    );
  }

  Color _overlayColor() => switch (_state) {
        _ScanState.scanning => AppColors.ink.withValues(alpha: 0.35),
        _ScanState.found => AppColors.success.withValues(alpha: 0.35),
        _ScanState.unknown => AppColors.danger.withValues(alpha: 0.35),
      };

  Widget _header() {
    final count = _added.values.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: _close,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scan barcode', style: AppText.sectionTitle(color: Colors.white).copyWith(fontSize: 16)),
                Text(
                  widget.forSale
                      ? (count == 0 ? 'Continuous scan is on' : '$count added to this sale')
                      : 'Point at a barcode',
                  style: AppText.caption(color: AppColors.faint),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              cameraController.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _torchOn ? AppColors.primary : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(_torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultGlyph(IconData icon, Color color) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 52),
    );
  }

  Widget _reticle() {
    const w = 262.0, h = 180.0;
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          ..._corners(),
          AnimatedBuilder(
            animation: _scanAnim,
            builder: (context, _) => Positioned(
              top: 8 + _scanAnim.value * (h - 16),
              left: 8,
              right: 8,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.7), blurRadius: 8)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _corners() {
    const len = 26.0, thick = 3.0;
    Widget corner({required bool top, required bool left}) {
      return Positioned(
        top: top ? 0 : null,
        bottom: top ? null : 0,
        left: left ? 0 : null,
        right: left ? null : 0,
        child: SizedBox(
          width: len,
          height: len,
          child: CustomPaint(
            painter: _CornerPainter(top: top, left: left, thickness: thick, color: AppColors.primary),
          ),
        ),
      );
    }

    return [
      corner(top: true, left: true),
      corner(top: true, left: false),
      corner(top: false, left: true),
      corner(top: false, left: false),
    ];
  }

  Widget _scanningFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: GestureDetector(
        onTap: _enterManually,
        child: Text(
          'Enter code manually',
          style: AppText.chip(color: Colors.white).copyWith(
            decoration: TextDecoration.underline,
            decorationColor: Colors.white54,
          ),
        ),
      ),
    );
  }

  Widget _sheet({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpace.sheetPad, 18, AppSpace.sheetPad, 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _matchSheet() {
    final p = _match!;
    final atStockCeiling = _matchQty >= p.stock;
    return _sheet(
      children: [
        Row(
          children: [
            const SizedBox(width: 52, height: 52, child: PhotoPlaceholder()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: AppText.cardTitle().copyWith(fontSize: 15),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${p.category} · ${p.stock} in stock', style: AppText.caption()),
                ],
              ),
            ),
            Text(formatPeso(p.price), style: AppText.cardTitle()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Quantity', style: AppText.body()),
            QtyStepper(
              value: _matchQty,
              canIncrement: !atStockCeiling,
              onDecrement: () {
                if (_matchQty > 1) setState(() => _matchQty--);
              },
              onIncrement: () => setState(() => _matchQty++),
            ),
          ],
        ),
        if (atStockCeiling) ...[
          const SizedBox(height: 8),
          Text('Only ${p.stock} in stock', style: AppText.caption(color: AppColors.warningText)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: p.stock <= 0 ? null : _addToSale,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.disabledFill,
              foregroundColor: Colors.white,
              disabledForegroundColor: AppColors.faint,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
            ),
            child: Text(
              p.stock <= 0 ? 'Out of stock' : 'Add to sale · ${formatPeso(p.price * _matchQty)}',
              style: AppText.chip(color: Colors.white).copyWith(fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: TextButton(
            onPressed: _resumeScanning,
            child: Text('Keep scanning', style: AppText.chip(color: AppColors.body)),
          ),
        ),
      ],
    );
  }

  Widget _unknownSheet() {
    return _sheet(
      children: [
        Container(
          width: double.infinity,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No product matches this code',
                        style: AppText.caption(color: AppColors.dangerText)),
                    const SizedBox(height: 2),
                    Text(_unknownCode ?? '', style: AppText.mono(color: AppColors.dangerText, size: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              ScanSale(added: Map.of(_added), newProductSku: _unknownCode),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
            ),
            child: Text('Add as new product', style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: TextButton(
            onPressed: _resumeScanning,
            child: Text('Scan again', style: AppText.chip(color: AppColors.body)),
          ),
        ),
      ],
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter({required this.top, required this.left, required this.thickness, required this.color});
  final bool top;
  final bool left;
  final double thickness;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = top ? 0.0 : size.height;
    final x = left ? 0.0 : size.width;
    canvas.drawPath(
      Path()
        ..moveTo(x, top ? 0 : size.height)
        ..lineTo(x, top ? size.height : 0),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(left ? 0 : size.width, y)
        ..lineTo(left ? size.width : 0, y),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
