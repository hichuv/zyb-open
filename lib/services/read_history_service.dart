import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 帖子已读状态持久化服务
/// 负责在手机本地存储已浏览帖子的 TID，保证清理后台、重启应用后已读状态永不丢失，
/// 并在全站（首页、板块、他人主页、我的发布/收藏）实现已读状态联动置灰。
class ReadHistoryService extends ChangeNotifier {
  static final ReadHistoryService instance = ReadHistoryService._();
  ReadHistoryService._();

  static const _storageKey = 'zyb_read_post_tids_v5';
  static const int _maxHistory = 2000;

  final Set<String> _readTids = {};
  bool _loaded = false;

  Set<String> get readTids => Set.unmodifiable(_readTids);
  bool get isLoaded => _loaded;

  /// 初始化从本地加载已读 TID 列表
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_storageKey) ?? [];
      _readTids
        ..clear()
        ..addAll(list);
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  /// 检查帖子是否已读
  bool isRead(String tid) {
    if (tid.isEmpty) return false;
    return _readTids.contains(tid);
  }

  /// 标记帖子为已读（内存即时更新 + 异步本地持久化）
  /// [notify] 为 false 时仅同步到内存与后台存储，不立刻打断正在发生的页面路由转场动画；
  /// 返回列表页后再触发通知置灰，确保切页 120 帧满帧丝滑。
  Future<void> markRead(String tid, {bool notify = true}) async {
    final trimmed = tid.trim();
    if (trimmed.isEmpty) return;
    final isNew = _readTids.add(trimmed);
    if (!isNew) return;

    if (notify) {
      notifyListeners();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      // 限制最多保存最近 _maxHistory 条，防止过度膨胀
      List<String> toSave;
      if (_readTids.length > _maxHistory) {
        toSave = _readTids.toList().sublist(_readTids.length - _maxHistory);
      } else {
        toSave = _readTids.toList();
      }
      await prefs.setStringList(_storageKey, toSave);
    } catch (_) {}
  }

  /// 供外部在页面转场结束后批量触发通知置灰
  void notifyReadChanged() {
    notifyListeners();
  }
}
