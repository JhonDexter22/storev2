import 'product_model.dart';

/// One line of an in-progress sale. Transient — lives only in POS/checkout state.
class CartLine {
  CartLine({required this.product, required this.qty});

  final Product product;
  int qty;

  double get lineTotal => product.price * qty;
}
