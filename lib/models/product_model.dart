class Product {
  final int? id;
  final String name;
  final int stock;
  final int minStock;
  final String category;
  final String createdAt;
  final double price;
  final String? sku;
  final String? imagePath;

  Product({
    this.id,
    required this.name,
    required this.stock,
    required this.minStock,
    required this.category,
    required this.createdAt,
    this.price = 0.0,
    this.sku,
    this.imagePath,
  });

  /// Something sold that is not in the catalog — ice, a single candy, load —
  /// rung up by price. It exists only in the cart and on the sale.
  ///
  /// Its id is negative, which no stored product's can be, and distinct
  /// within a sale: the line is saved with that id as its product_id, so a
  /// return can still tell two quick items on one receipt apart. Nothing in
  /// the products table matches it, so no stock moves.
  factory Product.quick({required int id, required String name, required double price}) {
    assert(id < 0);
    return Product(
      id: id,
      name: name,
      price: price,
      stock: quickStock,
      minStock: 0,
      category: '',
      createdAt: '',
    );
  }

  /// Not counted: what the till's "only so many on the shelf" caps compare
  /// against, so a quick item never hits them.
  static const quickStock = 9999;

  bool get isQuick => (id ?? 0) < 0;

  /// The same, for a product id read back from a sale line.
  static bool isQuickId(int id) => id < 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'stock': stock,
      'min_stock': minStock,
      'category': category,
      'created_at': createdAt,
      'price': price,
      'sku': sku,
      'image_path': imagePath,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      name: map['name'],
      stock: map['stock'],
      minStock: map['min_stock'],
      category: map['category'],
      createdAt: map['created_at'],
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      sku: map['sku'],
      imagePath: map['image_path'],
    );
  }

  Product copyWith({
    int? id,
    String? name,
    int? stock,
    int? minStock,
    String? category,
    String? createdAt,
    double? price,
    String? sku,
    String? imagePath,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      stock: stock ?? this.stock,
      minStock: minStock ?? this.minStock,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      price: price ?? this.price,
      sku: sku ?? this.sku,
      imagePath: imagePath ?? this.imagePath,
    );
  }
}