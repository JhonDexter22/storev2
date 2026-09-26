import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/design_tokens.dart';
import '../l10n/tr.dart';
import '../services/settings_service.dart';
import '../services/staff_service.dart';
import '../widgets/language_switch.dart';
import '../widgets/pin_sheet.dart';
import '../widgets/restore_flow.dart';

/// Shows [SetupScreen] until it is finished, then [child].
///
/// Holds its own "finished" flag rather than reading the saved one: setup is
/// recorded as done before its last screen, so that closing the app on "You're
/// ready" does not run it a second time — and the last screen still has to be
/// seen.
class FirstRunGate extends StatefulWidget {
  const FirstRunGate({super.key, required this.child});

  final Widget child;

  @override
  State<FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<FirstRunGate> {
  bool _finished = false;

  @override
  Widget build(BuildContext context) => _finished
      ? widget.child
      : SetupScreen(onFinished: () => setState(() => _finished = true));
}

enum _Step { welcome, store, owner, cash, done }

/// The few things a new till has to know before it can be trusted with a
/// day's takings: what the store is called, who runs it (with a PIN nobody
/// else knows), and how much change the drawer opens with.
///
/// Everything else has a sensible default and lives in Settings. Products are
/// deliberately not a step: the Products screen is where they are added, and
/// setup ends there.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.onFinished, this.staff});

  final VoidCallback? onFinished;

  /// Injectable for tests.
  final StaffService? staff;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _settings = SettingsService.instance;
  late final StaffService _staff = widget.staff ?? StaffService();

  _Step _step = _Step.welcome;
  bool _busy = false;

  final _storeName = TextEditingController();
  final _ownerName = TextEditingController();
  late final _float = TextEditingController(text: _plain(_settings.openingFloat));

  /// The amount step follows the PIN sheet, and a field that autofocuses
  /// while a sheet is still closing loses the focus back to the sheet's
  /// caller — so this one is asked for explicitly.
  final _floatFocus = FocusNode();

  /// Held only until setup is saved, then hashed by [StaffService].
  String? _pin;

  @override
  void initState() {
    super.initState();
    for (final c in [_storeName, _ownerName, _float]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _storeName.dispose();
    _ownerName.dispose();
    _float.dispose();
    _floatFocus.dispose();
    super.dispose();
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  double? get _floatValue {
    final v = double.tryParse(_float.text.replaceAll(',', '').trim());
    return v == null || v < 0 ? null : v;
  }

  void _go(_Step step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
  }

  void _back() {
    if (_busy) return;
    switch (_step) {
      case _Step.store:
        _go(_Step.welcome);
      case _Step.owner:
        _go(_Step.store);
      case _Step.cash:
        _go(_Step.owner);
      case _Step.welcome:
      case _Step.done:
        break;
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
      ));
  }

  /// A new phone replacing a lost or broken one: the books come back first,
  /// and the rest of setup confirms what came with them.
  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final done = await runRestoreFlow(context);
      if (done == null || !mounted) return;
      if (done.hadSettings) {
        _storeName.text = _settings.storeName;
        _float.text = _plain(_settings.openingFloat);
      }
      _toast(tr('Restored {n} rows. Now check the details below.', {'n': done.rows}));
      _go(_Step.store);
    } catch (e) {
      if (mounted) _toast(tr('Could not restore: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks for the PIN twice, the same way changing one does: a typo here
  /// would lock the owner out of their own till on day one.
  Future<void> _choosePin() async {
    final initials = _ownerName.text.trim().isEmpty
        ? null
        : _ownerName.text.trim()[0].toUpperCase();
    final first = await PinSheet.capture(
      context,
      title: tr('Your PIN'),
      hint: tr('Four digits only you know. Keep it off the counter.'),
      confirmLabel: tr('Continue'),
      avatarInitials: initials,
    );
    if (first == null || !mounted) return;
    final again = await PinSheet.capture(
      context,
      title: tr('Repeat the PIN'),
      hint: tr('Enter it once more to be sure.'),
      confirmLabel: tr('Save PIN'),
      avatarInitials: initials,
    );
    if (again == null || !mounted) return;
    if (first != again) {
      _toast(tr('Those two PINs did not match. Try again.'));
      return;
    }
    setState(() => _pin = first);
    _go(_Step.cash);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _step == _Step.cash) _floatFocus.requestFocus();
    });
  }

  /// Saves everything at once, at the end, so backing out halfway leaves the
  /// install exactly as it was.
  Future<void> _finish() async {
    final float = _floatValue;
    final pin = _pin;
    if (float == null || pin == null) return;

    setState(() => _busy = true);
    try {
      final owner = await _staff.claimStore(name: _ownerName.text, pin: pin);
      await _settings.setStoreName(_storeName.text);
      await _settings.setOpeningFloat(float);
      await _settings.setCashier(owner.name);
      await _settings.markSetupDone();
      _pin = null;
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _go(_Step.done);
    } on StaffValidationException catch (e) {
      if (!mounted) return;
      _toast(e.message);
      _go(_Step.owner);
    } catch (e) {
      if (mounted) _toast(tr('Could not save: {error}', {'error': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              // A tablet gets a column, not a form stretched across the room.
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 20, bottom: 16),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: KeyedSubtree(
                            key: ValueKey(_step),
                            child: _body(),
                          ),
                        ),
                      ),
                    ),
                    ..._actions(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Back and "Step n of 3" on the three questions; nothing on the welcome
  /// and the finish, which are not steps anyone needs to count.
  Widget _topBar() {
    final n = switch (_step) {
      _Step.store => 1,
      _Step.owner => 2,
      _Step.cash => 3,
      _ => 0,
    };
    if (n == 0) return const SizedBox(height: 38);
    return Row(
      children: [
        Semantics(
          button: true,
          label: tr('Back'),
          child: GestureDetector(
            onTap: _back,
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
        ),
        const Spacer(),
        for (var i = 1; i <= 3; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(left: 6),
            width: i == n ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i <= n ? AppColors.primary : AppColors.hairline,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
          ),
        const SizedBox(width: 10),
        Text(tr('Step {n} of {total}', {'n': n, 'total': 3}),
            style: AppText.caption()),
      ],
    );
  }

  Widget _body() => switch (_step) {
        _Step.welcome => _welcome(),
        _Step.store => _question(
            title: tr('What is your store called?'),
            detail: tr('It goes at the top of every receipt. You can change it later in Settings.'),
            field: _field(
              _storeName,
              hint: tr("e.g. Aling Nena's Store"),
              capitalization: TextCapitalization.words,
              onDone: _storeName.text.trim().isEmpty ? null : () => _go(_Step.owner),
            ),
          ),
        _Step.owner => _question(
            title: tr('Who runs the store?'),
            detail: tr('You will be the manager. Your PIN closes the day, approves refunds and discounts, and adds cashiers.'),
            field: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(
                  _ownerName,
                  hint: tr('Your name'),
                  capitalization: TextCapitalization.words,
                ),
                if (_pin != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(tr('PIN chosen'),
                              style: AppText.body(color: AppColors.successText))),
                      TextButton(
                        onPressed: _choosePin,
                        child: Text(tr('Change PIN'),
                            style: AppText.chip(color: AppColors.primary)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        _Step.cash => _question(
            title: tr('Cash in the drawer to start'),
            detail: tr('The change you open with each day. Closing the day counts from this amount.'),
            field: _field(
              _float,
              focus: _floatFocus,
              prefix: '₱ ',
              keyboard: const TextInputType.numberWithOptions(decimal: true),
              formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            ),
          ),
        _Step.done => _done(),
      };

  Widget _welcome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 24),
        Text(tr('Welcome'), style: AppText.screenTitle().copyWith(fontSize: 30)),
        const SizedBox(height: 8),
        Text(tr("Let's get your store ready. It takes about a minute."),
            style: AppText.body().copyWith(fontSize: 14, height: 1.4)),
        const SizedBox(height: 28),
        Text(tr('Language'), style: AppText.overline(color: AppColors.muted)),
        const SizedBox(height: 8),
        const LanguageSwitch(),
      ],
    );
  }

  Widget _question({
    required String title,
    required String detail,
    required Widget field,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppText.screenTitle()),
        const SizedBox(height: 8),
        Text(detail, style: AppText.body().copyWith(fontSize: 13.5, height: 1.4)),
        const SizedBox(height: 24),
        field,
      ],
    );
  }

  Widget _field(
    TextEditingController controller, {
    FocusNode? focus,
    String? hint,
    String? prefix,
    TextCapitalization capitalization = TextCapitalization.none,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    VoidCallback? onDone,
  }) {
    return TextField(
      controller: controller,
      focusNode: focus,
      autofocus: true,
      textCapitalization: capitalization,
      keyboardType: keyboard,
      inputFormatters: formatters,
      maxLength: 40,
      style: AppText.cardTitle().copyWith(fontSize: 17),
      onSubmitted: onDone == null ? null : (_) => onDone(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppText.cardTitle(color: AppColors.faint).copyWith(fontSize: 17),
        prefixText: prefix,
        prefixStyle: AppText.cardTitle(color: AppColors.body).copyWith(fontSize: 17),
        counterText: '',
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _done() {
    final owner = _ownerName.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.successFill,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: AppColors.success, size: 34),
          ),
        ),
        const SizedBox(height: 24),
        Text(tr("You're ready, {name}", {'name': owner}),
            style: AppText.screenTitle()),
        const SizedBox(height: 8),
        Text(
          tr('Next, add what you sell — a name and a price are enough to start. Cashiers can be added any time from More.'),
          style: AppText.body().copyWith(fontSize: 13.5, height: 1.4),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            children: [
              _summaryRow(tr('Store'), _settings.storeName),
              const Divider(color: AppColors.divider, height: 1),
              _summaryRow(tr('Manager'), owner),
              const Divider(color: AppColors.divider, height: 1),
              _summaryRow(tr('Opening cash'), formatPeso(_settings.openingFloat)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Text(label, style: AppText.body()),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                style: AppText.cardTitle(),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  List<Widget> _actions() {
    return switch (_step) {
      _Step.welcome => [
          _primary(tr('Set up my store'), () => _go(_Step.store)),
          const SizedBox(height: 4),
          SizedBox(
            height: 46,
            child: TextButton(
              onPressed: _busy ? null : _restore,
              child: Text(
                _busy ? tr('Restoring…') : tr('Moving from another phone? Restore a backup'),
                style: AppText.chip(color: AppColors.primary),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      _Step.store => [
          _primary(tr('Next'),
              _storeName.text.trim().isEmpty ? null : () => _go(_Step.owner)),
        ],
      _Step.owner => [
          _primary(
            _pin == null ? tr('Choose a PIN') : tr('Next'),
            _ownerName.text.trim().isEmpty
                ? null
                : _pin == null
                    ? _choosePin
                    : () => _go(_Step.cash),
          ),
        ],
      _Step.cash => [
          _primary(_busy ? tr('Saving…') : tr('Finish setup'),
              _floatValue == null || _busy ? null : _finish),
        ],
      _Step.done => [
          _primary(tr('Add my products'), widget.onFinished),
        ],
    };
  }

  Widget _primary(String label, VoidCallback? onPressed) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.disabledFill,
          disabledForegroundColor: AppColors.muted,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.cta)),
        ),
        child: Text(label,
            style: AppText.chip(color: onPressed == null ? AppColors.muted : Colors.white)
                .copyWith(fontSize: 15)),
      ),
    );
  }
}
