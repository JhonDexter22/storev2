import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// Lets the owning screen poke the [CartBar] from outside its build: ask
/// where the bag icon is (so a product can be flown into it) and trigger the
/// "caught something" bump once it lands.
class CartBarController {
  _CartBarState? _state;

  /// Global centre of the bag icon, or null when the bar is not laid out
  /// (tablet layout, or before first frame).
  Offset? bagCenter() => _state?._bagCenter();

  /// Play the landing animation: bar scales, bag wiggles, badge pops, and a
  /// blue flash runs across the bar.
  void bump() => _state?._bump();
}

/// The floating "N items · ₱total · Checkout" bar on the phone POS.
///
/// Stays mounted while the cart is empty so its resting position is known
/// before the first item lands; it slides in with a small overshoot when
/// [count] first goes above zero and drops away when it returns to zero.
class CartBar extends StatefulWidget {
  const CartBar({
    super.key,
    required this.count,
    required this.total,
    required this.onTap,
    required this.onCheckout,
    this.controller,
  });

  final int count;
  final double total;
  final VoidCallback onTap;
  final VoidCallback onCheckout;
  final CartBarController? controller;

  @override
  State<CartBar> createState() => _CartBarState();
}

class _CartBarState extends State<CartBar> with TickerProviderStateMixin {
  /// 0 = tucked below the screen edge, 1 = resting position.
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    reverseDuration: const Duration(milliseconds: 240),
    value: widget.count > 0 ? 1 : 0,
  );

  late final AnimationController _bumpCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// Outside every transform, so its rect is the bar's resting place even
  /// while the bar is sliding or hidden.
  final GlobalKey _restKey = GlobalKey();

  // Bar geometry the bag centre is derived from.
  static const _padH = 16.0;
  static const _bagSize = 24.0;

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 1.6),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _show,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  ));

  late final Animation<double> _fade = CurvedAnimation(
    parent: _show,
    curve: const Interval(0, 0.5, curve: Curves.easeOut),
    reverseCurve: const Interval(0.4, 1, curve: Curves.easeIn),
  );

  // ── Bump: a quick swell, then settle with a little overshoot.
  late final Animation<double> _barScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.05).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.05, end: 1.0).chain(CurveTween(curve: Curves.easeOutBack)), weight: 70),
  ]).animate(_bumpCtrl);

  late final Animation<double> _bagWiggle = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.22).chain(CurveTween(curve: Curves.easeOut)), weight: 25),
    TweenSequenceItem(tween: Tween(begin: -0.22, end: 0.16).chain(CurveTween(curve: Curves.easeInOut)), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 0.16, end: 0.0).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
  ]).animate(_bumpCtrl);

  late final Animation<double> _badgePop = Tween<double>(begin: 1.5, end: 1.0)
      .chain(CurveTween(curve: Curves.easeOutBack))
      .animate(_bumpCtrl);

  late final Animation<Color?> _flash = TweenSequence<Color?>([
    TweenSequenceItem(
      tween: ColorTween(begin: AppColors.ink, end: Color.lerp(AppColors.ink, AppColors.primary, 0.45)),
      weight: 25,
    ),
    TweenSequenceItem(
      tween: ColorTween(begin: Color.lerp(AppColors.ink, AppColors.primary, 0.45), end: AppColors.ink),
      weight: 75,
    ),
  ]).animate(_bumpCtrl);

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(CartBar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    final wasVisible = old.count > 0;
    final visible = widget.count > 0;
    if (visible && !wasVisible) _show.forward();
    if (!visible && wasVisible) _show.reverse();
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    _show.dispose();
    _bumpCtrl.dispose();
    super.dispose();
  }

  void _bump() {
    if (!mounted) return;
    _bumpCtrl.forward(from: 0);
  }

  Offset? _bagCenter() {
    final box = _restKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return Offset(origin.dx + _padH + _bagSize / 2, origin.dy + box.size.height / 2);
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.count > 0;
    return IgnorePointer(
      ignoring: !visible,
      child: Padding(
        // Clear the Sell button that rises out of the bottom bar.
        padding: EdgeInsets.fromLTRB(
          AppSpace.screenH, 0, AppSpace.screenH, MediaQuery.paddingOf(context).bottom),
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: AnimatedBuilder(
              animation: _bumpCtrl,
              builder: (context, child) => Transform.scale(
                scale: _barScale.value,
                child: GestureDetector(
                  onTap: widget.onTap,
                  child: Container(
                    key: _restKey,
                    padding: const EdgeInsets.fromLTRB(_padH, 12, 12, 12),
                    decoration: BoxDecoration(
                      color: _flash.value ?? AppColors.ink,
                      borderRadius: BorderRadius.circular(AppRadius.hero),
                      boxShadow: AppShadows.floatingCart,
                    ),
                    child: child,
                  ),
                ),
              ),
              child: Row(
                children: [
                  _bag(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Rolling<int>(
                          value: widget.count,
                          builder: (n) => Text(
                            '$n item${n == 1 ? '' : 's'}',
                            style: AppText.caption(color: AppColors.faint),
                          ),
                        ),
                        _Rolling<double>(
                          value: widget.total,
                          builder: (v) => Text(
                            formatPeso(v),
                            style: AppText.screenTitle(color: Colors.white).copyWith(fontSize: 21),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onCheckout,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text('Checkout',
                          style: AppText.chip(color: Colors.white).copyWith(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bag() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        RotationTransition(
          turns: _bagWiggle.drive(Tween(begin: 0.0, end: 1 / 6.28)),
          child: const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: _bagSize),
        ),
        Positioned(
          top: -6,
          right: -8,
          child: ScaleTransition(
            scale: _badgePop,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: _Rolling<int>(
                value: widget.count,
                builder: (n) => Text('$n', style: AppText.chip(color: Colors.white)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Odometer text: when the value goes up the old figure slides out the top
/// and the new one rises in from below; going down runs the other way.
class _Rolling<T extends Comparable<num>> extends StatefulWidget {
  const _Rolling({required this.value, required this.builder});

  final T value;
  final Widget Function(T value) builder;

  @override
  State<_Rolling<T>> createState() => _RollingState<T>();
}

class _RollingState<T extends Comparable<num>> extends State<_Rolling<T>> {
  late T _previous = widget.value;

  @override
  void didUpdateWidget(_Rolling<T> old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _previous = old.value;
  }

  @override
  Widget build(BuildContext context) {
    final up = widget.value.compareTo(_previous as num) >= 0;
    final currentKey = ValueKey(widget.value);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, animation) {
          final incoming = child.key == currentKey;
          // Incoming: from one line away → rest. Outgoing: the switcher runs
          // its animation backwards, so begin is where it ends up.
          final from = incoming ? (up ? 0.8 : -0.8) : (up ? -0.8 : 0.8);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: Offset(0, from), end: Offset.zero).animate(animation),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(key: currentKey, child: widget.builder(widget.value)),
      ),
    );
  }
}
