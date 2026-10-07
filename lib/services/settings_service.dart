import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/tr.dart';

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
  static const _kCreditLimit = 'credit_limit';
  static const _kLastBackup = 'last_backup';
  static const _kDisabledPayments = 'disabled_payment_types';
  static const _kCustomPayments = 'custom_payment_types';
  static const _kPrinterName = 'printer_name';
  static const _kPrinterAddress = 'printer_address';
  static const _kPaperWidth = 'paper_width';
  static const _kProductsGrid = 'products_grid_view';
  static const _kLanguage = 'language';
  static const _kSetupDone = 'setup_done';
  static const _kErrorsSeen = 'errors_seen_at';
  static const _kSignedOut = 'signed_out';

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
  /// On unless switched off. The reminder is the only thing in the app that
  /// says the store lives on this phone alone, and a shopkeeper who has never
  /// heard that cannot know to turn it on.
  bool get autoBackup => _prefs?.getBool(_kAutoBackup) ?? true;
  int get defaultMinStock => _prefs?.getInt(_kDefaultMinStock) ?? 5;
  String get cashier => _prefs?.getString(_kCashier) ?? 'May';
  String get storeName => _prefs?.getString(_kStoreName) ?? 'Sari-Sari Store';
  String get terminal => _prefs?.getString(_kTerminal) ?? 'Terminal 1';
  double get openingFloat => _prefs?.getDouble(_kOpeningFloat) ?? 1000;

  /// How far a customer's tab can run before checkout warns, unless the
  /// customer has a limit of their own. Zero means no limit.
  double get creditLimit => _prefs?.getDouble(_kCreditLimit) ?? 500;

  Future<void> setCreditLimit(double v) async {
    await _prefs?.setDouble(_kCreditLimit, v < 0 ? 0 : v);
    notifyListeners();
  }
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

  /// Puts back a type removed a moment ago — Undo — in the place it had
  /// among the added ones, and switched on or off as it was. Adding it again
  /// would put it last, and switched on.
  Future<void> restorePaymentType(PaymentType type, {required int at, required bool enabled}) async {
    if (type.builtIn) return;
    final custom = [...?_prefs?.getStringList(_kCustomPayments)];
    if (custom.contains(type.name)) return;
    custom.insert(at.clamp(0, custom.length), type.name);
    await _prefs?.setStringList(_kCustomPayments, custom);
    await setPaymentTypeEnabled(type, enabled);
  }

  /// Whether [name] is taken by a type already in the list, ignoring case.
  bool hasPaymentType(String name) =>
      allPaymentTypes.any((t) => t.name.toLowerCase() == name.trim().toLowerCase());

  Future<void> setPrintReceipt(bool v) => _setBool(_kPrintReceipt, v);
  Future<void> setScanSound(bool v) => _setBool(_kScanSound, v);
  Future<void> setLowStockAlerts(bool v) => _setBool(_kLowStockAlerts, v);
  Future<void> setAutoBackup(bool v) => _setBool(_kAutoBackup, v);

  /// Whether the Products screen shows cards (true) or the denser list.
  /// List is the default: on an inventory screen the stock figure matters
  /// more than the photo.
  bool get productsGridView => _prefs?.getBool(_kProductsGrid) ?? false;
  Future<void> setProductsGridView(bool v) => _setBool(_kProductsGrid, v);

  /// The language the app is shown in. English until the shopkeeper picks.
  AppLanguage get language => AppLanguage.byName(_prefs?.getString(_kLanguage));
  Future<void> setLanguage(AppLanguage v) async {
    await _prefs?.setString(_kLanguage, v.name);
    notifyListeners();
  }

  Future<void> setDefaultMinStock(int v) async {
    await _prefs?.setInt(_kDefaultMinStock, v);
    notifyListeners();
  }

  /// Renames the store. Blank is ignored rather than saved: the name goes on
  /// every receipt, and an empty header reads as a printer fault.
  Future<void> setStoreName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _prefs?.setString(_kStoreName, trimmed);
    notifyListeners();
  }

  /// Whether the first-run setup has been finished — or was never needed,
  /// because the store already had data when this flag was introduced.
  bool get setupDone => _prefs?.getBool(_kSetupDone) ?? false;
  Future<void> markSetupDone() => _setBool(_kSetupDone, true);

  /// When the error log was last opened, so the bell on Home only lights
  /// for errors nobody has looked at yet.
  DateTime? get errorsSeenAt =>
      DateTime.tryParse(_prefs?.getString(_kErrorsSeen) ?? '');
  Future<void> markErrorsSeen() async {
    await _prefs?.setString(_kErrorsSeen, DateTime.now().toIso8601String());
    notifyListeners();
  }

  Future<void> setCashier(String name) async {
    await _prefs?.setString(_kCashier, name);
    // Signing someone in is what ends a sign-out.
    await _prefs?.remove(_kSignedOut);
    notifyListeners();
  }

  /// True after Sign out, until someone signs in with their code. Kept across
  /// a restart: otherwise closing and reopening the app would be a way past
  /// the lock, straight back in as whoever was last signed in.
  bool get signedOut => _prefs?.getBool(_kSignedOut) ?? false;
  Future<void> signOut() => _setBool(_kSignedOut, true);

  Future<void> setOpeningFloat(double v) async {
    await _prefs?.setDouble(_kOpeningFloat, v);
    notifyListeners();
  }

  Future<void> markBackedUp() async {
    await _prefs?.setString(_kLastBackup, DateTime.now().toIso8601String());
    notifyListeners();
  }

  /// The settings that describe the store rather than this phone, for the
  /// backup to carry.
  ///
  /// Effective values, defaults included, so a restore reproduces the store as
  /// it was instead of keeping whatever the new phone happened to have.
  ///
  /// Left out on purpose: the printer (a Bluetooth pairing belongs to one
  /// handset), the signed-in cashier (a session, and staff are not in a
  /// backup), the last-backup stamp (restoring is not backing up), and the
  /// grid-or-list view (a matter of screen size).
  Map<String, Object> exportSettings() => {
        _kStoreName: storeName,
        _kTerminal: terminal,
        _kOpeningFloat: openingFloat,
        _kCreditLimit: creditLimit,
        _kDefaultMinStock: defaultMinStock,
        _kPrintReceipt: printReceipt,
        _kScanSound: scanSound,
        _kLowStockAlerts: lowStockAlerts,
        _kAutoBackup: autoBackup,
        _kDisabledPayments: [...?_prefs?.getStringList(_kDisabledPayments)],
        _kCustomPayments: [...?_prefs?.getStringList(_kCustomPayments)],
        _kPaperWidth: paperWidth.name,
        _kLanguage: language.name,
      };

  /// Applies settings read from a backup. Returns how many were applied.
  ///
  /// The file came off a share sheet and may have been through anyone's hands,
  /// so each value is checked against the type its key expects: a wrong type
  /// or an unknown key is skipped rather than written, and a key the backup
  /// does not mention keeps its current value.
  Future<int> importSettings(Map<String, Object?> values) async {
    final prefs = _prefs;
    if (prefs == null) return 0;

    var applied = 0;
    for (final MapEntry(:key, :value) in values.entries) {
      final ok = switch ((key, value)) {
        (_kStoreName || _kTerminal || _kPaperWidth || _kLanguage, String v) =>
          await prefs.setString(key, v),
        (_kPrintReceipt || _kScanSound || _kLowStockAlerts || _kAutoBackup,
            bool v) =>
          await prefs.setBool(key, v),
        (_kDefaultMinStock, int v) => await prefs.setInt(key, v),
        // JSON has one number type: a float of 1000 may come back as an int.
        (_kOpeningFloat || _kCreditLimit, num v) => await prefs.setDouble(key, v.toDouble()),
        (_kDisabledPayments || _kCustomPayments, List v)
            when v.every((e) => e is String) =>
          await prefs.setStringList(key, v.cast<String>()),
        _ => false,
      };
      if (ok) applied++;
    }
    if (applied > 0) notifyListeners();
    return applied;
  }

  Future<void> _setBool(String key, bool v) async {
    await _prefs?.setBool(key, v);
    notifyListeners();
  }
}
