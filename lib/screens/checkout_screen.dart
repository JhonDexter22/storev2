import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/change_breakdown.dart';
import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/cart_line.dart';
import '../models/customer.dart';
import '../models/discount.dart';
import '../models/payment_type.dart';
import '../services/printer_service.dart';
import '../services/receipt_document.dart';
import '../services/sales_service.dart';
import '../services/settings_service.dart';
import '../services/utang_service.dart';
import 'printer_screen.dart';
import '../widgets/discount_sheet.dart';
import '../l10n/tr.dart';
import '../models/sale_model.dart';
import '../services/error_log.dart';

/// How the cashier left checkout. Both outcomes clear the cart; only
/// [completed] means stock moved and needs re-reading.
enum CheckoutOutcome { completed, voided }

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.lines});

  final List<CartLine> lines;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final SalesService _salesService = SalesService();
  final UtangService _utang = UtangService();

  /// The types offered here come from settings, so a store that does not take
  /// Card never sees a Card button. Read once on open: changing the setting
  /// mid-sale would move the buttons under the cashier's finger.
  late final List<PaymentType> _methods =
      SettingsService.instance.paymentTypes;
  late PaymentType _method = _methods.first;
  double _received = 0;
  final _receivedCtrl = TextEditingController();
  bool _saving = false;
  _CompletedSale? _done;

  List<Customer> _customers = [];
  Customer? _chargeTo;
  String _customerSearch = '';

  Discount _discount = Discount.none;
  bool _showAllLines = false;

  double get _subtotal => widget.lines.fold(0, (s, l) => s + l.lineTotal);
  double get _discountAmount => _discount.amountOn(_subtotal);

  /// What the customer pays. Every downstream figure — cash received, change,
  /// the utang charge, the CTA — reads this, so a discount cannot be shown on
  /// screen and then quietly left out of one of them.
  double get _due => _subtotal - _discountAmount;
  double get _change => (_received - _due).clamp(0, double.infinity);

  bool get _canComplete {
    if (_method.kind == PaymentKind.cash) return _received >= _due;
    // Nothing is charged until a name is picked.
    if (_method.kind == PaymentKind.utang) return _chargeTo != null;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final list = await _utang.getCustomers();
    if (!mounted) return;
    setState(() => _customers = list);
  }

  @override
  void dispose() {
    _receivedCtrl.dispose();
    super.dispose();
  }

  void _setReceived(double v) {
    setState(() {
      _received = v;
      // Centavos shown when there are any: Exact on ₱27.50 used to put "28"
      // in the box while recording 27.50.
      _receivedCtrl.text = v == 0
          ? ''
          : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));
    });
  }

  /// The next notes up from what is due — what a customer actually hands
  /// over. A ₱37 sale offers ₱50, ₱100 and ₱200; fixed ₱500 / ₱1,000 chips
  /// fit almost nothing a sari-sari store sells.
  List<double> get _quickCash {
    const notes = [20.0, 50.0, 100.0, 200.0, 500.0, 1000.0];
    final up = notes.where((n) => n > _due + 0.005).take(3).toList();
    if (up.isNotEmpty) return up;
    // Above ₱1,000: the next round ₱500 and ₱1,000.
    final byFive = (_due / 500).ceil() * 500.0;
    final byThousand = (_due / 1000).ceil() * 1000.0;
    return {byFive, byThousand}.where((n) => n > _due + 0.005).toList();
  }

  static String _note(double v) => formatPeso(v).replaceAll('.00', '');

  Future<void> _completeSale() async {
    if (!_canComplete || _saving) return;
    setState(() => _saving = true);
    final methodLabel = _method.name;
    final isCash = _method.kind == PaymentKind.cash;
    final onCredit = _method.kind == PaymentKind.utang;
    // A failure used to leave the button spinning for good, with no message
    // and no way to try again — a frozen sale at the till.
    try {
      final sale = await _salesService.recordSale(
        lines: widget.lines,
        paymentMethod: methodLabel,
        // No cash is tendered on the credit path, so nothing is received and no
        // change is calculated.
        cashReceived: _method.kind == PaymentKind.cash
            ? _received
            : (onCredit ? 0 : _due),
        changeAmount: _method.kind == PaymentKind.cash ? _change : 0,
        discount: _discount,
        cashier: SettingsService.instance.cashier,
      );
      Customer? tab;
      if (onCredit && _chargeTo?.id != null) {
        await _utang.charge(
          customerId: _chargeTo!.id!,
          amount: _due,
          saleId: sale.id,
          note: sale.reference,
        );
        tab = await _tabAfterCharge(_chargeTo!);
      }
      if (!mounted) return;
      _finish(sale, methodLabel, isCash: isCash, tab: tab);
    } catch (e, st) {
      ErrorLog.caught(e, st, 'checkout: saving the sale');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(tr('Could not save the sale. Try again.'),
            style: const TextStyle(color: Colors.white)),
      ));
    }
  }

  /// The customer as they stand after this sale, for the balance on the done
  /// screen. The sale and the charge are already saved, so a failure here
  /// must not surface as "could not save" — it falls back to adding this sale
  /// to the balance the picker showed.
  Future<Customer> _tabAfterCharge(Customer c) async {
    try {
      final fresh = await _utang.getCustomer(c.id!);
      if (fresh != null) return fresh;
    } catch (e, st) {
      ErrorLog.caught(e, st, 'checkout: reading the tab after a charge');
    }
    return c.copyWith(balance: c.balance + _due);
  }

  void _finish(Sale sale, String methodLabel, {required bool isCash, Customer? tab}) {
    // The one moment on this screen that deserves a thump.
    HapticFeedback.mediumImpact();
    setState(() {
      _saving = false;
      _done = _CompletedSale(
        reference: sale.reference,
        method: methodLabel,
        isCash: isCash,
        time: DateTime.now(),
        tab: tab,
        subtotal: _subtotal,
        discountAmount: _discountAmount,
        discountLabel: _discount.label(_subtotal),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done != null) {
      return _SuccessView(
        done: _done!,
        due: _due,
        received: _received,
        change: _change,
        lines: widget.lines,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _appBar(),
            Expanded(
              child: Breakpoints.isTablet(context) ? _tabletBody() : _phoneBody(),
            ),
            _ctaBar(),
          ],
        ),
      ),
    );
  }

  /// The payment half: how they are paying, and everything that depends on
  /// it. Shared by both layouts so the two never drift apart.
  List<Widget> _paymentSection() {
    return [
      Text(tr('Payment method'), style: AppText.sectionTitle()),
      const SizedBox(height: 10),
      _paymentMethodRow(),
      if (_method.kind == PaymentKind.utang) ...[
        const SizedBox(height: AppSpace.gapSection),
        Text(tr('Charge to'), style: AppText.sectionTitle()),
        const SizedBox(height: 10),
        _customerPicker(),
      ],
      if (_method.kind == PaymentKind.cash) ...[
        const SizedBox(height: AppSpace.gapSection),
        _cashReceivedCard(),
        if (_received > 0 && _received < _due) ...[
          const SizedBox(height: 10),
          _notice(
            tr('Cash received is less than the amount due.'),
            AppColors.warning,
            AppColors.warningFill,
            AppColors.warningBorder,
          ),
        ],
        if (_received >= _due && _received > 0) ...[
          const SizedBox(height: 10),
          _changeBlock(),
        ],
      ],
    ];
  }

  Widget _phoneBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenH,
        6,
        AppSpace.screenH,
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _orderSummaryCard(fold: true),
          const SizedBox(height: AppSpace.gapSection),
          ..._paymentSection(),
        ],
      ),
    );
  }

  /// Tablet: what they are buying stays put on the left while the cashier
  /// works the payment on the right. On the phone the summary scrolls away as
  /// soon as the number pad opens, which is exactly when the customer asks
  /// what they are paying for.
  Widget _tabletBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 6, 12, 24),
            child: _orderSummaryCard(),
          ),
        ),
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 6, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _paymentSection(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _appBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screenH,
        12,
        AppSpace.screenH,
        8,
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
                  tr('Checkout'),
                  style: AppText.sectionTitle().copyWith(fontSize: 18),
                ),
                Text(
                  trCount(widget.lines.fold<int>(0, (s, l) => s + l.qty), '{n} item', '{n} items'),
                  style: AppText.caption(),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _confirmVoid,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.dangerFill,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: AppColors.dangerBorder),
              ),
              child: Text(
                tr('Void sale'),
                style: AppText.chip(color: AppColors.dangerText),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Clears the in-progress cart and returns to POS. Confirmed first because
  /// there is no undo for a discarded cart.
  Future<void> _confirmVoid() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr('Void this sale?'),
          style: AppText.sectionTitle().copyWith(fontSize: 17),
        ),
        content: Text(
          tr('The items in this sale will be cleared and you will go back to the register. Nothing is charged.'),
          style: AppText.body(),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              tr('Keep the sale'),
              style: AppText.chip(color: AppColors.body),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              tr('Void sale'),
              style: AppText.chip(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.pop(context, CheckoutOutcome.voided);
    }
  }

  /// [fold] shortens a long basket to its first few lines. The phone wants it:
  /// fifteen lines pushed Cash received off the screen on every big sale. The
  /// tablet does not — its summary scrolls on its own, beside the payment.
  Widget _orderSummaryCard({bool fold = false}) {
    const folded = 4;
    // Folding away a single line saves nothing.
    final lines = !fold || _showAllLines || widget.lines.length <= folded + 1
        ? widget.lines
        : widget.lines.take(folded).toList();
    final hidden = widget.lines.length - lines.length;
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (final line in lines) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '×${line.qty}',
                    style: AppText.chip(color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    line.product.name,
                    style: AppText.cardTitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                // Its own width, against the right edge. It used to be
                // Flexible, which gave the price half the row: names were cut
                // short and prices floated mid-card.
                Text(formatPeso(line.lineTotal), style: AppText.cardTitle()),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (hidden > 0) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => setState(() => _showAllLines = true),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    trCount(hidden, '+{n} more item', '+{n} more items'),
                    style: AppText.chip(color: AppColors.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          _discountRow(),
          if (!_discount.isZero) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('Subtotal'), style: AppText.body()),
                Text(formatPeso(_subtotal), style: AppText.body()),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _discount.label(_subtotal),
                    style: AppText.body(color: AppColors.successText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text('−${formatPeso(_discountAmount)}',
                    style: AppText.body(color: AppColors.successText)),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(color: AppColors.divider, height: 1),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('Amount due'), style: AppText.sectionTitle()),
              Text(
                formatPeso(_due),
                style: AppText.largeFigure().copyWith(fontSize: 21),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The discount affordance. Present but quiet when unused — a discount is
  /// the exception, not part of every sale.
  Widget _discountRow() {
    final has = !_discount.isZero;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _openDiscountSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(has ? Icons.sell_rounded : Icons.sell_outlined,
                  size: 17,
                  color: has ? AppColors.successText : AppColors.body),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  has ? tr('Discount applied') : tr('Add a discount'),
                  style: AppText.body(
                      color: has ? AppColors.successText : AppColors.body),
                ),
              ),
              if (has)
                GestureDetector(
                  onTap: () => setState(() => _discount = Discount.none),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(tr('Remove'),
                        style: AppText.chip(color: AppColors.dangerText)),
                  ),
                )
              else
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.faint),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDiscountSheet() async {
    final picked = await DiscountSheet.show(
      context,
      subtotal: _subtotal,
      current: _discount,
    );
    if (picked == null || !mounted) return;
    setState(() => _discount = picked);
  }

  Widget _paymentMethodRow() {
    Widget option(PaymentType type) {
      final selected = _method == type;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _method = type),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryTint : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.hairline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  type.icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.body,
                ),
                const SizedBox(height: 6),
                Text(
                  type.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.chip(
                    color: selected ? AppColors.primary : AppColors.body,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Wraps rather than a fixed row: a shopkeeper who adds Maya and a bank
    // transfer would otherwise squeeze six buttons into four widths. Sized
    // from the space it is given, not the screen: on a tablet that is the
    // right-hand panel, and screen-width buttons wrapped two to a row there.
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final type in _methods)
            SizedBox(
              width: _optionWidth(box.maxWidth, _methods.length),
              child: Row(children: [option(type)]),
            ),
        ],
      ),
    );
  }

  /// Four across at most, so the buttons stay a comfortable tap target however
  /// many types the store has switched on.
  static double _optionWidth(double available, int count) {
    final perRow = count <= 4 ? count : 4;
    // Floored: a fraction of a pixel over would wrap the last button.
    return ((available - 8 * (perRow - 1)) / perRow).floorToDouble();
  }

  /// Each row shows the balance now and the balance this sale would create, so
  /// the consequence is visible before committing.
  /// Adds someone to the book and puts this sale on their tab. Starting a
  /// tab used to mean abandoning the sale for the Credit screen.
  Future<void> _newCustomer() async {
    final ctrl = TextEditingController(text: _customerSearch.trim());
    String? error;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          void save() {
            if (ctrl.text.trim().isEmpty) {
              setDialog(() => error = tr('Enter a name'));
              return;
            }
            Navigator.pop(ctx, ctrl.text.trim());
          }

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(tr('New customer'), style: AppText.sectionTitle().copyWith(fontSize: 17)),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => save(),
              onChanged: (_) {
                if (error != null) setDialog(() => error = null);
              },
              style: AppText.body(color: AppColors.ink),
              decoration: InputDecoration(
                hintText: tr('Name'),
                errorText: error,
                filled: true,
                fillColor: AppColors.canvas,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Cancel'), style: AppText.chip(color: AppColors.body)),
              ),
              TextButton(
                onPressed: save,
                child: Text(tr('Add'), style: AppText.chip(color: AppColors.primary)),
              ),
            ],
          );
        },
      ),
    );
    if (name == null) return;
    final id = await _utang.addCustomer(name);
    final list = await _utang.getCustomers();
    if (!mounted) return;
    setState(() {
      _customers = list;
      _chargeTo = list.firstWhere((c) => c.id == id);
      _customerSearch = '';
    });
  }

  Widget _newCustomerButton() => SizedBox(
        width: double.infinity,
        height: 46,
        child: OutlinedButton.icon(
          onPressed: _newCustomer,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.hairline),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
          ),
          icon: const Icon(Icons.person_add_alt_rounded, size: 17),
          label: Text(tr('New customer'), style: AppText.chip(color: AppColors.primary)),
        ),
      );

  Widget _customerPicker() {
    if (_customers.isEmpty) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              children: [
                Text(tr('No customers on credit yet'), style: AppText.cardTitle()),
                const SizedBox(height: 4),
                // Was "Add one from More → Utang" — a row More does not have.
                Text(
                  tr('Add their name to start a tab.'),
                  textAlign: TextAlign.center,
                  style: AppText.caption(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _newCustomerButton(),
        ],
      );
    }

    final q = _customerSearch.trim().toLowerCase();
    final shown = q.isEmpty
        ? _customers
        : _customers
            .where((c) => c.name.toLowerCase().contains(q) || (c.phone ?? '').contains(q))
            .toList();

    return Column(
      children: [
        if (_customers.length > 5) ...[
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: AppColors.hairline),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _customerSearch = v),
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
          ),
          const SizedBox(height: 10),
        ],
        if (shown.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < shown.length; i++) ...[
                  _customerRow(shown[i]),
                  if (i != shown.length - 1)
                    const Divider(color: AppColors.divider, height: 1),
                ],
              ],
            ),
          ),
        const SizedBox(height: 10),
        _newCustomerButton(),
      ],
    );
  }

  Widget _customerRow(Customer c) {
    final selected = _chargeTo?.id == c.id;
    final becomes = c.balance + _due;
    final overCeiling = isOverLimit(c, balance: becomes);

    return Material(
      color: selected ? AppColors.primaryTint : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _chargeTo = c),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.canvas,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  c.initials,
                  style: AppText.chip(
                    color: selected ? Colors.white : AppColors.body,
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
                      style: AppText.cardTitle(),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Short enough to fit beside "Over limit", which used
                      // to cut off the very figure it was warning about.
                      tr('Owes {owes} → {becomes}', {'owes': formatPeso(c.balance), 'becomes': formatPeso(becomes)}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(),
                    ),
                  ],
                ),
              ),
              if (overCeiling) ...[
                const SizedBox(width: 8),
                StatusPill(
                  label: tr('Over limit'),
                  fg: AppColors.warningText,
                  bg: AppColors.warningFill,
                  dot: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cashReceivedCard() {
    final quick = _quickCash;
    return Container(
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Cash received'), style: AppText.body()),
          const SizedBox(height: 8),
          TextField(
            controller: _receivedCtrl,
            keyboardType: TextInputType.number,
            style: AppText.largeFigure().copyWith(fontSize: 24),
            decoration: InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              hintText: '0',
              hintStyle: AppText.largeFigure(
                color: AppColors.faint,
              ).copyWith(fontSize: 24),
              prefixText: '₱ ',
              prefixStyle: AppText.largeFigure(
                color: AppColors.muted,
              ).copyWith(fontSize: 24),
            ),
            // "1,000" is a thousand, not nothing.
            onChanged: (v) => setState(
                () => _received = double.tryParse(v.replaceAll(',', '').trim()) ?? 0),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final amount in quick) ...[
                _quickAmountChip(
                  _note(amount),
                  () => _setReceived(amount),
                  selected: _isReceived(amount),
                ),
                const SizedBox(width: 8),
              ],
              _quickAmountChip(tr('Exact'), () => _setReceived(_due),
                  selected: _isReceived(_due)),
            ],
          ),
        ],
      ),
    );
  }

  /// Lights the chip matching what is in the box, typed or tapped, so the
  /// cashier can see which note they took without reading the figure.
  bool _isReceived(double amount) =>
      _received > 0 && (_received - amount).abs() < 0.005;

  Widget _quickAmountChip(String label, VoidCallback onTap, {bool selected = false}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryTint : AppColors.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.hairline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Text(label,
              style: AppText.chip(color: selected ? AppColors.primary : AppColors.ink)),
        ),
      ),
    );
  }

  Widget _notice(String text, Color fg, Color bg, Color border) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppText.caption(color: fg)),
          ),
        ],
      ),
    );
  }

  Widget _changeBlock() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.successFill,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tr('Change'), style: AppText.body(color: AppColors.successText)),
          Text(
            formatPeso(_change),
            style: AppText.largeFigure(
              color: AppColors.successText,
            ).copyWith(fontSize: 22),
          ),
        ],
      ),
    );
  }

  /// What the button says. While it cannot be pressed it says what is
  /// missing: a greyed-out "Complete sale" left the cashier to work out why.
  String get _ctaLabel {
    final onCredit = _method.kind == PaymentKind.utang;
    if (!_canComplete) {
      if (onCredit) return tr('Pick a customer');
      if (_received > 0) {
        return tr('Short by {amount}', {'amount': formatPeso(_due - _received)});
      }
      return tr('Enter cash received');
    }
    return onCredit
        ? tr('Charge to utang · {amount}', {'amount': formatPeso(_due)})
        : tr('Complete sale · {amount}', {'amount': formatPeso(_due)});
  }

  Widget _ctaBar() {
    final onCredit = _method.kind == PaymentKind.utang;
    final label = _ctaLabel;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.screenH,
        12,
        AppSpace.screenH,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Once a name is picked, say whose tab this lands on before they commit.
          if (onCredit && _chargeTo != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.warningFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warningBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 15,
                    color: AppColors.warningText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr("On {name}'s tab", {'name': _chargeTo!.name}),
                      style: AppText.caption(color: AppColors.warningText),
                    ),
                  ),
                  Text(
                    formatPeso(_due),
                    style: AppText.chip(color: AppColors.warningText),
                  ),
                ],
              ),
            ),
          ],
          _ctaButton(label),
        ],
      ),
    );
  }

  Widget _ctaButton(String label) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _canComplete && !_saving ? _completeSale : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.disabledFill,
          foregroundColor: Colors.white,
          disabledForegroundColor: AppColors.faint,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.cta),
          ),
        ),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                // Muted rather than white while disabled: it is an
                // instruction now, and white on the grey fill barely read.
                style: AppText.chip(
                  color: _canComplete ? Colors.white : AppColors.muted,
                ).copyWith(fontSize: 15),
              ),
      ),
    );
  }
}

class _CompletedSale {
  _CompletedSale({
    required this.reference,
    required this.method,
    required this.isCash,
    required this.time,
    this.tab,
    this.subtotal = 0,
    this.discountAmount = 0,
    this.discountLabel = '',
  });
  final String reference;
  final String method;

  /// From the payment type's kind, not its name: a store can rename "Cash".
  final bool isCash;
  final DateTime time;

  /// Kept for the receipt: a customer given a senior or PWD discount should be
  /// able to see it was applied, not just a smaller number.
  final double subtotal;
  final double discountAmount;
  final String discountLabel;

  bool get hasDiscount => discountAmount > 0;

  /// Set only on the credit path: whose tab this landed on, with the balance
  /// after this sale.
  final Customer? tab;

  String? get chargedTo => tab?.name;
  bool get onCredit => tab != null;
}

class _SuccessView extends StatefulWidget {
  const _SuccessView({
    required this.done,
    required this.due,
    required this.received,
    required this.change,
    required this.lines,
  });

  final _CompletedSale done;
  final double due;
  final double received;
  final double change;
  final List<CartLine> lines;

  @override
  State<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends State<_SuccessView> {
  bool _printing = false;
  bool _showAll = false;

  _CompletedSale get done => widget.done;
  double get due => widget.due;
  double get received => widget.received;
  double get change => widget.change;
  List<CartLine> get lines => widget.lines;

  @override
  void initState() {
    super.initState();
    // "Automatically print after checkout" was a setting that did nothing
    // until there was a printer to send to. It only fires when one is chosen,
    // so leaving it on costs nothing until then.
    if (SettingsService.instance.printReceipt &&
        PrinterService.instance.hasPrinter) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _print(auto: true));
    }
  }

  /// The receipt, as a document that renders to both paper and text.
  ///
  /// One model for both so a customer comparing the slip in their hand with
  /// the copy sent to their phone sees the same thing. A senior or PWD
  /// discount is itemised because that is the half of the receipt they are
  /// most likely to be asked to show.
  List<ReceiptBlock> _blocks() => ReceiptDocument.sale(
        storeName: SettingsService.instance.storeName,
        reference: done.reference,
        time: done.time,
        cashier: SettingsService.instance.cashier,
        items: [
          for (final line in lines)
            ReceiptLineItem(
              name: line.product.name,
              qty: line.qty,
              unitPrice: line.product.price,
              lineTotal: line.lineTotal,
            ),
        ],
        subtotal: done.subtotal,
        total: due,
        method: done.method,
        discountLabel: done.discountLabel,
        discountAmount: done.discountAmount,
        cashReceived: received,
        change: change,
        chargedTo: done.chargedTo,
      );

  /// Text rather than a file: it goes wherever the customer already is —
  /// Messenger, SMS, email — without them needing an app that opens
  /// attachments.
  String buildReceipt() => ReceiptDocument.asText(_blocks());

  Future<void> _print({bool auto = false}) async {
    if (_printing) return;
    setState(() => _printing = true);
    final result = await PrinterService.instance.printDocument(_blocks());
    if (!mounted) return;
    setState(() => _printing = false);

    // An automatic print that worked needs no announcement — the paper is the
    // announcement. One that failed does, or the cashier hands over nothing.
    if (auto && result.ok) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: result.ok ? AppColors.success : AppColors.ink,
      content: Text(result.message),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(done.time).format(context);
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // A tablet gets the phone's column rather than a stretched one, so
            // the change figure and the buttons stay where the eye expects.
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.screenH, 24, AppSpace.screenH, 16),
                    child: Column(
                      children: [
                        _statusPill(time),
                        const SizedBox(height: 20),
                        ..._hero(),
                        const SizedBox(height: 22),
                        _itemsCard(),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.screenH, 8, AppSpace.screenH, 24),
                  child: _actions(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// What happened, in one line. It used to be the screen's headline, but the
  /// cashier already knows the sale went through — they pressed the button.
  /// The pop is for the corner of the eye: their attention is on the customer.
  Widget _statusPill(String time) {
    final credit = done.onCredit;
    final fg = credit ? AppColors.primary : AppColors.successText;
    final bg = credit ? AppColors.primaryTint : AppColors.successFill;
    final still = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0.6, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(
        scale: t,
        child: Opacity(opacity: ((t - 0.6) / 0.4).clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
              child: Icon(
                credit ? Icons.receipt_long_rounded : Icons.check_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                // Nothing was paid on the credit path — "paid" there would
                // misreport what happened.
                credit
                    ? tr('Charged to utang · {time}', {'time': time})
                    : tr('Paid · {method} · {time}',
                        {'method': done.method, 'time': time}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.chip(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The one figure the cashier needs next. On cash that is the change, with
  /// the bills and coins that make it; elsewhere it is what was paid or put
  /// on the tab.
  List<Widget> _hero() {
    if (done.onCredit) return _tabHero(done.tab!);
    if (!done.isCash) {
      return [
        Text(tr('Paid with {method}', {'method': done.method}),
            style: AppText.body()),
        const SizedBox(height: 2),
        _bigFigure(formatPeso(due)),
      ];
    }
    if (change < 0.005) {
      // A big ₱0.00 reads, at a glance, like "something is owed".
      return [
        Text(tr('Change to give'), style: AppText.body()),
        const SizedBox(height: 2),
        _bigFigure(tr('No change'), color: AppColors.body),
        const SizedBox(height: 6),
        Text(tr('{amount} paid exactly', {'amount': formatPeso(received)}),
            style: AppText.caption()),
      ];
    }
    return [
      Text(tr('Change to give'), style: AppText.body()),
      const SizedBox(height: 2),
      _bigFigure(formatPeso(change)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [for (final p in changeBreakdown(change)) _pieceChip(p)],
      ),
      const SizedBox(height: 10),
      Text(
        tr('{due} total · {received} received',
            {'due': formatPeso(due), 'received': formatPeso(received)}),
        style: AppText.caption(),
      ),
    ];
  }

  /// Where the customer's tab stands now. Seen here, at the counter, rather
  /// than discovered on their next visit.
  List<Widget> _tabHero(Customer c) {
    final limit = creditLimitFor(c);
    final over = isOverLimit(c);
    final tone = over ? AppColors.warningText : AppColors.ink;
    return [
      Text(tr("Added to {name}'s tab", {'name': c.name}),
          textAlign: TextAlign.center, style: AppText.body()),
      const SizedBox(height: 2),
      _bigFigure(formatPeso(due)),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: over ? AppColors.warningFill : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
              color: over ? AppColors.warningBorder : AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr('{name} now owes', {'name': c.name}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body()),
                ),
                const SizedBox(width: 8),
                Text(formatPeso(c.balance), style: AppText.cardTitle(color: tone)),
              ],
            ),
            if (limit > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (c.balance / limit).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: AppColors.divider,
                  color: over ? AppColors.warning : AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                over
                    ? tr('Over the {limit} limit by {amount}', {
                        'limit': formatPeso(limit),
                        'amount': formatPeso(c.balance - limit),
                      })
                    : tr('{left} left of the {limit} limit', {
                        'left': formatPeso(limit - c.balance),
                        'limit': formatPeso(limit),
                      }),
                style: AppText.caption(
                    color: over ? AppColors.warningText : AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _bigFigure(String text, {Color color = AppColors.ink}) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          style: AppText.heroFigure(color: color).copyWith(fontSize: 46),
        ),
      );

  /// Bills in blue, coins in amber — the split a hand reaches for first.
  Widget _pieceChip(ChangePiece p) {
    final money = p.centavos >= 100
        ? formatPeso(p.value).replaceAll('.00', '')
        : '${p.centavos}¢';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.isBill ? AppColors.primaryTint : AppColors.warningFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        p.count > 1 ? '$money ×${p.count}' : money,
        style: AppText.chip(
            color: p.isBill ? AppColors.primaryPressed : AppColors.warningText),
      ),
    );
  }

  /// What was sold, so the customer can check it before walking off. Long
  /// baskets fold after a few lines; the reference sits here because it is
  /// for disputes, not for reading at the counter.
  Widget _itemsCard() {
    const folded = 4;
    final count = lines.fold<int>(0, (s, l) => s + l.qty);
    // Folding away a single line saves nothing.
    final shown = _showAll || lines.length <= folded + 1
        ? lines
        : lines.take(folded).toList();
    final hidden = lines.length - shown.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.cardPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(trCount(count, '{n} item', '{n} items'),
                  style: AppText.caption()),
              const Spacer(),
              Text(done.reference, style: AppText.mono()),
            ],
          ),
          const SizedBox(height: 10),
          for (final l in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${l.qty} × ${l.product.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(formatPeso(l.lineTotal), style: AppText.cardTitle()),
                ],
              ),
            ),
          if (hidden > 0)
            InkWell(
              onTap: () => setState(() => _showAll = true),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  trCount(hidden, '+{n} more item', '+{n} more items'),
                  style: AppText.chip(color: AppColors.primary),
                ),
              ),
            ),
          const SizedBox(height: 6),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          // A senior or PWD discount is itemised: the customer may be asked
          // to show it was applied, not just a smaller number.
          if (done.hasDiscount) ...[
            _receiptRow(tr('Subtotal'), formatPeso(done.subtotal)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(done.discountLabel,
                      style: AppText.body(color: AppColors.successText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                Text('-${formatPeso(done.discountAmount)}',
                    style: AppText.cardTitle(color: AppColors.successText)),
              ],
            ),
            const SizedBox(height: 6),
          ],
          _receiptRow(tr('Total'), formatPeso(due)),
        ],
      ),
    );
  }

  Widget _actions() {
    final hasPrinter = PrinterService.instance.hasPrinter;
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, CheckoutOutcome.completed),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.cta),
              ),
            ),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(
              tr('New sale'),
              style: AppText.chip(color: Colors.white).copyWith(fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              // With no printer chosen, Print used to fail with a message
              // pointing at Settings. Now it goes there.
              child: hasPrinter
                  ? _secondaryBtn(
                      _printing ? tr('Printing…') : tr('Print receipt'),
                      Icons.print_outlined,
                      _printing ? null : _print,
                    )
                  : _secondaryBtn(
                      tr('Set up printer'),
                      Icons.print_outlined,
                      _setUpPrinter,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _secondaryBtn(
                tr('Share'),
                Icons.ios_share_rounded,
                () => SharePlus.instance.share(
                  ShareParams(
                    text: buildReceipt(),
                    subject:
                        '${SettingsService.instance.storeName} · ${done.reference}',
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _setUpPrinter() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrinterScreen()),
    );
    // Back with a printer: the button becomes Print for this same sale.
    if (mounted) setState(() {});
  }

  Widget _receiptRow(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: AppText.body()),
      Text(value, style: AppText.cardTitle()),
    ],
  );

  Widget _secondaryBtn(String label, IconData icon, VoidCallback? onTap) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.body,
          side: const BorderSide(color: AppColors.hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label, style: AppText.chip(color: AppColors.body)),
      ),
    );
  }
}
