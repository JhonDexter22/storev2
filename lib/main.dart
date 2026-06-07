import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/product_screen.dart';
import 'screens/restock_screen.dart';
import 'screens/settings_screen.dart';

void main() {
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
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FC),
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

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;

  // One AnimationController per tab for the press/tap scale effect
  late final List<AnimationController> _scaleControllers;
  late final List<Animation<double>> _scaleAnims;

  static const _accent     = Color(0xFF2563EB);
  static const _accentBg   = Color(0xFFEEF3FF);
  static const _ink        = Color(0xFF0D0F1A);
  static const _inkLight   = Color(0xFFB0B5CC);
  static const _navBg      = Color(0xFFFFFFFF);
  static const _navBorder  = Color(0xFFEAECF5);

  static const _tabs = [
    _TabItem(
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2_rounded,
    ),
    _TabItem(
      label: 'Restock',
      icon: Icons.autorenew_outlined,
      activeIcon: Icons.autorenew_rounded,
    ),
    _TabItem(
      label: 'Settings',
      icon: Icons.tune_outlined,
      activeIcon: Icons.tune_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: _navBg,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    _scaleControllers = List.generate(
      _tabs.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        lowerBound: 0.85,
        upperBound: 1.0,
        value: 1.0,
      ),
    );
    _scaleAnims = _scaleControllers
        .map((c) => CurvedAnimation(parent: c, curve: Curves.easeOut))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _scaleControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTabTap(int index) async {
    HapticFeedback.selectionClick();
    // Animate pressed tab down then back up
    _scaleControllers[index].reverse();
    await Future.delayed(const Duration(milliseconds: 100));
    _scaleControllers[index].forward();
    setState(() => _currentIndex = index);
  }

  Widget _getScreen() {
    switch (_currentIndex) {
      case 0:
        return const ProductsScreen();
      case 1:
        return const RestockScreen();
      case 2:
        return const SettingsScreen();
      default:
        return const ProductsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
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
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        tabs: _tabs,
        scaleAnims: _scaleAnims,
        onTap: _onTabTap,
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

  static const _accent    = Color(0xFF2563EB);
  static const _accentBg  = Color(0xFFEEF3FF);
  static const _ink       = Color(0xFF0D0F1A);
  static const _inkLight  = Color(0xFFB0B5CC);
  static const _navBg     = Color(0xFFFFFFFF);
  static const _navBorder = Color(0xFFEAECF5);

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: _navBg,
        border: Border(top: BorderSide(color: _navBorder, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final selected = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: ScaleTransition(
                    scale: scaleAnims[i],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon pill
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? _accentBg : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            selected ? tabs[i].activeIcon : tabs[i].icon,
                            size: 22,
                            color: selected ? _accent : _inkLight,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // Label
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          style: TextStyle(
                            color: selected ? _accent : _inkLight,
                            fontSize: 11,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                          child: Text(tabs[i].label),
                        ),
                      ],
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
}

// ── Data class ─────────────────────────────────────────────────────────────────
class _TabItem {
  const _TabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}