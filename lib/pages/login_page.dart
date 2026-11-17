import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../services/api_service.dart';
import '../state/login_state.dart';
import '../theme/app_theme.dart';
import '../widgets/zyb_feedback.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  Timer? _pollingTimer;
  bool _checking = false;
  bool _hasHandledSuccess = false;

  @override
  void initState() {
    super.initState();
    // 启动高可靠后台轮询检测，防止部分设备 Webview 回调丢失或异步 Cookie 写入未触发 onLoadStop
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      _checkLogin();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    super.dispose();
  }

  Future<void> _checkLogin() async {
    if (_checking || _hasHandledSuccess || !mounted) return;
    _checking = true;

    try {
      final api = ApiService();
      // 1. 优先直接从 CookieManager 读取（性能极高，毫秒级响应）
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(baseUrl),
      );
      bool hasAuthCookie = false;
      String? cookieUid;

      for (final c in cookies) {
        final name = c.name.toLowerCase();
        if (name.endsWith('_auth') && c.value.isNotEmpty) {
          hasAuthCookie = true;
        }
        if ((name.contains('discuz_uid') || name.endsWith('_uid')) &&
            c.value.isNotEmpty &&
            c.value != '0') {
          cookieUid = c.value;
        }
      }

      final loggedIn = hasAuthCookie || await api.isLoggedIn();

      if (loggedIn) {
        await api.refreshCookie();

        String? uid = cookieUid;
        if (uid == null || uid.isEmpty) {
          uid = await api.getUid();
        }

        if (uid != null && uid.isNotEmpty && uid != '0') {
          _hasHandledSuccess = true;
          _pollingTimer?.cancel();

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('uid', uid);
          await prefs.setString('discuz_uid', uid);
          await prefs.setString('username', '');
          await prefs.setBool('logged_in', true);

          if (mounted) {
            // 广播全局登录态变化（通知首页/我的/消息等刷新数据）
            notifyLoginStateChanged();
            // 准确返回上一级页面，由调用方（如帖子详情页、我的页面）自行恢复或刷新
            Navigator.pop(context, true);
          }
          return;
        }
      }
    } catch (_) {
      // 忽略检查中的网络抖动，下一次轮询继续检测
    } finally {
      _checking = false;
    }
  }

  bool _isDisallowedAuthScheme(String url) {
    return url.startsWith('wtloginmqq://') ||
        url.startsWith('mqq://') ||
        url.startsWith('mqqapi://') ||
        url.startsWith('ptlogin2://') ||
        url.contains('connect.php');
  }

  Future<NavigationActionPolicy> _handleNavigation(
    NavigationAction action,
  ) async {
    final url = action.request.url?.toString() ?? '';
    if (_isDisallowedAuthScheme(url)) {
      if (mounted) {
        showZybFeedback(context, '暂不支持 QQ 唤起登录，请使用论坛账号密码登录', error: true);
      }
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录'),
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(loginUrl)),
        initialSettings: InAppWebViewSettings(
          useHybridComposition: true,
          userAgent: mobileUserAgent,
          preferredContentMode: UserPreferredContentMode.MOBILE,
          useShouldOverrideUrlLoading: true,
        ),
        onLoadStart: (controller, url) {
          controller.injectCSSCode(
            source: 'header, .header, #header, .nav, .top_nav, .btn_qqlogin { display: none !important; } body { padding-top: 0 !important; margin-top: 0 !important; }',
          );
        },
        onLoadStop: (controller, url) async {
          await controller.injectCSSCode(
            source: 'header, .header, #header, .nav, .top_nav, .btn_qqlogin { display: none !important; } body { padding-top: 0 !important; margin-top: 0 !important; }',
          );
          _checkLogin();
        },
        onProgressChanged: (controller, progress) {
          if (progress >= 30) {
            controller.injectCSSCode(
              source: 'header, .header, #header, .nav, .top_nav, .btn_qqlogin { display: none !important; } body { padding-top: 0 !important; margin-top: 0 !important; }',
            );
          }
          if (progress >= 80) {
            _checkLogin();
          }
        },
        onUpdateVisitedHistory: (controller, url, isReload) {
          _checkLogin();
        },
        shouldOverrideUrlLoading: (controller, navigationAction) {
          return _handleNavigation(navigationAction);
        },
      ),
    );
  }
}

