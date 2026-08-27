import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/product_model.dart';
import '../models/sale_model.dart';
import '../services/product_service.dart';
import '../services/sales_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onStartSale});

  final VoidCallback? onStartSale;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

enum _Period { today, week, month }

class _DashboardScreenState extends State<DashboardScreen> {
  final ProductService _productService = ProductService();
  final SalesService _salesService = SalesService();

  _Period _period = _Period.today;
  bool _loading = true;

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
    setState(() => _loading = true);
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
  }

  Future<void> _setPeriod(_Period p) async {
    setState(() => _period = p);
    final stats = await _salesService.getPeriodStats(_periodDays);
    if (!mounted) return;
    setState(() => _stats = stats);
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
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _load,
                child: ListView(
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
                ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, size: 18, color: color),
          Text(value, style: AppText.statFigure()),
          Text(label, style: AppText.caption()),
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
          Row(
            children: [
              Text('$_lowCount', style: AppText.statFigure(color: AppColors.warningText, size: 20)),
              Text(' low', style: AppText.caption(color: AppColors.warningText)),
              const SizedBox(width: 8),
              Text('$_outCount', style: AppText.statFigure(color: AppColors.dangerText, size: 20)),
              Text(' out', style: AppText.caption(color: AppColors.dangerText)),
            ],
          ),
          Text('Stock alerts', style: AppText.caption()),
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
