import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../l10n/tr.dart';

/// "It worked", for the end of a flow: a solid green disc in a soft halo,
/// with a tick that draws itself in. A flat tick on a pale circle read as
/// plain, too close to the small status ticks everywhere else in the app.
///
/// Plays once when it first appears; still when animations are turned off.
class SuccessMark extends StatefulWidget {
  const SuccessMark({super.key, this.size = 84});

  /// The halo's diameter; the disc is two thirds of it.
  final double size;

  @override
  State<SuccessMark> createState() => _SuccessMarkState();
}

class _SuccessMarkState extends State<SuccessMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  late final Animation<double> _halo =
      CurvedAnimation(parent: _c, curve: const Interval(0, 0.6, curve: Curves.easeOut));
  late final Animation<double> _disc =
      CurvedAnimation(parent: _c, curve: const Interval(0, 0.55, curve: Curves.easeOutBack));
  late final Animation<double> _tick =
      CurvedAnimation(parent: _c, curve: const Interval(0.35, 1, curve: Curves.easeOutCubic));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final disc = s * 2 / 3;
    return Semantics(
      label: tr('Done'),
      child: SizedBox.square(
        dimension: s,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 0.7 + 0.3 * _halo.value,
                child: Opacity(
                  opacity: _halo.value,
                  child: Container(
                    decoration: const BoxDecoration(color: AppColors.successFill, shape: BoxShape.circle),
                  ),
                ),
              ),
              Transform.scale(
                scale: 0.4 + 0.6 * _disc.value,
                child: Container(
                  width: disc,
                  height: disc,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.22),
                        blurRadius: disc * 0.35,
                        offset: Offset(0, disc * 0.06),
                      ),
                    ],
                  ),
                  child: CustomPaint(painter: _TickPainter(_tick.value)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tick drawn along its own path, [progress] from nothing to whole.
class _TickPainter extends CustomPainter {
  _TickPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final w = size.width;
    final path = Path()
      ..moveTo(w * 0.29, w * 0.52)
      ..lineTo(w * 0.44, w * 0.66)
      ..lineTo(w * 0.72, w * 0.37);
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final metric = path.computeMetrics().single;
    canvas.drawPath(metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)), paint);
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.progress != progress;
}
