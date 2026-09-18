import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/design_tokens.dart';
import 'core/responsive.dart';
import 'services/product_image_store.dart';
import 'services/product_service.dart';
import 'services/settings_service.dart';
import 'services/stock_alerts.dart';
import 'screens/dashboard_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/product_screen.dart';
import 'screens/restock_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Settings drive the headers and the cash count, so they must be readable
  // synchronously by the time the first screen builds.
  await SettingsService.instance.load();
  // Photos saved by earlier versions sit in the cache directory, where Android
  // deletes them without warning. Move them somewhere durable before that
  // happens; it costs one query on a store with no photos and must never stop
  // the app opening.
  unawaited(ProductImageStore().rescueStrays(ProductService()).catchError((_) => 0));
  runApp(const RestockApp());
}

class RestockApp extends StatelessWidget {
  const RestockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Restock App',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.canvas,
        textTheme: GoogleFonts.plusJakartaSansTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _currentIndex = _kProducts;

  // One AnimationController per tab for the press/tap scale effect
  late final List<AnimationController> _scaleControllers;
  late final List<Animation<double>> _scaleAnims;

  static const _navBg = AppColors.surface;

  // Tab indices. Sell sits in the middle: it is the tab a cashier reaches for
  // most, and centre-bottom is the easiest spot to hit one-handed.
  static const _kHome = 0;
  static const _kProducts = 1;
  static const _kSell = 2;
  static const _kRestock = 3;
  static const _kMore = 4;

  static const _tabs = [
    _TabItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      badge: _TabBadge.outOfStockDot,
    ),
    _TabItem(
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2_rounded,
    ),
    _TabItem(
      label: 'Sell',
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale_rounded,
      hero: true,
    ),
    _TabItem(
      label: 'Restock',
      icon: Icons.local_shipping_outlined,
      activeIcon: Icons.local_shipping_rounded,
      badge: _TabBadge.needsRestockCount,
    ),
    _TabItem(
      label: 'More',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: _navBg,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    _scaleControllers = List.generate(
      _tabs.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 140),
        lowerBound: 0.92,
        upperBound: 1.0,
        value: 1.0,
      ),
    );
    _scaleAnims = _scaleControllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOutBack))
        .toList();

    unawaited(StockAlerts.instance.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _scaleControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stock can change while the app is in the background (a restore, or a
    // sale on another device sharing the store), so recount on return.
    if (state == AppLifecycleState.resumed) {
      unawaited(StockAlerts.instance.refresh());
    }
  }

  /// One per tab. A distinct key per tab means switching tabs builds a new
  /// [Navigator] — so the content pane starts at that tab's root rather than
  /// still showing whatever was pushed on the last one — while still giving a
  /// handle on the stack that is currently mounted.
  late final List<GlobalKey<NavigatorState>> _contentNavKeys =
      List.generate(_tabs.length, (_) => GlobalKey<NavigatorState>());

  void _onTabTap(int index) async {
    HapticFeedback.selectionClick();
    // Every screen that changes stock lives behind one of these tabs, so a
    // tab change is the moment a badge count can have gone stale.
    unawaited(StockAlerts.instance.refresh());
    // Animate pressed tab down then back up
    _scaleControllers[index].reverse();
    await Future.delayed(const Duration(milliseconds: 100));
    _scaleControllers[index].forward();
    setState(() => _currentIndex = index);
  }

  void _startSale() => setState(() => _currentIndex = _kSell);

  Widget _getScreen() {
    switch (_currentIndex) {
      case _kHome:
        return DashboardScreen(onStartSale: _startSale);
      case _kSell:
        return const PosScreen();
      case _kProducts:
        return const ProductsScreen();
      case _kRestock:
        return const RestockScreen();
      case _kMore:
        return SettingsScreen(onStartSale: _startSale);
      default:
        return const ProductsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      child: KeyedSubtree(
        key: ValueKey(_currentIndex),
        child: _getScreen(),
      ),
    );

    // On a tablet the bottom bar becomes a left icon rail, so the horizontal
    // space goes to the content panes instead.
    if (Breakpoints.isTablet(context)) {
      return Scaffold(
        body: PopScope(
          // Back belongs to the content pane first: it should close whatever
          // was opened from the More hub, not leave the app.
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            final nav = _contentNavKeys[_currentIndex].currentState;
            if (nav != null && nav.canPop()) nav.pop();
          },
          child: Row(
            children: [
              _NavRail(currentIndex: _currentIndex, tabs: _tabs, onTap: _onTabTap),
              Expanded(
                child: Navigator(
                  key: _contentNavKeys[_currentIndex],
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => body,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        tabs: _tabs,
        scaleAnims: _scaleAnims,
        onTap: _onTabTap,
      ),
    );
  }
}

/// 96px icon rail used on tablet.
///
/// The handoff shows a 96px icon rail on POS and returns and a 212px labelled
/// rail on the dashboard; one consistent rail is used here so the chrome does
/// not resize as you move between tabs.
class _NavRail extends StatelessWidget {
  const _NavRail({required this.currentIndex, required this.tabs, required this.onTap});

  final int currentIndex;
  final List<_TabItem> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.dividerStrong)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 18),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 21),
            ),
            const SizedBox(height: 22),
            for (int i = 0; i < tabs.length; i++) ...[
              _railItem(i),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _railItem(int i) {
    final tab = tabs[i];
    final selected = i == currentIndex;
    // The hero tab is always filled so it reads as the primary action even
    // when another tab is open; selection is shown by the label instead.
    final filled = tab.hero;
    final fg = filled
        ? Colors.white
        : selected
            ? AppColors.primary
            : AppColors.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        onTap: () => onTap(i),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 68,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: filled
                ? (selected ? AppColors.primaryPressed : AppColors.primary)
                : selected
                    ? AppColors.primaryTint
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.iconBtn),
          ),
          child: Column(
            children: [
              _Badged(
                badge: tab.badge,
                child: Icon(
                  selected ? tab.activeIcon : tab.icon,
                  size: 21,
                  color: fg,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tab.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 10,
                  fontWeight: selected || filled ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Nav bar widget ─────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.currentIndex,
    required this.tabs,
    required this.scaleAnims,
    required this.onTap,
  });

  final int currentIndex;
  final List<_TabItem> tabs;
  final List<Animation<double>> scaleAnims;
  final ValueChanged<int> onTap;

  static const _accent    = AppColors.primary;
  static const _accentBg  = AppColors.primaryTint;
  static const _inkLight  = AppColors.muted;
  static const _navBg     = AppColors.surface;

  /// Bar height, not counting the system inset. The hero button pokes above
  /// it, so the bar needs enough room for a label under a 56px circle.
  static const _height = 70.0;
  static const _heroSize = 56.0;
  static const _heroLift = 22.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      // No top hairline: the shadow alone carries the edge, which reads
      // cleaner than shadow + border stacked on top of each other.
      decoration: const BoxDecoration(
        color: _navBg,
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _height,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final tab = tabs[i];
              final selected = i == currentIndex;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: tab.label,
                  child: GestureDetector(
                    onTap: () => onTap(i),
                    behavior: HitTestBehavior.opaque,
                    child: ScaleTransition(
                      scale: scaleAnims[i],
                      child: tab.hero ? _heroTab(tab, selected) : _tab(tab, selected),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  /// A regular destination: capsule indicator behind the icon, label below.
  Widget _tab(_TabItem tab, bool selected) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? _accentBg : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: _Badged(
            badge: tab.badge,
            child: Icon(
              selected ? tab.activeIcon : tab.icon,
              size: 24,
              color: selected ? _accent : _inkLight,
            ),
          ),
        ),
        const SizedBox(height: 4),
        _label(tab.label, selected),
      ],
    );
  }

  /// The Sell tab: a filled circle raised out of the bar so it is the first
  /// thing the eye lands on and the easiest target for a thumb.
  Widget _heroTab(_TabItem tab, bool selected) {
    // A Stack rather than a Column so the circle can overhang the top of the
    // bar without asking the bar for the extra height.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          // Lines up with where a regular tab's label sits.
          bottom: 9,
          child: _label(tab.label, true),
        ),
        Positioned(
          top: -_heroLift,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: _heroSize,
            height: _heroSize,
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryPressed : _accent,
              shape: BoxShape.circle,
              // The ring in the bar colour makes the circle look cut out of
              // the bar rather than pasted on top of it.
              border: Border.all(color: _navBg, width: 4),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              selected ? tab.activeIcon : tab.icon,
              size: 26,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String text, bool selected) {
    // The label nudges up 2px when selected so the change registers as
    // motion, not just a weight swap.
    return AnimatedSlide(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      offset: Offset(0, selected ? -0.1 : 0),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 180),
        style: TextStyle(
          color: selected ? _accent : _inkLight,
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: 0.1,
        ),
        child: Text(text),
      ),
    );
  }
}

// ── Badges ─────────────────────────────────────────────────────────────────────
/// What a tab reports from [StockAlerts], if anything.
enum _TabBadge {
  /// A count of products at or under their minimum.
  needsRestockCount,

  /// A dot when anything is at zero.
  outOfStockDot,
}

/// Wraps an icon with its [_TabBadge], listening to [StockAlerts] so the badge
/// updates without the bar being rebuilt.
class _Badged extends StatelessWidget {
  const _Badged({required this.badge, required this.child});

  final _TabBadge? badge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = badge;
    if (b == null) return child;
    final alerts = StockAlerts.instance;
    return switch (b) {
      _TabBadge.needsRestockCount => ValueListenableBuilder<int>(
          valueListenable: alerts.needsRestock,
          builder: (_, count, __) => ValueListenableBuilder<int>(
            valueListenable: alerts.outOfStock,
            builder: (_, out, __) => _CountBadge(
              count: count,
              // Red once something has actually run out; amber while it is
              // only running low.
              color: out > 0 ? AppColors.danger : AppColors.warning,
              child: child,
            ),
          ),
        ),
      _TabBadge.outOfStockDot => ValueListenableBuilder<int>(
          valueListenable: alerts.outOfStock,
          builder: (_, out, __) => _DotBadge(show: out > 0, child: child),
        ),
    };
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color, required this.child});

  final int count;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -6,
          right: -10,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            scale: count > 0 ? 1 : 0,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17),
              height: 17,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DotBadge extends StatelessWidget {
  const _DotBadge({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -2,
          right: -3,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            scale: show ? 1 : 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Data class ─────────────────────────────────────────────────────────────────
class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    this.hero = false,
    this.badge,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;

  /// Drawn as the raised, filled centre button instead of a plain tab.
  final bool hero;

  /// Live count or dot from [StockAlerts] drawn over the icon.
  final _TabBadge? badge;
}
