class Product {
  final int? id;
  final String name;
  final int stock;
  final int minStock;
  final String category;
  final String createdAt;

  Product({
    this.id,
    required this.name,
    required this.stock,
    required this.minStock,
    required this.category,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'stock': stock,
      'min_stock': minStock,
      'category': category,
      'created_at': createdAt,
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
    );
  }
}
