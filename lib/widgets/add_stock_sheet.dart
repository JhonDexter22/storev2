import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';

/// A number pad and a Save: what restocking off a delivery actually needs.
///
/// Adds via the relative [ProductService.addStock], so a sale that lands
/// while the sheet is open is not overwritten. Completes with the amount
/// added, or null if dismissed; the caller reloads and announces it.
Future<int?> showAddStockSheet(BuildContext context, Product p) {
  final ctrl = TextEditingController();
  int amount = 0;

  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final after = p.stock + amount;

        Future<void> save() async {
          if (amount <= 0) return;
          final added = amount;
          await ProductService().addStock(p.id!, added);
          HapticFeedback.lightImpact();
          if (ctx.mounted) Navigator.pop(ctx, added);
        }

        Widget quick(int n) => Expanded(
          child: GestureDetector(
            onTap: () {
              ctrl.text = '${amount + n}';
              setSheet(() => amount += n);
            },
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(AppRadius.iconBtn),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Text('+$n', style: AppText.chip()),
            ),
          ),
        );

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              AppSpace.sheetPad,
              14,
              AppSpace.sheetPad,
              20 + MediaQuery.paddingOf(ctx).bottom,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
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
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add stock',
                  style: AppText.sectionTitle().copyWith(fontSize: 18),
                ),
                const SizedBox(height: 2),
                Text(
                  '${p.name} · ${p.stock} on hand',
                  style: AppText.caption(),
                ),
                const SizedBox(height: 16),
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.center,
                    style: AppText.largeFigure(),
                    onChanged: (v) =>
                        setSheet(() => amount = int.tryParse(v) ?? 0),
                    onSubmitted: (_) => save(),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      hintText: '0',
                      hintStyle: AppText.largeFigure(color: AppColors.faint),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    quick(5),
                    const SizedBox(width: 8),
                    quick(10),
                    const SizedBox(width: 8),
                    quick(12),
                    const SizedBox(width: 8),
                    quick(24),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('After', style: AppText.body()),
                    const Spacer(),
                    Text(
                      '$after',
                      style: AppText.statFigure(
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(' units', style: AppText.caption()),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: amount > 0 ? save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.disabledFill,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.cta),
                      ),
                    ),
                    child: Text(
                      amount > 0 ? 'Add $amount' : 'Add stock',
                      style: AppText.chip(
                        color: Colors.white,
                      ).copyWith(fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
