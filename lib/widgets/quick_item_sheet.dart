import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import '../l10n/tr.dart';

/// What the cashier rang up: a name (never empty — "Quick item" when they
/// gave none), the price of one, and how many.
typedef QuickItem = ({String name, double price, int qty});

/// Rings up something that is not in the catalog — ice, a single candy,
/// load — by price. Price first and focused: it is the one thing needed.
/// [name] pre-fills the name, usually from the search that found nothing.
class QuickItemSheet extends StatefulWidget {
  const QuickItemSheet({super.key, this.name = ''});

  final String name;

  static Future<QuickItem?> show(BuildContext context, {String name = ''}) {
    return showModalBottomSheet<QuickItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickItemSheet(name: name),
    );
  }

  @override
  State<QuickItemSheet> createState() => _QuickItemSheetState();
}

class _QuickItemSheetState extends State<QuickItemSheet> {
  final _price = TextEditingController();
  // A search is typed in lower case; the name goes on the receipt.
  late final _name = TextEditingController(text: _capitalised(widget.name.trim()));

  static String _capitalised(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  int _qty = 1;

  double get _priceValue => double.tryParse(_price.text.replaceAll(',', '').trim()) ?? 0;

  @override
  void dispose() {
    _price.dispose();
    _name.dispose();
    super.dispose();
  }

  void _add() {
    if (_priceValue <= 0) return;
    final name = _name.text.trim();
    Navigator.pop<QuickItem>(context, (
      name: name.isEmpty ? tr('Quick item') : name,
      price: (_priceValue * 100).roundToDouble() / 100,
      qty: _qty,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final price = _priceValue;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: EdgeInsets.fromLTRB(
            AppSpace.sheetPad, 14, AppSpace.sheetPad, 20 + MediaQuery.paddingOf(context).bottom),
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
                decoration:
                    BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(tr('Quick item'), style: AppText.sectionTitle().copyWith(fontSize: 18)),
            const SizedBox(height: 2),
            Text(tr('For something not on the product list. No stock is counted.'),
                style: AppText.caption()),
            const SizedBox(height: 16),
            Text(tr('Price'), style: AppText.body()),
            const SizedBox(height: 6),
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(color: AppColors.hairline),
              ),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: _price,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: AppText.largeFigure().copyWith(fontSize: 24),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: '0',
                  hintStyle: AppText.largeFigure(color: AppColors.faint).copyWith(fontSize: 24),
                  prefixText: '₱ ',
                  prefixStyle: AppText.largeFigure(color: AppColors.muted).copyWith(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Name (optional)'), style: AppText.body()),
                      const SizedBox(height: 6),
                      Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.canvas,
                          borderRadius: BorderRadius.circular(AppRadius.input),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        alignment: Alignment.centerLeft,
                        child: TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.sentences,
                          style: AppText.body(color: AppColors.ink),
                          onSubmitted: (_) => _add(),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                            hintText: tr('Yelo, candy, load…'),
                            hintStyle: AppText.body(color: AppColors.faint),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                QtyStepper(
                  value: _qty,
                  onDecrement: () => setState(() => _qty = _qty > 1 ? _qty - 1 : 1),
                  onIncrement: () => setState(() => _qty++),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: price > 0 ? _add : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.disabledFill,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                // Says what is missing while it cannot be pressed, as checkout does.
                child: Text(
                  price > 0
                      ? tr('Add {n} · {amount}', {'n': _qty, 'amount': formatPeso(price * _qty)})
                      : tr('Enter a price'),
                  style: AppText.chip(color: price > 0 ? Colors.white : AppColors.muted)
                      .copyWith(fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
