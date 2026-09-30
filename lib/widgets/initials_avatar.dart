import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

enum AvatarTone {
  /// The person on the till: solid primary, the same everywhere they appear
  /// (Home header, More card, Switch cashier).
  active,

  /// Anyone else on the roster.
  idle,

  /// Someone being asked for their code (PIN sheet).
  soft,
}

/// A staff member's initials in a circle. One widget so the signed-in cashier
/// looks the same on every screen rather than each screen picking a colour.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.initials, {super.key, this.size = 46, this.tone = AvatarTone.active});

  final String initials;
  final double size;
  final AvatarTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      AvatarTone.active => (AppColors.primary, Colors.white),
      AvatarTone.idle => (AppColors.canvas, AppColors.body),
      AvatarTone.soft => (AppColors.primaryTint, AppColors.primary),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        maxLines: 1,
        style: AppText.statFigure(color: foreground, size: size * 0.36),
      ),
    );
  }
}
