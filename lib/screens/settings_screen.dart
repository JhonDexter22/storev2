import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../models/staff.dart';
import '../services/settings_service.dart';
import '../services/shift_service.dart';
import '../services/utang_service.dart';
import 'cash_count_screen.dart';
import 'cashier_switch_screen.dart';
import 'reports_screen.dart';
import 'returns_screen.dart';
import 'shift_history_screen.dart';
import 'store_settings_screen.dart';
import 'utang_screen.dart';
import '../l10n/tr.dart';
import '../widgets/initials_avatar.dart';

/// The More hub: everything that is not one of the four main tabs.
///
/// Destinations are grouped by when a cashier reaches for them — what runs
/// every day, what happens at the counter, and what is set up once — rather
/// than listed flat. The rows that have a live number worth glancing at
/// (money owed, cash expected in the drawer) show it on the right so the hub
/// answers the common question without a tap.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onStartSale});

  /// Jumps to the POS tab — used by the Utang ledger's "Charge" CTA, which
  /// starts a sale to put on someone's tab.
  final VoidCallback? onStartSale;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Two columns of about a phone's width each.
  static const _tabletWidth = 920.0;

  // Not final: reloaded on the way back from any row, or closing the day in
  // Close day and taking a payment in Credit left them showing the old
  // figures until the tab was left and reopened.
  late Future<double> _owed = _loadOwed();
  late Future<double> _drawer = _loadDrawer();

  /// The figure Cash count and Home's tile call "Expected in drawer". The
  /// row used to show all sales this shift — GCash, card and utang included
  /// — beside a title that says cash.
  Future<double> _loadDrawer() async => (await ShiftService().drawerNow()).expected;

  Future<double> _loadOwed() async {
    final customers = await UtangService().getCustomers();
    return customers.fold<double>(0, (sum, c) => sum + (c.balance > 0 ? c.balance : 0));
  }

  String _todayLabel() => trDay(DateTime.now());

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    setState(() {
      _owed = _loadOwed();
      _drawer = _loadDrawer();
    });
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(tr('Lock the till?'), style: AppText.sectionTitle()),
        content: Text(
          tr('It stays locked until someone enters their code.'),
          style: AppText.body(),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Cancel'), style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Was only a shortcut to the switch screen, which Back left
              // with the same person still signed in. Now the till is locked
              // until someone enters their code — across a restart too.
              await SettingsService.instance.signOut();
              if (!mounted) return;
              await CashierSwitchScreen.showSignedOut(context);
            },
            child: Text(tr('Lock'), style: AppText.chip(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final settings = SettingsService.instance;

    final sections = <_Section>[
      _Section(
        // All three are about money; "Today" sat over Reports (up to 30
        // days) and Closed days (past days).
        title: tr('Money'),
        tint: AppColors.primaryTint,
        iconColor: AppColors.primary,
        items: [
          _MoreItem(
            icon: Icons.bar_chart_rounded,
            title: tr('Reports'),
            subtitle: tr('Revenue, top products, payment mix'),
            onTap: () => _open(const ReportsScreen()),
          ),
          _MoreItem(
            icon: Icons.payments_outlined,
            // The name Home's card and the screen itself use.
            title: tr('Close day'),
            subtitle: tr('Count and close the day'),
            trailing: _DrawerMeta(future: _drawer),
            onTap: () => _open(const CashCountScreen()),
          ),
          _MoreItem(
            icon: Icons.history_rounded,
            title: tr('Closed days'),
            subtitle: tr('Past days and drawer checks'),
            onTap: () => _open(const ShiftHistoryScreen()),
          ),
        ],
      ),
      _Section(
        title: tr('At the counter'),
        tint: AppColors.warningFill,
        iconColor: AppColors.warningText,
        items: [
          _MoreItem(
            icon: Icons.assignment_return_outlined,
            title: tr('Returns & voids'),
            subtitle: tr('Reverse a line or a whole sale'),
            onTap: () => _open(const ReturnsScreen()),
          ),
          _MoreItem(
            icon: Icons.receipt_long_outlined,
            title: tr('Credit'),
            subtitle: tr('Who owes, oldest first'),
            trailing: _OwedMeta(future: _owed),
            onTap: () => _open(UtangScreen(onCharge: widget.onStartSale)),
          ),
        ],
      ),
      _Section(
        title: tr('Store'),
        tint: AppColors.divider,
        iconColor: AppColors.body,
        items: [
          _MoreItem(
            icon: Icons.manage_accounts_outlined,
            title: tr('Staff'),
            subtitle: tr('Add cashiers, change PINs'),
            onTap: () => _open(const CashierSwitchScreen(openStaff: true)),
          ),
          _MoreItem(
            icon: Icons.settings_outlined,
            title: tr('Settings'),
            subtitle: tr('Receipts, alerts, backup'),
            onTap: () => _open(const StoreSettingsScreen()),
          ),
        ],
      ),
    ];

    final header = <Widget>[
      // Language lives in Settings only: a set-once choice, and a pill
      // up here was one stray tap from flipping the app mid-shift.
      Text(tr('More'), style: AppText.screenTitle()),
      const SizedBox(height: 16),
      _CashierCard(
        name: settings.cashier,
        // No terminal: a store with one phone never sees a second, and it
        // cut the line off on a phone. Day closes and receipts keep it.
        detail: '${settings.storeName} · ${_todayLabel()}',
        onSwitch: () => _open(const CashierSwitchScreen()),
      ),
      const SizedBox(height: 24),
    ];

    List<Widget> column(Iterable<_Section> list, {bool lock = false}) => [
          for (final s in list) ...[
            _SectionCard(section: s),
            const SizedBox(height: 20),
          ],
          if (lock) _LockRow(onTap: _confirmSignOut),
        ];

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Tablet: two columns, so the whole menu — Lock till included —
            // is on one screen, where a lone 720px column left it below the
            // fold with empty space either side.
            if (Breakpoints.isTablet(context)) {
              final side = ((constraints.maxWidth - _tabletWidth) / 2).clamp(24.0, double.infinity);
              return ListView(
                padding: EdgeInsets.fromLTRB(side, 24, side, 32),
                children: [
                  ...header,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Column(children: column(sections.take(1)))),
                      const SizedBox(width: 20),
                      Expanded(child: Column(children: column(sections.skip(1), lock: true))),
                    ],
                  ),
                ],
              );
            }
            return ListView(
              padding: Breakpoints.pagePadding(
                context,
                constraints.maxWidth,
                top: 24,
                // Clear the Sell button that rises out of the bottom bar.
                bottom: 32 + MediaQuery.paddingOf(context).bottom,
                phoneSide: 24,
              ),
              children: [...header, ...column(sections, lock: true)],
            );
          },
        ),
      ),
    );
  }
}

// ── Cashier card ───────────────────────────────────────────────────────────────
/// Who is on the till, where, and a one-tap way to hand over.
class _CashierCard extends StatelessWidget {
  const _CashierCard({required this.name, required this.detail, required this.onSwitch});

  final String name;
  final String detail;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          InitialsAvatar(Staff.initialsOf(name)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Signed in as'), style: AppText.caption()),
                const SizedBox(height: 2),
                Text(name, style: AppText.sectionTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                // The line opens with the store's name, which beside a
                // cashier's name read as a second person without the icon.
                Row(
                  children: [
                    const Icon(Icons.storefront_outlined, size: 14, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(detail,
                          style: AppText.caption(color: AppColors.body),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SwitchButton(onTap: onSwitch),
        ],
      ),
    );
  }
}

class _SwitchButton extends StatelessWidget {
  const _SwitchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr('Switch cashier'),
      child: Material(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_horiz_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(tr('Switch'), style: AppText.chip(color: AppColors.primary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sections ───────────────────────────────────────────────────────────────────
class _Section {
  const _Section({
    required this.title,
    required this.tint,
    required this.iconColor,
    required this.items,
  });

  final String title;
  final Color tint;
  final Color iconColor;
  final List<_MoreItem> items;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});

  final _Section section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            section.title.toUpperCase(),
            style: AppText.overline(color: AppColors.muted),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.hairline),
            boxShadow: AppShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < section.items.length; i++) ...[
                _MenuRow(
                  item: section.items[i],
                  tint: section.tint,
                  iconColor: section.iconColor,
                ),
                if (i != section.items.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 70),
                    child: Divider(color: AppColors.divider, height: 1),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MoreItem {
  const _MoreItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// A live figure shown before the chevron, if the row has one.
  final Widget? trailing;
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.tint, required this.iconColor});

  final _MoreItem item;
  final Color tint;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        splashColor: AppColors.primaryTint,
        highlightColor: AppColors.divider,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(item.icon, size: 21, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: AppText.cardTitle().copyWith(fontSize: 14.5)),
                    const SizedBox(height: 2),
                    // Two lines rather than one: beside a figure on a small
                    // phone, and in Filipino, one line cut the sentence off.
                    Text(
                      item.subtitle,
                      style: AppText.caption(color: AppColors.body),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (item.trailing != null) ...[
                const SizedBox(width: 10),
                item.trailing!,
              ],
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: AppColors.faint, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Live figures ───────────────────────────────────────────────────────────────
/// Total outstanding utang, shown only once there is something owed.
class _OwedMeta extends StatelessWidget {
  const _OwedMeta({required this.future});

  final Future<double> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: future,
      builder: (context, snap) {
        final owed = snap.data ?? 0;
        if (owed <= 0) return const SizedBox.shrink();
        return _MetaPill(
          text: formatPeso(owed),
          color: AppColors.warningText,
          background: AppColors.warningFill,
        );
      },
    );
  }
}

/// What should be in the drawer now.
class _DrawerMeta extends StatelessWidget {
  const _DrawerMeta({required this.future});

  final Future<double> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: future,
      builder: (context, snap) {
        final expected = snap.data;
        if (expected == null) return const SizedBox.shrink();
        return _MetaPill(
          text: formatPeso(expected),
          color: AppColors.primary,
          background: AppColors.primaryTint,
        );
      },
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.text, required this.color, required this.background});

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        text,
        style: AppText.chip(color: color)
            .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

// ── Lock till ──────────────────────────────────────────────────────────────────
/// A row like every other on this screen, in its own group at the bottom.
///
/// Was a full-width red outlined "Sign out" button: it looked like a warning
/// rather than part of the list, and its name suggested the store account
/// would go — when what it does is lock the till until someone enters their
/// code. The red lock tile still sets it apart from the places to go above.
class _LockRow extends StatelessWidget {
  const _LockRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: AppColors.dangerFill,
          highlightColor: AppColors.divider,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.dangerFill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.lock_outline_rounded, size: 21, color: AppColors.dangerText),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Lock till'),
                          style: AppText.cardTitle(color: AppColors.dangerText).copyWith(fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(
                        tr('A code is needed to sell again'),
                        style: AppText.caption(color: AppColors.body),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
