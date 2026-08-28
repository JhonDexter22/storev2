import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import 'cash_count_screen.dart';
import 'cashier_switch_screen.dart';
import 'product_screen.dart';
import 'reports_screen.dart';
import 'returns_screen.dart';
import 'shift_history_screen.dart';
import 'store_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // ── Design Tokens (matches ProductsScreen) ──────────────────────────────
  static const Color _bg           = Color(0xFFF5F6FA);
  static const Color _cardBg       = Color(0xFFFFFFFF);
  static const Color _ink          = Color(0xFF0D0F1A);
  static const Color _inkMid       = Color(0xFF5A5F7A);
  static const Color _border       = Color(0xFFE7EAF4);
  static const Color _danger       = Color(0xFFDC2626);

  static const _cardShadow = [
    BoxShadow(color: Color(0x08000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _todayLabel() {
    final now = DateTime.now();
    return '${now.day} ${_months[now.month - 1]}';
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign out?',
            style: TextStyle(color: _ink, fontWeight: FontWeight.w800)),
        content: const Text(
          'You will need to sign in again to continue using this device.',
          style: TextStyle(color: _inkMid, fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: _inkMid, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Signing out means someone has to sign back in to the till.
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CashierSwitchScreen()),
              );
            },
            child: const Text('Sign out',
                style: TextStyle(color: _danger, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <_MoreItem>[
      _MoreItem(
        code: 'RT',
        title: 'Returns & voids',
        subtitle: 'Reverse a line or a whole sale',
        onTap: (ctx) => _open(ctx, const ReturnsScreen()),
      ),
      _MoreItem(
        code: 'RP',
        title: 'Reports',
        subtitle: 'Revenue, top products, payment mix',
        onTap: (ctx) => _open(ctx, const ReportsScreen()),
      ),
      _MoreItem(
        code: 'CC',
        title: 'Cash count',
        subtitle: 'End of day reconciliation',
        onTap: (ctx) => _open(ctx, const CashCountScreen()),
      ),
      _MoreItem(
        code: 'SH',
        title: 'Shift history',
        subtitle: 'Past closes and drawer variance',
        onTap: (ctx) => _open(ctx, const ShiftHistoryScreen()),
      ),
      _MoreItem(
        code: 'CS',
        title: 'Switch cashier',
        subtitle: 'Change who is on the till',
        onTap: (ctx) => _open(ctx, const CashierSwitchScreen()),
      ),
      _MoreItem(
        code: 'ST',
        title: 'Settings',
        subtitle: 'Receipts, alerts, backup',
        onTap: (ctx) => _open(ctx, const StoreSettingsScreen()),
      ),
      _MoreItem(
        code: 'PR',
        title: 'Products',
        subtitle: 'Full inventory list',
        onTap: (ctx) => _open(ctx, const ProductsScreen()),
      ),
    ];

    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) => _buildScaffold(context, items),
    );
  }

  Widget _buildScaffold(BuildContext context, List<_MoreItem> items) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            const Text(
              'More',
              style: TextStyle(
                color: _ink,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${SettingsService.instance.cashier} · '
              '${SettingsService.instance.terminal} · ${_todayLabel()}',
              style: const TextStyle(
                color: _inkMid,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 22),

            // ── Menu list ────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: _cardShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    _MenuRow(item: items[i]),
                    if (i != items.length - 1)
                      const Padding(
                        padding: EdgeInsets.only(left: 76),
                        child: Divider(color: _border, height: 1),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Sign out ─────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
                boxShadow: _cardShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _confirmSignOut(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Text(
                        'Sign out',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem({
    required this.code,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String code;
  final String title;
  final String subtitle;
  final void Function(BuildContext context) onTap;
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});

  final _MoreItem item;

  static const Color _ink         = Color(0xFF0D0F1A);
  static const Color _inkMid      = Color(0xFF5A5F7A);
  static const Color _inkLight    = Color(0xFFA2A7BF);
  static const Color _accent      = Color(0xFF2554E8);
  static const Color _accentLight = Color(0xFFEEF2FE);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => item.onTap(context),
        splashColor: _accentLight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _accentLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  item.code,
                  style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        color: _inkMid,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: _inkLight, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
