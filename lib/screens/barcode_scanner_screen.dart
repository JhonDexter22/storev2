import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class SimpleBarcodeScannerScreen extends StatefulWidget {
  const SimpleBarcodeScannerScreen({super.key});

  @override
  State<SimpleBarcodeScannerScreen> createState() => _SimpleBarcodeScannerScreenState();
}

class _SimpleBarcodeScannerScreenState extends State<SimpleBarcodeScannerScreen> {
  // MobileScannerController handles the camera instance
  final MobileScannerController cameraController = MobileScannerController();
  bool _isScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        actions: [
          // Optional: A button to turn on the flashlight!
          IconButton(
            icon: const Icon(Icons.flashlight_on),
            onPressed: () => cameraController.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: cameraController,
        onDetect: (BarcodeCapture capture) {
          // Prevent multiple scans from triggering at once
          if (_isScanned) return;

          // Get the raw value of the scanned barcode
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            _isScanned = true;
            final String scannedCode = barcodes.first.rawValue!;
            
            // Return the scanned code back to your button
            Navigator.pop(context, scannedCode);
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    // Always dispose of the camera controller to prevent memory leaks
    cameraController.dispose();
    super.dispose();
  }
}