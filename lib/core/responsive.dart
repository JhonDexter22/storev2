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
