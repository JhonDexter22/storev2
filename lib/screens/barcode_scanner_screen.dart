import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/design_tokens.dart';

class SimpleBarcodeScannerScreen extends StatefulWidget {
  const SimpleBarcodeScannerScreen({super.key});

  @override
  State<SimpleBarcodeScannerScreen> createState() => _SimpleBarcodeScannerScreenState();
}

class _SimpleBarcodeScannerScreenState extends State<SimpleBarcodeScannerScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController cameraController = MobileScannerController();
  bool _isScanned = false;
  bool _torchOn = false;
  late final AnimationController _scanAnim;

  @override
  void initState() {
    super.initState();
    _scanAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanAnim.dispose();
    cameraController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;
    final barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      _isScanned = true;
      Navigator.pop(context, barcodes.first.rawValue!);
    }
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
            child: Text('Add', style: AppText.chip(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (code != null && code.isNotEmpty && mounted) Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  Positioned.fill(
                    child: Container(color: AppColors.ink.withValues(alpha: 0.35)),
                  ),
                  _reticle(),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Scan barcode', style: AppText.sectionTitle(color: Colors.white).copyWith(fontSize: 16)),
                Text('Continuous scan is on', style: AppText.caption(color: AppColors.faint)),
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
              child: Icon(_torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reticle() {
    const w = 262.0, h = 180.0;
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.transparent)),
          ..._corners(w, h),
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

  List<Widget> _corners(double w, double h) {
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

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        children: [
          GestureDetector(
            onTap: _enterManually,
            child: Text(
              'Enter code manually',
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
    final path = Path();
    final y = top ? 0.0 : size.height;
    final x = left ? 0.0 : size.width;
    // Vertical leg
    path.moveTo(x, top ? 0 : size.height);
    path.lineTo(x, top ? size.height : 0);
    canvas.drawPath(path, paint);
    // Horizontal leg
    final hPath = Path()
      ..moveTo(left ? 0 : size.width, y)
      ..lineTo(left ? size.width : 0, y);
    canvas.drawPath(hPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
