import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../models/zk_post.dart';
import '../models/zk_user_profile.dart';
import '../utils/helpers.dart';
import '../utils/time_parser.dart';

class ForumListException implements Exception {
  final int fid;
  final String message;
  final bool loginRequired;

  const ForumListException(
    this.fid,
    this.message, {
    this.loginRequired = false,
  });

  @override
  String toString() => message;
}

/// 多板块动态聚合器（按真实时间严格交织合并，杜绝断层与成堆聚集）
class ForumFeedAggregator {
  final ApiService api;
  final SortMode sortMode;
  List<int> fids;

  final Map<int, int> _pages = {};
  final Map<int, bool> _hasMore = {};
  final Map<int, List<ZkPost>> _buffers = {};

  ForumFeedAggregator({
    required this.api,
    required this.sortMode,
    required this.fids,
  });

  void reset({List<int>? newFids}) {
    if (newFids != null) fids = newFids;
    _pages.clear();
    _hasMore.clear();
    _buffers.clear();
  }

  Future<void> _fetchMoreFor(int fid) async {
    if (_hasMore[fid] == false) return;
    final nextPage = (_pages[fid] ?? 0) + 1;
    try {
      final posts = await api.fetchForumList(
        fid: fid,
        sortMode: sortMode,
        page: nextPage,
      );
      if (posts.isEmpty) {
        _hasMore[fid] = false;
      } else {
        _pages[fid] = nextPage;
        final existingTids = _buffers[fid]!.map((p) => p.tid).toSet();
        for (final p in posts) {
          if (existingTids.add(p.tid)) {
            _buffers[fid]!.add(p);
          }
        }
      }
    } catch (_) {
      // 瞬时网络异常不永久断流，保留后续重试机会
    }
  }

  /// 获取下一批合并交织帖子（默认每次向界面提供 35 条）
  Future<List<ZkPost>> nextBatch({int targetCount = 35}) async {
    if (fids.isEmpty) return [];

    await api.refreshCookie();

    // 初始化各板块状态
    for (final fid in fids) {
      _pages.putIfAbsent(fid, () => 0);
      _hasMore.putIfAbsent(fid, () => true);
      _buffers.putIfAbsent(fid, () => <ZkPost>[]);
    }

    // 1. 若缓冲区为空且有下一页，初始并发拉取
    final initialFetches = <Future<void>>[];
    for (final fid in fids) {
      if (_buffers[fid]!.isEmpty && _hasMore[fid]!) {
        initialFetches.add(_fetchMoreFor(fid));
      }
    }
    if (initialFetches.isNotEmpty) {
      await Future.wait(initialFetches);
    }

    // 2. 单板块（如热门只查大家谈 fid 15），直接单流出队
    if (fids.length == 1) {
      final fid = fids.first;
      if (_buffers[fid]!.length < 15 && _hasMore[fid]!) {
        await _fetchMoreFor(fid);
      }
      final available = _buffers[fid]!;
      if (available.isEmpty) return [];
      final emitCount =
          available.length > targetCount ? targetCount : available.length;
      final emitted = available.sublist(0, emitCount);
      _buffers[fid] = available.sublist(emitCount);
      return emitted;
    }

    // 3. 多板块聚合交织（时间水位线闸门机制）
    // 以发帖最活跃的【大家谈 fid 15】作为基准时间锚点
    final anchorFid = fids.contains(15) ? 15 : fids.first;

    int advanceLoops = 0;
    while (advanceLoops < 3) {
      DateTime? watermark;
      if (_hasMore[anchorFid] == true && _buffers[anchorFid]!.isNotEmpty) {
        final oldestAnchor = _buffers[anchorFid]!.last;
        final t = parseZkTime(
          sortMode == SortMode.latestPost
              ? oldestAnchor.postTime
              : oldestAnchor.lastReplyTime,
        );
        if (t != null) watermark = t;
      }

      int eligibleCount = 0;
      for (final fid in fids) {
        for (final p in _buffers[fid]!) {
          if (watermark == null) {
            eligibleCount++;
          } else {
            final t = parseZkTime(
              sortMode == SortMode.latestPost
                  ? p.postTime
                  : p.lastReplyTime,
            );
            if (t == null || !t.isBefore(watermark)) {
              eligibleCount++;
            }
          }
        }
      }

      if (eligibleCount >= targetCount || _hasMore[anchorFid] == false) {
        break;
      }

      // 主导板块时间推移不足，自动在后台追加一页主导板块，使水位线下移
      await _fetchMoreFor(anchorFid);
      advanceLoops++;
    }

    DateTime? finalWatermark;
    if (_hasMore[anchorFid] == true && _buffers[anchorFid]!.isNotEmpty) {
      final oldestAnchor = _buffers[anchorFid]!.last;
      finalWatermark = parseZkTime(
        sortMode == SortMode.latestPost
            ? oldestAnchor.postTime
            : oldestAnchor.lastReplyTime,
      );
    }

    final eligiblePosts = <ZkPost>[];
    for (final fid in fids) {
      for (final p in _buffers[fid]!) {
        if (finalWatermark == null) {
          eligiblePosts.add(p);
        } else {
          final t = parseZkTime(
            sortMode == SortMode.latestPost
                ? p.postTime
                : p.lastReplyTime,
          );
          if (t == null || !t.isBefore(finalWatermark)) {
            eligiblePosts.add(p);
          }
        }
      }
    }

    final pool = eligiblePosts.isNotEmpty
        ? eligiblePosts
        : [for (final fid in fids) ..._buffers[fid]!];

    if (pool.isEmpty) return [];

    pool.sort((a, b) {
      final aTime = parseZkTime(
        sortMode == SortMode.latestPost ? a.postTime : a.lastReplyTime,
      );
      final bTime = parseZkTime(
        sortMode == SortMode.latestPost ? b.postTime : b.lastReplyTime,
      );
      if (aTime != null && bTime != null) return bTime.compareTo(aTime);
      if (aTime != null) return -1;
      if (bTime != null) return 1;
      return int.tryParse(b.tid)?.compareTo(int.tryParse(a.tid) ?? 0) ?? 0;
    });

    final emitCount = pool.length > targetCount ? targetCount : pool.length;
    final emitted = pool.sublist(0, emitCount);
    final emittedTids = emitted.map((p) => p.tid).toSet();

    for (final fid in fids) {
      _buffers[fid]!.removeWhere((p) => emittedTids.contains(p.tid));
    }

    return emitted;
  }
}

/// API 服务层 - 负责网络请求和 HTML 解析（全局单例，保证 Cookie 与请求状态全局共享）
class ApiService {
  static final ApiService instance = ApiService._internal();
  factory ApiService() => instance;
  ApiService._internal();

  String _cookie = '';
  List<ZkPost>? _preloadedHotPosts;

  /// 取出预加载的热门帖子（仅限首页首次启动消费，消费后即清空）
  List<ZkPost>? get consumePreloadedHotPosts {
    final posts = _preloadedHotPosts;
    _preloadedHotPosts = null;
    return posts;
  }

  /// 开屏静默预加载首页第一页数据
  Future<void> preloadHomePosts() async {
    try {
      await refreshCookie();
      final posts = await fetchForumList(
        fid: 15,
        sortMode: SortMode.hot,
        page: 1,
      );
      if (posts.isNotEmpty) {
        _preloadedHotPosts = posts;
      }
    } catch (_) {
      // 静默失败，由进入主页后正常拉取逻辑接管
    }
  }

  /// 从 WebView CookieManager 提取 Cookie
  Future<void> refreshCookie() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri(baseUrl),
    );
    _cookie = cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  /// 通用请求头
  Map<String, String> get _headers => {
    'User-Agent': userAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9',
    if (_cookie.isNotEmpty) 'Cookie': _cookie,
  };

  /// GET 请求并返回 GBK 解码后的 HTML
  Future<String> _get(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return decodeGbk(response.bodyBytes);
  }

  // ─── 帖子列表 ────────────────────────────────────────────

  /// 获取帖子列表（合并多个板块）
  Future<List<ZkPost>> fetchPostList({
    required SortMode sortMode,
    required List<int> fids,
    int page = 1,
  }) async {
    await refreshCookie();
    final futures = fids.map(
      (fid) => _fetchForumPosts(fid: fid, sortMode: sortMode, page: page),
    );
    final results = await Future.wait(
      futures.map((future) async {
        try {
          return await future;
        } on ForumListException {
          return <ZkPost>[];
        }
      }),
    );

    // 合并并按 tid 去重
    final seen = <String>{};
    final merged = <ZkPost>[];
    for (final posts in results) {
      for (final post in posts) {
        if (seen.add(post.tid)) {
          merged.add(post);
        }
      }
    }

    merged.sort((a, b) {
      final aTime = parseZkTime(
        sortMode == SortMode.latestPost ? a.postTime : a.lastReplyTime,
      );
      final bTime = parseZkTime(
        sortMode == SortMode.latestPost ? b.postTime : b.lastReplyTime,
      );
      if (aTime != null && bTime != null) return bTime.compareTo(aTime);
      if (aTime != null) return -1;
      if (bTime != null) return 1;
      return int.tryParse(b.tid)?.compareTo(int.tryParse(a.tid) ?? 0) ?? 0;
    });
    return merged;
  }

  /// 获取单个板块的帖子（原生板块页用）
  Future<List<ZkPost>> fetchForumList({
    required int fid,
    required SortMode sortMode,
    int page = 1,
  }) async {
    await refreshCookie();
    return _fetchForumPosts(fid: fid, sortMode: sortMode, page: page);
  }

  /// 获取单个板块的帖子
  Future<List<ZkPost>> _fetchForumPosts({
    required int fid,
    required SortMode sortMode,
    int page = 1,
  }) async {
    try {
      final url = forumListUrl(
        fid: fid,
        filter: sortMode.filter,
        orderby: sortMode.orderby,
        page: page,
      );
      final body = await _get(url);
      final document = html_parser.parse(body);
      final matchedForums = browseForums.where((f) => f.fid == fid);
      final forumName = matchedForums.isNotEmpty ? matchedForums.first.name : '板块$fid';
      final pageTitle = normalize(document.querySelector('title')?.text ?? '');
      final pageText = normalize(document.body?.text ?? '');
      final loginRequired = pageTitle.contains('登录') ||
          pageText.contains('您需要先登录') ||
          pageText.contains('请先登录');
      if (loginRequired) {
        throw ForumListException(fid, '$forumName 需要登录', loginRequired: true);
      }
      if (pageTitle.contains('提示信息')) {
        throw ForumListException(fid, '$forumName 当前账号无权访问');
      }

      final posts = <ZkPost>[];
      final rows = document.querySelectorAll('tbody');
      for (final row in rows) {
        final id = row.attributes['id'] ?? '';
        if (!id.startsWith('normalthread_')) continue;

        final tid = id.replaceFirst('normalthread_', '');

        final titleLink =
            row.querySelector('a.xst') ??
            row.querySelector('a[href*="thread-"]') ??
            row.querySelector('a[href*="tid="]');
        if (titleLink == null) continue;

        final title = normalize(titleLink.text);
        if (title.isEmpty) continue;

        final href = absoluteUrl(titleLink.attributes['href'] ?? '');

        // 作者、发帖时间
        final byCells = row.querySelectorAll('td.by');
        String author = '';
        String authorId = '';
        String postTime = '';
        String lastReplyTime = '';
        if (byCells.isNotEmpty) {
          author = normalize(byCells[0].querySelector('cite a')?.text ?? '');
          final authorHref =
              byCells[0].querySelector('cite a')?.attributes['href'] ?? '';
          authorId =
              RegExp(
                r'(?:uid=|space-uid-)(\d+)',
              ).firstMatch(authorHref)?.group(1) ??
              '';
          final span = byCells[0].querySelector('em span');
          final em = byCells[0].querySelector('em');
          final titleAttr = normalize(
            span?.attributes['title'] ?? em?.attributes['title'] ?? '',
          );
          final text = normalize(span?.text ?? em?.text ?? '');
          postTime = titleAttr.isNotEmpty ? titleAttr : text;
        }
        if (byCells.length > 1) {
          final replySpan =
              byCells[1].querySelector('em span') ??
              byCells[1].querySelector('em a');
          final replyEm = byCells[1].querySelector('em');
          final replyTitle = normalize(
            replySpan?.attributes['title'] ??
                replyEm?.attributes['title'] ??
                '',
          );
          final replyText = normalize(replySpan?.text ?? replyEm?.text ?? '');
          lastReplyTime = replyTitle.isNotEmpty ? replyTitle : replyText;
        }

        // 回复数、浏览数
        int replies = 0;
        int views = 0;
        final numCell = row.querySelector('td.num');
        if (numCell != null) {
          replies = toInt(numCell.querySelector('a')?.text ?? '');
          views = toInt(numCell.querySelector('em')?.text ?? '');
        }

        posts.add(
          ZkPost(
            tid: tid,
            title: title,
            url: href.isNotEmpty ? href : threadUrl(tid),
            author: author,
            authorId: authorId,
            postTime: postTime,
            lastReplyTime: lastReplyTime,
            replies: replies,
            views: views,
            fid: fid,
            forumName: forumName,
          ),
        );
      }
      return posts;
    } on ForumListException {
      rethrow;
    } catch (e) {
      throw ForumListException(fid, '板块加载失败：$e');
    }
  }

  // ─── 用户资料 ────────────────────────────────────────────

  /// 获取当前登录用户资料
  Future<ZkUserProfile?> fetchMyProfile() async {
    try {
      await refreshCookie();
      final profileHtml = await _get(myProfileUrl);
      final doc = html_parser.parse(profileHtml);

      final displayName = normalize(
        doc.querySelector('.vwmy a')?.text ??
            doc.querySelector('#um .vwmy')?.text ??
            doc.querySelector('a[href*="home.php?mod=space&uid="]')?.text ??
            '',
      );
      if (displayName.isEmpty) return null;

      String avatarUrl = absoluteUrl(
        doc.querySelector('.avt img')?.attributes['src'] ??
            doc.querySelector('img[src*="avatar"]')?.attributes['src'] ??
            '',
      );
      final groupName = normalize(
        doc
                .querySelector('a[href*="home.php?mod=spacecp&ac=usergroup"]')
                ?.text ??
            '',
      );

      final bodyText = doc.body?.text ?? '';
      final threadsMatch = RegExp(r'主题\s*(\d+)').firstMatch(bodyText);
      final repliesMatch = RegExp(r'回复\s*(\d+)').firstMatch(bodyText);
      final favoritesMatch = RegExp(r'收藏\s*(\d+)').firstMatch(bodyText);

      String unreadPm = '0';
      final pmNode = doc.querySelector('#pm_ntc');
      if (pmNode != null) {
        final pmMatch = RegExp(r'(\d+)').firstMatch(pmNode.text);
        if (pmMatch != null) unreadPm = pmMatch.group(1)!;
      }

      // 步骤2: 获取果果数量
      String guoguo = '0';
      try {
        final creditHtml = await _get(myCreditUrl);
        final creditDoc = html_parser.parse(creditHtml);
        final lis = creditDoc.querySelectorAll('li.xi1.cl');
        for (final li in lis) {
          final match = RegExp(r'果果\s*[:：]?\s*(\d+)').firstMatch(li.text);
          if (match != null) {
            guoguo = match.group(1)!;
            break;
          }
        }
      } catch (_) {}

      return ZkUserProfile(
        displayName: displayName,
        avatarUrl: avatarUrl,
        groupName: groupName,
        guoguo: guoguo,
        threads: threadsMatch?.group(1) ?? '0',
        replies: repliesMatch?.group(1) ?? '0',
        favorites: favoritesMatch?.group(1) ?? '0',
        unreadPm: unreadPm,
      );
    } catch (e) {
      return null;
    }
  }

  /// 获取 PLUS 状态
  Future<bool> fetchPlusEnabled() async {
    try {
      await refreshCookie();
      if (_cookie.isEmpty) return false;
      final body = await _get(plusUrl);
      return body.contains('Plus有效期至') ||
          RegExp(r'Plus\s*有效期\s*至').hasMatch(body);
    } catch (_) {
      return false;
    }
  }

  // ─── 登录检测 ────────────────────────────────────────────

  /// 检测是否已登录（从 Cookie）
  Future<bool> isLoggedIn() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri(baseUrl),
    );
    for (final c in cookies) {
      if (c.name.contains('discuz_uid') || c.name.endsWith('_uid')) {
        if (c.value != '0' && c.value.isNotEmpty) return true;
      }
      if (c.name.endsWith('_auth') && c.value.isNotEmpty) return true;
    }
    return false;
  }

  /// 获取当前登录用户的 uid
  Future<String?> getUid() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri(baseUrl),
    );
    for (final c in cookies) {
      final name = c.name.toLowerCase();
      if (name.contains('discuz_uid') || name.endsWith('_uid')) {
        if (c.value != '0' && c.value.isNotEmpty) return c.value;
      }
    }

    await refreshCookie();
    if (_cookie.isEmpty) return null;
    final html = await _get(checkLoginUrl);
    final document = html_parser.parse(html);
    final links = document.querySelectorAll(
      'a[href*="home.php?mod=space&uid="]',
    );
    for (final link in links) {
      final href = link.attributes['href'] ?? '';
      final match = RegExp(r'[?&]uid=(\d+)').firstMatch(href);
      final uid = match?.group(1) ?? '';
      if (uid.isNotEmpty && uid != '0') return uid;
    }
    final uidFromScript = RegExp(
      r'''discuz_uid\s*[=:]\s*['"]?(\d+)''',
    ).firstMatch(html);
    final uidFromLink = RegExp(r'[?&]uid=(\d+)').firstMatch(html);
    final uid = uidFromScript?.group(1) ?? uidFromLink?.group(1) ?? '';
    return uid.isEmpty || uid == '0' ? null : uid;
  }

  /// 清除所有 Cookie
  Future<void> clearCookies() async {
    await CookieManager.instance().deleteAllCookies();
    _cookie = '';
  }
}
