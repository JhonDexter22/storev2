import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/payment_type.dart';
import 'escpos.dart';

/// Store settings and the active till session, persisted across launches.
///
/// A [ChangeNotifier] so the headers that show the active cashier update the
/// moment someone else signs in, rather than on the next rebuild by luck.
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const _kPrintReceipt = 'print_receipt';
  static const _kScanSound = 'scan_sound';
  static const _kLowStockAlerts = 'low_stock_alerts';
  static const _kAutoBackup = 'auto_backup';
  static const _kDefaultMinStock = 'default_min_stock';
  static const _kCashier = 'active_cashier';
  static const _kStoreName = 'store_name';
  static const _kTerminal = 'terminal';
  static const _kOpeningFloat = 'opening_float';
  static const _kLastBackup = 'last_backup';
  static const _kDisabledPayments = 'disabled_payment_types';
  static const _kCustomPayments = 'custom_payment_types';
  static const _kPrinterName = 'printer_name';
  static const _kPrinterAddress = 'printer_address';
  static const _kPaperWidth = 'paper_width';

  SharedPreferences? _prefs;
  bool get isLoaded => _prefs != null;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    notifyListeners();
  }

  /// Drops the cached preferences so the next [load] reads them again.
  ///
  /// `setMockInitialValues` replaces the store behind SharedPreferences but
  /// not the copy held here, so without this one test's settings quietly leak
  /// into the next and a test can pass on the previous test's printer.
  @visibleForTesting
  void resetForTests() => _prefs = null;

  bool get printReceipt => _prefs?.getBool(_kPrintReceipt) ?? true;
  bool get scanSound => _prefs?.getBool(_kScanSound) ?? true;
  bool get lowStockAlerts => _prefs?.getBool(_kLowStockAlerts) ?? true;
  bool get autoBackup => _prefs?.getBool(_kAutoBackup) ?? false;
  int get defaultMinStock => _prefs?.getInt(_kDefaultMinStock) ?? 5;
  String get cashier => _prefs?.getString(_kCashier) ?? 'May';
  String get storeName => _prefs?.getString(_kStoreName) ?? 'Sari-Sari Store';
  String get terminal => _prefs?.getString(_kTerminal) ?? 'Terminal 1';
  double get openingFloat => _prefs?.getDouble(_kOpeningFloat) ?? 1000;
  String? get lastBackup => _prefs?.getString(_kLastBackup);

  /// The paired thermal printer, if one has been chosen.
  ///
  /// The address is what the app connects to; the name is only ever shown, so
  /// a printer renamed in Android's settings still prints.
  String? get printerAddress => _prefs?.getString(_kPrinterAddress);
  String get printerName => _prefs?.getString(_kPrinterName) ?? '';

  /// 58 mm is the roll nearly every handheld printer takes, so it is the
  /// default. Getting this wrong wraps every line, which is why it is a
  /// setting rather than a guess.
  PaperWidth get paperWidth => PaperWidth.byName(_prefs?.getString(_kPaperWidth));

  Future<void> setPrinter(String? address, {String name = ''}) async {
    if (address == null || address.isEmpty) {
      await _prefs?.remove(_kPrinterAddress);
      await _prefs?.remove(_kPrinterName);
    } else {
      await _prefs?.setString(_kPrinterAddress, address);
      await _prefs?.setString(_kPrinterName, name);
    }
    notifyListeners();
  }

  Future<void> setPaperWidth(PaperWidth width) async {
    await _prefs?.setString(_kPaperWidth, width.name);
    notifyListeners();
  }

  /// The payment types offered at checkout, in the order they appear.
  ///
  /// Disabling one only changes what is *offered*. Sales store the method as
  /// plain text, so a Card sale taken last month still displays and still
  /// refunds after Card is switched off — turning a type off must never
  /// rewrite history.
  List<PaymentType> get paymentTypes {
    final off = _prefs?.getStringList(_kDisabledPayments) ?? const [];
    final custom = _prefs?.getStringList(_kCustomPayments) ?? const [];
    return [
      for (final t in PaymentType.builtInTypes)
        if (!t.canBeDisabled || !off.contains(t.name)) t,
      for (final name in custom)
        if (!off.contains(name))
          PaymentType(name: name, kind: PaymentKind.plain, builtIn: false),
    ];
  }

  /// Every type the shopkeeper can see in settings, on or off.
  List<PaymentType> get allPaymentTypes => [
        ...PaymentType.builtInTypes,
        for (final name in _prefs?.getStringList(_kCustomPayments) ?? const [])
          PaymentType(name: name, kind: PaymentKind.plain, builtIn: false),
      ];

  bool isPaymentTypeEnabled(PaymentType type) {
    if (!type.canBeDisabled) return true;
    final off = _prefs?.getStringList(_kDisabledPayments) ?? const [];
    return !off.contains(type.name);
  }

  Future<void> setPaymentTypeEnabled(PaymentType type, bool enabled) async {
    if (!type.canBeDisabled) return;
    final off = [...?_prefs?.getStringList(_kDisabledPayments)];
    if (enabled) {
      off.remove(type.name);
    } else if (!off.contains(type.name)) {
      off.add(type.name);
    }
    await _prefs?.setStringList(_kDisabledPayments, off);
    notifyListeners();
  }

  /// Adds a type of the shopkeeper's own — Maya, a bank transfer, whatever
  /// they actually take. Returns false if the name is already in use.
  Future<bool> addPaymentType(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    final taken = allPaymentTypes
        .any((t) => t.name.toLowerCase() == trimmed.toLowerCase());
    if (taken) return false;

    final custom = [...?_prefs?.getStringList(_kCustomPayments), trimmed];
    await _prefs?.setStringList(_kCustomPayments, custom);
    // Adding one that was previously removed should arrive switched on.
    final off = [...?_prefs?.getStringList(_kDisabledPayments)]..remove(trimmed);
    await _prefs?.setStringList(_kDisabledPayments, off);
    notifyListeners();
    return true;
  }

  /// Removes a type the shopkeeper added. Built-in ones are switched off
  /// rather than deleted, so they can be turned back on.
  Future<void> removePaymentType(PaymentType type) async {
    if (type.builtIn) return;
    final custom = [...?_prefs?.getStringList(_kCustomPayments)]
      ..remove(type.name);
    await _prefs?.setStringList(_kCustomPayments, custom);
    notifyListeners();
  }

  Future<void> setPrintReceipt(bool v) => _setBool(_kPrintReceipt, v);
  Future<void> setScanSound(bool v) => _setBool(_kScanSound, v);
  Future<void> setLowStockAlerts(bool v) => _setBool(_kLowStockAlerts, v);
  Future<void> setAutoBackup(bool v) => _setBool(_kAutoBackup, v);

  Future<void> setDefaultMinStock(int v) async {
    await _prefs?.setInt(_kDefaultMinStock, v);
    notifyListeners();
  }

  Future<void> setCashier(String name) async {
    await _prefs?.setString(_kCashier, name);
    notifyListeners();
  }

  Future<void> setOpeningFloat(double v) async {
    await _prefs?.setDouble(_kOpeningFloat, v);
    notifyListeners();
  }

  Future<void> markBackedUp() async {
    await _prefs?.setString(_kLastBackup, DateTime.now().toIso8601String());
    notifyListeners();
  }

  Future<void> _setBool(String key, bool v) async {
    await _prefs?.setBool(key, v);
    notifyListeners();
  }
}
