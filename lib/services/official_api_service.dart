import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/private_message.dart';
import '../models/thread_detail.dart';
import '../models/zk_post.dart';
import '../config/constants.dart';
import '../utils/helpers.dart';

class OfficialApiException implements Exception {
  final String message;
  final bool loginRequired;

  const OfficialApiException(this.message, {this.loginRequired = false});

  @override
  String toString() => message;
}

class SearchPostsResult {
  final List<ZkPost> posts;
  final String searchId;

  const SearchPostsResult({required this.posts, required this.searchId});
}

class PostingThreadType {
  final String id;
  final String name;

  const PostingThreadType({required this.id, required this.name});

  factory PostingThreadType.fromJson(Map<String, dynamic> json) =>
      PostingThreadType(
        id: _text(json['typeid']),
        name: _text(json['typename']),
      );
}

class NewThreadPreparation {
  final List<PostingThreadType> threadTypes;

  const NewThreadPreparation({required this.threadTypes});
}

class NewThreadResult {
  final String tid;
  final String pid;

  const NewThreadResult({required this.tid, required this.pid});
}

/// 官方用户资料（mobile API module=profile）。
class OfficialUserProfile {
  final String userId;
  final String userName;
  final String avatar;
  final String groupTitle;
  final String credits;
  final String posts;
  final String threads;
  final String registeredAt;

  const OfficialUserProfile({
    required this.userId,
    required this.userName,
    required this.avatar,
    required this.groupTitle,
    required this.credits,
    required this.posts,
    required this.threads,
    required this.registeredAt,
  });

  factory OfficialUserProfile.fromJson(Map<String, dynamic> json) {
    final groupMap = _map(json['group']);
    final rawGroup = _text(groupMap['grouptitle']);
    final fallbackGroup = _text(json['grouptitle']);
    final authorTitle = _text(json['authortitle']);
    String groupTitle = rawGroup.isNotEmpty
        ? rawGroup
        : (fallbackGroup.isNotEmpty ? fallbackGroup : authorTitle);

    if (groupTitle.isEmpty) {
      final gid = _text(groupMap['groupid']).isNotEmpty
          ? _text(groupMap['groupid'])
          : _text(json['groupid']);
      groupTitle = discuzUserGroupTitle(gid);
    }

    return OfficialUserProfile(
      userId: _text(json['uid']),
      userName: _text(json['username']),
      avatar: avatarUrl(_text(json['avatar'])),
      groupTitle: groupTitle,
      credits: _text(json['credits']),
      posts: _text(json['posts']),
      threads: _text(json['threads']),
      registeredAt: _text(json['regdate']),
    );
  }
}

class OfficialApiService {
  static const _mobileEndpoint = 'http://www.zuanke8.com/api/mobile/index.php';
  static const _signKey = 'lpj31rg85htgtj';

  static final OfficialApiService instance = OfficialApiService._internal();

  final http.Client _client;
  final Map<String, OfficialUserProfile> _profileCache = {};
  final Map<String, List<ParsedRatingRecord>> _ratingCache = {};
  String _webFormhash = '';

  factory OfficialApiService({http.Client? client}) {
    if (client != null) return OfficialApiService._internal(client: client);
    return instance;
  }

  OfficialApiService._internal({http.Client? client})
      : _client = client ?? http.Client();

  Future<NewThreadPreparation> prepareNewThread(String fid) async {
    final context = await _requestContext(
      requireLogin: true,
      preferWebLogin: true,
    );
    final json = await _executeMobileRequest(
      module: 'prethread',
      signedFields: const {},
      fields: {'fid': fid},
      context: context,
      retries: 1,
    );
    final data = _map(_requireSuccess(json)['data']);
    return NewThreadPreparation(
      threadTypes: _list(data['threadtypes'])
          .map((item) => PostingThreadType.fromJson(_map(item)))
          .where((type) => type.name.isNotEmpty)
          .toList(),
    );
  }

  Future<NewThreadResult> publishThread({
    required String fid,
    required String subject,
    required String message,
    required String typeId,
    List<String> imagePaths = const [],
  }) async {
    final aids = <String>[];
    for (final path in imagePaths) {
      aids.add(await uploadImage(path));
    }
    final finalMessage = [
      message,
      for (final aid in aids) '[attachimg]$aid[/attachimg]',
    ].join('\n');
    final result = _requireSuccess(
      await _legacyRequest(
        module: 'newthread',
        fields: {
          'fid': fid,
          'subject': subject,
          'message': finalMessage,
          'readperm': '',
          'typeid': typeId,
          'allownoticeauthor': '1',
          'allowphone': '1',
          'topicsubmit': 'yes',
          for (final aid in aids) 'attachnew[$aid][description]': '',
        },
      ),
    );
    final data = _map(result['data']);
    final published = NewThreadResult(
      tid: _text(data['tid']),
      pid: _text(data['pid']),
    );
    if (published.tid.isEmpty) {
      throw const OfficialApiException('发布成功，但服务器没有返回帖子编号');
    }
    return published;
  }

  Future<String> uploadImage(String path) async {
    final cookies = await _webCookies();
    final cookieHeader = cookies
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
    if (cookieHeader.isEmpty) {
      throw const OfficialApiException('请先登录后再上传图片', loginRequired: true);
    }
    final page = await _client
        .get(
          Uri.parse(
            'http://www.zuanke8.com/forum.php?mod=post&action=newthread&fid=15',
          ),
          headers: {'Cookie': cookieHeader, 'User-Agent': userAgent},
        )
        .timeout(const Duration(seconds: 20));
    final text = decodeGbk(page.bodyBytes);
    final uid =
        RegExp(
          r'''(?:(?:"uid"|uid)\s*[:=]\s*['"]?)(\d+)''',
        ).firstMatch(text)?.group(1) ??
        '';
    final hash =
        RegExp(
          r'''(?:(?:"hash"|hash)\s*[:=]\s*['"])([a-fA-F0-9]{32})''',
        ).firstMatch(text)?.group(1) ??
        '';
    if (uid.isEmpty || hash.isEmpty)
      throw const OfficialApiException('未取得图片上传参数，请重新登录后再试');
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse(
              'http://www.zuanke8.com/misc.php?mod=swfupload&operation=upload&simple=1&type=image',
            ),
          )
          ..headers.addAll({'Cookie': cookieHeader, 'User-Agent': userAgent})
          ..fields['uid'] = uid
          ..fields['hash'] = hash
          ..files.add(await http.MultipartFile.fromPath('Filedata', path));
    final response = await http.Response.fromStream(
      await request.send(),
    ).timeout(const Duration(seconds: 45));
    final parts = decodeGbk(response.bodyBytes).trim().split('|');
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        parts.length < 3 ||
        parts[0] != 'DISCUZUPLOAD' ||
        parts[1] != '0') {
      throw const OfficialApiException('图片上传失败，请稍后重试');
    }
    return parts[2];
  }

  /// App 只保留网页登录，所有登录能力统一以 WebView Cookie 为准。
  Future<bool> isAnyLoggedIn() => hasWebLogin();

  Future<bool> hasWebLogin() async {
    final cookies = await _webCookies();
    return cookies.any(
      (cookie) =>
          ((cookie.name.contains('discuz_uid') ||
                  cookie.name.endsWith('_uid')) &&
              cookie.value.isNotEmpty &&
              cookie.value != '0') ||
          (cookie.name.endsWith('_auth') && cookie.value.isNotEmpty),
    );
  }

  Future<ThreadDetail> fetchThread({
    required String tid,
    int page = 1,
    String? authorId,
  }) async {
    final fields = <String, String>{'tid': tid, 'page': '$page'};
    if (authorId != null && authorId.isNotEmpty) {
      fields['authorid'] = authorId;
    }
    final json = await _mobileRequest(module: 'viewthread', fields: fields);
    return ThreadDetail.fromJson(_map(_requireSuccess(json)['data']));
  }

  Future<RatingRange> fetchRatingRange({
    required String tid,
    required String pid,
  }) async {
    final json = await _mobileRequest(
      module: 'rate',
      fields: {'tid': tid, 'pid': pid, 'inajax': '1'},
    );
    return RatingRange.fromJson(_map(_requireSuccess(json)['data']));
  }

  List<ParsedRatingRecord>? getCachedRatingDetails(String tid, String pid) {
    if (tid.isEmpty || pid.isEmpty) return null;
    return _ratingCache['$tid:$pid'];
  }

  Future<List<ParsedRatingRecord>> fetchRatingDetails({
    required String tid,
    required String pid,
  }) async {
    if (tid.isEmpty || pid.isEmpty) return const [];
    final cacheKey = '$tid:$pid';
    final existing = _ratingCache[cacheKey];
    if (existing != null) return existing;

    final context = await _requestContext(
      requireLogin: false,
      preferWebLogin: true,
    );

    final uri = Uri.parse(
      'http://www.zuanke8.com/forum.php?mod=misc&action=viewratings&tid=$tid&pid=$pid',
    );

    try {
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          if (context.cookieHeader.isNotEmpty) 'Cookie': context.cookieHeader,
        },
      ).timeout(const Duration(seconds: 8));

      final html = decodeGbk(response.bodyBytes);
      final records = parseRatingRecords(html);
      if (records.isNotEmpty) {
        _ratingCache[cacheKey] = records;
      }
      return records;
    } catch (_) {
      return const [];
    }
  }

  Future<void> rateFloor({
    required String tid,
    required String pid,
    required int score,
  }) async {
    final context = await _requestContext();
    final json = await _mobileRequest(
      module: 'rate',
      signedFields: {'formhash': context.formhash},
      fields: {
        'tid': tid,
        'pid': pid,
        'inajax': '1',
        'score1': '$score',
        'ratesubmit': 'yes',
      },
      retries: 0,
    );
    _requireSuccess(json);
  }

  Future<void> replyThread({
    required String tid,
    required String message,
    String? repquote,
    String? repAuthor,
    String? repDateline,
    String? repMessage,
    String noticeTrim = '',
    List<String> imagePaths = const [],
  }) async {
    final aids = <String>[];
    for (final path in imagePaths) {
      aids.add(await uploadImage(path));
    }
    final finalMessage = [
      message,
      for (final aid in aids) '[attachimg]$aid[/attachimg]',
    ].join('\n');

    final fields = <String, String>{
      'message': finalMessage,
      'replysubmit': 'yes',
      'tid': tid,
      'mobiletype': '2',
      for (final aid in aids) 'attachnew[$aid][description]': '',
    };

    if (repquote != null && repquote.isNotEmpty) {
      fields['repquote'] = repquote;
      fields['reppost'] = repquote;
      if (noticeTrim.isNotEmpty) {
        fields['noticetrimstr'] = noticeTrim;
      } else {
        String quoteStr = '';
        try {
          final noticeJson = await _legacyGet(
            module: 'sendreply',
            query: {'tid': tid, 'repquote': repquote},
          );
          final data = _map(noticeJson['data']);
          quoteStr = _text(data['noticetrimstr']);
        } catch (_) {}

        if (quoteStr.isEmpty && repAuthor != null && repAuthor.isNotEmpty) {
          final cleanMsg = (repMessage ?? '')
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .trim()
              .replaceAll(RegExp(r'\s+'), ' ');
          final truncatedMsg = cleanMsg.length > 80
              ? '${cleanMsg.substring(0, 80)}...'
              : cleanMsg;
          quoteStr =
              '[quote][size=2][color=#999999]$repAuthor 发表于 ${repDateline ?? ''}[/color][/size]\n$truncatedMsg[/quote]';
        }
        if (quoteStr.isNotEmpty) {
          fields['noticetrimstr'] = quoteStr;
        }
      }
    }

    _requireSuccess(await _legacyRequest(module: 'sendreply', fields: fields));
  }

  Future<void> commentFloor({
    required String tid,
    required String pid,
    required String message,
  }) async {
    _requireSuccess(
      await _legacyRequest(
        module: 'comment',
        fields: {
          'inajax': '1',
          'comment': 'yes',
          'commentsubmit': 'yes',
          'tid': tid,
          'pid': pid,
          'message': message,
        },
      ),
    );
  }

  Future<void> reportFloor({
    required String tid,
    required String pid,
    String message = '违规内容',
  }) async {
    final context = await _requestContext(requireLogin: true);
    final fields = <String, String>{
      'formhash': context.formhash,
      'reportsubmit': 'true',
      'rtype': 'post',
      'rid': pid,
      'url': 'forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=$pid',
      'message': message,
      'handlekey': 'miscreport',
    };
    final uri = Uri.parse('http://www.zuanke8.com/misc.php?mod=report&inajax=1');
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        if (context.cookieHeader.isNotEmpty) 'Cookie': context.cookieHeader,
        'User-Agent': userAgent,
      },
      body: formEncodeGbk(fields),
    );
    final text = decodeGbk(response.bodyBytes);
    if (text.contains('login') || text.contains('请先登录')) {
      throw const OfficialApiException('请先登录后再使用该功能', loginRequired: true);
    }
    if (text.contains('两次举报间隔') || text.contains('已经举报')) {
      throw const OfficialApiException('该内容已在处理中，请勿重复举报');
    }
  }

  Future<List<PrivateConversation>> fetchConversations({int page = 1}) async {
    final json = await _mobileRequest(
      module: 'mypm',
      fields: {'page': '$page'},
    );
    final data = _map(_requireSuccess(json)['data']);
    return _list(
      data['list'],
    ).map((item) => PrivateConversation.fromJson(_map(item))).toList();
  }

  Future<List<PrivateMessage>> fetchMessages(String userId) async {
    final json = await _mobileRequest(
      module: 'mypm',
      fields: {'subop': 'view', 'touid': userId},
    );
    final data = _map(_requireSuccess(json)['data']);
    return _list(
      data['list'],
    ).map((item) => PrivateMessage.fromJson(_map(item))).toList();
  }

  Future<void> sendPrivateMessage({
    required String userId,
    required String message,
  }) async {
    _requireSuccess(
      await _legacyRequest(
        module: 'sendpm',
        fields: {'pmsubmit': 'yes', 'message': message, 'touid': userId},
      ),
    );
  }

  /// 他人资料（官方原生客户端同样使用 module=profile）。
  Future<OfficialUserProfile> fetchUserProfile(String userId, {bool forceRefresh = false}) async {
    if (!forceRefresh && _profileCache.containsKey(userId)) {
      return _profileCache[userId]!;
    }
    final json = await _mobileRequest(
      module: 'profile',
      fields: {'uid': userId},
    );
    final data = _map(_requireSuccess(json)['data']);
    final space = _map(data['space']);
    final merged = <String, dynamic>{
      ...data,
      ...space,
      if (space['group'] != null) 'group': space['group'],
      if (data['group'] != null && space['group'] == null) 'group': data['group'],
      if (space['grouptitle'] != null) 'grouptitle': space['grouptitle'],
      if (data['grouptitle'] != null && space['grouptitle'] == null)
        'grouptitle': data['grouptitle'],
      if (space['groupid'] != null) 'groupid': space['groupid'],
      if (data['groupid'] != null && space['groupid'] == null)
        'groupid': data['groupid'],
    };
    final profile = OfficialUserProfile.fromJson(merged);
    _profileCache[userId] = profile;
    return profile;
  }

  OfficialUserProfile? getCachedUserProfile(String userId) => _profileCache[userId];

  /// 指定用户发布的主题帖；不包含其回复记录。
  Future<List<ZkPost>> fetchUserThreads({
    required String userId,
    int page = 1,
  }) async {
    final json = await _mobileRequest(
      module: 'userthread',
      fields: {'uid': userId, 'page': '$page'},
    );
    final data = _map(_requireSuccess(json)['data']);
    return _list(
      data['data'],
    ).map((item) => _threadFromJson(_map(item))).toList();
  }

  // ─── 搜索 ────────────────────────────────────────────────

  Future<SearchPostsResult> searchPosts({
    required String keyword,
    int page = 1,
    String searchId = '',
  }) async {
    final fields = <String, String>{
      'searchsubmit': 'yes',
      'page': '$page',
      'orderby': 'lastpost',
      if (page == 1 || searchId.isEmpty) 'srchtxt': keyword,
      if (page > 1 && searchId.isNotEmpty) 'searchid': searchId,
    };
    final json = await _legacyRequest(
      module: 'search',
      fields: fields,
      requireLogin: false,
      retries: 1,
    );
    final data = _map(_requireSuccess(json)['data']);
    return SearchPostsResult(
      posts: _list(
        data['data'],
      ).map((item) => _threadFromJson(_map(item))).toList(),
      searchId: _text(data['searchid']).isEmpty
          ? searchId
          : _text(data['searchid']),
    );
  }

  // ─── 我的发布 / 回复 / 收藏 ─────────────────────────────

  /// 我的发布（官方 mobile API module=userthread）
  Future<List<ZkPost>> fetchMyThreads({int page = 1}) async {
    final uid = await _currentUid();
    if (uid.isEmpty) {
      throw const OfficialApiException('请先登录后再使用该功能', loginRequired: true);
    }
    return fetchUserThreads(userId: uid, page: page);
  }

  /// 我的回复（官方 mobile API module=userreply 与网页版双重兜底，支持全量翻页）
  Future<List<ZkPost>> fetchMyReplies({int page = 1}) async {
    final uid = await _currentUid();
    if (uid.isEmpty) {
      throw const OfficialApiException('请先登录后再使用该功能', loginRequired: true);
    }
    List<ZkPost> list = [];
    try {
      final json = await _mobileRequest(
        module: 'userreply',
        fields: {'uid': uid, 'page': '$page'},
      );
      final data = _map(_requireSuccess(json)['data']);
      list = _list(
        data['data'],
      ).map((item) => _threadFromJson(_map(item))).toList();
    } catch (_) {}

    // 若 mobile API 在翻页时无数据、或者获取条目较少，自动由网页版补充翻页数据
    if (list.isEmpty) {
      try {
        final webList = await _fetchMyRepliesFromWeb(page: page);
        if (webList.isNotEmpty) {
          return webList;
        }
      } catch (_) {}
    }

    return list;
  }

  Future<List<ZkPost>> _fetchMyRepliesFromWeb({int page = 1}) async {
    final context = await _requestContext();
    if (context.cookieHeader.isEmpty) return const [];
    final uri = Uri.parse(
      '$baseUrl/forum.php?mod=guide&view=my&type=reply&page=$page',
    );
    final res = await _client.get(
      uri,
      headers: {
        'Cookie': context.cookieHeader,
        'User-Agent': mobileUserAgent,
      },
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final doc = html_parser.parse(decodeGbk(res.bodyBytes));
    final rows = doc.querySelectorAll('tbody[id^="normalthread_"]');
    final posts = <ZkPost>[];
    for (final row in rows) {
      final tidAttr = row.attributes['id'] ?? '';
      final tid = tidAttr.replaceFirst('normalthread_', '').trim();
      if (tid.isEmpty) continue;
      final titleEl = row.querySelector('a.xst');
      final title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) continue;
      final authorEl = row.querySelector('.by cite a');
      final author = authorEl?.text.trim() ?? '';
      final authorIdMatch = RegExp(r'uid=(\d+)').firstMatch(authorEl?.attributes['href'] ?? '');
      final authorId = authorIdMatch?.group(1) ?? '';
      final forumEl = row.querySelector('th em a');
      final forumName = forumEl?.text.trim() ?? '';
      final fidMatch = RegExp(r'fid=(\d+)').firstMatch(forumEl?.attributes['href'] ?? '');
      final fid = int.tryParse(fidMatch?.group(1) ?? '') ?? 0;
      final numEl = row.querySelector('td.num a.xi2');
      final replies = numEl?.text.trim() ?? '0';
      final viewsEl = row.querySelector('td.num em');
      final views = viewsEl?.text.trim() ?? '0';
      final timeEl = row.querySelector('td.by em span') ?? row.querySelector('td.by em');
      final time = timeEl?.text.trim() ?? '';

      posts.add(ZkPost(
        tid: tid,
        title: title,
        url: '',
        author: author,
        authorId: authorId,
        forumName: forumName,
        fid: fid,
        replies: toInt(replies),
        views: toInt(views),
        postTime: time,
        lastReplyTime: time,
      ));
    }
    return posts;
  }

  /// 我的收藏（官方 mobile API module=myfavthread）
  Future<List<ZkPost>> fetchMyFavorites({int page = 1}) async {
    final json = await _mobileRequest(
      module: 'myfavthread',
      fields: {'page': '$page'},
    );
    final data = _map(_requireSuccess(json)['data']);
    return _list(
      data['list'],
    ).map((item) => _favoriteFromJson(_map(item))).toList();
  }

  /// 收藏本帖（官方 mobile API 与 spacecp 双重保障，返回 favid）
  Future<String> favoriteThread(String tid) async {
    final context = await _requestContext();
    try {
      final json = await _mobileRequest(
        module: 'favthread',
        signedFields: {'formhash': context.formhash},
        fields: {
          'id': tid,
          'favoritesubmit': 'true',
          'inajax': '1',
        },
        retries: 0,
      );
      final data = _map(_requireSuccess(json)['data']);
      return _text(data['favid']);
    } catch (_) {
      if (context.cookieHeader.isNotEmpty) {
        final uri = Uri.parse(
          '$baseUrl/home.php?mod=spacecp&ac=favorite&type=thread&id=$tid&formhash=${context.formhash}&inajax=1',
        );
        final res = await _client.get(
          uri,
          headers: {
            'Cookie': context.cookieHeader,
            'User-Agent': mobileUserAgent,
            'Referer': '$baseUrl/forum.php?mod=viewthread&tid=$tid',
          },
        );
        final body = decodeGbk(res.bodyBytes);
        if (body.contains('favorite_do_success') ||
            body.contains('成功') ||
            body.contains('已收藏') ||
            body.contains('favorite_repeat')) {
          final match = RegExp(r'favid=(\d+)').firstMatch(body);
          return match?.group(1) ?? '';
        }
      }
      rethrow;
    }
  }

  /// 取消收藏（官方 mobile API favthread delete 与 spacecp 双重保障）
  Future<void> unfavoriteThread({String favId = '', String tid = ''}) async {
    final context = await _requestContext();
    String targetFavId = favId.trim();

    // 如果未传 favId 但传了 tid，尝试从收藏列表快速查出对应的 favid
    if (targetFavId.isEmpty && tid.isNotEmpty) {
      try {
        final favorites = await fetchMyFavorites(page: 1);
        final hit = favorites.cast<ZkPost?>().firstWhere(
          (p) => p?.tid == tid,
          orElse: () => null,
        );
        if (hit != null && hit.favId.isNotEmpty) {
          targetFavId = hit.favId;
        }
      } catch (_) {}
    }

    // 1. 优先尝试官方 mobile API: module=favthread, op=delete, favid=...
    if (targetFavId.isNotEmpty) {
      try {
        final json = await _mobileRequest(
          module: 'favthread',
          signedFields: {'formhash': context.formhash},
          fields: {
            'favid': targetFavId,
            'op': 'delete',
            'deletesubmit': 'yes',
            'inajax': '1',
            'type': 'all',
          },
          retries: 0,
        );
        _requireSuccess(json);
        return;
      } catch (_) {}
    }

    // 2. 网页端 spacecp delete 兜底
    if (context.cookieHeader.isNotEmpty) {
      final deleteUrl = targetFavId.isNotEmpty
          ? '$baseUrl/home.php?mod=spacecp&ac=favorite&op=delete&favid=$targetFavId&formhash=${context.formhash}&inajax=1'
          : '$baseUrl/home.php?mod=spacecp&ac=favorite&type=thread&id=$tid&op=delete&formhash=${context.formhash}&inajax=1';

      final res = await _client.get(
        Uri.parse(deleteUrl),
        headers: {
          'Cookie': context.cookieHeader,
          'User-Agent': mobileUserAgent,
          if (tid.isNotEmpty) 'Referer': '$baseUrl/forum.php?mod=viewthread&tid=$tid',
        },
      );
      final body = decodeGbk(res.bodyBytes);
      if (body.contains('succeed') ||
          body.contains('成功') ||
          body.contains('do_success') ||
          body.contains('favorite_delete')) {
        return;
      }
    }

    throw const OfficialApiException('取消收藏失败，请稍后重试');
  }

  /// 当前登录用户 uid（优先官方会话，其次网页 Cookie）
  Future<String> _currentUid() async {
    final cookieUid = await webUid();
    if (cookieUid.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('uid', cookieUid);
      await prefs.setString('discuz_uid', cookieUid);
      return cookieUid;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('uid') ?? prefs.getString('discuz_uid') ?? '';
  }

  /// 从网页 Cookie 中解析当前登录用户 uid
  Future<String> webUid() async {
    final cookies = await _webCookies();
    for (final cookie in cookies) {
      if (cookie.name.contains('discuz_uid') || cookie.name.endsWith('_uid')) {
        if (cookie.value.isNotEmpty && cookie.value != '0') {
          return cookie.value;
        }
      }
    }
    return '';
  }

  ZkPost _threadFromJson(Map<String, dynamic> json) {
    final fid = toInt(_text(json['fid']));
    String forumName = _text(json['forumname']);
    if (forumName.isEmpty && fid > 0) {
      final match = browseForums.where((f) => f.fid == fid);
      if (match.isNotEmpty) {
        forumName = match.first.name;
      }
    }
    return ZkPost(
      tid: _text(json['tid']),
      title: _text(json['subject']),
      url: '',
      author: _text(json['author']),
      authorId: _text(json['authorid'] ?? json['uid']),
      postTime: _text(json['dateline']),
      lastReplyTime: _text(json['lastpost']),
      replies: toInt(_text(json['replies'])),
      views: toInt(_text(json['views'])),
      fid: fid,
      forumName: forumName,
    );
  }

  ZkPost _favoriteFromJson(Map<String, dynamic> json) {
    final fid = toInt(_text(json['fid']));
    String forumName = _text(json['forumname']);
    if (forumName.isEmpty && fid > 0) {
      final match = browseForums.where((f) => f.fid == fid);
      if (match.isNotEmpty) {
        forumName = match.first.name;
      }
    }
    return ZkPost(
      tid: _text(json['id']),
      title: _text(json['title']),
      url: '',
      author: _text(json['author']),
      authorId: _text(json['authorid'] ?? json['uid']),
      postTime: _text(json['dateline']),
      lastReplyTime: '',
      replies: toInt(_text(json['replies'])),
      views: toInt(_text(json['views'])),
      fid: fid,
      forumName: forumName,
      favId: _text(json['favid']),
    );
  }

  Future<Map<String, dynamic>> _mobileRequest({
    required String module,
    Map<String, String> signedFields = const {},
    Map<String, String> fields = const {},
    int retries = 1,
  }) async {
    final context = await _requestContext(
      requireLogin: false,
      preferWebLogin: true,
    );
    try {
      return await _executeMobileRequest(
        module: module,
        signedFields: signedFields,
        fields: fields,
        context: context,
        retries: retries,
      );
    } on OfficialApiException catch (error) {
      if (!error.loginRequired || context.sessionId.isEmpty) {
        rethrow;
      }
      final fallback = await _requestContext(
        requireLogin: false,
        preferWebLogin: false,
      );
      if (fallback.sessionId == context.sessionId) {
        rethrow;
      }
      return _executeMobileRequest(
        module: module,
        signedFields: signedFields,
        fields: fields,
        context: fallback,
        retries: retries,
      );
    }
  }

  Future<Map<String, dynamic>> _executeMobileRequest({
    required String module,
    required Map<String, String> signedFields,
    required Map<String, String> fields,
    required _RequestContext context,
    required int retries,
  }) async {
    final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signed = <String, String>{
      'sessionid': context.sessionId,
      'version': '4.1',
      'zstamp': '$stamp',
      'module': module,
      ...signedFields,
    };
    final signSource = signed.keys.toList()..sort();
    final sign = md5
        .convert(
          utf8.encode(
            '${signSource.map((key) => '$key${signed[key]}').join()}$_signKey',
          ),
        )
        .toString();
    final uri = Uri.parse(
      _mobileEndpoint,
    ).replace(queryParameters: {...signed, 'sign': sign});
    return _sendJson(
      () => _client.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          if (context.cookieHeader.isNotEmpty) 'Cookie': context.cookieHeader,
        },
        body: fields,
      ),
      retries: retries,
    ).then((json) {
      _captureWebContext(json);
      return json;
    });
  }

  Future<Map<String, dynamic>> _legacyRequest({
    required String module,
    required Map<String, String> fields,
    bool requireLogin = true,
    bool preferWebLogin = true,
    int retries = 0,
  }) async {
    var context = await _requestContext(
      requireLogin: requireLogin,
      preferWebLogin: preferWebLogin,
    );
    if (context.formhash.isEmpty && preferWebLogin) {
      await _refreshWebFormhash(context.cookieHeader);
      context = await _requestContext(
        requireLogin: requireLogin,
        preferWebLogin: preferWebLogin,
      );
    }
    final uri = Uri.parse(_mobileEndpoint).replace(
      queryParameters: {
        'formhash': context.formhash,
        'version': '4',
        'sessionid': context.sessionId,
        'module': module,
      },
    );
    final encoded = formEncodeGbk(fields);
    if (module == 'search') {
      return _sendSearchRequest(
        uri: uri,
        encodedBody: encoded,
        cookieHeader: context.cookieHeader,
        retries: retries,
      );
    }
    return _sendJson(
      () => _client.post(
        uri,
        headers: {
          // body 已由 formEncodeGbk 预编码为纯 ASCII 的 URL 编码串，
          // 不能再写 charset=GBK，否则 http 包编码 String body 时会抛
          // FormatException: Unsupported encoding "GBK"。
          'Content-Type': 'application/x-www-form-urlencoded',
          if (context.cookieHeader.isNotEmpty) 'Cookie': context.cookieHeader,
        },
        body: encoded,
      ),
      retries: retries,
    );
  }

  Future<Map<String, dynamic>> _legacyGet({
    required String module,
    required Map<String, String> query,
    bool requireLogin = true,
  }) async {
    final context = await _requestContext(requireLogin: requireLogin);
    final uri = Uri.parse(_mobileEndpoint).replace(
      queryParameters: {
        'formhash': context.formhash,
        'version': '4',
        'sessionid': context.sessionId,
        'module': module,
        ...query,
      },
    );
    return _sendJson(
      () => _client.get(
        uri,
        headers: {
          if (context.cookieHeader.isNotEmpty) 'Cookie': context.cookieHeader,
          'User-Agent': userAgent,
        },
      ),
      retries: 0,
    );
  }

  Future<Map<String, dynamic>> _sendSearchRequest({
    required Uri uri,
    required String encodedBody,
    required String cookieHeader,
    required int retries,
  }) async {
    return _sendJson(() async {
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers.addAll({
          'Content-Type': 'application/x-www-form-urlencoded',
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
        })
        ..body = encodedBody;
      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 300 || response.statusCode >= 400) {
        return response;
      }
      final location = response.headers['location'];
      if (location == null || location.isEmpty) return response;
      final destination = uri.resolve(location.replaceAll('&amp;', '&'));
      return _client.get(
        destination,
        headers: {if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader},
      );
    }, retries: retries);
  }

  Future<void> _refreshWebFormhash(String cookieHeader) async {
    final response = await _client
        .get(
          Uri.parse('http://www.zuanke8.com/forum.php?mobile=2'),
          headers: {if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) return;
    final document = html_parser.parse(decodeGbk(response.bodyBytes));
    final formhash = document
        .querySelector('input[name="formhash"]')
        ?.attributes['value'];
    if (formhash != null && formhash.isNotEmpty) _webFormhash = formhash;
  }

  Future<_RequestContext> _requestContext({
    bool requireLogin = true,
    bool preferWebLogin = true,
  }) async {
    final cookies = await _webCookies();
    final cookieHeader = cookies
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
    final webLoggedIn = cookies.any((cookie) {
      final name = cookie.name.toLowerCase();
      return ((name.contains('discuz_uid') || name.endsWith('_uid')) &&
              cookie.value.isNotEmpty &&
              cookie.value != '0') ||
          (name.endsWith('_auth') && cookie.value.isNotEmpty);
    });
    var webSessionId = '';
    for (final cookie in cookies) {
      if (cookie.name.toLowerCase().endsWith('_sid') &&
          cookie.value.isNotEmpty) {
        webSessionId = cookie.value;
        break;
      }
    }
    if (requireLogin && !webLoggedIn) {
      throw const OfficialApiException('请先登录后再使用该功能', loginRequired: true);
    }
    return _RequestContext(
      sessionId: preferWebLogin && webLoggedIn ? webSessionId : '',
      formhash: preferWebLogin && webLoggedIn && _webFormhash.isNotEmpty
          ? _webFormhash
          : '',
      cookieHeader: cookieHeader,
    );
  }

  Future<List<Cookie>> _webCookies() {
    return CookieManager.instance().getCookies(
      url: WebUri('http://www.zuanke8.com'),
    );
  }

  void _captureWebContext(Map<String, dynamic> json) {
    final data = _map(json['data']);
    final formhash = '${data['formhash'] ?? ''}';
    if (formhash.isNotEmpty) _webFormhash = formhash;
  }

  static bool _isSensitiveWordMessage(String text) {
    final lower = text.toLowerCase();
    return lower.contains('post_words_banned') ||
        lower.contains('word_banned') ||
        text.contains('敏感词') ||
        text.contains('不良媒体') ||
        text.contains('违禁词') ||
        text.contains('不良信息');
  }

  static String _extractDiscuzErrorFromHtmlOrXml(String text) {
    if (text.contains('<![CDATA[')) {
      final match = RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true).firstMatch(text);
      if (match != null) {
        final cdata = match.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
        if (cdata.isNotEmpty) return cdata;
      }
    }
    try {
      final doc = html_parser.parse(text);
      final alertNode = doc.querySelector('.alert_error, .jump_c, #messagetext, p, body');
      if (alertNode != null) {
        final t = alertNode.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (t.isNotEmpty && t.length < 150) return t;
      }
    } catch (_) {}
    return '';
  }

  Future<Map<String, dynamic>> _sendJson(
    Future<http.Response> Function() request, {
    int retries = 1,
  }) async {
    try {
      final response = await _requestWithRetry(request, retries);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OfficialApiException('服务器连接失败 (${response.statusCode})');
      }
      final text = _decodeJson(response.bodyBytes);
      if (text.isEmpty) throw const OfficialApiException('服务器返回了空数据');

      // 优先检测敏感词/不良媒体拦截
      if (_isSensitiveWordMessage(text)) {
        throw const OfficialApiException('内容包含敏感词，请修改！');
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        final extracted = _extractDiscuzErrorFromHtmlOrXml(text);
        if (extracted.isNotEmpty) {
          if (_isSensitiveWordMessage(extracted)) {
            throw const OfficialApiException('内容包含敏感词，请修改！');
          }
          throw OfficialApiException(extracted);
        }
        throw const OfficialApiException('服务器返回格式异常');
      }

      if (decoded is! Map<String, dynamic>) {
        throw const OfficialApiException('服务器返回格式异常');
      }
      if (decoded['error'] == 'to_login') {
        throw const OfficialApiException('登录会话已失效，请重新登录', loginRequired: true);
      }
      return decoded;
    } on OfficialApiException {
      rethrow;
    } catch (error) {
      throw OfficialApiException('网络请求失败：$error');
    }
  }

  /// 对非 2xx / 网络错误自动重试一次，规避首次请求偶发失败
  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function() request,
    int retries,
  ) async {
    http.Response? last;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final response = await request().timeout(const Duration(seconds: 20));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        last = response;
      } catch (_) {
        last = null;
      }
      if (attempt < retries) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    if (last != null) return last;
    throw const OfficialApiException('网络请求失败，请稍后重试');
  }

  /// legacy 接口（sendpm/sendreply/comment）响应可能是 GBK 编码，
  /// 先按严格 UTF-8 解码，失败再回退 GBK。
  String _decodeJson(List<int> bytes) {
    try {
      return utf8.decode(bytes).trim();
    } on FormatException {
      return decodeGbk(bytes).trim();
    }
  }

  Map<String, dynamic> _requireSuccess(Map<String, dynamic> json) {
    final code = int.tryParse('${json['ResultCode'] ?? 0}') ?? 0;
    if (code == 1) return json;

    var message = '${json['ResultMessage'] ?? ''}'.trim();
    if (message.isEmpty) {
      final msgObj = json['Message'] ?? json['message'];
      if (msgObj is Map) {
        message = '${msgObj['messagestr'] ?? msgObj['messageval'] ?? ''}'.trim();
      } else if (msgObj != null) {
        message = '$msgObj'.trim();
      }
    }
    if (message.isEmpty && json['error'] != null) {
      message = '${json['error']}'.trim();
    }

    if (_isSensitiveWordMessage(message) || _isSensitiveWordMessage('$json')) {
      throw const OfficialApiException('内容包含敏感词，请修改！');
    }

    final loginRequired = message.contains('登录') || message.contains('签名');
    throw OfficialApiException(
      message.isEmpty ? '操作失败，请稍后重试' : message,
      loginRequired: loginRequired,
    );
  }
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<dynamic> _list(dynamic value) => value is List ? value : const [];

String _text(dynamic value) => value?.toString() ?? '';

class _RequestContext {
  final String sessionId;
  final String formhash;
  final String cookieHeader;

  const _RequestContext({
    required this.sessionId,
    required this.formhash,
    required this.cookieHeader,
  });
}
