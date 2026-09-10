import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'receipt_document.dart';
import 'settings_service.dart';

/// A printer the phone has already been paired with.
class PrinterDevice {
  const PrinterDevice({required this.name, required this.address});

  final String name;
  final String address;

  /// Some printers report an empty name; the address is the only thing that
  /// identifies them, so it stands in rather than showing a blank row.
  String get label => name.trim().isEmpty ? address : name.trim();
}

/// What happened when we tried to print.
///
/// A sealed result rather than a bool because every failure needs a different
/// thing from the shopkeeper — switch Bluetooth on, pick a printer, turn the
/// printer on — and "printing failed" tells them none of it.
sealed class PrintResult {
  const PrintResult();

  bool get ok => this is PrintOk;

  /// What to show on screen. Written as an instruction where there is one.
  String get message;
}

class PrintOk extends PrintResult {
  const PrintOk();
  @override
  String get message => 'Printed';
}

class PrintNoPrinter extends PrintResult {
  const PrintNoPrinter();
  @override
  String get message => 'No printer chosen yet — pick one in Settings';
}

class PrintPermissionNeeded extends PrintResult {
  const PrintPermissionNeeded();
  @override
  String get message => 'Allow Bluetooth access, then try again';
}

class PrintBluetoothOff extends PrintResult {
  const PrintBluetoothOff();
  @override
  String get message => 'Bluetooth is off — switch it on and try again';
}

class PrintUnsupported extends PrintResult {
  const PrintUnsupported();
  @override
  String get message => 'This device cannot print to a Bluetooth printer';
}

class PrintFailed extends PrintResult {
  const PrintFailed(this.detail);
  final String detail;

  @override
  String get message => 'Could not reach the printer. Is it switched on?';
}

/// The Bluetooth side of printing, behind an interface.
///
/// Split out so the receipt path can be tested end to end without a printer,
/// a phone, or a Bluetooth radio.
abstract class PrinterTransport {
  Future<bool> get isSupported;
  Future<bool> get hasPermission;
  Future<bool> get isBluetoothOn;
  Future<bool> get isConnected;
  Future<List<PrinterDevice>> paired();
  Future<bool> connect(String address);
  Future<bool> write(List<int> bytes);
  Future<void> disconnect();
}

/// Talks to a classic Bluetooth (SPP) thermal printer.
///
/// Only ever lists printers the phone is *already* paired with — pairing
/// happens in Android's own Bluetooth settings, where the PIN prompt belongs.
/// That also means the app never scans, so it needs no location permission.
class BluetoothPrinterTransport implements PrinterTransport {
  const BluetoothPrinterTransport();

  @override
  Future<bool> get isSupported async => Platform.isAndroid;

  /// Also *asks* for the permission on Android 12+, which is why a first
  /// attempt can come back false: the dialog is still on screen.
  @override
  Future<bool> get hasPermission =>
      PrintBluetoothThermal.isPermissionBluetoothGranted;

  @override
  Future<bool> get isBluetoothOn => PrintBluetoothThermal.bluetoothEnabled;

  @override
  Future<bool> get isConnected => PrintBluetoothThermal.connectionStatus;

  @override
  Future<List<PrinterDevice>> paired() async {
    final found = await PrintBluetoothThermal.pairedBluetooths;
    return [
      for (final d in found) PrinterDevice(name: d.name, address: d.macAdress),
    ];
  }

  @override
  Future<bool> connect(String address) =>
      PrintBluetoothThermal.connect(macPrinterAddress: address);

  @override
  Future<bool> write(List<int> bytes) => PrintBluetoothThermal.writeBytes(bytes);

  @override
  Future<void> disconnect() => PrintBluetoothThermal.disconnect;
}

/// Prints receipts to the paired thermal printer.
class PrinterService {
  PrinterService._();

  static final PrinterService instance = PrinterService._();

  /// Swapped for a fake in tests. The real one needs a radio and a printer;
  /// everything above it is ordinary code that deserves ordinary tests.
  PrinterTransport transport = const BluetoothPrinterTransport();

  SettingsService get _settings => SettingsService.instance;

  @visibleForTesting
  void resetForTests(PrinterTransport t) => transport = t;

  bool get hasPrinter => (_settings.printerAddress ?? '').isNotEmpty;

  Future<List<PrinterDevice>> pairedPrinters() => transport.paired();

  /// Prints a document, or says why it could not.
  Future<PrintResult> printDocument(List<ReceiptBlock> blocks) async {
    final address = _settings.printerAddress ?? '';
    if (address.isEmpty) return const PrintNoPrinter();
    return send(
      ReceiptDocument.asBytes(blocks, _settings.paperWidth),
      address,
    );
  }

  /// A short slip proving the printer is reachable and the paper width is set
  /// right — the rule should reach both edges without wrapping.
  Future<PrintResult> printTestPage() {
    final paper = _settings.paperWidth;
    return printDocument([
      ReceiptTitle(_settings.storeName),
      const ReceiptCentred('Printer test'),
      const ReceiptRule(),
      ReceiptRow('Paper', paper.label),
      ReceiptRow('Columns', '${paper.cols}'),
      const ReceiptRow('Peso sign', '1,234.50'),
      const ReceiptRule(),
      const ReceiptNote('If the dashed lines above reach both edges of the '
          'paper without wrapping, the width is right.'),
      const ReceiptGap(),
      const ReceiptCentred('Ready to print receipts'),
    ]);
  }

  @visibleForTesting
  Future<PrintResult> send(List<int> bytes, String address) async {
    try {
      if (!await transport.isSupported) return const PrintUnsupported();
      if (!await transport.hasPermission) return const PrintPermissionNeeded();
      if (!await transport.isBluetoothOn) return const PrintBluetoothOff();

      if (await transport.isConnected) {
        if (await transport.write(bytes)) return const PrintOk();
        // A socket that was open a minute ago can be dead without ever saying
        // so, and the shopkeeper only finds out when nothing comes out. One
        // reconnect costs a second and saves a re-rung sale. The failed write
        // printed nothing, so retrying cannot double up.
        await transport.disconnect();
      }

      if (!await transport.connect(address)) {
        return const PrintFailed('connect refused');
      }
      if (await transport.write(bytes)) return const PrintOk();
      return const PrintFailed('write refused');
    } catch (e) {
      // A printer going out of range mid-write throws from the platform. It
      // must not take the sale screen down with it.
      return PrintFailed('$e');
    }
  }
}
