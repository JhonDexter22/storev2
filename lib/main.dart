import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/design_tokens.dart';
import 'core/responsive.dart';
import 'l10n/tr.dart';
import 'services/first_run.dart';
import 'services/product_image_store.dart';
import 'services/product_service.dart';
import 'services/settings_service.dart';
import 'services/stock_alerts.dart';
import 'screens/dashboard_screen.dart';
import 'screens/pos_screen.dart';
import 'screens/product_screen.dart';
import 'screens/restock_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';

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
  // A store that cannot answer "is this new?" is better opened than locked
  // behind a welcome screen it may not need.
  final firstRun = await FirstRun.needed().catchError((_) => false);
  runApp(RestockApp(firstRun: firstRun));
}

class RestockApp extends StatelessWidget {
  const RestockApp({super.key, this.firstRun = false});

  /// Opens on the setup steps instead of the till. Decided once, before the
  /// first frame, so an existing store never flashes a welcome screen.
  final bool firstRun;

  @override
  Widget build(BuildContext context) {
    return LanguageScope(
      child: ListenableBuilder(
        listenable: SettingsService.instance,
        builder: (context, _) => _app(),
      ),
    );
  }

  Widget _app() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Restock App',
      // Material's own text — date pickers, the back tooltip, "Cancel" in a
      // system dialog — follows the app language too.
      locale: SettingsService.instance.language.locale,
      supportedLocales: [for (final l in AppLanguage.values) l.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
      home: firstRun
          ? const FirstRunGate(child: HomeScreen())
          : const HomeScreen(),
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

  /// Which way the content slides on the next tab change: +1 when moving to a
  /// tab further right, -1 when moving left.
  int _slideDir = 1;

  void _goTo(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _slideDir = index > _currentIndex ? 1 : -1;
      _currentIndex = index;
    });
  }

  void _onTabTap(int index) {
    HapticFeedback.selectionClick();
    // Every screen that changes stock lives behind one of these tabs, so a
    // tab change is the moment a badge count can have gone stale.
    unawaited(StockAlerts.instance.refresh());
    // Switch on the touch itself; the press bounce plays alongside instead of
    // holding the tab back. A cashier taps these hundreds of times a day.
    _goTo(index);
    final press = _scaleControllers[index];
    press.reverse().then((_) {
      if (mounted) press.forward();
    });
  }

  void _startSale() => _goTo(_kSell);

  Widget _getScreen() {
    switch (_currentIndex) {
      case _kHome:
        return DashboardScreen(
          onStartSale: _startSale,
          onOpenProducts: () => _goTo(_kProducts),
          onOpenRestock: () => _goTo(_kRestock),
        );
      case _kSell:
        return const PosScreen();
      case _kProducts:
        return ProductsScreen(onRestock: () => _goTo(_kRestock));
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
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final body = AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
      reverseDuration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // The new tab drifts in from the side it sits on in the bar and the old
      // one drifts out the other way, so the page moves the way the pill does.
      // This closure is rebuilt every build, which makes AnimatedSwitcher
      // re-run it for the outgoing child too, with the current direction.
      transitionBuilder: (child, anim) {
        final incoming = child.key == ValueKey(_currentIndex);
        final dx = 0.06 * _slideDir * (incoming ? 1 : -1);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(anim),
            child: child,
          ),
        );
      },
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
      // The Sell button rises out of the bar and over the body's bottom edge.
      // Report that overhang as bottom padding so screens that respect the
      // safe area (SafeArea, ListView defaults) keep their last row clear of
      // it — the Scaffold itself has already stripped the system inset here.
      body: Builder(
        builder: (context) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(bottom: _BottomNav.overhang),
            ),
            child: body,
          );
        },
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        tabs: _tabs,
        scaleAnims: _scaleAnims,
        onTap: _onTabTap,
      ),
      floatingActionButton: _SellDock(
        tab: _tabs[_kSell],
        selected: _currentIndex == _kSell,
        scale: _scaleAnims[_kSell],
        onTap: () => _onTabTap(_kSell),
      ),
      floatingActionButtonLocation: const _SellDockLocation(),
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

  static const _width = 96.0;
  static const _itemWidth = 68.0;
  static const _itemHeight = 60.0;
  static const _itemGap = 6.0;

  /// Where the first item starts: top gap, logo, gap below the logo.
  static const _itemsTop = 18.0 + 44.0 + 22.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _width,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.dividerStrong)),
      ),
      child: SafeArea(
        right: false,
        child: Stack(
          children: [
            _GlidingPill(
              index: currentIndex,
              hidden: tabs[currentIndex].hero,
              axis: Axis.vertical,
              startOf: (i) => _itemsTop + i * (_itemHeight + _itemGap),
              extent: _itemHeight,
              crossStart: (_width - _itemWidth) / 2,
              crossExtent: _itemWidth,
              radius: AppRadius.iconBtn,
            ),
            Positioned.fill(
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
                    const SizedBox(height: _itemGap),
                  ],
                ],
              ),
            ),
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
      label: tr(tab.label),
      child: GestureDetector(
        onTap: () => onTap(i),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: _itemWidth,
          height: _itemHeight,
          // Only the hero paints its own fill; the selected tint behind the
          // other items is the gliding pill underneath.
          decoration: BoxDecoration(
            color: filled
                ? (selected ? AppColors.primaryPressed : AppColors.primary)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.iconBtn),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
                tr(tab.label),
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
  static const _inkLight  = AppColors.muted;
  static const _navBg     = AppColors.surface;

  /// Bar height, not counting the system inset. The hero button pokes above
  /// it, so the bar needs enough room for a label under a 56px circle.
  static const _height = 70.0;
  static const _heroSize = 56.0;
  static const _heroLift = 22.0;

  /// The selected-tab pill, and where it sits: every regular tab lays out
  /// from the top at the same offsets, so one pill can glide behind any icon.
  static const _pillTop = 9.0;
  static const _pillWidth = 64.0;
  static const _pillHeight = 34.0;

  /// How far the hero button reaches above the bar's top edge.
  static const overhang = _heroLift;

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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / tabs.length;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  _GlidingPill(
                    index: currentIndex,
                    // On Sell the raised button is the indicator; the pill
                    // fades out as it arrives underneath it.
                    hidden: tabs[currentIndex].hero,
                    axis: Axis.horizontal,
                    startOf: (i) => i * slot + (slot - _pillWidth) / 2,
                    extent: _pillWidth,
                    crossStart: _pillTop,
                    crossExtent: _pillHeight,
                    radius: AppRadius.chip,
                  ),
                  Positioned.fill(
                    child: Row(
                      children: List.generate(tabs.length, (i) {
                        final tab = tabs[i];
                        final selected = i == currentIndex;
                        final target = GestureDetector(
                          onTap: () => onTap(i),
                          behavior: HitTestBehavior.opaque,
                          child: ScaleTransition(
                            scale: scaleAnims[i],
                            child: tab.hero ? _heroTab(tab, selected) : _tab(tab, selected),
                          ),
                        );
                        return Expanded(
                          // The Sell circle announces itself, so its slot
                          // stays silent: one node for the tab, not two.
                          child: tab.hero
                              ? ExcludeSemantics(child: target)
                              : Semantics(
                                  button: true,
                                  selected: selected,
                                  label: tr(tab.label),
                                  child: target,
                                ),
                        );
                      }),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// A regular destination: icon in the pill's slot, label below. The pill
  /// itself is drawn once, behind the row, by [_GlidingPill].
  Widget _tab(_TabItem tab, bool selected) {
    // Align fills the slot so the whole tab stays tappable, while the content
    // sits at fixed offsets from the top that the pill can line up with.
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: _pillTop),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _pillWidth,
              height: _pillHeight,
              child: Center(
                child: _Badged(
                  badge: tab.badge,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      selected ? tab.activeIcon : tab.icon,
                      key: ValueKey(selected),
                      size: 24,
                      color: selected ? _accent : _inkLight,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            _label(tr(tab.label), selected),
          ],
        ),
      ),
    );
  }

  /// The Sell tab's slot in the bar: just its label. The raised circle above
  /// it is [_SellDock], which the Scaffold floats over this spot so that the
  /// part poking above the bar can be tapped too; a child of the bar could
  /// only ever be hit inside the bar's own bounds.
  Widget _heroTab(_TabItem tab, bool selected) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Positioned(
          // Lines up with where a regular tab's label sits.
          bottom: 9,
          child: _label(tr(tab.label), true),
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

// ── Gliding pill ───────────────────────────────────────────────────────────────
/// The selected-tab tint, drawn once and moved between tabs rather than faded
/// in and out per tab, so the eye follows where the cashier went.
///
/// The two ends travel on offset timings: the leading end sets off first and
/// the trailing end catches up, so the pill stretches toward its target and
/// then settles. A tap mid-glide sets off from wherever the pill is now, so
/// quick taps redirect it instead of queueing up.
class _GlidingPill extends StatefulWidget {
  const _GlidingPill({
    required this.index,
    required this.hidden,
    required this.axis,
    required this.startOf,
    required this.extent,
    required this.crossStart,
    required this.crossExtent,
    required this.radius,
  });

  final int index;

  /// Fades the pill out, for tabs that show selection some other way.
  final bool hidden;

  /// The direction the tabs run in.
  final Axis axis;

  /// Where the pill starts along [axis] for a tab index.
  final double Function(int index) startOf;
  final double extent;
  final double crossStart;
  final double crossExtent;
  final double radius;

  @override
  State<_GlidingPill> createState() => _GlidingPillState();
}

class _GlidingPillState extends State<_GlidingPill> with SingleTickerProviderStateMixin {
  static const _lead = Interval(0.0, 0.7, curve: Curves.easeOutCubic);
  static const _trail = Interval(0.2, 1.0, curve: Curves.easeOutCubic);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: 1,
  );

  late double _fromA, _fromB, _toA, _toB;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _toA = widget.startOf(widget.index);
    _toB = _toA + widget.extent;
    _fromA = _toA;
    _fromB = _toB;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _a => _lerp(_fromA, _toA, (_forward ? _trail : _lead).transform(_c.value));
  double get _b => _lerp(_fromB, _toB, (_forward ? _lead : _trail).transform(_c.value));

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void didUpdateWidget(_GlidingPill old) {
    super.didUpdateWidget(old);
    final target = widget.startOf(widget.index);
    if (target == _toA && widget.extent == old.extent) return;

    // Same tab but a new position means the layout changed (a rotation or a
    // resize), and coming back from a hidden tab there is nothing on screen
    // to glide from. Either way, jump rather than travel.
    final jump = widget.index == old.index ||
        (old.hidden && !widget.hidden) ||
        MediaQuery.of(context).disableAnimations;

    final a = _a, b = _b;
    _toA = target;
    _toB = target + widget.extent;
    if (jump) {
      _fromA = _toA;
      _fromB = _toB;
      _c.value = 1;
    } else {
      _fromA = a;
      _fromB = b;
      _forward = _toA >= _fromA;
      _c.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final a = _a, b = _b;
        final horizontal = widget.axis == Axis.horizontal;
        return Positioned(
          left: horizontal ? a : widget.crossStart,
          top: horizontal ? widget.crossStart : a,
          width: horizontal ? b - a : widget.crossExtent,
          height: horizontal ? widget.crossExtent : b - a,
          child: child!,
        );
      },
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: widget.hidden ? 0 : 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sell dock ──────────────────────────────────────────────────────────────────
/// The raised Sell circle, floated by the Scaffold over the bar's centre slot.
///
/// It lives in the floating-button slot rather than inside the bar because a
/// widget can only be tapped within its parent's bounds: drawn as part of the
/// bar, the top of the circle that pokes above it looked tappable but was not.
class _SellDock extends StatelessWidget {
  const _SellDock({
    required this.tab,
    required this.selected,
    required this.scale,
    required this.onTap,
  });

  final _TabItem tab;
  final bool selected;
  final Animation<double> scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: tr(tab.label),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ScaleTransition(
          scale: scale,
          child: _SellButton(
            selected: selected,
            icon: selected ? tab.activeIcon : tab.icon,
            size: _BottomNav._heroSize,
            ringColor: _BottomNav._navBg,
          ),
        ),
      ),
    );
  }
}

/// Pins [_SellDock] to the bar's centre, lifted [_BottomNav.overhang] above
/// its top edge.
///
/// Measured from the bottom of the screen rather than from the Scaffold's
/// content edge, so the circle stays put under the keyboard like the bar it
/// belongs to instead of riding up above it.
class _SellDockLocation extends FloatingActionButtonLocation {
  const _SellDockLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry g) {
    final barTop = g.scaffoldSize.height - g.minViewPadding.bottom - _BottomNav._height;
    return Offset(
      (g.scaffoldSize.width - g.floatingActionButtonSize.width) / 2,
      barTop - _BottomNav.overhang,
    );
  }
}

// ── Sell button ────────────────────────────────────────────────────────────────
/// The raised centre button. A ring ripples out from it on every press, from
/// the moment of touch, so the most-used action answers the thumb at once.
class _SellButton extends StatefulWidget {
  const _SellButton({
    required this.selected,
    required this.icon,
    required this.size,
    required this.ringColor,
  });

  final bool selected;
  final IconData icon;
  final double size;

  /// The bar colour, for the border that makes the circle look cut out of it.
  final Color ringColor;

  @override
  State<_SellButton> createState() => _SellButtonState();
}

class _SellButtonState extends State<_SellButton> with SingleTickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void dispose() {
    _ripple.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent _) {
    if (MediaQuery.of(context).disableAnimations) return;
    _ripple.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    // A Listener, not a gesture detector, so it sees the touch without
    // competing with the tab's own tap handler for it.
    return Listener(
      onPointerDown: _onDown,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Behind the circle, so it emerges from under the cut-out border.
            AnimatedBuilder(
              animation: _ripple,
              builder: (context, _) {
                if (!_ripple.isAnimating) return const SizedBox.shrink();
                final t = Curves.easeOutCubic.transform(_ripple.value);
                return Transform.scale(
                  scale: 1 + 0.55 * t,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.6 * (1 - t)),
                        width: 2,
                      ),
                    ),
                  ),
                );
              },
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: widget.selected ? AppColors.primaryPressed : AppColors.primary,
                shape: BoxShape.circle,
                // The ring in the bar colour makes the circle look cut out of
                // the bar rather than pasted on top of it.
                border: Border.all(color: widget.ringColor, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(widget.icon, size: 26, color: Colors.white),
            ),
          ],
        ),
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
