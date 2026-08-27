import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared design tokens for the POS redesign.
/// Source: design_handoff_pos_redesign/README.md — direction 1b.
class AppColors {
  AppColors._();

  static const canvas = Color(0xFFF5F6FA);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0D0F1A);
  static const body = Color(0xFF5A5F7A);
  static const muted = Color(0xFF8A90AB);
  static const faint = Color(0xFFA2A7BF);
  static const hairline = Color(0xFFE7EAF4);
  static const divider = Color(0xFFF0F2F8);
  static const dividerStrong = Color(0xFFEAECF5);

  static const primary = Color(0xFF2554E8);
  static const primaryPressed = Color(0xFF1B44C8);
  static const primaryTint = Color(0xFFEEF2FE);
  static const disabledFill = Color(0xFFDDE2F0);

  static const success = Color(0xFF16A34A);
  static const successText = Color(0xFF15803D);
  static const successFill = Color(0xFFECFDF3);

  static const warning = Color(0xFFD97706);
  static const warningText = Color(0xFFB45309);
  static const warningFill = Color(0xFFFFFBEB);
  static const warningBorder = Color(0xFFFDE9C8);

  static const danger = Color(0xFFDC2626);
  static const dangerText = Color(0xFFB91C1C);
  static const dangerFill = Color(0xFFFEF2F2);
  static const dangerBorder = Color(0xFFFBDADA);

  static const skeleton = Color(0xFFEDEFF7);
  static const skeletonEmphasis = Color(0xFFE4E8F3);
}

class AppShadows {
  AppShadows._();

  static const card = [
    BoxShadow(color: Color(0x0D141830), blurRadius: 3, offset: Offset(0, 1)),
  ];

  static const cardHover = [
    BoxShadow(color: Color(0x1A141830), blurRadius: 20, offset: Offset(0, 8)),
  ];

  static const primaryCta = [
    BoxShadow(color: Color(0x472554E8), blurRadius: 24, offset: Offset(0, 10)),
  ];

  static const floatingCart = [
    BoxShadow(color: Color(0x480D0F1A), blurRadius: 32, offset: Offset(0, 14)),
  ];

  static const overlay = [
    BoxShadow(color: Color(0x730D0F1A), blurRadius: 60, offset: Offset(0, 24)),
  ];
}

/// Text styles built on Plus Jakarta Sans, per the handoff typography scale.
class AppText {
  AppText._();

  static TextStyle _f({
    required double size,
    required FontWeight weight,
    double? letterSpacing,
    Color color = AppColors.ink,
    double? height,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
      height: height,
      fontFeatures: const [],
    );
  }

  static TextStyle screenTitle({Color color = AppColors.ink}) =>
      _f(size: 25, weight: FontWeight.w800, letterSpacing: -0.75, color: color);

  static TextStyle sectionTitle({Color color = AppColors.ink}) =>
      _f(size: 15, weight: FontWeight.w800, letterSpacing: -0.3, color: color);

  static TextStyle heroFigure({Color color = AppColors.ink}) => _f(
      size: 33,
      weight: FontWeight.w800,
      letterSpacing: -1.32,
      color: color,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle largeFigure({Color color = AppColors.ink}) => _f(
      size: 26,
      weight: FontWeight.w800,
      letterSpacing: -0.91,
      color: color,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle statFigure({Color color = AppColors.ink, double size = 23}) =>
      _f(size: size, weight: FontWeight.w800, letterSpacing: -0.7, color: color)
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle cardTitle({Color color = AppColors.ink}) =>
      _f(size: 13.5, weight: FontWeight.w700, letterSpacing: -0.13, color: color);

  static TextStyle body({Color color = AppColors.body}) =>
      _f(size: 12.5, weight: FontWeight.w600, color: color);

  static TextStyle caption({Color color = AppColors.muted}) =>
      _f(size: 11.5, weight: FontWeight.w600, color: color);

  static TextStyle overline({Color color = AppColors.primary}) =>
      _f(size: 10.5, weight: FontWeight.w700, letterSpacing: 1.05, color: color);

  static TextStyle chip({Color color = AppColors.ink}) =>
      _f(size: 11.5, weight: FontWeight.w700, color: color);

  static TextStyle mono({Color color = AppColors.muted, double size = 10.5}) =>
      GoogleFonts.robotoMono(fontSize: size, color: color, fontWeight: FontWeight.w500);
}

class AppRadius {
  AppRadius._();
  static const hero = 20.0;
  static const card = 18.0;
  static const cta = 16.0;
  static const input = 14.0;
  static const iconBtn = 13.0;
  static const navPill = 11.0;
  static const chip = 999.0;
}

class AppSpace {
  AppSpace._();
  static const screenH = 20.0;
  static const cardPad = 14.0;
  static const sheetPad = 20.0;
  static const gapChip = 8.0;
  static const gapGrid = 11.0;
  static const gapSection = 14.0;
  static const gapBlock = 22.0;
}

/// Diagonal-striped placeholder used everywhere a product photo would go.
class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({super.key, this.borderRadius = 12, this.iconSize = 18});

  final double borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CustomPaint(
        painter: _StripePainter(),
        child: Center(
          child: Text(
            'photo',
            style: AppText.mono(color: AppColors.faint, size: iconSize * 0.6),
          ),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = AppColors.divider;
    canvas.drawRect(Offset.zero & size, bg);
    final stripe = Paint()..color = AppColors.dividerStrong;
    const gap = 12.0;
    final diag = size.width + size.height;
    for (double x = -size.height; x < diag; x += gap) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + 6, 0)
        ..lineTo(x + 6 + size.height, size.height)
        ..lineTo(x + size.height, size.height)
        ..close();
      canvas.drawPath(path, stripe);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small colored status pill — used for stock state, sync state, etc.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.fg,
    required this.bg,
    this.dot = true,
  });

  final String label;
  final Color fg;
  final Color bg;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(label, style: AppText.chip(color: fg)),
        ],
      ),
    );
  }
}

class StockStatus {
  static Color dot(int stock, int minStock) {
    if (stock <= 0) return AppColors.danger;
    if (stock <= minStock) return AppColors.warning;
    return AppColors.success;
  }

  static Color fill(int stock, int minStock) {
    if (stock <= 0) return AppColors.dangerFill;
    if (stock <= minStock) return AppColors.warningFill;
    return AppColors.successFill;
  }

  static Color text(int stock, int minStock) {
    if (stock <= 0) return AppColors.dangerText;
    if (stock <= minStock) return AppColors.warningText;
    return AppColors.successText;
  }

  static String label(int stock, int minStock) {
    if (stock <= 0) return 'Out of stock';
    if (stock <= minStock) return 'Low stock';
    return 'In stock';
  }
}

/// 42x26 track switch matching the handoff spec.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeInOut,
        width: 42,
        height: 26,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? AppColors.primary : AppColors.disabledFill,
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeInOut,
          width: 22,
          height: 22,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

String formatPeso(num value) {
  final isNeg = value < 0;
  final v = value.abs();
  final s = v.toStringAsFixed(2);
  final parts = s.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    final posFromEnd = intPart.length - i;
    buf.write(intPart[i]);
    if (posFromEnd > 1 && posFromEnd % 3 == 1) buf.write(',');
  }
  return '${isNeg ? '-' : ''}₱${buf.toString()}.${parts[1]}';
}
