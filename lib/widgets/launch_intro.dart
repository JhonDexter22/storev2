import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';

/// The moment between the launch splash and the till, under a second: the
/// amber dot hops and lands on the "b", the mark draws back, then the screen
/// zooms through the hole in the "b" and the app is behind it.
///
/// Its first frame is the Android splash exactly (res/drawable/splash_mark.xml:
/// brand blue, the mark centred, [glyphHeight] tall), so the hand-over from
/// Android to Flutter does not show. The app builds underneath from the first
/// frame, so its own loading overlaps the intro. Taps wait until the intro is
/// gone, and with the phone's animations turned off it does not run at all.
///
/// The status bar keeps the splash's white icons until the intro ends, then
/// turns dark for the app's light screens.
class LaunchIntro extends StatefulWidget {
  const LaunchIntro({super.key, required this.child});

  final Widget child;

  /// The glyph's height on the splash, in logical pixels.
  static const glyphHeight = 128.0;

  /// A still beat on the splash picture first, so a slow first frame on a
  /// cheap phone eats the wait and not the start of the hop.
  static const hold = Duration(milliseconds: 120);

  static const duration = Duration(milliseconds: 950);

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

class _LaunchIntroState extends State<LaunchIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: LaunchIntro.duration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _finish();
        });
  Timer? _hold;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        // After this frame's own system-bar style has gone out: one set in
        // the same frame replaces it rather than adding to it.
        scheduleMicrotask(_finish);
      } else {
        _hold = Timer(LaunchIntro.hold, _controller.forward);
      }
    });
  }

  void _finish() {
    if (!mounted) return;
    setState(() => _done = true);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _hold?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The app keeps the same place in the tree before and after, so nothing
    // in it is rebuilt from scratch when the intro goes.
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) =>
              Transform.scale(scale: _IntroTimeline(_controller.value).appScale, child: child),
          child: widget.child,
        ),
        if (!_done)
          AbsorbPointer(
            child: CustomPaint(painter: _IntroPainter(_controller)),
          ),
      ],
    );
  }
}

/// Where each part of the intro is at time [t], 0 to 1.
class _IntroTimeline {
  _IntroTimeline(this.t);

  final double t;

  static double _span(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  /// The dot's lift above its place, in glyph units: one parabolic hop.
  double get dotLift {
    final x = _span(t, 0, 0.36);
    return 13 * 4 * x * (1 - x);
  }

  /// How far the dot squashes as it lands, 0 to 1 and back.
  double get dotSquash {
    final x = _span(t, 0.36, 0.5);
    return x == 0 || x == 1 ? 0 : math.sin(math.pi * x);
  }

  /// The mark's scale: a step back, then the zoom (its far end is set by
  /// the screen size, so it is a 0-to-1 progress here).
  double get pullBack => Curves.easeInOut.transform(_span(t, 0.4, 0.58));
  double get zoom => Curves.easeInCubic.transform(_span(t, 0.58, 1));

  /// The hole in the "b" turns from blue into a window on the app.
  double get holeOpen => Curves.easeOut.transform(_span(t, 0.5, 0.62));

  /// The whole overlay fades over the last stretch of the zoom.
  double get opacity => 1 - Curves.easeIn.transform(_span(t, 0.82, 1));

  /// The app comes forward to meet the zoom, from slightly small to its size.
  double get appScale => 0.94 + 0.06 * Curves.easeOutCubic.transform(_span(t, 0.58, 1));
}

class _IntroPainter extends CustomPainter {
  _IntroPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static const _amber = Color(0xFFFFC23D);

  // tool/make_icons.py's glyph, in its 100-unit design space.
  static const _glyphCenter = Offset(55, 49.25);
  static const _glyphUnits = 62.5;
  static const _bowl = Offset(54, 58);
  static const _bowlOuter = 22.5;
  static const _bowlInner = 9.5;
  static const _dot = Offset(74, 26);
  static const _dotRadius = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final time = _IntroTimeline(animation.value);
    final unit = LaunchIntro.glyphHeight / _glyphUnits;
    final center = size.center(Offset.zero);
    // Everything scales about the bowl's centre, so the zoom goes through it.
    final pivot = center + (_bowl - _glyphCenter) * unit;

    // Far enough that the hole clears the farthest corner of the screen.
    final reach = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ].map((c) => (c - pivot).distance).reduce(math.max);
    const pulled = 0.9;
    final zoomed = reach / (_bowlInner * unit) * 1.05;
    final scale = (1 - (1 - pulled) * time.pullBack) + (zoomed - pulled) * time.zoom;

    if (time.opacity < 1) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(0, 0, 0, time.opacity),
      );
    }

    final blue = Paint()..color = AppColors.primary;
    final hole = Rect.fromCircle(center: pivot, radius: _bowlInner * unit * scale);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addOval(hole),
      blue,
    );
    if (time.holeOpen < 1) {
      canvas.drawOval(hole, Paint()..color = AppColors.primary.withValues(alpha: 1 - time.holeOpen));
    }

    canvas
      ..save()
      ..translate(pivot.dx, pivot.dy)
      ..scale(unit * scale)
      ..translate(-_bowl.dx, -_bowl.dy);

    final white = Paint()..color = Colors.white;
    canvas
      ..drawRRect(RRect.fromLTRBR(28, 20, 41, 80, const Radius.circular(6.5)), white)
      ..drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addOval(Rect.fromCircle(center: _bowl, radius: _bowlOuter))
          ..addOval(Rect.fromCircle(center: _bowl, radius: _bowlInner)),
        white,
      );

    // The dot squashes against its own bottom edge, where it lands.
    final squash = 0.2 * time.dotSquash;
    final base = _dot.translate(0, _dotRadius);
    canvas
      ..translate(base.dx, base.dy - time.dotLift)
      ..scale(1 + squash, 1 - squash)
      ..drawCircle(const Offset(0, -_dotRadius), _dotRadius, Paint()..color = _amber)
      ..restore();

    if (time.opacity < 1) canvas.restore();
  }

  @override
  bool shouldRepaint(_IntroPainter oldDelegate) => oldDelegate.animation != animation;
}
