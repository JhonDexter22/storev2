import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/product_model.dart';
import '../widgets/product_thumb.dart';
import '../services/product_service.dart';
import '../services/scan_feedback.dart';
import '../l10n/tr.dart';

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

/// What a scan did in sale mode.
enum ScanOutcome { added, full }

/// The rules of one continuous-scan session, kept apart from the camera so
/// they can be checked without one.
///
/// A known product is added the moment it is read — one unit, no button —
/// and the same code is then ignored for [repeatGuard], because the camera
/// sees a barcode many times a second while it is held in frame. Nothing is
/// added past what is on the shelf once the units already in the cart
/// ([inCart]) and the ones added this session are counted.
class ScanSession {
  ScanSession({Map<int, int> inCart = const {}, this.repeatGuard = const Duration(seconds: 2)})
      : inCart = Map.unmodifiable(inCart);

  final Map<int, int> inCart;
  final Duration repeatGuard;

  /// Product id to units added during this session.
  final Map<int, int> added = {};

  String? _lastCode;
  DateTime? _lastAt;

  /// [code] is the one just handled, still in front of the camera.
  bool isRepeat(String code, DateTime now) =>
      code == _lastCode && _lastAt != null && now.difference(_lastAt!) < repeatGuard;

  void saw(String code, DateTime now) {
    _lastCode = code;
    _lastAt = now;
  }

  /// Units that can still go into the sale.
  int roomFor(Product p) => p.stock - (inCart[p.id] ?? 0) - (added[p.id] ?? 0);

  /// The most this session can hold of [p], for setting a count outright.
  int ceilingFor(Product p) => p.stock - (inCart[p.id] ?? 0);

  ScanOutcome add(Product p, {int qty = 1}) {
    final room = roomFor(p);
    if (room <= 0 || p.id == null) return ScanOutcome.full;
    added.update(p.id!, (v) => v + qty.clamp(1, room), ifAbsent: () => qty.clamp(1, room));
    return qty > room ? ScanOutcome.full : ScanOutcome.added;
  }

  /// Sets this session's count of [p] outright; zero takes it back out.
  void setCount(Product p, int n) {
    if (p.id == null) return;
    final capped = n.clamp(0, ceilingFor(p).clamp(0, 1 << 30));
    if (capped == 0) {
      added.remove(p.id);
    } else {
      added[p.id!] = capped;
    }
  }

  int countOf(Product p) => added[p.id] ?? 0;
  int get total => added.values.fold(0, (a, b) => a + b);
}

class SimpleBarcodeScannerScreen extends StatefulWidget {
  /// Capture mode — returns a [ScanCapture] with the first code read.
  const SimpleBarcodeScannerScreen({super.key})
      : forSale = false,
        inCart = const {};

  /// Sale mode — looks each code up, adds matches to the running sale without
  /// leaving the scanner, and returns a [ScanSale] when dismissed. [inCart]
  /// is what the sale already holds, so the scanner never offers past stock.
  const SimpleBarcodeScannerScreen.forSale({super.key, this.inCart = const {}}) : forSale = true;

  final bool forSale;
  final Map<int, int> inCart;

  @override
  State<SimpleBarcodeScannerScreen> createState() => _SimpleBarcodeScannerScreenState();
}

class _SimpleBarcodeScannerScreenState extends State<SimpleBarcodeScannerScreen>
    with TickerProviderStateMixin {
  final MobileScannerController cameraController = MobileScannerController();
  final ProductService _productService = ProductService();

  bool _torchOn = false;
  bool _busy = false;
  late final AnimationController _scanAnim;

  _ScanState _state = _ScanState.scanning;
  Product? _match;
  int _matchQty = 1;
  String? _unknownCode;

  late final ScanSession _session = ScanSession(inCart: widget.inCart);
  Map<int, int> get _added => _session.added;

  /// The last product a scan touched, for the line above "Enter code
  /// manually", and whether that scan found the shelf empty.
  Product? _last;
  bool _lastWasFull = false;

  /// The match sheet is setting a scanned item's count, not adding more.
  bool _adjusting = false;

  /// A brief wash of colour over the viewfinder on each read. Starts
  /// finished (invisible); a read runs it from the top.
  late final AnimationController _flash =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450), value: 1);
  Color _flashColor = AppColors.success;

  @override
  void initState() {
    super.initState();
    _scanAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flash.dispose();
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
      ScanFeedback.found();
      Navigator.pop(context, ScanCapture(code));
      return;
    }

    // Held in frame, a barcode is read many times a second.
    final now = DateTime.now();
    if (_session.isRepeat(code, now)) return;
    _session.saw(code, now);

    _busy = true;
    final product = await _productService.findBySku(code);
    if (!mounted) return;
    if (product == null) {
      ScanFeedback.unknown();
      setState(() {
        _busy = false;
        _state = _ScanState.unknown;
        _unknownCode = code;
      });
      return;
    }
    // Added on sight: "Continuous scan" used to stop on a sheet for every
    // item and wait for a tap.
    final outcome = _session.add(product);
    outcome == ScanOutcome.added ? ScanFeedback.found() : ScanFeedback.unknown();
    setState(() {
      _busy = false;
      _last = product;
      _lastWasFull = outcome == ScanOutcome.full;
      _flashColor = _lastWasFull ? AppColors.warning : AppColors.success;
    });
    _flash.forward(from: 0);
  }

  /// "Edit" on the last scanned item: its count for this sale, set outright.
  void _adjustLast() {
    final p = _last;
    if (p == null) return;
    setState(() {
      _adjusting = true;
      _state = _ScanState.found;
      _match = p;
      _matchQty = _session.countOf(p);
    });
  }

  void _resumeScanning() {
    setState(() {
      _state = _ScanState.scanning;
      _match = null;
      _unknownCode = null;
      _matchQty = 1;
      _adjusting = false;
    });
  }

  void _addToSale() {
    final p = _match;
    if (p?.id == null) return;
    if (_adjusting) {
      _session.setCount(p!, _matchQty);
    } else {
      final outcome = _session.add(p!, qty: _matchQty);
      _lastWasFull = outcome == ScanOutcome.full;
    }
    _last = p;
    _resumeScanning();
  }

  Future<void> _enterManually() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(tr('Enter code manually'), style: AppText.sectionTitle()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: AppText.body(color: AppColors.ink),
          decoration: InputDecoration(
            hintText: tr('Barcode / SKU'),
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
            child: Text(tr('Cancel'), style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Look up'), style: AppText.chip(color: AppColors.primary)),
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
      _adjusting = false;
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
                      child: MobileScanner(
                        controller: cameraController,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) => _cameraError(error),
                      ),
                    ),
                    Positioned.fill(child: Container(color: _overlayColor())),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: FadeTransition(
                          opacity: ReverseAnimation(_flash),
                          child: ColoredBox(color: _flashColor.withValues(alpha: 0.35)),
                        ),
                      ),
                    ),
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
    final count = _session.total;
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
                Text(tr('Scan barcode'), style: AppText.sectionTitle(color: Colors.white).copyWith(fontSize: 16)),
                Text(
                  widget.forSale
                      ? (count == 0 ? tr('Continuous scan is on') : tr('{n} added to this sale', {'n': count}))
                      : tr('Point at a barcode'),
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
    // The frame is a target the cashier aims at, so it scales with the
    // viewfinder rather than staying a phone-sized box in a tablet's middle.
    final tablet = Breakpoints.isTablet(context);
    final w = tablet ? 380.0 : 262.0, h = tablet ? 260.0 : 180.0;
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
    final last = _last;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.forSale && last != null) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: Row(
                children: [
                  Icon(_lastWasFull ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                      size: 18, color: _lastWasFull ? AppColors.warning : AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastWasFull
                          ? tr('Only {n} {name} in stock', {'n': last.stock, 'name': last.name})
                          : tr('{name} added · {n} in this sale',
                              {'name': last.name, 'n': _session.countOf(last)}),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(color: Colors.white),
                    ),
                  ),
                  if (_session.countOf(last) > 0)
                    TextButton(
                      onPressed: _adjustLast,
                      child: Text(tr('Edit'), style: AppText.chip(color: Colors.white)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          GestureDetector(
            onTap: _enterManually,
            child: Text(
              tr('Enter code manually'),
              style: AppText.chip(color: Colors.white).copyWith(
                decoration: TextDecoration.underline,
                decorationColor: Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// In place of the plugin's bare English error on a black box.
  Widget _cameraError(MobileScannerException error) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => tr(
          "The camera is off for this app. Allow it in your phone's settings, or type the code instead."),
      MobileScannerErrorCode.unsupported =>
        tr("This phone's camera cannot scan here. Type the code instead."),
      _ => tr('The camera could not start. Type the code instead.'),
    };
    return ColoredBox(
      color: AppColors.ink,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 40),
              const SizedBox(height: 14),
              Text(message, textAlign: TextAlign.center, style: AppText.body(color: Colors.white)),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _enterManually,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                child: Text(tr('Type the code'), style: AppText.chip(color: Colors.white)),
              ),
            ],
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
      // The surface stays full width so the sheet still reads as anchored to
      // the bottom edge, but its contents do not: a product row and a pair of
      // buttons stretched across a tablet are a lap apart.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.maxReadingWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _matchSheet() {
    final p = _match!;
    // What can go in, once the cart and this session are counted — the sheet
    // used to cap at the shelf and ignore both.
    final ceiling = _adjusting ? _session.ceilingFor(p) : _session.roomFor(p);
    final minimum = _adjusting ? 0 : 1;
    final atStockCeiling = _matchQty >= ceiling;
    final noRoom = ceiling <= 0;
    return _sheet(
      children: [
        Row(
          children: [
            ProductThumb(product: p, size: 52, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: AppText.cardTitle().copyWith(fontSize: 15),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${p.category} · ${tr('{n} in stock', {'n': p.stock})}', style: AppText.caption()),
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
            Text(tr('Quantity'), style: AppText.body()),
            QtyStepper(
              value: _matchQty,
              canIncrement: !atStockCeiling,
              onDecrement: () {
                if (_matchQty > minimum) setState(() => _matchQty--);
              },
              onIncrement: () => setState(() => _matchQty++),
            ),
          ],
        ),
        if (atStockCeiling) ...[
          const SizedBox(height: 8),
          Text(tr('Only {n} in stock', {'n': p.stock}), style: AppText.caption(color: AppColors.warningText)),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: noRoom && !_adjusting ? null : _addToSale,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.disabledFill,
              foregroundColor: Colors.white,
              disabledForegroundColor: AppColors.faint,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
            ),
            child: Text(
              _adjusting
                  ? (_matchQty == 0
                      ? tr('Take out of this sale')
                      : tr('Set to {n} · {amount}', {'n': _matchQty, 'amount': formatPeso(p.price * _matchQty)}))
                  : noRoom
                      ? tr('Out of stock')
                      : tr('Add to sale · {amount}', {'amount': formatPeso(p.price * _matchQty)}),
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
            child: Text(tr('Keep scanning'), style: AppText.chip(color: AppColors.body)),
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
                    Text(tr('No product matches this code'),
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
            child: Text(tr('Add as new product'), style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: TextButton(
            onPressed: _resumeScanning,
            child: Text(tr('Scan again'), style: AppText.chip(color: AppColors.body)),
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
