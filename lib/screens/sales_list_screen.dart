import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/product_model.dart';
import '../models/sale_model.dart';
import '../services/product_service.dart';
import '../services/sales_service.dart';
import '../widgets/sale_detail_sheet.dart';
import '../widgets/sale_row.dart';
import '../widgets/skeleton.dart';
import '../l10n/tr.dart';

/// Every sale in a period, newest first — what the Transactions tile on
/// Home opens onto. Tap a row for the receipt.
class SalesListScreen extends StatefulWidget {
  const SalesListScreen({super.key, required this.days});

  /// 1 = today, 7 = this week, 30 = this month.
  final int days;

  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  final SalesService _sales = SalesService();
  final ProductService _productService = ProductService();

  List<Sale> _list = [];
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sales = await _sales.getSalesForPeriod(widget.days);
    final products = await _productService.getAllProducts();
    if (!mounted) return;
    setState(() {
      _list = sales;
      _products = products;
      _loading = false;
    });
  }

  String get _title => switch (widget.days) {
        1 => tr("Today's sales"),
        7 => tr("This week's sales"),
        30 => tr("This month's sales"),
        _ => tr('Sales · last {n} days', {'n': widget.days}),
      };

  double get _total => _list.fold(0, (s, x) => s + x.total);
  int get _items => _list.fold(0, (s, x) => s + x.itemCount);

  @override
  Widget build(BuildContext context) {
    final top = <Widget>[
      _header(),
      const SizedBox(height: 16),
      if (_loading)
        _skeleton()
      else if (_list.isEmpty)
        _empty()
      else ...[
        _summary(),
        const SizedBox(height: 14),
      ],
    ];
    final groups = _loading ? const <MapEntry<String, List<Sale>>>[] : _dayGroups();
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            // Built a day at a time as it scrolls into view. A busy month is
            // well over a thousand sales, and laying every row out before the
            // first frame was a visible stall on a budget phone.
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: Breakpoints.pagePadding(
                context,
                constraints.maxWidth,
                top: 12,
                bottom: 32 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: top.length + groups.length,
              itemBuilder: (context, i) =>
                  i < top.length ? top[i] : _dayGroup(groups[i - top.length]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.hairline),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.body, size: 15),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(_title, style: AppText.screenTitle())),
      ],
    );
  }

  Widget _summary() {
    Widget cell(String value, String label) => Expanded(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: AppText.statFigure(size: 19)),
              ),
              const SizedBox(height: 2),
              Text(label, style: AppText.caption()),
            ],
          ),
        );
    Widget rule() => Container(width: 1, height: 30, color: AppColors.divider);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          cell('${_list.length}', _list.length == 1 ? tr('Sale') : tr('Sales')),
          rule(),
          cell('$_items', tr('Items')),
          rule(),
          cell(formatPeso(_total), tr('Revenue')),
        ],
      ),
    );
  }

  /// Sales grouped under a day heading, so a week's list has landmarks.
  List<MapEntry<String, List<Sale>>> _dayGroups() {
    final groups = <String, List<Sale>>{};
    for (final s in _list) {
      groups.putIfAbsent(_dayLabel(s.createdAtDate), () => []).add(s);
    }
    return groups.entries.toList();
  }

  Widget _dayGroup(MapEntry<String, List<Sale>> e) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.days > 1) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(e.key.toUpperCase(), style: AppText.overline(color: AppColors.muted)),
          ),
        ],
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < e.value.length; i++) ...[
                SaleRow(
                  sale: e.value[i],
                  products: _products,
                  onTap: () async {
                    final changed = await showSaleDetail(context, e.value[i]);
                    if (changed == true) _load();
                  },
                ),
                if (i != e.value.length - 1) const Divider(color: AppColors.divider, height: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  String _dayLabel(DateTime d) => trRelativeDay(d);

  Widget _skeleton() {
    return Column(
      children: [
        for (int i = 0; i < 6; i++) ...[
          SkeletonCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: const [
                SkeletonBox(width: 40, height: 40, radius: 10),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 150, height: 12, emphasis: true),
                      SizedBox(height: 8),
                      SkeletonBox(width: 100, height: 10),
                    ],
                  ),
                ),
                SizedBox(width: 12),
                SkeletonBox(width: 56, height: 14, emphasis: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_outlined, color: AppColors.faint, size: 28),
          const SizedBox(height: 10),
          Text(tr('No sales in this period'), style: AppText.cardTitle()),
        ],
      ),
    );
  }
}
