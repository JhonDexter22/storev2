import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/product_model.dart';
import 'product_thumb.dart';

/// One product thumbnail in flight from a tapped card to the cart bag.
///
/// The screen owns a list of these so it can settle them early (when the
/// cart is edited underneath them) or dispose them if it unmounts mid-air.
class FlyToCart {
  FlyToCart._(this._entry, this._ctrl);

  final OverlayEntry _entry;
  final AnimationController _ctrl;

  /// Launches a chip at [from] that arcs into [to] and calls [onLand] when
  /// it gets there. The caller keeps the returned handle until then.
  static FlyToCart launch({
    required BuildContext context,
    required TickerProvider vsync,
    required Product product,
    required Offset from,
    required Offset to,
    required VoidCallback onLand,
    int qty = 1,
  }) {
    final ctrl = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 520),
    );
    late final FlyToCart flight;
    final entry = OverlayEntry(
      builder: (_) =>
          _FlightChip(product: product, from: from, to: to, progress: ctrl, qty: qty),
    );
    flight = FlyToCart._(entry, ctrl);
    Overlay.of(context, rootOverlay: true).insert(entry);
    ctrl.forward().whenCompleteOrCancel(() {
      if (flight._live) {
        flight._dispose();
        onLand();
      }
    });
    return flight;
  }

  bool _live = true;

  /// Pull the chip out of the air without landing it.
  void cancel() {
    if (!_live) return;
    _dispose();
  }

  void _dispose() {
    _live = false;
    _ctrl.dispose();
    _entry.remove();
  }
}

class _FlightChip extends StatelessWidget {
  const _FlightChip({
    required this.product,
    required this.from,
    required this.to,
    required this.progress,
    this.qty = 1,
  });

  final Product product;
  final Offset from;
  final Offset to;
  final Animation<double> progress;

  /// More than one shows a "×N" tag on the chip so a bulk add reads as one.
  final int qty;

  static const _size = 52.0;

  @override
  Widget build(BuildContext context) {
    // A quadratic curve whose control point sits above and slightly toward
    // the side the chip came from, so it lobs up before dropping into the
    // bag rather than sliding down a straight line.
    final lift = math.max(90.0, (from - to).distance * 0.25);
    final control = Offset(
      (from.dx * 0.6 + to.dx * 0.4),
      math.min(from.dy, to.dy) - lift,
    );

    final path = CurvedAnimation(
      parent: progress,
      curve: Curves.easeInOutCubic,
    );
    final shrink = CurvedAnimation(
      parent: progress,
      curve: const Interval(0.35, 1, curve: Curves.easeIn),
    );
    final fade = CurvedAnimation(
      parent: progress,
      curve: const Interval(0.82, 1, curve: Curves.easeIn),
    );

    // Positioned has to sit directly under a Stack, so the overlay entry
    // brings its own rather than leaning on the Overlay's.
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: progress,
            builder: (context, child) {
              final t = path.value;
              final u = 1 - t;
              final p = from * (u * u) + control * (2 * u * t) + to * (t * t);
              final scale = 1 - 0.65 * shrink.value;
              final half = _size / 2;
              return Positioned(
                left: p.dx - half,
                top: p.dy - half,
                child: Opacity(
                  opacity: 1 - fade.value,
                  child: Transform.scale(scale: scale, child: child),
                ),
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: _size,
                  height: _size,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface,
                    boxShadow: AppShadows.cardHover,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: ClipOval(
                    child: ProductThumb(
                      product: product,
                      size: _size - 6,
                      radius: _size,
                      iconSize: 20,
                    ),
                  ),
                ),
                if (qty > 1)
                  Positioned(
                    right: -6,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                      child: Text(
                        '×$qty',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
