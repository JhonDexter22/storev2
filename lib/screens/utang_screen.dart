import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/customer.dart';
import '../models/payment_type.dart';
import '../services/settings_service.dart';
import '../services/utang_service.dart';
import '../widgets/customer_ledger_sheet.dart';
import '../widgets/utang_remind_sheet.dart';
import '../l10n/tr.dart';

enum _Filter { all, dueSoon, overdue }

/// Utang ledger — who owes what, aged rather than alphabetical, so the overdue
/// balance is the first thing read.
class UtangScreen extends StatefulWidget {
  const UtangScreen({super.key, this.onCharge, this.overdueOnly = false});

  /// Opens on the Overdue filter — from the bell's overdue alert, so the
  /// customers it counted are the ones on screen.
  final bool overdueOnly;

  /// Header CTA — starts a sale to put on someone's tab.
  final VoidCallback? onCharge;

  @override
  State<UtangScreen> createState() => _UtangScreenState();
}

class _UtangScreenState extends State<UtangScreen> {
  final UtangService _utang = UtangService();

  List<Customer> _customers = [];
  late _Filter _filter = widget.overdueOnly ? _Filter.overdue : _Filter.all;

  /// The settled group at the bottom of All, folded until asked for.
  bool _showSettled = false;
  String _search = '';
  bool _loading = true;
  ({double amount, int count}) _collected = (amount: 0, count: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _utang.getCustomers();
    final collected = await _utang.collectedToday();
    if (!mounted) return;
    setState(() {
      _customers = list;
      _collected = collected;
      _loading = false;
    });
  }

  List<Customer> get _visible => _customers.where((c) {
    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty &&
        !c.name.toLowerCase().contains(q) &&
        !(c.phone ?? '').contains(q)) {
      return false;
    }
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
    UtangStatus.overdue => tr('Overdue'),
    UtangStatus.dueSoon => tr('Due soon'),
    UtangStatus.current => tr('Current'),
  };

  Future<void> _addCustomer() async {
    final result = await _customerForm();
    if (result == null) return;
    await _utang.addCustomer(result.name, phone: result.phone, creditLimit: result.creditLimit);
    _load();
  }

  /// Name and number, for a new customer or an existing one. Returns null
  /// when cancelled.
  Future<({String name, String? phone, double? creditLimit})?> _customerForm({
    Customer? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final own = existing?.creditLimit;
    final limitCtrl = TextEditingController(
        text: own == null ? '' : (own == own.roundToDouble() ? '${own.toInt()}' : own.toStringAsFixed(2)));
    final storeLimit = SettingsService.instance.creditLimit;
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: AppText.body(color: AppColors.faint),
      filled: true,
      fillColor: AppColors.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          existing == null ? tr('Add a customer') : tr('Edit customer'),
          style: AppText.sectionTitle().copyWith(fontSize: 17),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: existing == null,
              textCapitalization: TextCapitalization.words,
              style: AppText.body(color: AppColors.ink),
              decoration: deco(tr('Name')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              style: AppText.body(color: AppColors.ink),
              decoration: deco(tr('Mobile number (optional)')),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('A number lets you send reminders by SMS.'),
                style: AppText.caption(color: AppColors.faint),
              ),
            ),
            const SizedBox(height: 12),
            // Their own limit, for a trusted regular or someone to keep
            // short. Empty follows the store's default in Settings.
            TextField(
              controller: limitCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppText.body(color: AppColors.ink),
              decoration: deco(storeLimit <= 0
                  ? tr('Credit limit (store default: none)')
                  : tr('Credit limit (store default: {amount})', {'amount': formatPeso(storeLimit)})),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('Leave empty for the store default. 0 means no limit.'),
                style: AppText.caption(color: AppColors.faint),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'), style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              existing == null ? tr('Add') : tr('Save'),
              style: AppText.chip(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    if (ok != true || name.isEmpty) return null;
    final limit = double.tryParse(limitCtrl.text.replaceAll(',', '').trim());
    return (
      name: name,
      phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
      creditLimit: limit == null || limit < 0 ? null : limit,
    );
  }

  Future<bool> _editCustomer(Customer c) async {
    final result = await _customerForm(existing: c);
    if (result == null) return false;
    await _utang.updateCustomer(c.id!, name: result.name, phone: result.phone, creditLimit: result.creditLimit);
    await _load();
    return true;
  }

  Future<bool> _remind(Customer c) async {
    final sent = await showRemindSheet(context, c);
    if (sent == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(tr('Reminder sent to {name}', {'name': c.name}))));
      }
      return true;
    }
    return false;
  }

  /// Everyone overdue who has not been reminded today, one after another —
  /// the morning round in a few taps.
  Future<void> _remindAllOverdue() async {
    final due = _owing
        .where((c) => c.status == UtangStatus.overdue && !c.remindedToday)
        .toList();
    for (final c in due) {
      if (!mounted) return;
      final sent = await showRemindSheet(context, c);
      if (sent != true) break; // Dismissed — stop the round.
    }
    _load();
  }

  Future<void> _openLedger(Customer c) async {
    final changed = await showCustomerLedger(
      context,
      c,
      onRecordPayment: (c) => _recordPayment(c, announce: false),
      onRemind: _remind,
      onEdit: _editCustomer,
    );
    if (changed == true) _load();
  }

  /// The store's own ways to be paid, less Utang — a debt is not paid off
  /// with more debt. Was a fixed Cash / GCash pair that ignored Settings.
  List<String> get _paymentMethods => [
        for (final t in SettingsService.instance.paymentTypes)
          if (t.kind != PaymentKind.utang) t.name,
      ];

  /// "1,000" and "1000" both; null when it is not a number at all.
  static double? _parseAmount(String raw) =>
      double.tryParse(raw.replaceAll(',', '').trim());

  /// Returns the payment's entry id, or null when nothing was recorded.
  /// [announce] off for the customer's panel, which shows its own Undo — a
  /// message here would land behind it.
  Future<int?> _recordPayment(Customer c, {bool announce = true}) async {
    final ctrl = TextEditingController(text: c.balance.toStringAsFixed(2));
    final methods = _paymentMethods;
    String method = methods.first;
    String? error;

    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // Says what is wrong instead of a button that does nothing: a
          // comma, an empty field, or more than is owed.
          void submit() {
            final v = _parseAmount(ctrl.text);
            if (v == null || v <= 0) {
              setSheet(() => error = tr('Enter an amount'));
              return;
            }
            if (v > c.balance + 0.005) {
              setSheet(() => error = tr('{name} only owes {amount}',
                  {'name': c.name, 'amount': formatPeso(c.balance)}));
              return;
            }
            Navigator.pop(ctx, v);
          }

          return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.sheetPad,
            14,
            AppSpace.sheetPad,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
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
                Text(
                  tr('Record payment'),
                  style: AppText.sectionTitle().copyWith(fontSize: 18),
                ),
                const SizedBox(height: 2),
                Text(
                  tr('{name} owes {amount}', {'name': c.name, 'amount': formatPeso(c.balance)}),
                  style: AppText.caption(),
                ),
                const SizedBox(height: 18),
                Text(tr('Amount'), style: AppText.body()),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) {
                    if (error != null) setSheet(() => error = null);
                  },
                  onSubmitted: (_) => submit(),
                  style: AppText.largeFigure().copyWith(fontSize: 24),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    prefixText: '₱ ',
                    prefixStyle: AppText.largeFigure(
                      color: AppColors.muted,
                    ).copyWith(fontSize: 24),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 6),
                  Text(error!, style: AppText.caption(color: AppColors.dangerText)),
                ],
                const SizedBox(height: 16),
                Text(tr('Method'), style: AppText.body()),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in methods)
                      GestureDetector(
                        onTap: () => setSheet(() => method = m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: method == m
                                ? AppColors.ink
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                            border: Border.all(
                              color: method == m
                                  ? AppColors.ink
                                  : AppColors.hairline,
                            ),
                          ),
                          child: Text(
                            tr(m),
                            style: AppText.chip(
                              color: method == m
                                  ? Colors.white
                                  : AppColors.body,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.cta),
                      ),
                    ),
                    child: Text(
                      tr('Record payment'),
                      style: AppText.chip(
                        color: Colors.white,
                      ).copyWith(fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        },
      ),
    );

    if (amount == null || amount <= 0) return null;
    final entryId = await _utang.recordPayment(
      customerId: c.id!,
      amount: amount,
      method: method,
    );
    HapticFeedback.lightImpact();
    await _load();
    if (!mounted || !announce) return entryId;
    final after = c.balance - amount;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(after <= 0.005
            ? tr('Paid {amount} · {name} is settled', {'amount': formatPeso(amount), 'name': c.name})
            : tr('Paid {amount} · {name} now owes {balance}',
                {'amount': formatPeso(amount), 'name': c.name, 'balance': formatPeso(after)})),
        action: SnackBarAction(
          label: tr('Undo'),
          onPressed: () async {
            await _utang.deletePayment(entryId);
            _load();
          },
        ),
      ));
    return entryId;
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
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
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
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: tablet
            ? const EdgeInsets.fromLTRB(24, 6, 24, 32)
            : const EdgeInsets.fromLTRB(
                AppSpace.screenH,
                6,
                AppSpace.screenH,
                32,
              ),
        children: [
          _statTiles(),
          const SizedBox(height: AppSpace.gapSection),
          // A search box once the book outgrows a glance.
          if (_customers.length > 5) ...[
            _searchField(),
            const SizedBox(height: 10),
          ],
          _filterChips(),
          const SizedBox(height: AppSpace.gapSection),
          if (_visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  tr('Nobody in this group right now'),
                  style: AppText.body(),
                ),
              ),
            )
          else ...[
            // Everyone who ever had a tab stays (their history matters), so
            // under All the settled ones fold into one line at the bottom.
            ..._cards(_split ? _visible.where((c) => c.balance > 0).toList() : _visible, tablet),
            if (_split && _visible.any((c) => c.balance <= 0)) ...[
              _settledHeader(_visible.where((c) => c.balance <= 0).length),
              if (_showSettled) ..._cards(_visible.where((c) => c.balance <= 0).toList(), tablet),
            ],
          ],
          const SizedBox(height: 6),
          _addButton(),
        ],
      ),
    );
  }

  /// Tablet: two customers per row. The cards are a fixed set of rows, so
  /// pairing them keeps each one readable instead of stretching a name and a
  /// balance across the full width. An odd last card keeps its half.
  /// Folding applies to All with no search: a search should find a settled
  /// customer without a second tap.
  bool get _split => _filter == _Filter.all && _search.trim().isEmpty;

  List<Widget> _cards(List<Customer> list, bool tablet) => tablet
      ? _cardPairs(list)
      : [
          for (final c in list) ...[
            _customerCard(c),
            const SizedBox(height: 10),
          ],
        ];

  Widget _settledHeader(int n) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: () => setState(() => _showSettled = !_showSettled),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.cardPad, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.successText),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr('Settled · {n}', {'n': n}), style: AppText.cardTitle())),
                  Icon(_showSettled ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: AppColors.muted),
                ],
              ),
            ),
          ),
        ),
      );

  List<Widget> _cardPairs(List<Customer> list) {
    final rows = <Widget>[];
    for (var i = 0; i < list.length; i += 2) {
      final left = list[i];
      final right = i + 1 < list.length ? list[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _customerCard(left)),
              const SizedBox(width: 10),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : _customerCard(right),
              ),
            ],
          ),
        ),
      );
      rows.add(const SizedBox(height: 10));
    }
    return rows;
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenH,
        12,
        AppSpace.screenH,
        12,
      ),
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
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.body,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Credit'),
                  style: AppText.screenTitle().copyWith(fontSize: 20),
                ),
                Text(
                  _loading
                      ? tr('Loading…')
                      : trCount(_owing.length, '{n} customer owing', '{n} customers owing'),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(tr('Charge'), style: AppText.chip(color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statTiles() {
    final overdueToRemind = _owing
        .where((c) => c.status == UtangStatus.overdue && !c.remindedToday)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _tile(
                tr('Total owed'),
                formatPeso(_totalOwed),
                AppColors.ink,
                AppColors.surface,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _tile(
                tr('Overdue'),
                formatPeso(_overdue),
                _overdue > 0 ? AppColors.dangerText : AppColors.ink,
                _overdue > 0 ? AppColors.dangerFill : AppColors.surface,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _tile(
                tr('Collected today'),
                formatPeso(_collected.amount),
                _collected.amount > 0 ? AppColors.successText : AppColors.ink,
                _collected.amount > 0
                    ? AppColors.successFill
                    : AppColors.surface,
              ),
            ),
          ],
        ),
        if (overdueToRemind > 0) ...[
          const SizedBox(height: 10),
          Material(
            color: AppColors.dangerFill,
            borderRadius: BorderRadius.circular(AppRadius.input),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.input),
              onTap: _remindAllOverdue,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.input),
                  border: Border.all(color: AppColors.dangerBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_outlined,
                      size: 18,
                      color: AppColors.dangerText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('{n} overdue not yet reminded today', {'n': overdueToRemind}),
                        style: AppText.chip(color: AppColors.dangerText),
                      ),
                    ),
                    Text(
                      tr('Remind all'),
                      style: AppText.chip(color: AppColors.dangerText),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.dangerText,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: AppText.statFigure(color: color, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.hairline),
      ),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        style: AppText.body(color: AppColors.ink),
        decoration: InputDecoration(
          border: InputBorder.none,
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          hintText: tr('Search name or number'),
          hintStyle: AppText.body(color: AppColors.faint),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted, size: 20),
          prefixIconConstraints: const BoxConstraints(minWidth: 42),
        ),
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
            border: Border.all(
              color: selected ? AppColors.ink : AppColors.hairline,
            ),
          ),
          child: Text(
            label,
            style: AppText.chip(
              color: selected ? Colors.white : AppColors.body,
            ),
          ),
        ),
      );
    }

    // Scrolls rather than clips: Filipino labels run longer than English,
    // and on a narrow phone the last chip would otherwise be cut off.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(_Filter.all, tr('All')),
          chip(_Filter.dueSoon, tr('Due soon')),
          chip(_Filter.overdue, tr('Overdue')),
        ],
      ),
    );
  }

  String _activityLabel(Customer c) {
    final amount = c.lastActivityAmount;
    if (amount == null) return tr('No activity yet');
    final money = {'amount': formatPeso(amount)};
    if (c.lastActivityIsCharge) return tr('Charged {amount}', money);
    if (c.lastActivityIsReturn) return tr('Returned {amount}', money);
    return tr('Paid {amount}', money);
  }

  Widget _customerCard(Customer c) {
    final status = c.status;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openLedger(c),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpace.cardPad),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _statusFill(status),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        c.initials,
                        style: AppText.statFigure(
                          color: _statusColor(status),
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.cardTitle().copyWith(fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            c.remindedToday
                                ? '${c.ageLabel} · ${tr('reminded today')}'
                                : c.hasPhone
                                ? '${c.ageLabel} · ${c.phone}'
                                : c.ageLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption(
                              color: c.remindedToday
                                  ? AppColors.successText
                                  : AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatPeso(c.balance),
                          style: AppText.statFigure(size: 17),
                        ),
                        const SizedBox(height: 4),
                        if (c.balance > 0)
                          StatusPill(
                            label: _statusLabel(status),
                            fg: _statusColor(status),
                            bg: _statusFill(status),
                            dot: false,
                          )
                        else
                          StatusPill(
                            label: tr('Settled'),
                            fg: AppColors.successText,
                            bg: AppColors.successFill,
                            dot: false,
                          ),
                        // Only checkout used to say so, at the moment of a sale.
                        if (isOverLimit(c)) ...[
                          const SizedBox(height: 4),
                          StatusPill(
                            label: tr('Over limit'),
                            fg: AppColors.dangerText,
                            bg: AppColors.dangerFill,
                            dot: false,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.divider, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.cardPad,
                  10,
                  AppSpace.cardPad,
                  10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _activityLabel(c),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption(),
                      ),
                    ),
                    if (c.balance > 0) ...[
                      _pill(
                        c.remindedToday
                            ? Icons.notifications_off_outlined
                            : Icons.notifications_none_rounded,
                        tr('Remind'),
                        () => _remind(c),
                        muted: c.remindedToday,
                      ),
                      const SizedBox(width: 6),
                      _pill(
                        Icons.payments_outlined,
                        tr('Payment'),
                        () => _recordPayment(c),
                        primary: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool primary = false,
    bool muted = false,
  }) {
    final fg = primary
        ? AppColors.primary
        : muted
        ? AppColors.faint
        : AppColors.body;
    return Material(
      color: primary ? AppColors.primaryTint : AppColors.canvas,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Text(label, style: AppText.chip(color: fg)),
            ],
          ),
        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.cta),
          ),
        ),
        icon: const Icon(Icons.person_add_alt_rounded, size: 17),
        label: Text(
          tr('Add a customer'),
          style: AppText.chip(color: AppColors.body),
        ),
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
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                color: AppColors.primary,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              tr('No customers on credit'),
              style: AppText.cardTitle().copyWith(fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              tr('Add a customer, then charge a sale to their tab from checkout.'),
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
