import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'design_tokens.dart';

/// Layout breakpoints.
///
/// The handoff's tablet artboards run 1000–1180 logical pixels wide, and the
/// phone ones are 390. Anything at or above [tabletMinWidth] gets the
/// side-by-side layouts; everything below keeps the phone stack.
class Breakpoints {
  Breakpoints._();

  static const tabletMinWidth = 840.0;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletMinWidth;

  /// How wide a single column of text and rows is allowed to get.
  ///
  /// Screens that are genuinely one column — settings, a sign-in list, a
  /// history feed — do not get better by being wider. Stretched across a
  /// tablet a settings row puts its label and its switch a hand's width
  /// apart, and the eye loses the line between them.
  static const maxReadingWidth = 720.0;

  /// Page padding that caps a single-column screen at [maxReadingWidth] and
  /// centres it once there is room. Below the breakpoint it is the ordinary
  /// phone padding, so callers can use it unconditionally.
  ///
  /// [available] is the width the list actually gets, not the window's: on a
  /// tablet the navigation rail has already taken its share, and measuring
  /// from the window would leave the column both narrower than intended and
  /// off-centre. Get it from a [LayoutBuilder].
  static EdgeInsets pagePadding(
    BuildContext context,
    double available, {
    double top = 12,
    double bottom = 32,
    double phoneSide = AppSpace.screenH,
  }) {
    final side = isTablet(context) && available > maxReadingWidth
        ? (available - maxReadingWidth) / 2
        : phoneSide;
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }
}

/// Phones stay upright; tablets turn.
///
/// Turned sideways, a phone is wider than [Breakpoints.tabletMinWidth] and
/// got the tablet layout on a screen under 400 points tall: the rail cut off
/// More, and Sell showed one row of products with their prices clipped. A
/// counter phone has no use for landscape. A tablet, whose short side is
/// [phoneMaxShortestSide] or more, turns as it always has.
class OrientationPolicy {
  OrientationPolicy._();

  /// Android's own line between phone and tablet (sw600dp).
  static const phoneMaxShortestSide = 600.0;

  static bool isPhone(Size logical) => logical.shortestSide < phoneMaxShortestSide;

  static bool? _locked;
  static bool _started = false;

  /// Applies the rule now and again whenever the screen changes size, as
  /// when a foldable opens. Before the first frame the size may not be
  /// known yet; the first change after it applies the rule then.
  static void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(_MetricsObserver());
    apply();
  }

  /// For the screen the app is on now.
  static Future<void> apply() {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view == null || view.devicePixelRatio == 0) return Future.value();
    return applyFor(view.physicalSize / view.devicePixelRatio);
  }

  /// Only talks to the platform when the answer changes.
  static Future<void> applyFor(Size logical) async {
    if (logical.isEmpty) return;
    final lock = isPhone(logical);
    if (lock == _locked) return;
    _locked = lock;
    await SystemChrome.setPreferredOrientations(
        lock ? const [DeviceOrientation.portraitUp] : const []);
  }

  @visibleForTesting
  static void reset() => _locked = null;
}

class _MetricsObserver with WidgetsBindingObserver {
  @override
  void didChangeMetrics() => OrientationPolicy.apply();
}
