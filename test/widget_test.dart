// 📁 test/ - 赚友吧 7.0 开源版自动化质量测试用例（22项全通测试，保障App稳定防回归）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zybapp/config/constants.dart';
import 'package:zybapp/main.dart';
import 'package:zybapp/models/thread_detail.dart';
import 'package:zybapp/models/zk_post.dart';
import 'package:zybapp/services/filter_service.dart';
import 'package:zybapp/services/haptic_service.dart';
import 'package:zybapp/services/official_api_service.dart';
import 'package:zybapp/services/read_history_service.dart';
import 'package:zybapp/utils/helpers.dart';
import 'package:zybapp/utils/time_parser.dart';
import 'package:zybapp/widgets/image_viewer.dart';
import 'package:zybapp/widgets/link_tools.dart';
import 'package:zybapp/widgets/native_html_content.dart';

void main() {
  test('App widget can be created', () {
    expect(const ZybApp(), isA<ZybApp>());
  });

  test('Avatar parser accepts official HTML and lazy-load fields', () {
    expect(
      avatarUrls(
        '<img src="static/image/common/none.gif" '
        'data-echo="//avatar.example.com/u/1015904.jpg">',
      ),
      contains('http://avatar.example.com/u/1015904.jpg'),
    );
    expect(
      avatarUrl('<img data-original="/data/avatar/1.jpg">'),
      'http://www.zuanke8.com/data/avatar/1.jpg',
    );
  });

  test('Link tool recognizes links, mini programs, and shopping commands', () {
    final links = detectLinks(
      '京东 https://u.jd.com/abc 淘宝 https://m.taobao.com/a '
      '小程序://demo ￥AbCdE123￥',
    );
    expect(links.map((item) => item.kind), contains(LinkKind.jd));
    expect(links.map((item) => item.kind), contains(LinkKind.taobao));
    expect(links.map((item) => item.kind), contains(LinkKind.miniProgram));
    expect(links.map((item) => item.kind), contains(LinkKind.command));
  });

  testWidgets('Image viewer gives the foreground a full centered frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openImageViewer(
              context,
              const ['https://example.invalid/test.jpg'],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byTooltip('关闭'), findsOneWidget);
    final frame = find.byKey(const ValueKey<String>('viewer-frame-0'));
    expect(frame, findsOneWidget);
    final size = tester.getSize(frame);
    expect(size.width, greaterThan(300));
    expect(size.height, greaterThan(400));
    expect(find.byType(FittedBox), findsOneWidget);
  });

  test('FilterService correctly blocks by author nickname and title keyword', () async {
    SharedPreferences.setMockInitialValues({});
    final filter = FilterService.instance;
    await filter.addAuthor('讨厌的楼主');
    await filter.addKeyword('砍一刀');
    await filter.addKeyword('助力');

    expect(filter.isAuthorBlocked('讨厌的楼主'), isTrue);
    expect(filter.isAuthorBlocked('正常的赚友'), isFalse);

    expect(filter.isTitleBlocked('拼多多求助力123'), isTrue);
    expect(filter.isTitleBlocked('来帮我砍一刀谢谢'), isTrue);
    expect(filter.isTitleBlocked('京东好价洗衣液'), isFalse);

    const post1 = ZkPost(
      tid: '1',
      title: '京东好价速抢',
      url: '',
      author: '讨厌的楼主',
      postTime: '10:00',
      lastReplyTime: '10:05',
      replies: 1,
      views: 10,
      fid: 15,
      forumName: '大家谈',
    );

    const post2 = ZkPost(
      tid: '2',
      title: '互助互助来砍一刀',
      url: '',
      author: '好人楼主',
      postTime: '10:00',
      lastReplyTime: '10:05',
      replies: 1,
      views: 10,
      fid: 15,
      forumName: '大家谈',
    );

    const post3 = ZkPost(
      tid: '3',
      title: '美团5元无门槛红包',
      url: '',
      author: '好人楼主',
      postTime: '10:00',
      lastReplyTime: '10:05',
      replies: 1,
      views: 10,
      fid: 15,
      forumName: '大家谈',
    );

    expect(filter.isPostBlocked(post1), isTrue); // author blocked
    expect(filter.isPostBlocked(post2), isTrue); // keyword blocked
    expect(filter.isPostBlocked(post3), isFalse); // allowed
  });

  test('extractZkThreadTid accurately extracts thread ID from various URL formats', () {
    expect(extractZkThreadTid('http://www.zuanke8.com/thread-1234567-1-1.html'), '1234567');
    expect(extractZkThreadTid('https://zuanke8.com/forum.php?mod=viewthread&tid=987654'), '987654');
    expect(extractZkThreadTid('thread-556677-1-1.html'), '556677');
    expect(extractZkThreadTid('https://item.jd.com/1000123.html'), isNull);

    final detected = detectLinks('推荐看这个帖子 http://www.zuanke8.com/thread-888999-1-1.html 速去');
    expect(detected.any((d) => d.kind == LinkKind.zkThread && d.value.contains('888999')), isTrue);
  });

  test('FilterService unblock author successfully removes them from blocked list', () async {
    SharedPreferences.setMockInitialValues({});
    final filter = FilterService.instance;
    await filter.addAuthor('测试拉黑用户');
    expect(filter.isAuthorBlocked('测试拉黑用户'), isTrue);

    await filter.removeAuthor('测试拉黑用户');
    expect(filter.isAuthorBlocked('测试拉黑用户'), isFalse);
  });

  test('ReadHistoryService correctly tracks and persists read post TIDs', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ReadHistoryService.instance;
    await service.load();

    expect(service.isRead('12345'), isFalse);
    await service.markRead('12345');
    expect(service.isRead('12345'), isTrue);
    expect(service.isRead('99999'), isFalse);
  });

  test('HapticService correctly manages state, persistence, and safe calling', () async {
    SharedPreferences.setMockInitialValues({});
    final haptics = HapticService.instance;
    await haptics.load();
    expect(haptics.enabled, isTrue);

    await haptics.setEnabled(false);
    expect(haptics.enabled, isFalse);

    // Verify calling lightImpact and selectionClick when disabled doesn't throw
    await haptics.lightImpact();
    await haptics.selectionClick();

    // Verify reload retains persisted disabled state
    await haptics.load();
    expect(haptics.enabled, isFalse);

    // Re-enable
    await haptics.setEnabled(true);
    expect(haptics.enabled, isTrue);
  });

  testWidgets('NativeHtmlContent strictly implements dual font size system', (tester) async {
    const html = '<p>正常正文字号<font size="5">网页夸张大字</font><font size="1">辅助小字尾巴</font></p>';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NativeHtmlContent(html: html, fontSize: 16),
        ),
      ),
    );
    await tester.pump();

    final textFinder = find.byType(SelectableText);
    expect(textFinder, findsOneWidget);
    final selectableText = tester.widget<SelectableText>(textFinder);
    final span = selectableText.textSpan!;
    final children = span.children!;
    // Normal text -> 16px (inherits)
    // Size 5 text -> strictly collapsed to standard 16px (no giant font)
    // Size 1 text -> 12px
    final smallSpan = children.whereType<TextSpan>().firstWhere((s) => s.text!.contains('辅助小字尾巴'));
    expect(smallSpan.style?.fontSize, 12.0);

    final normalSpan = children.whereType<TextSpan>().firstWhere((s) => s.text!.contains('网页夸张大字'));
    expect(normalSpan.style?.fontSize, isNull); // inherits 16px from parent SelectableText
  });

  test('Search history persists and retrieves correctly via SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({
      'zyb_search_history': ['话费', '抽奖'],
    });
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('zyb_search_history');
    expect(list, equals(['话费', '抽奖']));

    // Update with new search keyword prepended
    final updated = ['京东', ...list!];
    await prefs.setStringList('zyb_search_history', updated);

    final reloaded = prefs.getStringList('zyb_search_history');
    expect(reloaded, equals(['京东', '话费', '抽奖']));
  });

  test('parseZkTime parses relative times, day offsets, and date strings', () {
    final now = DateTime.now();

    // 10 minutes ago
    final m10 = parseZkTime('10分钟前');
    expect(m10 != null, isTrue);
    expect(m10!.isBefore(now.add(const Duration(seconds: 1))), isTrue);
    expect(now.difference(m10).inMinutes >= 9 && now.difference(m10).inMinutes <= 11, isTrue);

    // 2 days ago
    final d2 = parseZkTime('2天前');
    expect(d2 != null, isTrue);
    expect(now.difference(d2!).inDays >= 1 && now.difference(d2).inDays <= 3, isTrue);

    // 昨天 12:00
    final yesterday = parseZkTime('昨天 12:00');
    expect(yesterday != null, isTrue);
    expect(yesterday!.hour, 12);
    expect(yesterday.minute, 0);

    // Standard date string
    final exact = parseZkTime('2026-09-28 15:30');
    expect(exact != null, isTrue);
    expect(exact!.year, 2026);
    expect(exact.month, 9);
    expect(exact.day, 28);
    expect(exact.hour, 15);
    expect(exact.minute, 30);

    // Month-Day format
    final md = parseZkTime('09-28 08:15');
    expect(md != null, isTrue);
    expect(md!.month, 9);
    expect(md.day, 28);
    expect(md.hour, 8);
    expect(md.minute, 15);
  });

  test('SortMode configurations match expected backend orderby filters', () {
    expect(SortMode.hot.filter, 'heat');
    expect(SortMode.hot.orderby, 'heats');
    expect(SortMode.latestPost.filter, 'author');
    expect(SortMode.latestPost.orderby, 'dateline');
  });

  test('discuzAvatarUrls generates correct mirror URLs and filters out placeholder images', () {
    // none.gif should be filtered out
    final emptyUrls = avatarUrls('<img src="static/image/common/none.gif">');
    expect(emptyUrls, isEmpty);

    // UID avatar mirrors
    final mirrors = discuzAvatarUrls('1234567');
    expect(mirrors, contains('http://www.zuanke8.com/uc_server/avatar.php?uid=1234567&size=middle'));
    expect(mirrors, contains('http://www.zuanke8.com/uc_server/data/avatar/001/23/45/67_avatar_middle.jpg'));
  });

  test('E-commerce short links detection for Taobao and JD', () {
    final links = detectLinks('淘宝短链 https://m.tb.cn/h.demo 京东短链 https://3.cn/123xyz');
    expect(links.any((l) => l.kind == LinkKind.taobao), isTrue);
    expect(links.any((l) => l.kind == LinkKind.jd), isTrue);
  });

  testWidgets('NativeHtmlContent renders div.quote and blockquote blocks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NativeHtmlContent(
            html: '<div class="quote"><blockquote><font size="2"><font color="#999999">张三 发表于 2026-10-12 10:00</font></font><br />这是引用内容</blockquote></div>这是回复正文',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('张三'), findsOneWidget);
    expect(find.textContaining('这是引用内容'), findsOneWidget);
    expect(find.textContaining('这是回复正文'), findsOneWidget);
  });

  test('formatRegDate formats timestamp, date strings and handles empty values correctly', () {
    expect(formatRegDate(''), isEmpty);
    expect(formatRegDate('2021-08-15'), equals('2021-08-15'));
    expect(formatRegDate('2021-08-15 14:32:00'), equals('2021-08-15'));
    expect(formatRegDate('2021/08/15'), equals('2021-08-15'));
    final tsDate = DateTime.fromMillisecondsSinceEpoch(1629000000 * 1000);
    final expected = '${tsDate.year.toString().padLeft(4, '0')}-${tsDate.month.toString().padLeft(2, '0')}-${tsDate.day.toString().padLeft(2, '0')}';
    expect(formatRegDate('1629000000'), equals(expected));
  });

  test('discuzUserGroupTitle maps group IDs correctly', () {
    expect(discuzUserGroupTitle('11'), equals('初级赚客'));
    expect(discuzUserGroupTitle('10'), equals('新手赚客'));
    expect(discuzUserGroupTitle('1'), equals('管理员'));
    expect(discuzUserGroupTitle('999'), equals(''));
  });

  test('OfficialUserProfile and ThreadFloor parse groupTitle from nested and fallback fields', () {
    // 1. OfficialUserProfile with nested group
    final prof1 = OfficialUserProfile.fromJson({
      'uid': '123',
      'username': 'test',
      'group': {'grouptitle': '初级赚客', 'groupid': '11'},
      'regdate': '1629000000',
    });
    expect(prof1.groupTitle, equals('初级赚客'));

    // 2. OfficialUserProfile with only groupid
    final prof2 = OfficialUserProfile.fromJson({
      'uid': '123',
      'username': 'test',
      'groupid': '11',
      'regdate': '1629000000',
    });
    expect(prof2.groupTitle, equals('初级赚客'));

    // 3. ThreadFloor with groupid
    final floor = ThreadFloor.fromJson({
      'pid': '1',
      'tid': '100',
      'author': '楼主',
      'authorid': '123',
      'groupid': '11',
    });
    expect(floor.groupTitle, equals('初级赚客'));
  });

  test('formatRatingTime correctly formats timestamp and date strings', () {
    expect(formatRatingTime(''), isEmpty);

    // Current year timestamp
    final now = DateTime.now();
    final dtCurrent = DateTime(now.year, 10, 12, 16, 53);
    final tsCurrent = (dtCurrent.millisecondsSinceEpoch / 1000).round();
    expect(formatRatingTime('$tsCurrent'), equals('10-12 16:53'));

    // Past year timestamp
    final dtPast = DateTime(2021, 8, 15, 9, 30);
    final tsPast = (dtPast.millisecondsSinceEpoch / 1000).round();
    expect(formatRatingTime('$tsPast'), equals('2021-08-15 09:30'));

    // Already formatted string
    expect(formatRatingTime('10-12 16:53'), equals('10-12 16:53'));
  });

  test('ThreadRating parses dateline from dateline/dgmdate/postdate/time', () {
    final r1 = ThreadRating.fromJson({
      'authorid': '101',
      'username': '果果友',
      'score': '1',
      'dateline': '1697100780',
    });
    expect(r1.dateline, equals('1697100780'));

    final r2 = ThreadRating.fromJson({
      'uid': '102',
      'username': '果友2',
      'score': '2',
      'dgmdate': '10-12 16:53',
    });
    expect(r2.dateline, equals('10-12 16:53'));
  });

  test('parseRatingRecords parses Discuz rating table HTML accurately', () {
    const html = '''
      <table class="dt mtm">
        <tr>
          <th>果果</th>
          <th>用户名</th>
          <th>时间</th>
          <th>理由</th>
        </tr>
        <tr>
          <td>果果 +1</td>
          <td><a href="home.php?mod=space&uid=123456" target="_blank">赚友张三</a></td>
          <td>2026-10-20 11:40</td>
          <td>好帖支持</td>
        </tr>
        <tr>
          <td>果果 +2</td>
          <td><a href="space-uid-789012.html">赚友李四</a></td>
          <td>10-20 12:05</td>
          <td>赞</td>
        </tr>
      </table>
    ''';

    final records = parseRatingRecords(html);
    expect(records.length, equals(2));

    expect(records[0].userName, equals('赚友张三'));
    expect(records[0].userId, equals('123456'));
    expect(records[0].time, equals('2026-10-20 11:40'));
    expect(records[0].score, equals('果果 +1'));
    expect(records[0].reason, equals('好帖支持'));

    expect(records[1].userName, equals('赚友李四'));
    expect(records[1].userId, equals('789012'));
    expect(records[1].time, equals('10-20 12:05'));
    expect(records[1].score, equals('果果 +2'));
    expect(records[1].reason, equals('赞'));

    // Empty html returns empty list
    expect(parseRatingRecords(''), isEmpty);
  });
}

