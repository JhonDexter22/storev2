import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  SharedPreferences? _prefs;
  bool get isLoaded => _prefs != null;

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    notifyListeners();
  }

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
