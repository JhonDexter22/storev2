import 'package:flutter/material.dart';

import '../core/design_tokens.dart';

/// A four-digit PIN gate, used both for the manager check before a shift close
/// and for per-cashier sign-in.
///
/// A wrong code turns the dots danger red and updates the hint; the sheet stays
/// open. Returns true only on a correct code.
class PinSheet extends StatefulWidget {
  const PinSheet({
    super.key,
    required this.expectedPin,
    required this.title,
    required this.hint,
    required this.confirmLabel,
    this.avatarInitials,
    this.subtitle,
  });

  final String expectedPin;
  final String title;
  final String hint;
  final String confirmLabel;

  /// When set, an initials avatar is shown above the title — used for
  /// cashier sign-in so it is obvious who is being signed in.
  final String? avatarInitials;
  final String? subtitle;

  /// Manager PIN for authorising a close. Prototype value — replace with real
  /// auth before shipping.
  static const managerPin = '2468';

  static Future<bool> show(
    BuildContext context, {
    required String expectedPin,
    String title = 'Manager PIN',
    String hint = 'Enter the manager PIN to close this shift.',
    String confirmLabel = 'Confirm close',
    String? avatarInitials,
    String? subtitle,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PinSheet(
        expectedPin: expectedPin,
        title: title,
        hint: hint,
        confirmLabel: confirmLabel,
        avatarInitials: avatarInitials,
        subtitle: subtitle,
      ),
    );
    return ok ?? false;
  }

  @override
  State<PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<PinSheet> {
  String _pin = '';
  bool _wrong = false;

  void _press(String digit) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _wrong = false;
    });
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _wrong = false;
    });
  }

  void _confirm() {
    if (_pin.length != 4) return;
    if (_pin == widget.expectedPin) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _wrong = true;
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.sheetPad,
        14,
        AppSpace.sheetPad,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 18),
          if (widget.avatarInitials != null) ...[
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: AppColors.primaryTint, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(widget.avatarInitials!,
                  style: AppText.statFigure(color: AppColors.primary, size: 20)),
            ),
            const SizedBox(height: 12),
          ],
          Text(widget.title, style: AppText.sectionTitle().copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            _wrong ? 'That PIN was not recognised. Try again.' : (widget.subtitle ?? widget.hint),
            textAlign: TextAlign.center,
            style: AppText.caption(color: _wrong ? AppColors.dangerText : AppColors.muted),
          ),
          const SizedBox(height: 20),
          _dots(),
          const SizedBox(height: 20),
          _keypad(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _pin.length == 4 ? _confirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.disabledFill,
                foregroundColor: Colors.white,
                disabledForegroundColor: AppColors.faint,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
              ),
              child: Text(widget.confirmLabel,
                  style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final filled = i < _pin.length;
        final color = _wrong
            ? AppColors.danger
            : (filled ? AppColors.primary : AppColors.disabledFill);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: (filled || _wrong) ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
        );
      }),
    );
  }

  /// 3x4 grid: 1-9, blank bottom-left, 0, backspace bottom-right.
  Widget _keypad() {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: keys.map((k) {
        if (k.isEmpty) return const SizedBox.shrink();
        final isBackspace = k == '<';
        return GestureDetector(
          onTap: () => isBackspace ? _backspace() : _press(k),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: AppColors.hairline),
            ),
            alignment: Alignment.center,
            child: isBackspace
                ? const Icon(Icons.backspace_outlined, size: 19, color: AppColors.body)
                : Text(k, style: AppText.statFigure(size: 21)),
          ),
        );
      }).toList(),
    );
  }
}
