import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';

class RestockScreen extends StatefulWidget {
  const RestockScreen({super.key});

  @override
  State<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends State<RestockScreen> {

  final ProductService _productService = ProductService();
  List<Product> _lowStockProducts = [];

  @override
  void initState() {
    super.initState();
    _loadLowStockProducts();
  }

  Future<void> _loadLowStockProducts() async {
    final products = await _productService.getLowStockProducts();
    setState(() {
      _lowStockProducts = products;
    });
  }

  void _showAddStockDialog(Product product) {
    final TextEditingController stockController =
        TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Add Stock - ${product.name}"),
        content: TextField(
          controller: stockController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Quantity to Add"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final int addedStock =
                  int.tryParse(stockController.text) ?? 0;

              if (addedStock > 0) {
                final updatedStock =
                    product.stock + addedStock;

                await _productService.updateStock(
                  product.id!,
                  updatedStock,
                );

                Navigator.pop(context);
                _loadLowStockProducts();
              }
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Restock List")),
      body: _lowStockProducts.isEmpty
          ? const Center(
              child: Text("No items need restocking 🎉"),
            )
          : ListView.builder(
              itemCount: _lowStockProducts.length,
              itemBuilder: (context, index) {
                final product = _lowStockProducts[index];

                return Card(
                  color: Colors.red.shade50,
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(product.name),
                    subtitle: Text(
                        "Current Stock: ${product.stock}"),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle,
                          color: Colors.green),
                      onPressed: () {
                        _showAddStockDialog(product);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
