import '../utils/helpers.dart';

class ThreadDetail {
  final String tid;
  final String fid;
  final String forumName;
  final String subject;
  final String author;
  final String authorId;
  final String avatar;
  final String dateline;
  final int views;
  final int replies;
  final int totalPage;
  final bool favorite;
  final String favId;
  final List<ThreadFloor> floors;

  const ThreadDetail({
    required this.tid,
    required this.fid,
    required this.forumName,
    required this.subject,
    required this.author,
    required this.authorId,
    required this.avatar,
    required this.dateline,
    required this.views,
    required this.replies,
    required this.totalPage,
    required this.favorite,
    this.favId = '',
    required this.floors,
  });

  factory ThreadDetail.fromJson(Map<String, dynamic> json) {
    final thread = _map(json['thread']);
    final favVal = _text(thread['fav']);
    final isFav = favVal.isNotEmpty && favVal != '0';
    return ThreadDetail(
      tid: _text(thread['tid']),
      fid: _text(thread['fid']),
      forumName: _text(thread['forumname']),
      subject: _text(thread['subject']),
      author: _text(thread['author']),
      authorId: _text(thread['authorid']),
      avatar: _avatar(thread['avatar']),
      dateline: _text(thread['dateline']),
      views: toInt(_text(thread['views'])),
      replies: toInt(_text(thread['replies'])),
      totalPage: toInt(_text(thread['totalpage'])).clamp(1, 999999),
      favorite: isFav,
      favId: isFav && favVal != '1' ? favVal : '',
      floors: _list(
        json['postlist'],
      ).map((item) => ThreadFloor.fromJson(_map(item))).toList(),
    );
  }
}

class ThreadFloor {
  final String pid;
  final String tid;
  final bool first;
  final String author;
  final String authorId;
  final String avatar;
  final String dateline;
  final String messageHtml;
  final String groupTitle;
  final List<String> attachments;
  final List<ThreadComment> comments;
  final List<ThreadRating> ratings;
  final int totalRate;

  const ThreadFloor({
    required this.pid,
    required this.tid,
    required this.first,
    required this.author,
    required this.authorId,
    required this.avatar,
    required this.dateline,
    required this.messageHtml,
    required this.groupTitle,
    required this.attachments,
    required this.comments,
    required this.ratings,
    required this.totalRate,
  });

  factory ThreadFloor.fromJson(Map<String, dynamic> json) {
    final groupMap = _map(json['group']);
    final rawGroup = _text(groupMap['grouptitle']);
    final directGroup = _text(json['grouptitle']);
    final authorTitle = _text(json['authortitle']);
    String groupTitle = rawGroup.isNotEmpty
        ? rawGroup
        : (directGroup.isNotEmpty ? directGroup : authorTitle);

    if (groupTitle.isEmpty) {
      final gid = _text(groupMap['groupid']).isNotEmpty
          ? _text(groupMap['groupid'])
          : _text(json['groupid']);
      groupTitle = discuzUserGroupTitle(gid);
    }

    return ThreadFloor(
      pid: _text(json['pid']),
      tid: _text(json['tid']),
      first: _text(json['first']) == '1',
      author: _text(json['author']),
      authorId: _text(json['authorid']),
      avatar: _avatar(json['avatar']),
      dateline: _text(json['dateline']),
      messageHtml: _text(json['message']),
      groupTitle: groupTitle,
      attachments: _list(json['attachs'])
          .map((item) => _attachmentUrl(item))
          .where((url) => url.isNotEmpty)
          .toList(),
      comments: _list(
        json['comments'],
      ).map((item) => ThreadComment.fromJson(_map(item))).toList(),
      ratings: _list(
        json['ratelog'],
      ).map((item) => ThreadRating.fromJson(_map(item))).toList(),
      totalRate: toInt(_text(json['totalrate'])),
    );
  }
}

class ThreadComment {
  final String author;
  final String authorId;
  final String avatar;
  final String message;
  final String dateline;

  const ThreadComment({
    required this.author,
    this.authorId = '',
    required this.avatar,
    required this.message,
    required this.dateline,
  });

  factory ThreadComment.fromJson(Map<String, dynamic> json) => ThreadComment(
    author: _text(json['author']),
    authorId: _text(json['authorid'] ?? json['uid'] ?? ''),
    avatar: _avatar(json['avatar']),
    message: _text(json['comment']),
    dateline: _text(json['dateline']),
  );
}

class ThreadRating {
  final String userId;
  final String userName;
  final String avatar;
  final int score;
  final String reason;
  final String dateline;

  const ThreadRating({
    required this.userId,
    required this.userName,
    required this.avatar,
    required this.score,
    required this.reason,
    this.dateline = '',
  });

  factory ThreadRating.fromJson(Map<String, dynamic> json) => ThreadRating(
    userId: _text(json['authorid'] ?? json['uid']),
    userName: _text(json['username']),
    avatar: _avatar(json['avatar']),
    score: int.tryParse(_text(json['score'])) ?? 0,
    reason: _text(json['reason']),
    dateline: _text(
      json['dateline'] ?? json['dgmdate'] ?? json['postdate'] ?? json['time'],
    ),
  );
}

class RatingRange {
  final int remaining;
  final int minimum;
  final int maximum;

  const RatingRange({
    required this.remaining,
    required this.minimum,
    required this.maximum,
  });

  factory RatingRange.fromJson(Map<String, dynamic> json) => RatingRange(
    remaining: toInt(_text(json['maxratetoday'])),
    minimum: toInt(_text(json['raterangemin'])).clamp(1, 999999),
    maximum: toInt(_text(json['raterangemax'])).clamp(1, 999999),
  );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<dynamic> _list(dynamic value) => value is List ? value : const [];

String _text(dynamic value) => value?.toString() ?? '';

String _avatar(dynamic value) {
  if (value is Map) {
    for (final key in const [
      'data-echo',
      'data-original',
      'data-src',
      'data-lazyload',
      'file',
      'src',
      'url',
      'avatar',
    ]) {
      final candidate = avatarUrl(_text(value[key]));
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }

  return avatarUrl(_text(value));
}

String _attachmentUrl(dynamic value) {
  if (value is String) return absoluteUrl(value);
  if (value is Map) {
    for (final key in const ['url', 'attachment', 'attachurl', 'src']) {
      final found = _text(value[key]);
      if (found.isNotEmpty) return absoluteUrl(found);
    }
  }
  return '';
}

/// 从网页版加果弹窗 (forum.php?mod=misc&action=viewratings) 解析出的加果明细
class ParsedRatingRecord {
  final String userId;
  final String userName;
  final String time;
  final String score;
  final String reason;

  const ParsedRatingRecord({
    this.userId = '',
    required this.userName,
    required this.time,
    this.score = '',
    this.reason = '',
  });
}

List<ParsedRatingRecord> parseRatingRecords(String html) {
  final records = <ParsedRatingRecord>[];
  if (html.isEmpty) return records;

  final trRegex = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false);
  final tdRegex = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true, caseSensitive: false);
  final uidRegex = RegExp(r'uid[=-](\d+)', caseSensitive: false);
  final stripTagRegex = RegExp(r'<[^>]*>');

  for (final trMatch in trRegex.allMatches(html)) {
    final trContent = trMatch.group(1) ?? '';
    final tdMatches = tdRegex.allMatches(trContent).toList();
    if (tdMatches.length < 3) continue;

    final td0 = tdMatches[0].group(1)?.replaceAll(stripTagRegex, '').trim() ?? '';
    final td1Raw = tdMatches[1].group(1) ?? '';
    final td1 = td1Raw.replaceAll(stripTagRegex, '').trim();

    if (td1.isEmpty || td1 == '用户名') continue;

    String uid = '';
    final uidMatch = uidRegex.firstMatch(td1Raw);
    if (uidMatch != null) {
      uid = uidMatch.group(1)!;
    }

    String time = '';
    for (int i = 0; i < tdMatches.length; i++) {
      final text = tdMatches[i].group(1)?.replaceAll(stripTagRegex, '').trim() ?? '';
      if (RegExp(r'\d{1,2}:\d{2}').hasMatch(text) &&
          (RegExp(r'\d{4}[-/.]\d{1,2}[-/.]\d{1,2}').hasMatch(text) ||
              RegExp(r'\d{1,2}[-/.]\d{1,2}').hasMatch(text))) {
        time = text;
        break;
      }
    }
    if (time.isEmpty && tdMatches.length >= 3) {
      time = tdMatches[2].group(1)?.replaceAll(stripTagRegex, '').trim() ?? '';
    }

    final reason = tdMatches.length >= 4
        ? (tdMatches[3].group(1)?.replaceAll(stripTagRegex, '').trim() ?? '')
        : '';

    records.add(ParsedRatingRecord(
      userId: uid,
      userName: td1,
      time: time,
      score: td0,
      reason: reason,
    ));
  }

  return records;
}
