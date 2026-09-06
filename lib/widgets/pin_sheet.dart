import 'dart:async';

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../services/staff_service.dart';

/// A four-digit PIN gate, used both for the manager check before a shift close
/// and for per-cashier sign-in.
///
/// The sheet does not know any PIN. It collects four digits and hands them to
/// [verify], which is the only thing that can say yes — so the code being
/// checked against is never in the widget tree.
///
/// A wrong code turns the dots danger red and says how many tries are left;
/// the sheet stays open. Past the last try the keypad goes dead and counts
/// down. Returns true only on a correct code.
class PinSheet extends StatefulWidget {
  const PinSheet({
    super.key,
    required this.verify,
    required this.title,
    required this.hint,
    required this.confirmLabel,
    this.avatarInitials,
    this.subtitle,
  });

  /// Null puts the sheet in capture mode: four digits are collected and
  /// returned rather than judged. Used for setting a new PIN, where there is
  /// nothing to check them against yet.
  final Future<PinResult> Function(String pin)? verify;
  final String title;
  final String hint;
  final String confirmLabel;

  /// When set, an initials avatar is shown above the title — used for
  /// cashier sign-in so it is obvious who is being signed in.
  final String? avatarInitials;
  final String? subtitle;

  /// Collects four digits and returns them, with nothing checked. Returns
  /// null if cancelled.
  static Future<String?> capture(
    BuildContext context, {
    required String title,
    required String hint,
    required String confirmLabel,
    String? avatarInitials,
  }) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => PinSheet(
        verify: null,
        title: title,
        hint: hint,
        confirmLabel: confirmLabel,
        avatarInitials: avatarInitials,
      ),
    );
  }

  static Future<bool> show(
    BuildContext context, {
    required Future<PinResult> Function(String pin) verify,
    String title = 'Manager PIN',
    String hint = 'Enter the manager PIN to close this shift.',
    String confirmLabel = 'Confirm close',
    String? avatarInitials,
    String? subtitle,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => PinSheet(
        verify: verify,
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
  bool _checking = false;
  int? _attemptsLeft;
  Duration? _lockLeft;
  Timer? _lockTimer;

  bool get _locked => _lockLeft != null;

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }

  void _press(String digit) {
    if (_locked || _checking || _pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _wrong = false;
    });
  }

  void _backspace() {
    if (_locked || _checking || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _wrong = false;
    });
  }

  /// Ticks the lockout down so the sheet says when it will be usable again,
  /// then re-enables the keypad on its own.
  void _startLockCountdown(Duration remaining) {
    _lockTimer?.cancel();
    setState(() {
      _lockLeft = remaining;
      _pin = '';
      _wrong = true;
    });
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      final left = (_lockLeft ?? Duration.zero) - const Duration(seconds: 1);
      setState(() {
        if (left.inSeconds <= 0) {
          _lockLeft = null;
          _wrong = false;
          timer.cancel();
        } else {
          _lockLeft = left;
        }
      });
    });
  }

  Future<void> _confirm() async {
    if (_pin.length != 4 || _checking || _locked) return;

    final verify = widget.verify;
    if (verify == null) {
      Navigator.pop(context, _pin);
      return;
    }

    setState(() => _checking = true);
    final result = await verify(_pin);
    if (!mounted) return;

    switch (result) {
      case PinAccepted():
        Navigator.pop(context, true);
      case PinRejected(:final attemptsRemaining):
        setState(() {
          _checking = false;
          _wrong = true;
          _pin = '';
          _attemptsLeft = attemptsRemaining;
        });
      case PinLockedOut(:final remaining):
        setState(() {
          _checking = false;
          _attemptsLeft = null;
        });
        _startLockCountdown(remaining);
    }
  }

  String get _message {
    final lock = _lockLeft;
    if (lock != null) {
      final s = lock.inSeconds;
      return 'Too many wrong codes. Try again in ${s}s.';
    }
    if (!_wrong) return widget.subtitle ?? widget.hint;
    final left = _attemptsLeft;
    if (left == null) return 'That PIN was not recognised. Try again.';
    return left == 1
        ? 'That PIN was not recognised. 1 try left.'
        : 'That PIN was not recognised. $left tries left.';
  }

  @override
  Widget build(BuildContext context) {
    final alert = _wrong || _locked;
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
      // Scrollable: the keypad plus two buttons is a tall sheet, and on a
      // short screen — or with text scaled up — Confirm would otherwise sit
      // below the bottom edge with no way to reach it.
      child: SingleChildScrollView(
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
            _message,
            textAlign: TextAlign.center,
            style: AppText.caption(color: alert ? AppColors.dangerText : AppColors.muted),
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
              onPressed: (_pin.length == 4 && !_checking && !_locked) ? _confirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.disabledFill,
                foregroundColor: Colors.white,
                disabledForegroundColor: AppColors.faint,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
              ),
              child: _checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.confirmLabel,
                      style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: TextButton(
              onPressed: _checking
                  ? null
                  : () => Navigator.pop(context, widget.verify == null ? null : false),
              child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final filled = i < _pin.length;
        final alert = _wrong || _locked;
        final color = alert
            ? AppColors.danger
            : (filled ? AppColors.primary : AppColors.disabledFill);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: (filled || alert) ? color : Colors.transparent,
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
    final disabled = _locked || _checking;
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
          onTap: disabled ? null : () => isBackspace ? _backspace() : _press(k),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: AppColors.hairline),
            ),
            alignment: Alignment.center,
            child: Opacity(
              opacity: disabled ? 0.4 : 1,
              child: isBackspace
                  ? const Icon(Icons.backspace_outlined, size: 19, color: AppColors.body)
                  : Text(k, style: AppText.statFigure(size: 21)),
            ),
          ),
        );
      }).toList(),
    );
  }
}
