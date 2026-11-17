// 📁 lib/ - 赚友吧 5.0 核心业务代码库（页面路由、网络通信、搜索历史、主题状态）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/home_page.dart';
import 'pages/my_page.dart';
import 'services/api_service.dart';
import 'services/haptic_service.dart';
import 'services/read_history_service.dart';
import 'state/login_state.dart';
import 'state/theme_state.dart';
import 'theme/app_theme.dart';
import 'widgets/zyb_feedback.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  await appThemeController.load();
  unawaited(ReadHistoryService.instance.load());
  unawaited(HapticService.instance.load());
  runApp(const ZybApp());
}

const Color primaryColor = Color(0xFFFF5F15);
const String appVersionLabel = '赚友吧 V6.0 版本';

class ZybApp extends StatelessWidget {
  const ZybApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appThemeController,
      builder: (context, _) => MaterialApp(
        title: '赚友吧',
        debugShowCheckedModeBanner: false,
        themeMode: appThemeController.themeMode,
        theme: zybTheme(Brightness.light),
        darkTheme: zybTheme(Brightness.dark),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        locale: const Locale('zh', 'CN'),
        home: const LaunchPage(),
      ),
    );
  }
}

class LaunchPage extends StatefulWidget {
  const LaunchPage({super.key});

  @override
  State<LaunchPage> createState() => _LaunchPageState();
}

class _LaunchPageState extends State<LaunchPage> {
  @override
  void initState() {
    super.initState();
    // 极速冷启动：首帧渲染完毕即刻进入首页，零人为卡顿傻等
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterApp();
    });
  }

  Future<void> _enterApp() async {
    // 1. 底线展示时长计时（0.8 秒）
    final minTimer = Future<void>.delayed(const Duration(milliseconds: 800));

    // 2. 后台静默预加载首页热门帖子（带最长 3 秒保底超时，防止弱网一直死卡开屏）
    final preloadTask = ApiService.instance.preloadHomePosts().timeout(
      const Duration(seconds: 3),
      onTimeout: () {},
    );

    // 3. 同时等待：至少 0.8 秒 且 帖子预加载就绪（或 3 秒超时保底）
    await Future.wait([minTimer, preloadTask]);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const MainShell(),
        transitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = appThemeController.isDark(context);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: const SizedBox.expand(
        child: Image(image: AssetImage('assets/qd.png'), fit: BoxFit.cover),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  DateTime? _lastBackPressedAt;
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();
  final GlobalKey<MyPageState> _myKey = GlobalKey<MyPageState>();

  late final List<Widget> _pages = [
    HomePage(key: _homeKey),
    MyPage(key: _myKey),
  ];

  @override
  void initState() {
    super.initState();
    rootTabIndex.addListener(_handleRootTabChanged);
  }

  @override
  void dispose() {
    rootTabIndex.removeListener(_handleRootTabChanged);
    super.dispose();
  }

  void _handleRootTabChanged() {
    final nextIndex = rootTabIndex.value;
    if (!mounted || nextIndex == _currentIndex) return;
    setState(() => _currentIndex = nextIndex);
  }

  Future<bool> _handleRootBack() async {
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return false;
    }

    final now = DateTime.now();
    final last = _lastBackPressedAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return true;
    }

    _lastBackPressedAt = now;
    _toast('再次返回退出赚友吧');
    return false;
  }

  void _toast(String msg) {
    showZybFeedback(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleRootBack();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: IndexedStack(index: _currentIndex, children: _pages),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: colors.navBackground,
            border: Border(
              top: BorderSide(
                color: colors.divider.withValues(alpha: 0.8),
                width: 0.8,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              height: 52,
              backgroundColor: Colors.transparent,
              elevation: 0,
              indicatorColor: colors.primary.withValues(alpha: 0.12),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontSize: 10.5,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: states.contains(WidgetState.selected)
                    ? colors.primary
                    : colors.textMuted,
              ),
            ),
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                size: 21,
                color: states.contains(WidgetState.selected)
                    ? colors.primary
                    : colors.textMuted,
              ),
            ),
          ),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              if (_currentIndex != index) {
                HapticService.instance.selectionClick();
                setState(() => _currentIndex = index);
              } else if (index == 0) {
                HapticService.instance.lightImpact();
                _homeKey.currentState?.scrollToTopAndRefresh();
              } else if (index == 1) {
                HapticService.instance.lightImpact();
                _myKey.currentState?.scrollToTopAndRefresh();
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: '我的',
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }
}
