import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/customer.dart';
import '../services/utang_service.dart';

enum _Filter { all, dueSoon, overdue }

/// Utang ledger — who owes what, aged rather than alphabetical, so the overdue
/// balance is the first thing read.
class UtangScreen extends StatefulWidget {
  const UtangScreen({super.key, this.onCharge});

  /// Header CTA — starts a sale to put on someone's tab.
  final VoidCallback? onCharge;

  @override
  State<UtangScreen> createState() => _UtangScreenState();
}

class _UtangScreenState extends State<UtangScreen> {
  final UtangService _utang = UtangService();

  List<Customer> _customers = [];
  _Filter _filter = _Filter.all;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _utang.getCustomers();
    if (!mounted) return;
    setState(() {
      _customers = list;
      _loading = false;
    });
  }

  List<Customer> get _visible => _customers.where((c) {
        switch (_filter) {
          case _Filter.all:
            return true;
          case _Filter.dueSoon:
            return c.status == UtangStatus.dueSoon;
          case _Filter.overdue:
            return c.status == UtangStatus.overdue;
        }
      }).toList();

  List<Customer> get _owing => _customers.where((c) => c.balance > 0).toList();
  double get _totalOwed => _owing.fold(0, (s, c) => s + c.balance);
  double get _overdue => _owing
      .where((c) => c.status == UtangStatus.overdue)
      .fold(0, (s, c) => s + c.balance);

  static Color _statusColor(UtangStatus s) => switch (s) {
        UtangStatus.overdue => AppColors.dangerText,
        UtangStatus.dueSoon => AppColors.warningText,
        UtangStatus.current => AppColors.successText,
      };

  static Color _statusFill(UtangStatus s) => switch (s) {
        UtangStatus.overdue => AppColors.dangerFill,
        UtangStatus.dueSoon => AppColors.warningFill,
        UtangStatus.current => AppColors.successFill,
      };

  static String _statusLabel(UtangStatus s) => switch (s) {
        UtangStatus.overdue => 'Overdue',
        UtangStatus.dueSoon => 'Due soon',
        UtangStatus.current => 'Current',
      };

  Future<void> _addCustomer() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Add a customer', style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: AppText.body(color: AppColors.ink),
          decoration: InputDecoration(
            hintText: 'Name',
            hintStyle: AppText.body(color: AppColors.faint),
            filled: true,
            fillColor: AppColors.canvas,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Add', style: AppText.chip(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _utang.addCustomer(name);
    _load();
  }

  Future<void> _recordPayment(Customer c) async {
    final ctrl = TextEditingController(text: c.balance.toStringAsFixed(2));
    String method = 'Cash';

    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(AppSpace.sheetPad, 14, AppSpace.sheetPad,
              MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.sheetPad),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Record payment', style: AppText.sectionTitle().copyWith(fontSize: 18)),
                const SizedBox(height: 2),
                Text('${c.name} owes ${formatPeso(c.balance)}', style: AppText.caption()),
                const SizedBox(height: 18),
                Text('Amount', style: AppText.body()),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: AppText.largeFigure().copyWith(fontSize: 24),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    prefixText: '₱ ',
                    prefixStyle: AppText.largeFigure(color: AppColors.muted).copyWith(fontSize: 24),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Method', style: AppText.body()),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final m in ['Cash', 'GCash']) ...[
                      GestureDetector(
                        onTap: () => setSheet(() => method = m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: method == m ? AppColors.ink : AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                            border: Border.all(
                                color: method == m ? AppColors.ink : AppColors.hairline),
                          ),
                          child: Text(m,
                              style: AppText.chip(
                                  color: method == m ? Colors.white : AppColors.body)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      final v = double.tryParse(ctrl.text) ?? 0;
                      if (v > 0) Navigator.pop(ctx, v);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                    ),
                    child: Text('Record payment',
                        style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (amount == null || amount <= 0) return;
    await _utang.recordPayment(customerId: c.id!, amount: amount, method: method);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _customers.isEmpty
                      ? _empty()
                      : _body(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final tablet = Breakpoints.isTablet(context);
    return ListView(
      padding: tablet
          ? const EdgeInsets.fromLTRB(24, 6, 24, 32)
          : const EdgeInsets.fromLTRB(AppSpace.screenH, 6, AppSpace.screenH, 32),
      children: [
        _statTiles(),
        const SizedBox(height: AppSpace.gapSection),
        _filterChips(),
        const SizedBox(height: AppSpace.gapSection),
        if (_visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text('Nobody in this group right now', style: AppText.body()),
            ),
          )
        else if (tablet)
          ..._cardPairs()
        else
          for (final c in _visible) ...[
            _customerCard(c),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 6),
        _addButton(),
      ],
    );
  }

  /// Tablet: two customers per row. The cards are a fixed set of rows, so
  /// pairing them keeps each one readable instead of stretching a name and a
  /// balance across the full width. An odd last card keeps its half.
  List<Widget> _cardPairs() {
    final rows = <Widget>[];
    for (var i = 0; i < _visible.length; i += 2) {
      final left = _visible[i];
      final right = i + 1 < _visible.length ? _visible[i + 1] : null;
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _customerCard(left)),
            const SizedBox(width: 10),
            Expanded(
              child: right == null ? const SizedBox.shrink() : _customerCard(right),
            ),
          ],
        ),
      ));
      rows.add(const SizedBox(height: 10));
    }
    return rows;
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 12, AppSpace.screenH, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.hairline),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.body, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Utang', style: AppText.screenTitle().copyWith(fontSize: 20)),
                Text(
                  _loading
                      ? 'Loading…'
                      : '${_owing.length} customer${_owing.length == 1 ? '' : 's'} owing',
                  style: AppText.caption(),
                ),
              ],
            ),
          ),
          if (widget.onCharge != null)
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                widget.onCharge!();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text('Charge', style: AppText.chip(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statTiles() {
    return Row(
      children: [
        Expanded(
          child: _tile('Total owed', formatPeso(_totalOwed), AppColors.ink, AppColors.surface),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _tile(
            'Overdue',
            formatPeso(_overdue),
            _overdue > 0 ? AppColors.dangerText : AppColors.ink,
            _overdue > 0 ? AppColors.dangerFill : AppColors.surface,
          ),
        ),
      ],
    );
  }

  Widget _tile(String label, String value, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption()),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.statFigure(color: color, size: 20)),
        ],
      ),
    );
  }

  Widget _filterChips() {
    Widget chip(_Filter f, String label) {
      final selected = _filter == f;
      return GestureDetector(
        onTap: () => setState(() => _filter = f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          margin: const EdgeInsets.only(right: AppSpace.gapChip),
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
        chip(_Filter.all, 'All'),
        chip(_Filter.dueSoon, 'Due soon'),
        chip(_Filter.overdue, 'Overdue'),
      ],
    );
  }

  String _activityLabel(Customer c) {
    final amount = c.lastActivityAmount;
    if (amount == null) return 'No activity yet';
    return '${c.lastActivityIsCharge ? 'Charged' : 'Paid'} ${formatPeso(amount)}';
  }

  Widget _customerCard(Customer c) {
    final status = c.status;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpace.cardPad),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: _statusFill(status), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(c.initials,
                      style: AppText.statFigure(color: _statusColor(status), size: 16)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.cardTitle().copyWith(fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(c.ageLabel, style: AppText.caption()),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatPeso(c.balance),
                        style: AppText.statFigure(size: 17)),
                    const SizedBox(height: 4),
                    if (c.balance > 0)
                      StatusPill(
                        label: _statusLabel(status),
                        fg: _statusColor(status),
                        bg: _statusFill(status),
                        dot: false,
                      )
                    else
                      const StatusPill(
                        label: 'Settled',
                        fg: AppColors.successText,
                        bg: AppColors.successFill,
                        dot: false,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.cardPad, 10, AppSpace.cardPad, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(_activityLabel(c),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.caption()),
                ),
                if (c.balance > 0)
                  GestureDetector(
                    onTap: () => _recordPayment(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('Record payment', style: AppText.chip(color: AppColors.primary)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _addButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _addCustomer,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.body,
          side: const BorderSide(color: AppColors.hairline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
        ),
        icon: const Icon(Icons.person_add_alt_rounded, size: 17),
        label: Text('Add a customer', style: AppText.chip(color: AppColors.body)),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration:
                  BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.account_balance_wallet_outlined,
                  color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 14),
            Text('No customers on credit', style: AppText.cardTitle().copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              'Add a customer, then charge a sale to their tab from checkout.',
              textAlign: TextAlign.center,
              style: AppText.caption(),
            ),
            const SizedBox(height: 18),
            _addButton(),
          ],
        ),
      ),
    );
  }
}
