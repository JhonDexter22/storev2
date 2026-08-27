import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/cart_line.dart';
import '../services/sales_service.dart';

enum _PayMethod { cash, gcash, card }

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.lines});

  final List<CartLine> lines;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final SalesService _salesService = SalesService();
  _PayMethod _method = _PayMethod.cash;
  double _received = 0;
  final _receivedCtrl = TextEditingController();
  bool _saving = false;
  _CompletedSale? _done;

  double get _due => widget.lines.fold(0, (s, l) => s + l.lineTotal);
  double get _change => (_received - _due).clamp(0, double.infinity);
  bool get _canComplete => _method != _PayMethod.cash || _received >= _due;

  @override
  void dispose() {
    _receivedCtrl.dispose();
    super.dispose();
  }

  void _setReceived(double v) {
    setState(() {
      _received = v;
      _receivedCtrl.text = v == 0 ? '' : v.toStringAsFixed(0);
    });
  }

  Future<void> _completeSale() async {
    if (!_canComplete || _saving) return;
    setState(() => _saving = true);
    final methodLabel = switch (_method) {
      _PayMethod.cash => 'Cash',
      _PayMethod.gcash => 'GCash',
      _PayMethod.card => 'Card',
    };
    final sale = await _salesService.recordSale(
      lines: widget.lines,
      paymentMethod: methodLabel,
      cashReceived: _method == _PayMethod.cash ? _received : _due,
      changeAmount: _method == _PayMethod.cash ? _change : 0,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _done = _CompletedSale(reference: sale.reference, method: methodLabel, time: DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done != null) return _SuccessView(done: _done!, due: _due, received: _received, change: _change);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _appBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 6, AppSpace.screenH, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _orderSummaryCard(),
                    const SizedBox(height: AppSpace.gapSection),
                    Text('Payment method', style: AppText.sectionTitle()),
                    const SizedBox(height: 10),
                    _paymentMethodRow(),
                    if (_method == _PayMethod.cash) ...[
                      const SizedBox(height: AppSpace.gapSection),
                      _cashReceivedCard(),
                      if (_received > 0 && _received < _due) ...[
                        const SizedBox(height: 10),
                        _notice(
                          'Cash received is less than the amount due.',
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
                  ],
                ),
              ),
            ),
            _ctaBar(),
          ],
        ),
      ),
    );
  }

  Widget _appBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 12, AppSpace.screenH, 8),
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
                Text('Checkout', style: AppText.sectionTitle().copyWith(fontSize: 18)),
                Text(
                  '${widget.lines.fold<int>(0, (s, l) => s + l.qty)} item${widget.lines.length == 1 ? '' : 's'}',
                  style: AppText.caption(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _orderSummaryCard() {
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
          for (final line in widget.lines) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.primaryTint, borderRadius: BorderRadius.circular(999)),
                  child: Text('×${line.qty}', style: AppText.chip(color: AppColors.primary)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(line.product.name, style: AppText.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Flexible(
                  child: Text(
                    formatPeso(line.lineTotal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: AppText.cardTitle(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Amount due', style: AppText.sectionTitle()),
              Text(formatPeso(_due), style: AppText.largeFigure().copyWith(fontSize: 21)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodRow() {
    Widget option(_PayMethod m, IconData icon, String label) {
      final selected = _method == m;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _method = m),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryTint : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: selected ? AppColors.primary : AppColors.hairline, width: selected ? 1.5 : 1),
            ),
            child: Column(
              children: [
                Icon(icon, size: 20, color: selected ? AppColors.primary : AppColors.body),
                const SizedBox(height: 6),
                Text(label, style: AppText.chip(color: selected ? AppColors.primary : AppColors.body)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(_PayMethod.cash, Icons.payments_outlined, 'Cash'),
        const SizedBox(width: 10),
        option(_PayMethod.gcash, Icons.qr_code_2_rounded, 'GCash'),
        const SizedBox(width: 10),
        option(_PayMethod.card, Icons.credit_card_rounded, 'Card'),
      ],
    );
  }

  Widget _cashReceivedCard() {
    final quick = [500.0, 1000.0];
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
          Text('Cash received', style: AppText.body()),
          const SizedBox(height: 8),
          TextField(
            controller: _receivedCtrl,
            keyboardType: TextInputType.number,
            style: AppText.largeFigure().copyWith(fontSize: 24),
            decoration: InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              hintText: '0',
              hintStyle: AppText.largeFigure(color: AppColors.faint).copyWith(fontSize: 24),
              prefixText: '₱ ',
              prefixStyle: AppText.largeFigure(color: AppColors.muted).copyWith(fontSize: 24),
            ),
            onChanged: (v) => setState(() => _received = double.tryParse(v) ?? 0),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final amount in quick) ...[
                _quickAmountChip('₱${amount.toInt()}', () => _setReceived(amount)),
                const SizedBox(width: 8),
              ],
              _quickAmountChip('Exact', () => _setReceived(_due)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickAmountChip(String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.canvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Text(label, style: AppText.chip()),
        ),
      ),
    );
  }

  Widget _notice(String text, Color fg, Color bg, Color border) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppText.caption(color: fg))),
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
          Text('Change', style: AppText.body(color: AppColors.successText)),
          Text(formatPeso(_change), style: AppText.largeFigure(color: AppColors.successText).copyWith(fontSize: 22)),
        ],
      ),
    );
  }

  Widget _ctaBar() {
    final label = _method == _PayMethod.cash ? 'Complete sale · ${formatPeso(_due)}' : 'Complete sale · ${formatPeso(_due)}';
    return Container(
      padding: EdgeInsets.fromLTRB(AppSpace.screenH, 12, AppSpace.screenH, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SizedBox(
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
          ),
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(label, style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
        ),
      ),
    );
  }
}

class _CompletedSale {
  _CompletedSale({required this.reference, required this.method, required this.time});
  final String reference;
  final String method;
  final DateTime time;
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.done, required this.due, required this.received, required this.change});

  final _CompletedSale done;
  final double due;
  final double received;
  final double change;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 32, AppSpace.screenH, 24),
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(color: AppColors.successFill, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: AppColors.success, size: 44),
              ),
              const SizedBox(height: 18),
              Text('Payment successful', style: AppText.sectionTitle().copyWith(fontSize: 19)),
              const SizedBox(height: 4),
              Text(
                '${done.method} · ${done.reference} · ${TimeOfDay.fromDateTime(done.time).format(context)}',
                style: AppText.caption(),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.cardPad),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  children: [
                    _receiptRow('Amount due', formatPeso(due)),
                    if (done.method == 'Cash') ...[
                      const SizedBox(height: 8),
                      _receiptRow('Received', formatPeso(received)),
                      const SizedBox(height: 8),
                      const Divider(color: AppColors.divider, height: 1),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Change', style: AppText.body()),
                          Text(formatPeso(change), style: AppText.largeFigure().copyWith(fontSize: 30)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                  ),
                  child: Text('New sale', style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _secondaryBtn('Print receipt', Icons.print_outlined, () {})),
                  const SizedBox(width: 10),
                  Expanded(child: _secondaryBtn('Share', Icons.ios_share_rounded, () {})),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body()),
          Text(value, style: AppText.cardTitle()),
        ],
      );

  Widget _secondaryBtn(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      height: 46,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.body,
          side: const BorderSide(color: AppColors.hairline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.input)),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label, style: AppText.chip(color: AppColors.body)),
      ),
    );
  }
}
