import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../l10n/tr.dart';
import '../models/product_model.dart';
import '../models/stock_move.dart';
import '../services/stock_history.dart';

/// Every change to stock, newest first: what moved it, by how much, what it
/// came to, and who was on the till. Given a [product], just that product's;
/// otherwise the whole store's, with filters for the kinds of change — "By
/// hand" is the one to read when the shelf and the app disagree.
class StockHistoryScreen extends StatefulWidget {
  const StockHistoryScreen({super.key, this.product, this.history});

  final Product? product;

  /// Injectable for tests.
  final StockHistory? history;

  @override
  State<StockHistoryScreen> createState() => _StockHistoryScreenState();
}

enum _Filter {
  all(null),
  restocks({StockMoveKind.restock, StockMoveKind.stockIn, StockMoveKind.added}),
  byHand({StockMoveKind.count, StockMoveKind.deleted, StockMoveKind.undo}),
  sales({StockMoveKind.sale}),
  returns({StockMoveKind.returned});

  const _Filter(this.kinds);

  final Set<StockMoveKind>? kinds;
}

class _StockHistoryScreenState extends State<StockHistoryScreen> {
  static const _page = 50;

  late final StockHistory _history = widget.history ?? StockHistory();
  List<StockMove> _moves = [];
  bool _loading = true;
  bool _hasMore = false;
  _Filter _filter = _Filter.all;

  bool get _oneProduct => widget.product != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<StockMove>> _fetch(int offset) => _history.moves(
        productId: widget.product?.id,
        kinds: _filter.kinds,
        limit: _page,
        offset: offset,
      );

  Future<void> _load() async {
    final filter = _filter;
    final moves = await _fetch(0);
    // A filter tapped while this was loading has its own load coming.
    if (!mounted || filter != _filter) return;
    setState(() {
      _moves = moves;
      _hasMore = moves.length == _page;
      _loading = false;
    });
  }

  Future<void> _loadOlder() async {
    final more = await _fetch(_moves.length);
    if (!mounted) return;
    setState(() {
      _moves = [..._moves, ...more];
      _hasMore = more.length == _page;
    });
  }

  void _setFilter(_Filter f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => ListView(
                  padding: Breakpoints.pagePadding(context, constraints.maxWidth, top: 6)
                      .add(EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom)),
                  children: [
                    if (!_oneProduct) ...[
                      _filterChips(),
                      const SizedBox(height: AppSpace.gapSection),
                    ],
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                      )
                    else if (_moves.isEmpty)
                      _empty()
                    else ...[
                      ..._byDay(),
                      if (_hasMore)
                        SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            onPressed: _loadOlder,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.body,
                              side: const BorderSide(color: AppColors.hairline),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.cta)),
                            ),
                            child: Text(tr('Show older'), style: AppText.chip(color: AppColors.body)),
                          ),
                        ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 12, AppSpace.screenH, 12),
      child: Row(
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
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.body, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Stock history'), style: AppText.screenTitle().copyWith(fontSize: 20)),
                Text(
                  widget.product?.name ?? tr('Every product'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChips() {
    Widget chip(_Filter f, String label) {
      final selected = _filter == f;
      return GestureDetector(
        onTap: () => _setFilter(f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          margin: const EdgeInsets.only(right: AppSpace.gapChip),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: selected ? AppColors.ink : AppColors.hairline),
          ),
          child: Text(label, style: AppText.chip(color: selected ? Colors.white : AppColors.body)),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(_Filter.all, tr('All')),
          chip(_Filter.byHand, tr('By hand')),
          chip(_Filter.restocks, tr('Restocks')),
          chip(_Filter.sales, tr('Sales')),
          chip(_Filter.returns, tr('Returns')),
        ],
      ),
    );
  }

  Widget _empty() {
    final (title, body) = switch (_filter) {
      _Filter.all => (
          tr('No stock changes yet'),
          tr('Sales, restocks and changes by hand show here from now on.'),
        ),
      _Filter.byHand => (
          tr('No changes by hand'),
          tr('Stock typed in on a product, deleted with stock, or put back with Undo shows here.'),
        ),
      _ => (tr('Nothing here yet'), ''),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 12),
      child: Column(
        children: [
          const Icon(Icons.history_rounded, size: 36, color: AppColors.faint),
          const SizedBox(height: 12),
          Text(title, style: AppText.cardTitle(), textAlign: TextAlign.center),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(body, style: AppText.body(), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  /// One card per day under its heading — Today, Yesterday, 29 Sep — the
  /// way Returns lists sales.
  List<Widget> _byDay() {
    final out = <Widget>[];
    var day = <StockMove>[];
    String? label;

    void flush() {
      if (day.isEmpty) return;
      out
        ..add(Padding(
          padding: EdgeInsets.only(top: out.isEmpty ? 0 : 8, bottom: 8, left: 2),
          child: Text(label!.toUpperCase(), style: AppText.overline(color: AppColors.muted)),
        ))
        ..add(Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            children: [
              for (var i = 0; i < day.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.divider, indent: 62),
                _row(day[i]),
              ],
            ],
          ),
        ))
        ..add(const SizedBox(height: 10));
    }

    for (final m in _moves) {
      final l = _dayLabel(m.createdAtDate);
      if (l != label) {
        flush();
        day = [];
        label = l;
      }
      day.add(m);
    }
    flush();
    return out;
  }

  /// "Today", "Yesterday", "29 Sep", and the year once it is another one.
  static String _dayLabel(DateTime d) {
    final rel = trRelativeDay(d);
    return d.year == DateTime.now().year ? rel : '$rel ${d.year}';
  }

  static String _kindLabel(StockMoveKind k) => switch (k) {
        StockMoveKind.sale => tr('Sold'),
        StockMoveKind.returned => tr('Returned'),
        StockMoveKind.restock => tr('Restocked'),
        StockMoveKind.stockIn => tr('Stock in'),
        StockMoveKind.count => tr('Changed by hand'),
        StockMoveKind.added => tr('New product'),
        StockMoveKind.deleted => tr('Deleted'),
        StockMoveKind.undo => tr('Undone'),
      };

  static (IconData, Color, Color) _look(StockMoveKind k) => switch (k) {
        StockMoveKind.sale => (Icons.shopping_bag_outlined, AppColors.body, AppColors.divider),
        StockMoveKind.returned =>
          (Icons.assignment_return_outlined, AppColors.primary, AppColors.primaryTint),
        StockMoveKind.restock ||
        StockMoveKind.stockIn ||
        StockMoveKind.added =>
          (Icons.inventory_2_outlined, AppColors.successText, AppColors.successFill),
        StockMoveKind.count => (Icons.edit_outlined, AppColors.warningText, AppColors.warningFill),
        StockMoveKind.deleted => (Icons.delete_outline_rounded, AppColors.danger, AppColors.dangerFill),
        StockMoveKind.undo => (Icons.undo_rounded, AppColors.body, AppColors.divider),
      };

  Widget _row(StockMove m) {
    final (icon, fg, bg) = _look(m.kind);
    final time = TimeOfDay.fromDateTime(m.createdAtDate).format(context);
    final details = [
      if (!_oneProduct) _kindLabel(m.kind),
      if (m.cashier.isNotEmpty) m.cashier,
      time,
      if (m.shortRef.isNotEmpty) m.shortRef,
    ].join(' · ');
    // Out by hand is the one to look at twice; out through a sale is the
    // shop working.
    final deltaColor = m.delta > 0
        ? AppColors.successText
        : m.kind.byHand
            ? AppColors.danger
            : AppColors.ink;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.cardPad, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: fg),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _oneProduct ? _kindLabel(m.kind) : m.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle(),
                ),
                const SizedBox(height: 2),
                Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption()),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_signed(m.delta), style: AppText.cardTitle(color: deltaColor)),
              const SizedBox(height: 2),
              Text(tr('{n} in stock', {'n': m.stockAfter}), style: AppText.caption()),
            ],
          ),
        ],
      ),
    );
  }

  /// "+24" and "−3", with a true minus sign.
  static String _signed(int n) => n > 0 ? '+$n' : '−${-n}';
}
