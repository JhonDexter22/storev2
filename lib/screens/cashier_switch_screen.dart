import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/staff.dart';
import '../services/settings_service.dart';
import '../widgets/pin_sheet.dart';

/// Cashier switch — record who is on the till, and who may close it.
///
/// A store this size has three people, not a directory, so this is a pick list
/// rather than a username field.
class CashierSwitchScreen extends StatefulWidget {
  const CashierSwitchScreen({super.key});

  @override
  State<CashierSwitchScreen> createState() => _CashierSwitchScreenState();
}

class _CashierSwitchScreenState extends State<CashierSwitchScreen> {
  final _settings = SettingsService.instance;

  Future<void> _pick(Staff person) async {
    if (person.name == _settings.cashier) return;
    final ok = await PinSheet.show(
      context,
      expectedPin: person.pin,
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text('${person.name} is signed in', style: const TextStyle(color: Colors.white)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final active = _settings.cashier;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.screenH, 12, AppSpace.screenH, 32),
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
            Center(child: Text('Sign in to the till', style: AppText.screenTitle().copyWith(fontSize: 22))),
            const SizedBox(height: 4),
            Center(child: Text('$active is signed in', style: AppText.caption())),
            const SizedBox(height: AppSpace.gapBlock),
            for (final person in Staff.roster) ...[
              _personCard(person, person.name == active),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            _notice(),
            const SizedBox(height: AppSpace.gapSection),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.ink,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    content: const Text('Staff management is not wired up yet',
                        style: TextStyle(color: Colors.white)),
                  ));
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.body,
                  side: const BorderSide(color: AppColors.hairline),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cta)),
                ),
                icon: const Icon(Icons.person_add_alt_rounded, size: 17),
                label: Text('Add a cashier', style: AppText.chip(color: AppColors.body)),
              ),
            ),
          ],
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
