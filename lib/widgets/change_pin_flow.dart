import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../models/staff.dart';
import '../services/staff_service.dart';
import 'pin_sheet.dart';

/// Why the change is being asked for, which decides whether it can be refused.
enum ChangePinReason {
  /// The shopkeeper chose to change a PIN. Cancelling is fine.
  chosen,

  /// The PIN is still the one printed in the source, and the person is about
  /// to use it to authorise something. Cancelling abandons that action.
  stillDefault,
}

/// Collects a new PIN and saves it. Returns true only if it was changed.
///
/// Shared by the roster screen and by the forced change in front of a
/// manager-only action, so both ask in exactly the same way — including the
/// confirm-twice step, without which a mistyped PIN locks somebody out of
/// their own till and is only discovered at the next sign-in.
Future<bool> runChangePinFlow(
  BuildContext context, {
  required StaffService staff,
  required Staff person,
  ChangePinReason reason = ChangePinReason.chosen,
  bool alreadyAuthorised = false,
}) async {
  if (!alreadyAuthorised) {
    final ok = await PinSheet.show(
      context,
      verify: (pin) => staff.verifyPinOrManager(person.id!, pin),
      title: "Change ${person.name}'s PIN",
      hint: "Enter ${person.name}'s current PIN, or a manager PIN.",
      confirmLabel: 'Continue',
      avatarInitials: person.initials,
    );
    if (!ok || !context.mounted) return false;
  }

  if (reason == ChangePinReason.stillDefault) {
    final understood = await _explainWhy(context, person);
    if (!understood || !context.mounted) return false;
  }

  final fresh = await PinSheet.capture(
    context,
    title: 'New PIN',
    hint: 'Choose four digits for ${person.name}.',
    confirmLabel: 'Continue',
    avatarInitials: person.initials,
  );
  if (fresh == null || !context.mounted) return false;

  final again = await PinSheet.capture(
    context,
    title: 'Repeat the PIN',
    hint: 'Enter it once more to be sure.',
    confirmLabel: 'Save PIN',
    avatarInitials: person.initials,
  );
  if (again == null || !context.mounted) return false;

  if (fresh != again) {
    _toast(context, 'Those two PINs did not match. Nothing was changed.');
    return false;
  }

  try {
    await staff.setPin(person.id!, fresh);
  } on StaffValidationException catch (e) {
    if (context.mounted) _toast(context, e.message);
    return false;
  }
  if (context.mounted) _toast(context, "${person.name}'s PIN was changed");
  return true;
}

/// Says plainly why the app is interrupting, rather than demanding a new PIN
/// with no reason given.
Future<bool> _explainWhy(BuildContext context, Staff person) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Change this PIN first',
          style: AppText.sectionTitle().copyWith(fontSize: 17)),
      content: Text(
        '${person.name} is still using the code the app shipped with. That code '
        'is public — anyone who has seen this app knows it. Pick a new one '
        'before authorising anything with it.',
        style: AppText.body(),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Not now', style: AppText.chip(color: AppColors.body)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Choose a PIN', style: AppText.chip(color: AppColors.primary)),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    backgroundColor: AppColors.ink,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    content: Text(message, style: const TextStyle(color: Colors.white)),
  ));
}

/// Runs a manager gate, and makes a manager still on the shipped code change
/// it before their authorisation counts.
///
/// Returns true only if a manager authorised *and* is no longer on a default.
/// Placing the friction here rather than at startup ties it to the moment the
/// privilege is actually used: a new till can still ring up sales on day one,
/// but nobody closes a shift on `2468`.
Future<bool> authoriseAsManager(
  BuildContext context, {
  required StaffService staff,
  required String hint,
  required String confirmLabel,
}) async {
  final manager = await PinSheet.authorise(
    context,
    verify: staff.verifyManagerPin,
    title: 'Manager PIN',
    hint: hint,
    confirmLabel: confirmLabel,
  );
  if (manager == null || !context.mounted) return false;
  if (!manager.onStartingPin) return true;

  return runChangePinFlow(
    context,
    staff: staff,
    person: manager,
    reason: ChangePinReason.stillDefault,
    alreadyAuthorised: true,
  );
}
