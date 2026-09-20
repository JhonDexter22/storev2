import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/product_model.dart';
import '../models/sale_model.dart';
import 'product_thumb.dart';

/// One sale in a list: what was bought, how it was paid and when, the total,
/// and the receipt number small on the right. Shared by Home's recent sales
/// and the full sales list so the two never drift apart.
class SaleRow extends StatelessWidget {
  const SaleRow({super.key, required this.sale, required this.products, required this.onTap});

  final Sale sale;

  /// The catalog, for the first line's photo. Missing products (deleted
  /// since the sale) fall back to a receipt icon.
  final List<Product> products;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = sale;
    final t = TimeOfDay.fromDateTime(s.createdAtDate);
    final count = s.itemCount;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _thumb(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.summary(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cardTitle()),
                    const SizedBox(height: 2),
                    Text(
                      // "1 item" says nothing the title has not; the count
                      // only earns its place once there is more than one.
                      '${count > 1 ? '$count items · ' : ''}${s.paymentMethod} · ${t.format(context)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatPeso(s.total), style: AppText.cardTitle()),
                  const SizedBox(height: 2),
                  Text(s.shortRef, style: AppText.mono(size: 10)),
                ],
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, color: AppColors.faint, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb() {
    final first = sale.items.isEmpty ? null : sale.items.first;
    Product? product;
    if (first != null) {
      for (final p in products) {
        if (p.id == first.productId) {
          product = p;
          break;
        }
      }
    }
    if (product == null) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.receipt_outlined, color: AppColors.primary, size: 18),
      );
    }
    return ProductThumb(product: product, size: 40, radius: 10);
  }
}
