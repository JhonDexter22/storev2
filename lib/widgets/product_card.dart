import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/product_model.dart';
import 'product_thumb.dart';

/// Grid tile shared by the till and the catalog: photo across the full top
/// edge, stock state floating on the photo, then name / category / price.
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

  /// Grid aspect that fits the text block with a roughly 4:3 photo above it.
  static const aspectRatio = 0.74;

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
                    const SizedBox(height: 2),
                    Text(product.category,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption()),
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
                        Text(
                          outOfStock ? '0 left' : '${product.stock} left',
                          style: AppText.caption(
                              color: StockStatus.text(product.stock, product.minStock)),
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
            top: 8,
            right: 8,
            child: Container(
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
      ],
    );
  }

  Widget _image() => ProductThumb(product: product, radius: 0, iconSize: 26);
}
