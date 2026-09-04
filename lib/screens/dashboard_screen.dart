import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/product_model.dart';
import '../models/sale_model.dart';
import '../services/product_service.dart';
import '../services/sales_service.dart';
import '../widgets/skeleton.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.onStartSale,
    this.productService,
    this.salesService,
  });

  final VoidCallback? onStartSale;

  /// Injectable so tests can drive the failure path; production passes neither.
  final ProductService? productService;
  final SalesService? salesService;

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
    } catch (e) {
      // Without this the spinner would run forever on a read failure.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = (code: _errorCode(e), at: DateTime.now());
      });
    }
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = (code: _errorCode(e), at: DateTime.now()));
    }
  }

  List<Product> get _needsAttention {
    final list = _products.where((p) => p.stock <= p.minStock).toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));
    return list.take(5).toList();
  }

  int get _totalUnits => _products.fold(0, (s, p) => s + p.stock);
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
                    onRefresh: _load,
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
        const SizedBox(height: AppSpace.gapBlock),
        _periodChips(),
        const SizedBox(height: AppSpace.gapSection),
        _salesCard(),
        const SizedBox(height: AppSpace.gapBlock),
        _statGrid(),
        const SizedBox(height: AppSpace.gapBlock),
        if (_needsAttention.isNotEmpty) ...[
          _sectionTitle('Needs attention'),
          const SizedBox(height: 10),
          _attentionList(),
          const SizedBox(height: AppSpace.gapBlock),
        ],
        _sectionTitle('Recent sales'),
        const SizedBox(height: 10),
        _recentSalesList(),
        const SizedBox(height: AppSpace.gapBlock),
        _startSaleCard(),
      ],
    );
  }

  /// Tablet: the hero sales card keeps the left column, and the four figures
  /// that were a 2x2 grid on the phone stack beside it under the CTA. Below,
  /// the two lists sit side by side, so what needs restocking and what just
  /// sold are both visible without scrolling.
  Widget _tabletBody() {
    final stats = _stats!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        _greetingHeader(),
        const SizedBox(height: AppSpace.gapSection),
        _periodChips(),
        const SizedBox(height: AppSpace.gapSection),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _salesCard()),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _startSaleCard(),
                  const SizedBox(height: AppSpace.gapGrid),
                  _statRow([
                    _statCard('Transactions', '${stats.transactions}',
                        Icons.receipt_long_outlined, AppColors.primary),
                    _statCard('Items sold', '${stats.itemsSold}',
                        Icons.shopping_bag_outlined, AppColors.primary),
                  ]),
                  const SizedBox(height: AppSpace.gapGrid),
                  _statRow([
                    _statCard('Inventory', '$_totalUnits units',
                        Icons.inventory_2_outlined, AppColors.body),
                    _stockAlertsCard(),
                  ]),
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
                  _sectionTitle('Needs attention'),
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
                  _sectionTitle('Recent sales'),
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
      child: Text('Everything is stocked', style: AppText.body()),
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
            Text("Could not load today's sales",
                textAlign: TextAlign.center,
                style: AppText.sectionTitle().copyWith(fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              'Nothing was lost — your products and sales are still saved on this device.',
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
                child: Text('Try again',
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
                child: Text('Continue to POS',
                    style: AppText.chip(color: AppColors.body).copyWith(fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _greetingHeader() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 18 ? 'Good afternoon' : 'Good evening');
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting, style: AppText.caption()),
              const SizedBox(height: 2),
              Text('Store Overview', style: AppText.screenTitle()),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.hairline),
              ),
              child: const Icon(Icons.notifications_outlined, color: AppColors.body, size: 19),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text('M', style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
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

    return Row(
      children: [
        chip(_Period.today, 'Today'),
        const SizedBox(width: AppSpace.gapChip),
        chip(_Period.week, '7 days'),
        const SizedBox(width: AppSpace.gapChip),
        chip(_Period.month, '30 days'),
      ],
    );
  }

  Widget _salesCard() {
    final stats = _stats!;
    // With no sales in the period, a ₱0.00 hero and a flat chart say nothing.
    // The rest of the dashboard (inventory, alerts) stays useful, so only this
    // card becomes an empty state.
    if (stats.transactions == 0) return _noSalesCard();
    final up = stats.deltaPct >= 0;
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
          Text('SALES ${_period == _Period.today ? 'TODAY' : (_period == _Period.week ? 'THIS WEEK' : 'THIS MONTH')}',
              style: AppText.overline()),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatPeso(stats.revenue), style: AppText.heroFigure()),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: StatusPill(
                  label: '${up ? '+' : ''}${(stats.deltaPct * 100).toStringAsFixed(0)}%',
                  fg: up ? AppColors.successText : AppColors.dangerText,
                  bg: up ? AppColors.successFill : AppColors.dangerFill,
                  dot: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _barChart(),
          const SizedBox(height: 8),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _footerStat('Transactions', '${stats.transactions}'),
              _footerStat('Avg sale', formatPeso(stats.avgSale)),
              _footerStat('Items', '${stats.itemsSold}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _noSalesCard() {
    final label = switch (_period) {
      _Period.today => 'No sales yet today',
      _Period.week => 'No sales in the last 7 days',
      _Period.month => 'No sales in the last 30 days',
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
            'Sales you ring up will show here, with the total and a breakdown of the week.',
            textAlign: TextAlign.center,
            style: AppText.caption(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: widget.onStartSale,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.cta)),
              ),
              child: Text('Start a sale',
                  style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppText.cardTitle()),
          const SizedBox(height: 2),
          Text(label, style: AppText.caption()),
        ],
      ),
    );
  }

  Widget _barChart() {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final maxVal = (_chartDays.isEmpty ? 1.0 : _chartDays.reduce((a, b) => a > b ? a : b)).clamp(1, double.infinity);
    final now = DateTime.now();
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(_chartDays.length, (i) {
          final v = _chartDays[i];
          final h = (v / maxVal) * 60;
          final isLast = i == _chartDays.length - 1;
          final dayIdx = (now.weekday - 1 - (_chartDays.length - 1 - i)) % 7;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: h < 4 ? 4 : h,
                    decoration: BoxDecoration(
                      color: isLast ? AppColors.primary : const Color(0xFFD7DDF5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(days[(dayIdx + 7) % 7], style: AppText.caption()),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _statGrid() {
    final stats = _stats!;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpace.gapGrid,
      crossAxisSpacing: AppSpace.gapGrid,
      childAspectRatio: 1.7,
      children: [
        _statCard('Transactions', '${stats.transactions}', Icons.receipt_long_outlined, AppColors.primary),
        _statCard('Items sold', '${stats.itemsSold}', Icons.shopping_bag_outlined, AppColors.primary),
        _statCard('Inventory', '$_totalUnits units', Icons.inventory_2_outlined, AppColors.body),
        _stockAlertsCard(),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      // The tile's height is fixed by the grid, so the figure and label are
      // loose-flexible: at ordinary text sizes nothing changes, and when the
      // reader has scaled text up they shrink rather than clip.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 18, color: color),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: AppText.statFigure()),
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
    );
  }

  Widget _stockAlertsCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text('$_lowCount',
                      style: AppText.statFigure(color: AppColors.warningText, size: 20)),
                  Text(' low', style: AppText.caption(color: AppColors.warningText)),
                  const SizedBox(width: 8),
                  Text('$_outCount',
                      style: AppText.statFigure(color: AppColors.dangerText, size: 20)),
                  Text(' out', style: AppText.caption(color: AppColors.dangerText)),
                ],
              ),
            ),
          ),
          Flexible(
            child: Text('Stock alerts',
                style: AppText.caption(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
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

  Widget _attentionRow(Product p) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const SizedBox(width: 40, height: 40, child: PhotoPlaceholder(borderRadius: 10)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: AppText.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${p.stock} left · min ${p.minStock}', style: AppText.caption()),
              ],
            ),
          ),
          StatusPill(
            label: StockStatus.label(p.stock, p.minStock),
            fg: StockStatus.text(p.stock, p.minStock),
            bg: StockStatus.fill(p.stock, p.minStock),
          ),
        ],
      ),
    );
  }

  Widget _recentSalesList() {
    if (_recentSales.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Text('No sales yet today', style: AppText.body()),
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
          for (int i = 0; i < _recentSales.length; i++) ...[
            _saleRow(_recentSales[i]),
            if (i != _recentSales.length - 1) const Divider(color: AppColors.divider, height: 1),
          ],
        ],
      ),
    );
  }

  Widget _saleRow(Sale s) {
    final t = TimeOfDay.fromDateTime(s.createdAtDate);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.receipt_outlined, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.reference, style: AppText.cardTitle()),
                Text('${s.paymentMethod} · ${t.format(context)}', style: AppText.caption()),
              ],
            ),
          ),
          Text(formatPeso(s.total), style: AppText.cardTitle()),
        ],
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
                  Text('Start a new sale', style: AppText.cardTitle(color: Colors.white).copyWith(fontSize: 15)),
                  Text('Open the register', style: AppText.caption(color: Colors.white70)),
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
