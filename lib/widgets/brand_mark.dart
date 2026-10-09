import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// The BasePoint mark: a white "b" with an amber dot on primary blue, the
/// same drawing as the launcher icon. The shapes mirror tool/make_icons.py,
/// which generates the platform icons, and the launch splash and intro draw
/// them too (see there) — change them all together.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size, required this.radius});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: CustomPaint(painter: _GlyphPainter()),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  static const _amber = Color(0xFFFFC23D);

  @override
  void paint(Canvas canvas, Size size) {
    // Design space is 100 units; the glyph is 62.5 tall, centred on (55, 49.25).
    final k = size.height * 0.6 / 62.5;
    canvas
      ..translate(size.width / 2 - 55 * k, size.height / 2 - 49.25 * k)
      ..scale(k);

    final white = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromLTRBR(28, 20, 41, 80, const Radius.circular(6.5)),
      white,
    );
    // Stroke centred between the bowl's outer (22.5) and inner (9.5) radii.
    canvas.drawCircle(
      const Offset(54, 58),
      16,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13,
    );
    canvas.drawCircle(const Offset(74, 26), 8, Paint()..color = _amber);
  }

  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) => false;
}
