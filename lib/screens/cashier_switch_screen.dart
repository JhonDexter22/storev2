import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/staff.dart';
import '../services/pin_hasher.dart';
import '../services/settings_service.dart';
import '../services/staff_service.dart';
import '../widgets/change_pin_flow.dart';
import '../widgets/pin_sheet.dart';

/// Cashier switch — record who is on the till, and who may close it.
///
/// A store this size has three people, not a directory, so this is a pick list
/// rather than a username field. The list and the codes behind it come from
/// the database; nothing here knows a PIN.
class CashierSwitchScreen extends StatefulWidget {
  const CashierSwitchScreen({super.key, this.staffService});

  /// Injectable so tests can drive the roster without a database.
  final StaffService? staffService;

  @override
  State<CashierSwitchScreen> createState() => _CashierSwitchScreenState();
}

class _CashierSwitchScreenState extends State<CashierSwitchScreen> {
  final _settings = SettingsService.instance;
  late final StaffService _staff = widget.staffService ?? StaffService();

  List<Staff> _roster = [];
  bool _loading = true;

  List<Staff> get _onStartingPin =>
      _roster.where((p) => p.onStartingPin).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final roster = await _staff.roster();
    if (!mounted) return;
    setState(() {
      _roster = roster;
      _loading = false;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text(message, style: const TextStyle(color: Colors.white)),
    ));
  }

  Future<void> _pick(Staff person) async {
    if (person.name == _settings.cashier) return;
    final ok = await PinSheet.show(
      context,
      verify: (pin) => _staff.verifyPin(person.id!, pin),
      title: person.name,
      hint: 'Enter ${person.name}\'s code to sign in.',
      confirmLabel: 'Sign in',
      avatarInitials: person.initials,
      subtitle: 'Enter ${person.name}\'s code to sign in.',
    );
    if (!ok || !mounted) return;
    await _settings.setCashier(person.name);
    if (!mounted) return;
    setState(() {});
    _toast('${person.name} is signed in');
  }

  /// Adding someone who can then ring up sales is a manager's decision, so it
  /// goes behind the same gate as closing a shift.
  Future<void> _addCashier() async {
    final authorised = await authoriseAsManager(
      context,
      staff: _staff,
      hint: 'Enter a manager PIN to add someone to the roster.',
      confirmLabel: 'Continue',
    );
    if (!authorised || !mounted) return;
    await _load();
    if (!mounted) return;

    final draft = await showModalBottomSheet<_NewStaff>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCashierSheet(),
    );
    if (draft == null || !mounted) return;

    try {
      await _staff.addStaff(
        name: draft.name,
        role: draft.isManager ? 'Manager' : 'Cashier',
        pin: draft.pin,
        isManager: draft.isManager,
      );
    } on StaffValidationException catch (e) {
      if (!mounted) return;
      _toast(e.message);
      return;
    }
    await _load();
    if (!mounted) return;
    _toast('${draft.name} was added to the roster');
  }

  /// Rotates someone off their current code.
  ///
  /// Authorised by that person's own PIN or any manager's: a cashier changes
  /// their own without involving anyone, and a manager can reset one for
  /// somebody who has forgotten it.
  Future<void> _changePin(Staff person) async {
    final changed =
        await runChangePinFlow(context, staff: _staff, person: person);
    if (changed && mounted) await _load();
  }

  /// Picks who to act on, then what to do with them.
  Future<void> _manageStaff() async {
    final person = await showModalBottomSheet<Staff>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(AppSpace.sheetPad, 14, AppSpace.sheetPad,
            20 + MediaQuery.of(ctx).padding.bottom),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('Manage staff',
                  style: AppText.sectionTitle().copyWith(fontSize: 18)),
              const SizedBox(height: 12),
              for (final person in _roster)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => Navigator.pop(ctx, person),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.canvas,
                    child: Text(person.initials,
                        style: AppText.statFigure(color: AppColors.body, size: 14)),
                  ),
                  title: Text(person.name, style: AppText.cardTitle()),
                  subtitle: Text(
                    person.onStartingPin
                        ? '${person.role} · still on the starting code'
                        : person.role,
                    style: AppText.caption(
                        color: person.onStartingPin
                            ? AppColors.warningText
                            : AppColors.muted),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: AppColors.faint, size: 20),
                ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (person == null || !mounted) return;
    await _actionsFor(person);
  }

  /// What can be done to one person.
  Future<void> _actionsFor(Staff person) async {
    final signedIn = person.name == _settings.cashier;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(AppSpace.sheetPad, 14, AppSpace.sheetPad,
            20 + MediaQuery.of(ctx).padding.bottom),
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
                    color: AppColors.hairline,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(person.name, style: AppText.sectionTitle().copyWith(fontSize: 18)),
            const SizedBox(height: 2),
            Text(person.role, style: AppText.caption()),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.pop(ctx, 'pin'),
              leading: const Icon(Icons.password_rounded,
                  size: 20, color: AppColors.body),
              title: Text('Change PIN', style: AppText.cardTitle()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: signedIn ? null : () => Navigator.pop(ctx, 'remove'),
              enabled: !signedIn,
              leading: Icon(Icons.person_remove_alt_1_rounded,
                  size: 20,
                  color: signedIn ? AppColors.faint : AppColors.dangerText),
              title: Text('Remove from roster',
                  style: AppText.cardTitle(
                      color: signedIn ? AppColors.faint : AppColors.dangerText)),
              subtitle: Text(
                signedIn
                    ? 'Sign in as someone else first.'
                    : 'They keep their place in past sales and shifts.',
                style: AppText.caption(),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'pin') return _changePin(person);
    await _removeStaff(person);
  }

  /// Takes someone off the till.
  ///
  /// A roster change, so it goes behind the same manager gate as adding.
  /// [StaffService.deactivate] keeps the row, so shifts and sales already
  /// recorded against the name still point at a real person — what stops is
  /// their ability to sign in.
  Future<void> _removeStaff(Staff person) async {
    final authorised = await authoriseAsManager(
      context,
      staff: _staff,
      hint: 'Enter a manager PIN to remove ${person.name}.',
      confirmLabel: 'Continue',
    );
    if (!authorised || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove ${person.name}?',
            style: AppText.sectionTitle().copyWith(fontSize: 17)),
        content: Text(
          '${person.name} will no longer be able to sign in or ring up sales. '
          'Their past sales and shifts are kept.',
          style: AppText.body(),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep them', style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: AppText.chip(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _staff.deactivate(person.id!);
    } on StaffValidationException catch (e) {
      if (!mounted) return;
      _toast(e.message);
      return;
    }
    await _load();
    if (!mounted) return;
    _toast('${person.name} was removed from the roster');
  }

  @override
  Widget build(BuildContext context) {
    final active = _settings.cashier;
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
                ],
              ),
              const SizedBox(height: 18),
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                  child: Text('Sign in to the till',
                      style: AppText.screenTitle().copyWith(fontSize: 22))),
              const SizedBox(height: 4),
              Center(child: Text('$active is signed in', style: AppText.caption())),
              const SizedBox(height: AppSpace.gapBlock),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                )
              else
                for (final person in _roster) ...[
                  _personCard(person, person.name == active),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 4),
              if (!_loading && _onStartingPin.isNotEmpty) ...[
                _startingPinWarning(),
                const SizedBox(height: 10),
              ],
              _notice(),
              const SizedBox(height: AppSpace.gapSection),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _manageStaff,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.body,
                    side: const BorderSide(color: AppColors.hairline),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.cta)),
                  ),
                  icon: const Icon(Icons.manage_accounts_rounded, size: 17),
                  label: Text('Manage staff', style: AppText.chip(color: AppColors.body)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _addCashier,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.body,
                    side: const BorderSide(color: AppColors.hairline),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.cta)),
                  ),
                  icon: const Icon(Icons.person_add_alt_rounded, size: 17),
                  label: Text('Add a cashier', style: AppText.chip(color: AppColors.body)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _personCard(Staff person, bool active) {
    return GestureDetector(
      onTap: () => _pick(person),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.cardPad),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryTint : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.hairline,
            width: active ? 1.5 : 1,
          ),
          boxShadow: active ? null : AppShadows.card,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.canvas,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                person.initials,
                style: AppText.statFigure(
                  color: active ? Colors.white : AppColors.body,
                  size: 16,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(person.name, style: AppText.cardTitle().copyWith(fontSize: 15)),
                      if (person.isManager) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.muted),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    active ? '${person.role} · Signed in' : person.role,
                    style: AppText.caption(color: active ? AppColors.primary : AppColors.muted),
                  ),
                ],
              ),
            ),
            if (active)
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 15),
              ),
          ],
        ),
      ),
    );
  }

  /// Names anyone still on a code that ships in the source, so "change it"
  /// is a specific instruction rather than general advice.
  Widget _startingPinWarning() {
    final names = _onStartingPin.map((p) => p.name).toList();
    final who = names.length == 1
        ? names.single
        : '${names.take(names.length - 1).join(', ')} and ${names.last}';
    final verb = names.length == 1 ? 'is' : 'are';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$who $verb still on the starting PIN',
                    style: AppText.cardTitle(color: AppColors.warningText)
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  'Those codes ship with the app, so anyone who has seen it '
                  'knows them. Change them below.',
                  style: AppText.caption(color: AppColors.warningText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice() {
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
              'Sales, voids and closes are recorded against whoever is signed in.',
              style: AppText.caption(),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the add sheet collects. The PIN is handed straight to [StaffService]
/// and never stored anywhere else.
class _NewStaff {
  const _NewStaff({required this.name, required this.pin, required this.isManager});
  final String name;
  final String pin;
  final bool isManager;
}

class _AddCashierSheet extends StatefulWidget {
  const _AddCashierSheet();

  @override
  State<_AddCashierSheet> createState() => _AddCashierSheetState();
}

class _AddCashierSheetState extends State<_AddCashierSheet> {
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isManager = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    if (!PinHasher.isWellFormed(_pinCtrl.text)) {
      setState(() => _error = 'The PIN has to be four digits.');
      return;
    }
    // Caught here rather than after saving: a mistyped PIN that is only found
    // out at the next sign-in means nobody can get in.
    if (_pinCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'The two PINs do not match.');
      return;
    }
    Navigator.pop(
      context,
      _NewStaff(name: name, pin: _pinCtrl.text, isManager: _isManager),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.sheetPad,
        14,
        AppSpace.sheetPad,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
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
            Text('Add a cashier', style: AppText.sectionTitle().copyWith(fontSize: 18)),
            const SizedBox(height: 2),
            Text('They will be able to ring up sales under their own name.',
                style: AppText.caption()),
            const SizedBox(height: 18),
            _label('Name'),
            _field(_nameCtrl, hint: 'e.g. Ana', keyboard: TextInputType.name),
            const SizedBox(height: 14),
            _label('PIN'),
            _field(_pinCtrl, hint: '4 digits', obscure: true, maxLength: 4),
            const SizedBox(height: 14),
            _label('Confirm PIN'),
            _field(_confirmCtrl, hint: 'Repeat it', obscure: true, maxLength: 4),
            const SizedBox(height: 14),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isManager,
              activeThumbColor: AppColors.primary,
              onChanged: (v) => setState(() => _isManager = v),
              title: Text('Can close a shift', style: AppText.body()),
              subtitle: Text('Managers authorise closes and roster changes.',
                  style: AppText.caption()),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: AppText.caption(color: AppColors.dangerText)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                child: Text('Add to roster',
                    style: AppText.chip(color: Colors.white).copyWith(fontSize: 15)),
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: AppText.body()),
      );

  Widget _field(
    TextEditingController controller, {
    required String hint,
    bool obscure = false,
    int? maxLength,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      maxLength: maxLength,
      keyboardType: obscure ? TextInputType.number : keyboard,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      style: AppText.body(color: AppColors.ink),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle: AppText.caption(),
        filled: true,
        fillColor: AppColors.canvas,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
    );
  }
}
