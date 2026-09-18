import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import '../core/responsive.dart';
import '../services/settings_service.dart';
import '../services/shift_service.dart';
import '../services/utang_service.dart';
import 'cash_count_screen.dart';
import 'cashier_switch_screen.dart';
import 'product_screen.dart';
import 'reports_screen.dart';
import 'returns_screen.dart';
import 'shift_history_screen.dart';
import 'store_settings_screen.dart';
import 'utang_screen.dart';

/// The More hub: everything that is not one of the four main tabs.
///
/// Destinations are grouped by when a cashier reaches for them — what runs
/// every day, what happens at the counter, and what is set up once — rather
/// than listed flat. The rows that have a live number worth glancing at
/// (money owed, sales so far this shift) show it on the right so the hub
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
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  late final Future<double> _owed = _loadOwed();
  late final Future<({double total, int count, DateTime openedAt})> _shift =
      ShiftService().currentShiftSales();

  Future<double> _loadOwed() async {
    final customers = await UtangService().getCustomers();
    return customers.fold<double>(0, (sum, c) => sum + (c.balance > 0 ? c.balance : 0));
  }

  String _todayLabel() {
    final now = DateTime.now();
    return '${now.day} ${_months[now.month - 1]}';
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sign out?', style: AppText.sectionTitle()),
        content: Text(
          'You will need to sign in again to continue using this device.',
          style: AppText.body(),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppText.chip(color: AppColors.body)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Signing out means someone has to sign back in to the till.
              _open(const CashierSwitchScreen());
            },
            child: Text('Sign out', style: AppText.chip(color: AppColors.danger)),
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
        title: 'Today',
        tint: AppColors.primaryTint,
        iconColor: AppColors.primary,
        items: [
          _MoreItem(
            icon: Icons.bar_chart_rounded,
            title: 'Reports',
            subtitle: 'Revenue, top products, payment mix',
            onTap: () => _open(const ReportsScreen()),
          ),
          _MoreItem(
            icon: Icons.payments_outlined,
            title: 'Cash count',
            subtitle: 'End of day reconciliation',
            trailing: _ShiftMeta(future: _shift),
            onTap: () => _open(const CashCountScreen()),
          ),
          _MoreItem(
            icon: Icons.history_rounded,
            title: 'Shift history',
            subtitle: 'Past closes and drawer variance',
            onTap: () => _open(const ShiftHistoryScreen()),
          ),
        ],
      ),
      _Section(
        title: 'At the counter',
        tint: AppColors.warningFill,
        iconColor: AppColors.warningText,
        items: [
          _MoreItem(
            icon: Icons.assignment_return_outlined,
            title: 'Returns & voids',
            subtitle: 'Reverse a line or a whole sale',
            onTap: () => _open(const ReturnsScreen()),
          ),
          _MoreItem(
            icon: Icons.receipt_long_outlined,
            title: 'Utang',
            subtitle: 'Who owes what, aged oldest first',
            trailing: _OwedMeta(future: _owed),
            onTap: () => _open(UtangScreen(onCharge: widget.onStartSale)),
          ),
        ],
      ),
      _Section(
        title: 'Store',
        tint: AppColors.divider,
        iconColor: AppColors.body,
        items: [
          _MoreItem(
            icon: Icons.inventory_2_outlined,
            title: 'Products',
            subtitle: 'Full inventory list',
            onTap: () => _open(const ProductsScreen()),
          ),
          _MoreItem(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Receipts, alerts, backup',
            onTap: () => _open(const StoreSettingsScreen()),
          ),
        ],
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: Breakpoints.pagePadding(
              context,
              constraints.maxWidth,
              top: 24,
              // Clear the Sell button that rises out of the bottom bar.
              bottom: 32 + MediaQuery.paddingOf(context).bottom,
              phoneSide: 24,
            ),
            children: [
              Text('More', style: AppText.screenTitle()),
              const SizedBox(height: 16),

              _CashierCard(
                name: settings.cashier,
                detail: '${settings.storeName} · ${settings.terminal} · ${_todayLabel()}',
                onSwitch: () => _open(const CashierSwitchScreen()),
              ),
              const SizedBox(height: 24),

              for (final s in sections) ...[
                _SectionCard(section: s),
                const SizedBox(height: 20),
              ],

              _SignOutRow(onTap: _confirmSignOut),
            ],
          ),
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

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

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
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials,
              style: AppText.sectionTitle(color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Signed in as', style: AppText.caption()),
                const SizedBox(height: 2),
                Text(name, style: AppText.sectionTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(detail, style: AppText.caption(color: AppColors.body), maxLines: 1, overflow: TextOverflow.ellipsis),
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
      label: 'Switch cashier',
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
                Text('Switch', style: AppText.chip(color: AppColors.primary)),
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
                    Text(
                      item.subtitle,
                      style: AppText.caption(color: AppColors.body),
                      maxLines: 1,
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

/// Sales rung up so far this shift.
class _ShiftMeta extends StatelessWidget {
  const _ShiftMeta({required this.future});

  final Future<({double total, int count, DateTime openedAt})> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({double total, int count, DateTime openedAt})>(
      future: future,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null || s.count == 0) return const SizedBox.shrink();
        return _MetaPill(
          text: formatPeso(s.total),
          color: AppColors.successText,
          background: AppColors.successFill,
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

// ── Sign out ───────────────────────────────────────────────────────────────────
/// Deliberately quieter than the destinations above it: a bordered row, no
/// fill, so it cannot be mistaken for a place to go.
class _SignOutRow extends StatelessWidget {
  const _SignOutRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.cta),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.cta),
            border: Border.all(color: AppColors.dangerBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.logout_rounded, size: 18, color: AppColors.dangerText),
              const SizedBox(width: 8),
              Text('Sign out', style: AppText.chip(color: AppColors.dangerText).copyWith(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}
