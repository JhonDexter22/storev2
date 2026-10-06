import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/product_model.dart';
import '../models/sale_model.dart';
import '../models/backup_status.dart';
import '../services/backup_share.dart';
import '../services/export_service.dart';
import '../services/product_service.dart';
import '../services/sales_service.dart';
import '../services/settings_service.dart';
import '../widgets/add_stock_sheet.dart';
import '../widgets/initials_avatar.dart';
import '../widgets/product_thumb.dart';
import '../widgets/sales_chart.dart';
import '../widgets/sale_detail_sheet.dart';
import '../widgets/sale_row.dart';
import '../widgets/skeleton.dart';
import '../services/shift_service.dart';
import '../services/stock_alerts.dart';
import 'cash_count_screen.dart';
import 'sales_list_screen.dart';
import '../l10n/tr.dart';
import '../services/error_log.dart';
import '../models/customer.dart';
import '../models/staff.dart';
import '../models/store_alerts.dart';
import '../services/utang_service.dart';
import 'cashier_switch_screen.dart';
import 'error_log_screen.dart';
import 'restock_screen.dart';
import 'utang_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.onStartSale,
    this.onOpenProducts,
    this.onOpenRestock,
    this.productService,
    this.salesService,
    this.shiftService,
    this.utangService,
  });

  final VoidCallback? onStartSale;

  /// Tab jumps for the Inventory and Stock alerts tiles. Null when the
  /// dashboard is shown outside the tab shell.
  final VoidCallback? onOpenProducts;
  final VoidCallback? onOpenRestock;

  /// Injectable so tests can drive the failure path; production passes neither.
  final ProductService? productService;
  final SalesService? salesService;
  final ShiftService? shiftService;
  final UtangService? utangService;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

enum _Period { today, week, month }

class _DashboardScreenState extends State<DashboardScreen> {
  late final ProductService _productService = widget.productService ?? ProductService();
  late final SalesService _salesService = widget.salesService ?? SalesService();

  _Period _period = _Period.today;
  bool _loading = true;

  /// Set when a load fails. Holds a short code and the time it happened, so a
  /// shopkeeper can quote something specific when asking for help.
  ({String code, DateTime at})? _error;

  List<Product> _products = [];
  List<Sale> _recentSales = [];
  PeriodStats? _stats;
  List<double> _chartDays = [];

  /// True while the reminder's own backup is being written and shared.
  bool _backingUp = false;

  /// Sales since the last close — what a Close day would sum up.
  ({double total, int count, DateTime openedAt})? _openShift;

  /// The figure Cash count calls "Expected in drawer", from the same place
  /// ([ShiftService.drawerNow]). Null until loaded.
  double? _expectedInDrawer;

  /// Everyone with a balance, for the "Owed to you" tile.
  ({int count, double amount}) _owed = (count: 0, amount: 0.0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _periodDays => switch (_period) {
        _Period.today => 1,
        _Period.week => 7,
        _Period.month => 30,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await _productService.getAllProducts();
      final recent = await _salesService.getRecentSales(limit: 5);
      final stats = await _salesService.getPeriodStats(_periodDays);
      final chart = await _salesService.getPeriodStats(7);
      if (!mounted) return;
      setState(() {
        _products = products;
        _recentSales = recent;
        _stats = stats;
        _chartDays = chart.dailyRevenue;
        _loading = false;
      });
      _loadOpenShift();
      _loadOverdue();
      _loadDrawer();
    } catch (e, st) {
      // Without this the spinner would run forever on a read failure.
      ErrorLog.caught(e, st, 'Home: loading (${_errorCode(e)})');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = (code: _errorCode(e), at: DateTime.now());
      });
    }
  }

  /// Reloads everything without dropping to the skeleton — for changes made
  /// from this screen, where a flash of placeholders would be jarring.
  Future<void> _refresh() async {
    try {
      final products = await _productService.getAllProducts();
      final recent = await _salesService.getRecentSales(limit: 5);
      final stats = await _salesService.getPeriodStats(_periodDays);
      final chart = await _salesService.getPeriodStats(7);
      if (!mounted) return;
      setState(() {
        _products = products;
        _recentSales = recent;
        _stats = stats;
        _chartDays = chart.dailyRevenue;
      });
      _loadOpenShift();
      _loadOverdue();
      _loadDrawer();
      // Stock added from Home changes the nav badges too.
      StockAlerts.instance.refresh();
    } catch (e, st) {
      ErrorLog.caught(e, st, 'Home: refreshing (${_errorCode(e)})');
      if (!mounted) return;
      setState(() => _error = (code: _errorCode(e), at: DateTime.now()));
    }
  }

  /// The Close day card's figures. Fetched on its own, after the screen has
  /// its data: it is a nicety, and a slow or failed read here must not hold
  /// up or break the dashboard.
  Future<void> _loadOpenShift() async {
    try {
      final shift = await (widget.shiftService ?? ShiftService()).currentShiftSales();
      if (!mounted) return;
      setState(() => _openShift = shift);
    } catch (e, st) {
      // Card simply stays hidden.
      ErrorLog.caught(e, st, 'Home: close-day card');
    }
  }

  Future<void> _loadDrawer() async {
    try {
      final drawer = await (widget.shiftService ??
              ShiftService(sales: _salesService, utang: widget.utangService))
          .drawerNow();
      if (!mounted) return;
      setState(() => _expectedInDrawer = drawer.expected);
    } catch (e, st) {
      // The tile shows a dash rather than a wrong figure.
      ErrorLog.caught(e, st, 'Home: drawer tile');
    }
  }

  /// Customers whose current balance is past the overdue line, for the bell.
  ({int count, double amount}) _overdue = (count: 0, amount: 0.0);

  /// Fetched after the screen has its data, like the Close day card: it walks
  /// every customer's ledger, and the bell can wait a moment for it.
  Future<void> _loadOverdue() async {
    try {
      final customers = await (widget.utangService ?? UtangService()).getCustomers();
      final overdue = customers.where((c) => c.status == UtangStatus.overdue).toList();
      final owing = customers.where((c) => c.balance > 0).toList();
      if (!mounted) return;
      setState(() {
        _overdue = (
          count: overdue.length,
          amount: overdue.fold(0.0, (s, c) => s + c.balance),
        );
        _owed = (
          count: owing.length,
          amount: owing.fold(0.0, (s, c) => s + c.balance),
        );
      });
    } catch (e, st) {
      ErrorLog.caught(e, st, 'Home: utang alerts');
    }
  }

  StoreAlerts get _alerts {
    final settings = SettingsService.instance;
    final raw = settings.lastBackup;
    return StoreAlerts.from(
      products: _products,
      overdueUtang: _overdue,
      backup: BackupStatus.from(raw == null ? null : DateTime.tryParse(raw)),
      remindBackup: settings.autoBackup,
      storeHasData: _products.isNotEmpty || _recentSales.isNotEmpty,
      lowStockAlerts: settings.lowStockAlerts,
      newErrors: ErrorLog.instance.newerThan(settings.errorsSeenAt),
    );
  }

  void _openRestock() {
    final jump = widget.onOpenRestock;
    if (jump != null) {
      jump();
    } else {
      _push(const RestockScreen());
    }
  }

  /// Everything the bell knows about, each row opening where it is fixed.
  Future<void> _showAlerts() async {
    final alerts = _alerts;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) {
        void go(VoidCallback action) {
          Navigator.pop(sheet);
          action();
        }

        Widget row(StoreAlert a) {
          final since = ExportService.sinceLastBackup(SettingsService.instance.lastBackup);
          final (IconData icon, Color fg, Color bg, String title, String detail, VoidCallback action) =
              switch (a.kind) {
            AlertKind.outOfStock => (
                Icons.remove_shopping_cart_outlined,
                AppColors.dangerText,
                AppColors.dangerFill,
                trCount(a.count, '{n} product out of stock', '{n} products out of stock'),
                tr('Restock before a customer asks for it'),
                _openRestock,
              ),
            AlertKind.lowStock => (
                Icons.trending_down_rounded,
                AppColors.warningText,
                AppColors.warningFill,
                trCount(a.count, '{n} product running low', '{n} products running low'),
                tr('At or under their minimum'),
                _openRestock,
              ),
            AlertKind.overdueUtang => (
                Icons.account_balance_wallet_outlined,
                AppColors.dangerText,
                AppColors.dangerFill,
                trCount(a.count, '{n} customer overdue', '{n} customers overdue'),
                tr('{amount} unpaid for {days} days or more',
                    {'amount': formatPeso(a.amount), 'days': Customer.overdueAfterDays}),
                () => _push(UtangScreen(onCharge: widget.onStartSale, overdueOnly: true)),
              ),
            AlertKind.backupDue => (
                Icons.backup_outlined,
                AppColors.warningText,
                AppColors.warningFill,
                tr('Back up your store'),
                since == null
                    ? tr('You have never exported a backup.')
                    : tr('Your last backup was {n} days ago.', {'n': since.inDays}),
                _backUpNow,
              ),
            AlertKind.newErrors => (
                Icons.error_outline_rounded,
                AppColors.dangerText,
                AppColors.dangerFill,
                trCount(a.count, '{n} new error recorded', '{n} new errors recorded'),
                tr('Open the error log to see what happened'),
                () => _push(const ErrorLogScreen()),
              ),
          };
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => go(action),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
                      child: Icon(icon, color: fg, size: 19),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppText.cardTitle()),
                          const SizedBox(height: 2),
                          Text(detail, style: AppText.caption()),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.faint, size: 20),
                  ],
                ),
              ),
            ),
          );
        }

        return Container(
          padding: EdgeInsets.fromLTRB(
              AppSpace.sheetPad, 14, AppSpace.sheetPad, 20 + MediaQuery.of(sheet).padding.bottom),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.hairline, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('Alerts'), style: AppText.sectionTitle().copyWith(fontSize: 18)),
              const SizedBox(height: 6),
              if (alerts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded,
                          color: AppColors.success, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tr('All caught up — nothing needs you right now.'),
                            style: AppText.body()),
                      ),
                    ],
                  ),
                )
              else
                for (final a in alerts.items) row(a),
            ],
          ),
        );
      },
    );
  }

  /// A short, stable-ish code derived from the failure, for the error tile.
  static String _errorCode(Object e) {
    final hash = e.runtimeType.toString().hashCode & 0xFFFF;
    return 'DASH-${hash.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  Future<void> _setPeriod(_Period p) async {
    setState(() => _period = p);
    try {
      final stats = await _salesService.getPeriodStats(_periodDays);
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (e, st) {
      ErrorLog.caught(e, st, 'Home: changing period (${_errorCode(e)})');
      if (!mounted) return;
      setState(() => _error = (code: _errorCode(e), at: DateTime.now()));
    }
  }

  /// Everything at or under its minimum, in Restock's order.
  List<Product> get _allNeedingAttention =>
      _products.where((p) => p.stock <= p.minStock).toList()..sort(byRestockUrgency);

  /// The first five; "See all" opens Restock for the rest.
  List<Product> get _needsAttention => _allNeedingAttention.take(5).toList();

  Widget _attentionHeading() {
    final total = _allNeedingAttention.length;
    return Row(
      children: [
        Expanded(child: _sectionTitle(tr('Needs attention'))),
        if (total > _needsAttention.length)
          GestureDetector(
            onTap: _openRestock,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('See all {n}', {'n': total}), style: AppText.chip(color: AppColors.primary)),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Retail value of what is on the shelves, as the Products header gives it.
  double get _inventoryValue => _products.fold(0.0, (s, p) => s + p.price * p.stock);

  int get _lowCount => _products.where((p) => p.stock > 0 && p.stock <= p.minStock).length;
  int get _outCount => _products.where((p) => p.stock <= 0).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? _loadingSkeleton()
            : _error != null
                ? _errorState(_error!)
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _refresh,
                    child: Breakpoints.isTablet(context)
                        ? _tabletBody()
                        : _phoneBody(),
                  ),
      ),
    );
  }

  Widget _phoneBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 16, AppSpace.screenH, 32),
      children: [
        _greetingHeader(),
        if (_backupIsStale) ...[
          const SizedBox(height: AppSpace.gapSection),
          _backupNudge(),
        ],
        const SizedBox(height: AppSpace.gapBlock),
        _periodChips(),
        const SizedBox(height: AppSpace.gapSection),
        _salesCard(),
        // Under the day's figures it closes, rather than below everything:
        // it was the last thing on the screen, under five sales and a
        // "Start a new sale" card that only repeated the Sell button in the
        // bar — which is why that card is gone from the phone.
        if (_openShift != null && _openShift!.count > 0) ...[
          const SizedBox(height: AppSpace.gapGrid),
          _closeDayCard(),
        ],
        const SizedBox(height: AppSpace.gapBlock),
        _statGrid(),
        const SizedBox(height: AppSpace.gapBlock),
        if (_needsAttention.isNotEmpty) ...[
          _attentionHeading(),
          const SizedBox(height: 10),
          _attentionList(),
          const SizedBox(height: AppSpace.gapBlock),
        ],
        // An empty list would only repeat what the sales card already says.
        if (_recentSales.isNotEmpty) ...[
          _recentHeading(),
          const SizedBox(height: 10),
          // Three on the phone, where five full rows were most of a screen.
          _recentSalesList(limit: 3),
        ],
      ],
    );
  }

  /// Tablet: the hero sales card keeps the left column, and the four figures
  /// that were a 2x2 grid on the phone stack beside it under the CTA. Below,
  /// the two lists sit side by side, so what needs restocking and what just
  /// sold are both visible without scrolling.
  Widget _tabletBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        _greetingHeader(),
        if (_backupIsStale) ...[
          const SizedBox(height: AppSpace.gapSection),
          _backupNudge(),
        ],
        const SizedBox(height: AppSpace.gapSection),
        _periodChips(),
        const SizedBox(height: AppSpace.gapSection),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _salesCard(showAction: false)),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _startSaleCard(),
                  if (_openShift != null && _openShift!.count > 0) ...[
                    const SizedBox(height: AppSpace.gapGrid),
                    _closeDayCard(),
                  ],
                  const SizedBox(height: AppSpace.gapGrid),
                  _statRow([_drawerCard(), _owedCard()]),
                  const SizedBox(height: AppSpace.gapGrid),
                  _statRow([_inventoryCard(), _stockAlertsCard()]),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.gapBlock),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _attentionHeading(),
                  const SizedBox(height: 10),
                  if (_needsAttention.isEmpty) _nothingToRestockCard() else _attentionList(),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _recentHeading(),
                  const SizedBox(height: 10),
                  _recentSalesList(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// The stat cards space their icon, figure and label apart, which needs a
  /// bounded height — the phone grid supplies one through its aspect ratio.
  /// [IntrinsicHeight] gives the pair the height of the taller card instead of
  /// a hardcoded one, so a longer figure cannot clip.
  Widget _statRow(List<Widget> cards) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: cards[0]),
          const SizedBox(width: AppSpace.gapGrid),
          Expanded(child: cards[1]),
        ],
      ),
    );
  }

  /// The phone drops the whole "Needs attention" block when nothing is low.
  /// The tablet keeps the column so the two lists stay aligned, so it needs
  /// something to say instead.
  Widget _nothingToRestockCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
          _products.isEmpty ? tr('No products yet') : tr('Everything is stocked'),
          style: AppText.body()),
    );
  }

  /// Mirrors the real layout block for block — hero card, 2x2 stats, list
  /// rows — so nothing jumps when the data lands.
  Widget _loadingSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 16, AppSpace.screenH, 32),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 96, height: 11),
                  SizedBox(height: 8),
                  SkeletonBox(width: 178, height: 22, emphasis: true),
                ],
              ),
            ),
            const SkeletonBox(width: 40, height: 40, radius: 12),
            const SizedBox(width: 10),
            const SkeletonBox(width: 40, height: 40, radius: 999),
          ],
        ),
        const SizedBox(height: AppSpace.gapBlock),
        Row(
          children: const [
            SkeletonBox(width: 78, height: 34, radius: 999),
            SizedBox(width: AppSpace.gapChip),
            SkeletonBox(width: 84, height: 34, radius: 999),
            SizedBox(width: AppSpace.gapChip),
            SkeletonBox(width: 92, height: 34, radius: 999),
          ],
        ),
        const SizedBox(height: AppSpace.gapSection),

        // Hero card: overline, figure, the seven bars, footer stats.
        SkeletonCard(
          radius: AppRadius.hero,
          padding: const EdgeInsets.all(AppSpace.sheetPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 74, height: 10),
              const SizedBox(height: 10),
              const SkeletonBox(width: 190, height: 30, emphasis: true),
              const SizedBox(height: 20),
              SizedBox(
                height: 96,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (i) {
                    const heights = [26.0, 40.0, 18.0, 52.0, 33.0, 46.0, 60.0];
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SkeletonBox(height: heights[i], radius: 4),
                            const SizedBox(height: 6),
                            const SkeletonBox(width: 10, height: 9),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 12),
              Row(
                children: List.generate(
                  3,
                  (_) => Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SkeletonBox(width: 54, height: 13),
                        SizedBox(height: 5),
                        SkeletonBox(width: 68, height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.gapBlock),

        // 2x2 stat cards.
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpace.gapGrid,
          crossAxisSpacing: AppSpace.gapGrid,
          childAspectRatio: 1.7,
          children: List.generate(
            4,
            (_) => SkeletonCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  SkeletonBox(width: 18, height: 18, radius: 5),
                  SkeletonBox(width: 62, height: 20, emphasis: true),
                  SkeletonBox(width: 78, height: 10),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.gapBlock),

        const SkeletonBox(width: 128, height: 14),
        const SizedBox(height: 12),
        SkeletonCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: List.generate(3, (i) {
              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(
                      children: [
                        SkeletonBox(width: 40, height: 40, radius: 10),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox(width: 130, height: 12),
                              SizedBox(height: 6),
                              SkeletonBox(width: 88, height: 10),
                            ],
                          ),
                        ),
                        SkeletonBox(width: 62, height: 12),
                      ],
                    ),
                  ),
                  if (i != 2) const Divider(color: AppColors.divider, height: 1),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _errorState(({String code, DateTime at}) error) {
    final t = TimeOfDay.fromDateTime(error.at).format(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.dangerFill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.error_outline_rounded,
                  color: AppColors.danger, size: 30),
            ),
            const SizedBox(height: 16),
            Text(tr("Could not load today's sales"),
                textAlign: TextAlign.center,
                style: AppText.sectionTitle().copyWith(fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              tr('Nothing was lost — your products and sales are still saved on this device.'),
              textAlign: TextAlign.center,
              style: AppText.body(),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Text('${error.code} · $t', style: AppText.mono()),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _load,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                child: Text(tr('Try again'),
                    style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: widget.onStartSale,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.body,
                  side: const BorderSide(color: AppColors.hairline),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                child: Text(tr('Continue to POS'),
                    style: AppText.chip(color: AppColors.body).copyWith(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// True when reminders are on and the last export is a week old or more —
  /// or never happened.
  ///
  /// The same line the till header's pill draws, so Home and Sell never
  /// disagree about whether a backup is due. A store with nothing in it yet
  /// has nothing to lose, and is not nagged on its first morning.
  bool get _backupIsStale {
    final settings = SettingsService.instance;
    if (!settings.autoBackup) return false;
    if (_products.isEmpty && _recentSales.isEmpty) return false;
    final raw = settings.lastBackup;
    final status = BackupStatus.from(raw == null ? null : DateTime.tryParse(raw));
    return status.level != BackupLevel.fresh;
  }

  /// Backs up from the reminder itself rather than sending the shopkeeper to
  /// find the button in Settings — the tap that reads the warning is the one
  /// that should fix it.
  Future<void> _backUpNow() async {
    if (_backingUp) return;
    setState(() => _backingUp = true);
    String message;
    try {
      final file = await shareBackup();
      message = file == null
          ? tr('Backup cancelled — nothing was sent')
          : tr('Backed up to {file}', {'file': file});
    } catch (e, st) {
      ErrorLog.caught(e, st, 'backup from Home');
      message = tr('Could not export: {error}', {'error': e});
    }
    if (!mounted) return;
    setState(() => _backingUp = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// The whole store lives in one file on this phone. This is the only thing
  /// in the app that says so.
  Widget _backupNudge() {
    final since = ExportService.sinceLastBackup(SettingsService.instance.lastBackup);
    final how = since == null
        ? tr('You have never exported a backup.')
        : tr('Your last backup was {n} days ago.', {'n': since.inDays});
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _backingUp ? null : _backUpNow,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warningFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warningBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.backup_outlined, size: 17, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_backingUp ? tr('Backing up…') : tr('Back up your store'),
                        style: AppText.cardTitle(color: AppColors.warningText)
                            .copyWith(fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('$how ${tr('Everything is on this phone only.')}',
                        style: AppText.caption(color: AppColors.warningText)),
                  ],
                ),
              ),
              Text(tr('Back up now'),
                  style: AppText.chip(color: AppColors.warningText)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _greetingHeader() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? tr('Good morning') : (hour < 18 ? tr('Good afternoon') : tr('Good evening'));
    return Row(
      children: [
        Expanded(
          // The store's own name and whoever is at the till, where a fixed
          // "Store Overview" said the same thing in every shop.
          child: ListenableBuilder(
            listenable: SettingsService.instance,
            builder: (context, _) {
              final cashier = SettingsService.instance.cashier.trim();
              final store = SettingsService.instance.storeName.trim();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cashier.isEmpty ? greeting : '$greeting, $cashier',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption()),
                  const SizedBox(height: 2),
                  Text(store.isEmpty ? tr('Store Overview') : store,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.screenTitle()),
                ],
              );
            },
          ),
        ),
        // Both were pictures from the mockup: a bell with its red dot painted
        // on for good, and a hard-coded "M" for the demo cashier. They now
        // say what is true, and each opens the thing it stands for.
        ListenableBuilder(
          listenable: Listenable.merge([SettingsService.instance, ErrorLog.instance]),
          builder: (context, _) {
            final urgent = _alerts.hasUrgent;
            final cashier = SettingsService.instance.cashier;
            return Row(
              children: [
                Semantics(
                  button: true,
                  label: urgent ? tr('Alerts, something needs attention') : tr('Alerts'),
                  child: GestureDetector(
                    onTap: _showAlerts,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.hairline),
                          ),
                          child: const Icon(Icons.notifications_outlined,
                              color: AppColors.body, size: 19),
                        ),
                        if (urgent)
                          Positioned(
                            top: 9,
                            right: 9,
                            child: Container(
                              key: const ValueKey('alert-dot'),
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                  color: AppColors.danger, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Semantics(
                  button: true,
                  label: tr('Signed in: {name}', {'name': cashier}),
                  child: GestureDetector(
                    onTap: () => _push(const CashierSwitchScreen()),
                    child: InitialsAvatar(Staff.initialsOf(cashier), size: 40),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _periodChips() {
    Widget chip(_Period p, String label) {
      final selected = _period == p;
      return GestureDetector(
        onTap: () => _setPeriod(p),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: selected ? AppColors.ink : AppColors.hairline),
          ),
          child: Text(label, style: AppText.chip(color: selected ? Colors.white : AppColors.body)),
        ),
      );
    }

    // Scrolls rather than clips: Filipino labels run longer than English,
    // and on a narrow phone the last chip would otherwise be cut off.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(_Period.today, tr('Today')),
          const SizedBox(width: AppSpace.gapChip),
          chip(_Period.week, tr('7 days')),
          const SizedBox(width: AppSpace.gapChip),
          chip(_Period.month, tr('30 days')),
        ],
      ),
    );
  }

  /// [showAction] is off on the tablet, where the Start a new sale card
  /// already sits beside it.
  Widget _salesCard({bool showAction = true}) {
    final stats = _stats!;
    // With no sales in the period, a ₱0.00 hero and a flat chart say nothing.
    // The rest of the dashboard (inventory, alerts) stays useful, so only this
    // card becomes an empty state.
    if (stats.transactions == 0) return _noSalesCard(showAction: showAction);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.sheetPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.hero),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // "Last 7 days", not "this week": the chips count back from
              // today, and a calendar week is a different number.
              Expanded(
                child: Text(switch (_period) {
                  _Period.today => tr('SALES TODAY'),
                  _Period.week => tr('SALES · LAST 7 DAYS'),
                  _Period.month => tr('SALES · LAST 30 DAYS'),
                },
                    style: AppText.overline()),
              ),
              PeriodComparison(stats: stats, days: _periodDays),
            ],
          ),
          const SizedBox(height: 6),
          Text(formatPeso(stats.revenue), style: AppText.heroFigure()),
          const SizedBox(height: 18),
          _barChart(),
          const SizedBox(height: 8),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              // The way to the list of sales, now the Transactions tile is gone.
              _footerStat(tr('Transactions'), '${stats.transactions}',
                  onTap: () => _push(SalesListScreen(days: _periodDays))),
              _footerStat(tr('Avg sale'), formatPeso(stats.avgSale)),
              _footerStat(tr('Items'), '${stats.itemsSold}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noSalesCard({required bool showAction}) {
    final label = switch (_period) {
      _Period.today => tr('No sales yet today'),
      _Period.week => tr('No sales in the last 7 days'),
      _Period.month => tr('No sales in the last 30 days'),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.sheetPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.hero),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.receipt_long_outlined, color: AppColors.muted, size: 26),
          ),
          const SizedBox(height: 14),
          Text(label, style: AppText.sectionTitle().copyWith(fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            tr('Sales you ring up will show here, with the total and a breakdown of the week.'),
            textAlign: TextAlign.center,
            style: AppText.caption(),
          ),
          // Outlined, not filled: the Sell button in the tab bar is the
          // primary way in, and two solid blue buttons competed for it.
          if (showAction) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: widget.onStartSale,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(tr('Start a sale'),
                    style: AppText.chip(color: AppColors.primary).copyWith(fontSize: 14)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _footerStat(String label, String value, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: Text(value, style: AppText.cardTitle())),
                if (onTap != null)
                  const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.muted),
              ],
            ),
            const SizedBox(height: 2),
            Text(label, style: AppText.caption()),
          ],
        ),
      ),
    );
  }

  /// Under "30 days", the chart is the 30 days; under "Today" and "7 days",
  /// the last week — labelled as such under Today, where it is context
  /// rather than the period itself. It was always 7 days, even beneath
  /// "SALES THIS MONTH".
  List<double> get _chartBars =>
      _period == _Period.month ? (_stats?.dailyRevenue ?? const []) : _chartDays;

  Widget _barChart() => SalesBarChart(
        values: _chartBars,
        caption: _period == _Period.today ? tr('Last 7 days') : null,
      );

  Widget _drawerCard() => _statCard(
        tr('Expected in drawer'),
        _expectedInDrawer == null ? '—' : formatPeso(_expectedInDrawer!),
        Icons.payments_outlined,
        AppColors.primary,
        onTap: () => _push(const CashCountScreen()),
      );

  Widget _owedCard() => _statCard(
        tr('Owed to you'),
        formatPeso(_owed.amount),
        Icons.receipt_long_outlined,
        _owed.amount > 0 ? AppColors.warning : AppColors.body,
        onTap: () => _push(UtangScreen(onCharge: widget.onStartSale)),
      );

  /// Pesos, not units: "10,775 units" told an owner nothing to act on.
  Widget _inventoryCard() => _statCard(
        tr('Inventory'),
        formatPeso(_inventoryValue),
        Icons.inventory_2_outlined,
        AppColors.body,
        onTap: widget.onOpenProducts,
      );

  Widget _statGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpace.gapGrid,
      crossAxisSpacing: AppSpace.gapGrid,
      childAspectRatio: 1.7,
      // Transactions and items sold were here too, a few pixels under the
      // sales card's own footer. These are what Home did not show at all.
      children: [
        _drawerCard(),
        _owedCard(),
        _inventoryCard(),
        _stockAlertsCard(),
      ],
    );
  }

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    // A return recorded from a receipt, or stock changed in Products,
    // changes the figures on this screen.
    if (mounted) _refresh();
  }

  /// A figure that opens the thing it counts. The arrow in the corner is
  /// the only hint it is a button; the whole tile is the target.
  Widget _statCard(String label, String value, IconData icon, Color color,
      {VoidCallback? onTap, Widget? figure, Color? tint, Color? border}) {
    return Material(
      color: tint ?? AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.cardPad),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: border ?? AppColors.hairline),
          ),
          // The tile's height is fixed by the grid, so the figure and label are
          // loose-flexible: at ordinary text sizes nothing changes, and when the
          // reader has scaled text up they shrink rather than clip.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const Spacer(),
                  if (onTap != null)
                    const Icon(Icons.arrow_outward_rounded, size: 16, color: AppColors.muted),
                ],
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: figure ?? Text(value, style: AppText.statFigure()),
                ),
              ),
              Flexible(
                child: Text(label,
                    style: AppText.caption(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Calm when there is nothing to do; coloured, and a shortcut to Restock,
  /// only once a number is above zero. Orange zeros read as a warning about
  /// nothing.
  Widget _stockAlertsCard() {
    // With no products, "All stocked" beside "0 units" contradicts itself.
    if (_products.isEmpty) {
      return _statCard(
        tr('Stock alerts'),
        tr('No products yet'),
        Icons.inventory_2_outlined,
        AppColors.muted,
        onTap: widget.onOpenProducts,
        figure: Text(tr('No products yet'), style: AppText.statFigure(color: AppColors.muted, size: 18)),
      );
    }
    final calm = _lowCount == 0 && _outCount == 0;
    if (calm) {
      return _statCard(
        tr('Stock alerts'),
        tr('All stocked'),
        Icons.check_circle_outline_rounded,
        AppColors.success,
        onTap: widget.onOpenRestock,
        figure: Text(tr('All stocked'), style: AppText.statFigure(color: AppColors.successText, size: 20)),
      );
    }
    final critical = _outCount > 0;
    return _statCard(
      tr('Stock alerts'),
      '',
      Icons.warning_amber_rounded,
      critical ? AppColors.danger : AppColors.warning,
      onTap: widget.onOpenRestock,
      tint: critical ? AppColors.dangerFill : AppColors.warningFill,
      border: critical ? AppColors.dangerBorder : AppColors.warningBorder,
      figure: Row(
        children: [
          if (_outCount > 0) ...[
            Text('$_outCount', style: AppText.statFigure(color: AppColors.dangerText, size: 20)),
            Text(tr(' out'), style: AppText.caption(color: AppColors.dangerText)),
          ],
          if (_outCount > 0 && _lowCount > 0) const SizedBox(width: 8),
          if (_lowCount > 0) ...[
            Text('$_lowCount', style: AppText.statFigure(color: AppColors.warningText, size: 20)),
            Text(tr(' low'), style: AppText.caption(color: AppColors.warningText)),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text, style: AppText.sectionTitle());

  Widget _attentionList() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < _needsAttention.length; i++) ...[
            _attentionRow(_needsAttention[i]),
            if (i != _needsAttention.length - 1) const Divider(color: AppColors.divider, height: 1),
          ],
        ],
      ),
    );
  }

  /// A product that needs restocking, with the fix on the row: "+ Stock"
  /// opens the same sheet Products uses, so a shortage seen on Home is
  /// dealt with on Home.
  Widget _attentionRow(Product p) {
    final tone = StockStatus.text(p.stock, p.minStock);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        children: [
          ProductThumb(product: p, size: 40, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: AppText.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: StockStatus.dot(p.stock, p.minStock),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        p.stock <= 0
                            ? tr('Out of stock · min {min}', {'min': p.minStock})
                            : tr('{n} left · min {min}', {'n': p.stock, 'min': p.minStock}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption(color: tone),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: tr('Add stock'),
            child: Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                onTap: () => _addStock(p),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(9, 8, 11, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 2),
                      Text(tr('Stock'),
                          style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addStock(Product p) async {
    // The same suggestion Restock offers for the same product.
    final added = await showAddStockSheet(context, p, suggested: suggestedRestock(p));
    if (added == null || !mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(tr('Added {n} · {name} now {after}', {'n': added, 'name': p.name, 'after': p.stock + added})),
        action: undoAddedStock(p.id!, added, onUndone: _refresh),
      ));
  }

  /// "See all" goes to the month's sales: the recent ones can be from any
  /// day, so the chips' period would sometimes open on an empty list.
  Widget _recentHeading() {
    return Row(
      children: [
        Expanded(child: _sectionTitle(tr('Recent sales'))),
        GestureDetector(
          onTap: () => _push(const SalesListScreen(days: 30)),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('See all'), style: AppText.chip(color: AppColors.primary)),
                const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _recentSalesList({int? limit}) {
    final sales = limit == null ? _recentSales : _recentSales.take(limit).toList();
    if (sales.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Text(tr('No sales yet'), style: AppText.body()),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < sales.length; i++) ...[
            _saleRow(sales[i]),
            if (i != sales.length - 1) const Divider(color: AppColors.divider, height: 1),
          ],
        ],
      ),
    );
  }

  Widget _saleRow(Sale s) {
    return SaleRow(
      sale: s,
      products: _products,
      onTap: () async {
        final changed = await showSaleDetail(context, s);
        if (changed == true) _load();
      },
    );
  }

  /// The end-of-day door, shown once there is a day to close. Quiet next
  /// to the sale button: it is pressed once, not a hundred times.
  Widget _closeDayCard() {
    final shift = _openShift!;
    final opened = shift.openedAt;
    final now = DateTime.now();
    final clock = TimeOfDay.fromDateTime(opened).format(context);
    // "since 9:00 PM" alone does not say which day, and the last close can
    // be days back.
    final since = opened.year == now.year && opened.month == now.month && opened.day == now.day
        ? clock
        : '${trRelativeDay(opened)}, $clock';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => _push(const CashCountScreen()),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.cardPad),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.nightlight_round, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Close day'), style: AppText.cardTitle()),
                    const SizedBox(height: 2),
                    Text(
                      trCount(shift.count, '{total} · {n} sale since {since}', '{total} · {n} sales since {since}', {'total': formatPeso(shift.total), 'since': since}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.faint, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _startSaleCard() {
    return GestureDetector(
      onTap: widget.onStartSale,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.sheetPad),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.hero),
          boxShadow: AppShadows.primaryCta,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Start a new sale'), style: AppText.cardTitle(color: Colors.white).copyWith(fontSize: 15)),
                  Text(tr('Open the register'), style: AppText.caption(color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}
