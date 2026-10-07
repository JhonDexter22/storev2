import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/payment_type.dart';
import '../services/settings_service.dart';
import '../l10n/tr.dart';

/// Which ways a customer can pay.
///
/// Plenty of sari-sari stores never take a card, and a Card button at the till
/// that is never pressed is clutter in the one place that has to be fast.
/// Switching a type off only changes what is offered — sales already taken
/// keep their method and still refund.
class PaymentTypesScreen extends StatefulWidget {
  const PaymentTypesScreen({super.key});

  @override
  State<PaymentTypesScreen> createState() => _PaymentTypesScreenState();
}

class _PaymentTypesScreenState extends State<PaymentTypesScreen> {
  final _settings = SettingsService.instance;

  /// Says what is wrong inside the sheet and stays open: it used to close on
  /// any Add and report afterwards — an empty box included, as "That name is
  /// already in the list", which it was not.
  Future<void> _add() async {
    final controller = TextEditingController();
    String? error;
    final name = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final typed = controller.text.trim();
        void submit() {
          if (typed.isEmpty) return;
          if (_settings.hasPaymentType(typed)) {
            setSheet(() => error = tr('That name is already in the list.'));
            return;
          }
          Navigator.pop(ctx, typed);
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(AppSpace.sheetPad, 14, AppSpace.sheetPad,
              MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.sheetPad),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Add a payment type'),
                    style: AppText.sectionTitle().copyWith(fontSize: 18)),
                const SizedBox(height: 2),
                Text(tr('Maya, a bank transfer — whatever you actually take.'),
                    style: AppText.caption()),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  style: AppText.body(color: AppColors.ink),
                  onChanged: (_) => setSheet(() => error = null),
                  decoration: InputDecoration(
                    hintText: tr('e.g. Maya'),
                    hintStyle: AppText.caption(),
                    errorText: error,
                    filled: true,
                    fillColor: AppColors.canvas,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      borderSide: const BorderSide(color: AppColors.hairline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      borderSide: const BorderSide(color: AppColors.hairline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: typed.isEmpty ? null : submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.disabledFill,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.cta)),
                    ),
                    // Says what is missing while it cannot be pressed.
                    child: Text(typed.isEmpty ? tr('Enter a name') : tr('Add'),
                        style: AppText.chip(color: typed.isEmpty ? AppColors.muted : Colors.white)
                            .copyWith(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
    if (name == null || !mounted) return;

    final added = await _settings.addPaymentType(name);
    if (!mounted) return;
    setState(() {});
    if (!added) _toast(tr('That name is already in the list.'));
  }

  Future<void> _remove(PaymentType type) async {
    // Where it was and whether it was on, for Undo: the bin sits a thumb's
    // width from the switch, and a slip used to mean typing it in again.
    final at = _settings.allPaymentTypes.where((t) => !t.builtIn).toList().indexWhere((t) => t.name == type.name);
    final enabled = _settings.isPaymentTypeEnabled(type);
    await _settings.removePaymentType(type);
    if (!mounted) return;
    setState(() {});
    // Past sales keep the name, so this is a change to the till, not the books.
    _toast(
      tr('{name} removed. Sales already taken keep it.', {'name': type.name}),
      action: SnackBarAction(
        label: tr('Undo'),
        textColor: AppColors.primary,
        onPressed: () async {
          await _settings.restorePaymentType(type, at: at, enabled: enabled);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _toast(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        action: action,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final types = _settings.allPaymentTypes;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: Breakpoints.pagePadding(context, constraints.maxWidth),
            children: [
              Row(
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
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: AppColors.body, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(tr('Payment types'),
                      style: AppText.screenTitle().copyWith(fontSize: 22)),
                ],
              ),
              const SizedBox(height: 4),
              Text(tr('These are the buttons a cashier sees at checkout.'),
                  style: AppText.body()),
              const SizedBox(height: AppSpace.gapBlock),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.hairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (int i = 0; i < types.length; i++) ...[
                      _row(types[i]),
                      if (i != types.length - 1)
                        const Divider(color: AppColors.divider, height: 1),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.gapSection),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _add,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.body,
                    side: const BorderSide(color: AppColors.hairline),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.cta)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(tr('Add a payment type'),
                      style: AppText.chip(color: AppColors.body)),
                ),
              ),
              const SizedBox(height: AppSpace.gapSection),
              _note(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(PaymentType type) {
    final enabled = _settings.isPaymentTypeEnabled(type);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Icon(type.icon,
              size: 20, color: enabled ? AppColors.body : AppColors.faint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.name,
                    style: AppText.cardTitle(
                        color: enabled ? AppColors.ink : AppColors.faint)),
                if (!type.canBeDisabled)
                  Text(tr('Always available'), style: AppText.caption())
                else if (type.kind == PaymentKind.utang)
                  Text(tr('Puts the sale on a customer\'s tab'),
                      style: AppText.caption())
                else if (!type.builtIn)
                  Text(tr('Added by you'), style: AppText.caption()),
              ],
            ),
          ),
          if (!type.builtIn)
            IconButton(
              onPressed: () => _remove(type),
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.dangerText),
              tooltip: tr('Remove {name}', {'name': type.name}),
            ),
          // Cash gets a label, not a disabled switch. A greyed-out switch
          // reads as "off" at a glance, which is the opposite of the truth.
          if (!type.canBeDisabled)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: StatusPill(
                label: tr('On'),
                fg: AppColors.successText,
                bg: AppColors.successFill,
                dot: false,
              ),
            )
          else
            Switch.adaptive(
              value: enabled,
              activeThumbColor: AppColors.primary,
              onChanged: (v) async {
                await _settings.setPaymentTypeEnabled(type, v);
                if (mounted) setState(() {});
              },
            ),
        ],
      ),
    );
  }

  Widget _note() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('Switching one off only changes what the cashier is offered. Sales already taken keep their payment type and still refund.'),
              style: AppText.caption(),
            ),
          ),
        ],
      ),
    );
  }
}
