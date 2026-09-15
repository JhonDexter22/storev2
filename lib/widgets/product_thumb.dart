import 'dart:io';

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/product_model.dart';

/// The product's photo, or the placeholder if there is none — or if the
/// file has gone, which is what a cleared cache used to leave behind.
///
/// Give it a [size] for a square thumbnail; leave it null to fill the parent.
class ProductThumb extends StatelessWidget {
  const ProductThumb({
    super.key,
    required this.product,
    this.size,
    this.radius = 12,
    this.iconSize = 18,
  });

  final Product product;
  final double? size;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final path = product.imagePath;
    final placeholder = PhotoPlaceholder(borderRadius: radius, iconSize: iconSize);
    final child = (path == null || path.isEmpty)
        ? placeholder
        : ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            ),
          );
    if (size == null) return child;
    return SizedBox(width: size, height: size, child: child);
  }
}
