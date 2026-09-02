import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// A placeholder block used while data loads.
///
/// Deliberately static: the handoff keeps motion to a minimum (the switch knob
/// is the only animated property), so a shimmer would be louder than the
/// design asks for.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
    this.emphasis = false,
  });

  final double? width;
  final double height;
  final double radius;

  /// Use for the one or two blocks that stand in for a headline figure, so a
  /// skeleton has the same visual hierarchy as the screen it replaces.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: emphasis ? AppColors.skeletonEmphasis : AppColors.skeleton,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Wraps skeleton content in the same card chrome the real content uses, so
/// nothing shifts when the data lands.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, required this.child, this.padding, this.radius});

  final Widget child;
  final EdgeInsets? padding;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius ?? AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: child,
    );
  }
}
