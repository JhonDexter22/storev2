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
    this.tinted = true,
  });

  final Product product;
  final double? size;
  final double radius;
  final double iconSize;

  /// With no photo, fill with the category's colour rather than stripes —
  /// everywhere, so "blue is noodles" holds from the till to Restock.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final path = product.imagePath;
    final placeholder = PhotoPlaceholder(
      borderRadius: radius,
      iconSize: iconSize,
      name: product.name,
      tint: tinted ? CategoryTint.of(product.category) : null,
    );
    if (path == null || path.isEmpty) {
      return size == null
          ? placeholder
          : SizedBox(width: size, height: size, child: placeholder);
    }

    Widget photo(double side) => ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image(
            image: _sized(File(path), side * MediaQuery.devicePixelRatioOf(context)),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => placeholder,
          ),
        );

    if (size != null) {
      return SizedBox(width: size, height: size, child: photo(size!));
    }
    return LayoutBuilder(
      builder: (context, c) {
        final side = c.hasBoundedWidth
            ? c.maxWidth
            : (c.hasBoundedHeight ? c.maxHeight : 200.0);
        return photo(side);
      },
    );
  }

  /// Decodes the photo at roughly the size it is drawn, not the size the
  /// camera took it.
  ///
  /// A saved photo is up to 1200 px wide — over 4 MB once decoded — and a
  /// 44 px thumbnail needs a fraction of that. With a few hundred products
  /// the full-size decodes overran the image cache, so scrolling the list
  /// decoded the same photos again and again and stuttered on a budget phone.
  ///
  /// Fitted within a square twice the drawn size, so a photo of any usual
  /// shape still has at least the drawn size along its short side and stays
  /// sharp when cropped to fill.
  static ImageProvider _sized(File file, double px) {
    final bound = (px * 2).ceil().clamp(64, 2048);
    return ResizeImage(
      FileImage(file),
      width: bound,
      height: bound,
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }
}
