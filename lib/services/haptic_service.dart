import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局触感振动反馈服务
/// 集中管控全站机械触感反馈，支持用户在【我的】页面随时开启或关闭，状态本地持久化。
class HapticService extends ChangeNotifier {
  static final HapticService instance = HapticService._();
  HapticService._();

  static const _prefKey = 'zyb_haptics_enabled_v5';
  bool _enabled = true;
  bool _loaded = false;

  bool get enabled => _enabled;
  bool get isLoaded => _loaded;

  /// 初始化加载本地开关状态（默认开启）
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKey) ?? true;
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  /// 切换触感开关并落盘持久化
  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    if (value) {
      // 开启时即时轻振一次，给用户直观确认
      unawaited(HapticFeedback.lightImpact());
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  /// 触发轻微机械触感（如列表刷新、点按、回顶、复制、发送等）
  Future<void> lightImpact() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// 触发错误触感反馈（如敏感词拦截、表单校验失败、网络请求异常）
  Future<void> errorImpact() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// 触发选择触感反馈
  Future<void> selection() => selectionClick();

  /// 触发选择点击触感（如底栏 Tab 切换）
  Future<void> selectionClick() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }
}
