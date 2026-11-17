import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/zk_post.dart';

/// 内容屏蔽与黑名单服务
/// 负责管理本地持久化的【屏蔽楼主昵称】与【屏蔽标题关键词】
class FilterService extends ChangeNotifier {
  static final FilterService instance = FilterService._();
  FilterService._();

  static const _authorsKey = 'zyb_blocked_author_names_v5';
  static const _keywordsKey = 'zyb_blocked_keywords_v5';

  final List<String> _blockedAuthors = [];
  final List<String> _blockedKeywords = [];
  bool _loaded = false;

  List<String> get blockedAuthors => List.unmodifiable(_blockedAuthors);
  List<String> get blockedKeywords => List.unmodifiable(_blockedKeywords);
  bool get isLoaded => _loaded;

  /// 初始化加载本地保存的屏蔽规则
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    final prefs = await SharedPreferences.getInstance();
    final authors = prefs.getStringList(_authorsKey) ?? [];
    final keywords = prefs.getStringList(_keywordsKey) ?? [];

    _blockedAuthors
      ..clear()
      ..addAll(authors);
    _blockedKeywords
      ..clear()
      ..addAll(keywords);

    _loaded = true;
    notifyListeners();
  }

  /// 添加要屏蔽的楼主昵称（去重、去除首尾空格）
  Future<bool> addAuthor(String authorName) async {
    final trimmed = authorName.trim();
    if (trimmed.isEmpty) return false;

    // 检查是否已经存在（忽略大小写比较）
    final exists = _blockedAuthors.any(
      (a) => a.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) return false;

    _blockedAuthors.add(trimmed);
    await _saveAuthors();
    notifyListeners();
    return true;
  }

  /// 移除已屏蔽的楼主昵称
  Future<bool> removeAuthor(String authorName) async {
    final trimmed = authorName.trim();
    final index = _blockedAuthors.indexWhere(
      (a) => a.toLowerCase() == trimmed.toLowerCase(),
    );
    if (index == -1) return false;

    _blockedAuthors.removeAt(index);
    await _saveAuthors();
    notifyListeners();
    return true;
  }

  /// 添加要屏蔽的标题关键词（去重、去除首尾空格）
  Future<bool> addKeyword(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return false;

    final exists = _blockedKeywords.any(
      (k) => k.toLowerCase() == trimmed.toLowerCase(),
    );
    if (exists) return false;

    _blockedKeywords.add(trimmed);
    await _saveKeywords();
    notifyListeners();
    return true;
  }

  /// 移除已屏蔽的关键词
  Future<bool> removeKeyword(String keyword) async {
    final trimmed = keyword.trim();
    final index = _blockedKeywords.indexWhere(
      (k) => k.toLowerCase() == trimmed.toLowerCase(),
    );
    if (index == -1) return false;

    _blockedKeywords.removeAt(index);
    await _saveKeywords();
    notifyListeners();
    return true;
  }

  /// 检查特定帖子是否应该被屏蔽
  /// 规则：
  /// 1. 帖子作者昵称命中屏蔽名单 -> 屏蔽
  /// 2. 帖子标题包含任意屏蔽关键词 -> 屏蔽
  bool isPostBlocked(ZkPost post) {
    if (isAuthorBlocked(post.author)) return true;
    if (isTitleBlocked(post.title)) return true;
    return false;
  }

  /// 检查作者昵称是否被屏蔽
  bool isAuthorBlocked(String author) {
    final target = author.trim().toLowerCase();
    if (target.isEmpty) return false;
    return _blockedAuthors.any((a) => a.toLowerCase() == target);
  }

  /// 检查标题是否命中任意屏蔽词
  bool isTitleBlocked(String title) {
    final target = title.toLowerCase();
    if (target.isEmpty) return false;
    for (final kw in _blockedKeywords) {
      if (kw.isNotEmpty && target.contains(kw.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  Future<void> _saveAuthors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_authorsKey, List<String>.from(_blockedAuthors));
  }

  Future<void> _saveKeywords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keywordsKey, List<String>.from(_blockedKeywords));
  }
}
