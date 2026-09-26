import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import '../l10n/tr.dart';
import '../services/settings_service.dart';

/// English | Filipino, as a segmented control. Each side is written in its
/// own language, so someone who cannot read the current one can still find
/// theirs. The switch is instant and keeps the screen in place.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key, this.compact = false});

  /// `EN | FIL` for a header; full names for a settings row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final current = SettingsService.instance.language;

    Widget side(AppLanguage lang) {
      final on = lang == current;
      final label = compact ? (lang == AppLanguage.en ? 'EN' : 'FIL') : lang.label;
      return Semantics(
        button: true,
        selected: on,
        label: lang.label,
        child: GestureDetector(
          onTap: on
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  SettingsService.instance.setLanguage(lang);
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16, vertical: compact ? 6 : 9),
            decoration: BoxDecoration(
              color: on ? AppColors.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(label, style: AppText.chip(color: on ? Colors.white : AppColors.body)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final l in AppLanguage.values) side(l)],
      ),
    );
  }
}
