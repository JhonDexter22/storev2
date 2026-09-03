import 'package:flutter/widgets.dart';

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
}
