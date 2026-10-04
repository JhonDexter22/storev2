import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/product_model.dart';
import 'product_thumb.dart';
import '../l10n/tr.dart';

/// Grid tile shared by the till and the catalog: photo across the full top
/// edge (or the category's colour when there is none), a Low pill floating
/// on it when that applies, then name / category / price.
///
/// The photo takes whatever height the grid leaves after the fixed text
/// block, so the card never ends in a band of dead space.
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

  /// Grid aspect that fits the text block with a roughly 4:3 photo above it.
  static const aspectRatio = 0.74;

  /// The name, category and price block below the photo, at normal text
  /// size, as measured; 18 less without the category line.
  static double textBlockHeight({bool showCategory = true}) => showCategory ? 105 : 87;

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stock <= 0;
    final dimmed = dimWhenOut && outOfStock;
    final selected = qtyInCart > 0;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.hairline,
              width: selected ? 1.5 : 1,
            ),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _photo()),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 36,
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.cardTitle().copyWith(height: 1.3),
                      ),
                    ),
                    if (showCategory) ...[
                      const SizedBox(height: 2),
                      Text(product.category,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption()),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            formatPeso(product.price),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.statFigure(size: 16),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Grey while healthy: a green count on most of the
                        // grid drowned the amber and red ones that matter.
                        // Out of stock is said here, once, not also in a pill.
                        Text(
                          outOfStock ? tr('Out of stock') : tr('{n} left', {'n': product.stock}),
                          style: AppText.caption(
                              color: product.stock <= product.minStock
                                  ? StockStatus.text(product.stock, product.minStock)
                                  : AppColors.muted),
                        ),
                      ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                  child: Text('$qtyInCart',
                      style: AppText.chip(color: Colors.white).copyWith(fontSize: 11)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Fills the area — except a photo in a short till tile, which becomes a
  /// centred square on the category colour. Cropped to a full-width strip it
  /// showed only a band through the middle of the picture.
  Widget _image() {
    final hasPhoto = (product.imagePath ?? '').isNotEmpty;
    if (!hasPhoto) return ProductThumb(product: product, radius: 0, iconSize: 26, tinted: true);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxHeight >= c.maxWidth * 0.5) {
        return ProductThumb(product: product, radius: 0, iconSize: 26, tinted: true);
      }
      // Inset and rounded like the thumbnails elsewhere, so it sits in the
      // strip rather than looking pasted across it.
      const gap = 6.0;
      return ColoredBox(
        color: CategoryTint.of(product.category).fill,
        child: Center(
          child: ProductThumb(
              product: product, size: c.maxHeight - gap * 2, radius: 10, tinted: true),
        ),
      );
    });
  }
}
