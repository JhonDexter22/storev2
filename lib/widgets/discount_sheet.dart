import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/discount.dart';

/// Picks a discount. Presets first because they are what actually gets used,
/// with a custom amount underneath for the cases they do not cover.
class DiscountSheet extends StatefulWidget {
  const DiscountSheet({super.key, required this.subtotal, required this.current});

  final double subtotal;
  final Discount current;

  static Future<Discount?> show(
    BuildContext context, {
    required double subtotal,
    required Discount current,
  }) {
    return showModalBottomSheet<Discount>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DiscountSheet(subtotal: subtotal, current: current),
    );
  }

  @override
  State<DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<DiscountSheet> {
  late final _valueCtrl = TextEditingController(
    text: widget.current.isZero ? '' : _trim(widget.current.value),
  );
  late final _reasonCtrl = TextEditingController(text: widget.current.reason);
  // Percent unless a fixed amount is already in play: every preset is a
  // percentage, so that is what the cashier is usually about to type.
  late DiscountKind _kind =
      widget.current.isZero ? DiscountKind.percent : widget.current.kind;
  String? _error;

  static String _trim(double v) =>
      v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _valueCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Discount get _draft => Discount(
        kind: _kind,
        value: double.tryParse(_valueCtrl.text.trim()) ?? 0,
        reason: _reasonCtrl.text.trim(),
      );

  void _apply(Discount discount) {
    if (discount.isZero) {
      setState(() => _error = 'Enter how much to take off.');
      return;
    }
    if (discount.kind == DiscountKind.percent && discount.value > 100) {
      setState(() => _error = 'A discount cannot be more than 100%.');
      return;
    }
    // The reason is what makes a discount auditable afterwards, so it is
    // required rather than a nicety.
    if (discount.reason.isEmpty) {
      setState(() => _error = 'Say what the discount is for.');
      return;
    }
    Navigator.pop(context, discount);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final off = draft.amountOn(widget.subtotal);
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.sheetPad,
        14,
        AppSpace.sheetPad,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Add a discount',
                style: AppText.sectionTitle().copyWith(fontSize: 18)),
            const SizedBox(height: 2),
            Text('Subtotal ${formatPeso(widget.subtotal)}', style: AppText.caption()),
            const SizedBox(height: 16),
            for (final preset in Discount.presets) ...[
              _presetRow(preset.label, preset.kind, preset.value),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            Text('Or set your own', style: AppText.body()),
            const SizedBox(height: 8),
            Row(
              children: [
                _kindToggle('%', DiscountKind.percent),
                const SizedBox(width: 8),
                _kindToggle(pesoSign, DiscountKind.amount),
                const SizedBox(width: 10),
                Expanded(
                  child: _field(_valueCtrl,
                      hint: _kind == DiscountKind.percent ? '10' : '20.00',
                      number: true),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _field(_reasonCtrl, hint: 'Reason (e.g. damaged packaging)'),
            if (!draft.isZero) ...[
              const SizedBox(height: 10),
              Text(
                'Takes off ${formatPeso(off)} · '
                'new total ${formatPeso(widget.subtotal - off)}',
                style: AppText.caption(color: AppColors.successText),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppText.caption(color: AppColors.dangerText)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => _apply(_draft),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                child: Text('Apply discount',
                    style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetRow(String label, DiscountKind kind, double value) {
    final discount = Discount(kind: kind, value: value, reason: label);
    final off = discount.amountOn(widget.subtotal);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.input),
        onTap: () => Navigator.pop(context, discount),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppText.cardTitle())),
              Text('${value.toStringAsFixed(0)}% · -${formatPeso(off)}',
                  style: AppText.caption(color: AppColors.successText)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindToggle(String label, DiscountKind kind) {
    final selected = _kind == kind;
    return GestureDetector(
      onTap: () => setState(() {
        _kind = kind;
        _error = null;
      }),
      child: Container(
        width: 46,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTint : AppColors.canvas,
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: AppText.cardTitle(
                color: selected ? AppColors.primary : AppColors.body)),
      ),
    );
  }

  Widget _field(TextEditingController controller,
      {required String hint, bool number = false}) {
    return TextField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (_) => setState(() => _error = null),
      style: AppText.body(color: AppColors.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.caption(),
        filled: true,
        fillColor: AppColors.canvas,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
