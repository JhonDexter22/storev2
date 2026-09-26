import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import 'fil.dart';

/// The languages the app speaks.
enum AppLanguage {
  en('English', Locale('en')),
  fil('Filipino', Locale('fil'));

  const AppLanguage(this.label, this.locale);

  /// Shown in the picker in its own language, so someone who cannot read the
  /// current one can still find theirs.
  final String label;
  final Locale locale;

  static AppLanguage byName(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => en);
}

/// Translates a piece of UI text.
///
/// The English is the key: it reads naturally at the call site, and a string
/// with no Filipino entry yet simply shows in English rather than as a blank
/// or a key name. Placeholders are written `{name}` and filled from [args]:
///
///     tr('Added {n} · {name} now {after}', {'n': 5, 'name': p.name, 'after': 12})
///
/// Keys must be plain literals — no `$` interpolation — so the coverage test
/// can find every one of them in the source.
String tr(String en, [Map<String, Object?> args = const {}]) {
  final lang = SettingsService.instance.language;
  var out = lang == AppLanguage.fil ? (fil[en] ?? en) : en;
  if (args.isNotEmpty) {
    args.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
  }
  return out;
}

/// `1 item` / `3 items` in English; Filipino does not inflect the noun, so
/// both forms map to the same translation there.
String trCount(int n, String one, String many, [Map<String, Object?> args = const {}]) =>
    tr(n == 1 ? one : many, {'n': n, ...args});

/// Rebuilds the whole app in place when the language changes, so every
/// `tr()` call picks up the new language without losing the screen the
/// shopkeeper is on, the cart, or anything half-typed.
class LanguageScope extends StatefulWidget {
  const LanguageScope({super.key, required this.child});

  final Widget child;

  @override
  State<LanguageScope> createState() => _LanguageScopeState();
}

class _LanguageScopeState extends State<LanguageScope> {
  // Read now, not lazily: a `late` initialiser would first run inside
  // [_changed], after the switch, and never see a difference.
  late AppLanguage _lang;

  @override
  void initState() {
    super.initState();
    _lang = SettingsService.instance.language;
    SettingsService.instance.addListener(_changed);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final now = SettingsService.instance.language;
    if (now == _lang) return;
    _lang = now;
    // Most widgets calling tr() depend on nothing that changes with the
    // language, so an ordinary rebuild would skip them. Marking every element
    // dirty is a heavy hammer, but it runs once per language switch.
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

const _monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _monthsFil = ['Ene', 'Peb', 'Mar', 'Abr', 'May', 'Hun', 'Hul', 'Ago', 'Set', 'Okt', 'Nob', 'Dis'];

/// Short month name, 1-based.
String trMonth(int month) =>
    (SettingsService.instance.language == AppLanguage.fil ? _monthsFil : _monthsEn)[month - 1];

/// "21 Sep" / "21 Set".
String trDay(DateTime d) => '${d.day} ${trMonth(d.month)}';

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "Today", "Yesterday" or "21 Sep" — the day part of a timestamp as a
/// shopkeeper would say it.
String trRelativeDay(DateTime d) {
  final now = DateTime.now();
  if (_sameDay(d, now)) return tr('Today');
  if (_sameDay(d, now.subtract(const Duration(days: 1)))) return tr('Yesterday');
  return trDay(d);
}

/// "Today · 3:08 PM", "Yesterday · 9:14 AM", "21 Sep · 1:24 PM".
String trWhen(BuildContext context, DateTime d) =>
    '${trRelativeDay(d)} · ${TimeOfDay.fromDateTime(d).format(context)}';

const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _weekdaysFil = ['Lun', 'Mar', 'Miy', 'Huw', 'Biy', 'Sab', 'Lin'];

/// Short weekday name, DateTime.weekday numbering (1 = Monday).
String trWeekday(int weekday) =>
    (SettingsService.instance.language == AppLanguage.fil ? _weekdaysFil : _weekdaysEn)[weekday - 1];
