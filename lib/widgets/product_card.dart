import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/design_tokens.dart';
import '../models/product_model.dart';
import 'product_thumb.dart';
import '../l10n/tr.dart';

/// Grid tile shared by the till and the catalog: a square photo across the
/// top (or a monogram on the category's colour when there is none), a Low
/// pill floating on it when that applies, then name / category / price.
///
/// Lay it out with [ProductGridDelegate], which makes the photo area square
/// and leaves exactly [ProductCard.textBlockHeight] for the text.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onLongPress,
    this.qtyInCart = 0,
    this.dimWhenOut = false,
    this.showLowStock = true,
    this.showCategory = true,
    this.onQtyTap,
  });

  final Product product;
  final VoidCallback? onTap;

  /// The catalog hangs its quick-action sheet off a long press.
  final VoidCallback? onLongPress;

  /// Units of this product already in the sale — drawn as a badge on the photo.
  final int qtyInCart;

  /// The till greys out what it cannot sell; the catalog keeps every product
  /// at full strength because an out-of-stock item is still editable there.
  final bool dimWhenOut;

  /// Off at the till: "Low stock" is the owner's job, and the card already
  /// says "2 left" in amber. Out of stock still shows.
  final bool showLowStock;

  /// Off at the till, where the chips already filter by category and the
  /// tile's colour says it at a glance.
  final bool showCategory;

  /// The till opens its quantity picker from the in-cart badge — a visible
  /// way in besides the long press.
  final VoidCallback? onQtyTap;

  /// The name, the stock line and the price below the photo, at normal text
  /// size: room for a two-line name, the stock (with the category in the
  /// catalog) on one small line, then the price. Narrow enough for three
  /// cards across a phone, where the price and "21 left" no longer share a
  /// line.
  static double textBlockHeight({bool showCategory = true}) => 96;

  /// [textBlockHeight] at the reader's text size, for sizing the grid.
  static double textBlockFor(BuildContext context, {bool showCategory = true}) =>
      MediaQuery.textScalerOf(context).scale(textBlockHeight(showCategory: showCategory));

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stock <= 0;
    final dimmed = dimWhenOut && outOfStock;
    final selected = qtyInCart > 0;
    final radius = BorderRadius.circular(AppRadius.card);
    final stockColor = product.stock <= product.minStock
        ? StockStatus.text(product.stock, product.minStock)
        : AppColors.muted;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: radius,
            boxShadow: AppShadows.card,
          ),
          // The edge is drawn over the photo and the tint, not under them:
          // underneath, their square corners covered the rounded border and
          // the blue outline of a card in the sale looked cut at every
          // corner.
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _photo()),
              Container(
                height: textBlockFor(context, showCategory: showCategory),
                // In the sale: a tint under the name and a blue edge. A thick
                // outline on every card in the cart made a busy grid.
                color: selected ? AppColors.primaryTint : null,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.cardTitle().copyWith(height: 1.3),
                    ),
                    const SizedBox(height: 2),
                    // Grey while healthy: a green count on most of the grid
                    // drowned the amber and red ones that matter. Out of
                    // stock is said here, once, not also in a pill.
                    Text.rich(
                      TextSpan(children: [
                        if (showCategory) TextSpan(text: '${product.category} · '),
                        TextSpan(
                          text: outOfStock ? tr('Out of stock') : tr('{n} left', {'n': product.stock}),
                          style: TextStyle(color: stockColor),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(),
                    ),
                    const Spacer(),
                    Text(
                      formatPeso(product.price),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.statFigure(size: 15),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photo() {
    return Stack(
      fit: StackFit.expand,
      children: [
        _image(),
        // Soft edge so the pill and badge stay legible over a busy photo.
        if ((product.imagePath ?? '').isNotEmpty)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.ink.withValues(alpha: 0.10), Colors.transparent],
                  stops: const [0, 0.5],
                ),
              ),
            ),
          ),
        // Low and Out only. "In stock" on every card was most of the grid
        // saying nothing, and it drowned the ones that need a restock.
        if (showLowStock && product.stock > 0 && product.stock <= product.minStock)
          Positioned(
            left: 8,
            top: 8,
            child: StatusPill(
              label: StockStatus.label(product.stock, product.minStock),
              fg: StockStatus.text(product.stock, product.minStock),
              bg: AppColors.surface,
            ),
          ),
        if (qtyInCart > 0)
          Positioned(
            // The padding is the touch target; the badge itself is 24px.
            top: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onQtyTap,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  key: const ValueKey('qty-badge'),
                  constraints: const BoxConstraints(minWidth: 24),
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                  child: Text('×$qtyInCart',
                      style: AppText.chip(color: Colors.white).copyWith(fontSize: 11)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The photo across the whole area (square in a grid laid out by
  /// [ProductGridDelegate], the shape the photos are kept in), or a
  /// monogram on the category's colour when there is none.
  Widget _image() {
    if ((product.imagePath ?? '').isEmpty) return _Monogram(product: product);
    return ProductThumb(product: product, radius: 0, iconSize: 26, tinted: true);
  }
}

/// Two letters in a rounded tile on the category's colour. One big letter on
/// a pastel block read as a picture that had not loaded, and "sanmarino" and
/// "skylfakesss" were both just "S".
class _Monogram extends StatelessWidget {
  const _Monogram({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final tint = CategoryTint.of(product.category);
    final letters = PhotoPlaceholder.initialsOf(product.name);
    return ColoredBox(
      color: tint.fill,
      child: LayoutBuilder(builder: (context, c) {
        final side = (c.biggest.shortestSide * 0.6).clamp(28.0, 48.0);
        return Center(
          child: Container(
            width: side,
            height: side,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color.alphaBlend(tint.ink.withValues(alpha: 0.12), tint.fill),
              borderRadius: BorderRadius.circular(side * 0.28),
            ),
            child: Text(
              letters,
              maxLines: 1,
              style: AppText.statFigure(color: tint.ink, size: side * 0.36),
            ),
          ),
        );
      }),
    );
  }
}

/// Lays product cards out with a square photo whatever the screen's width:
/// the tile is as wide as its column and as tall as that plus the text
/// block. A fixed aspect ratio left the photo wider than tall on most
/// phones, so the square photos lost their top and bottom.
class ProductGridDelegate extends SliverGridDelegate {
  const ProductGridDelegate({
    required this.columns,
    required this.textBlock,
    this.photoHeight,
    this.spacing = AppSpace.gapGrid,
  });

  final int columns;

  /// The text block's height at the reader's text size
  /// ([ProductCard.textBlockFor]).
  final double textBlock;

  /// A fixed photo height (the till's short strip); null for a square.
  final double? photoHeight;
  final double spacing;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = (constraints.crossAxisExtent - spacing * (columns - 1)) / columns;
    final height = (photoHeight ?? width) + textBlock;
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: height + spacing,
      crossAxisStride: width + spacing,
      childMainAxisExtent: height,
      childCrossAxisExtent: width,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(ProductGridDelegate old) =>
      old.columns != columns ||
      old.textBlock != textBlock ||
      old.photoHeight != photoHeight ||
      old.spacing != spacing;
}
