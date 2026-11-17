import 'package:flutter/material.dart';

/// 板块配置
class ForumConfig {
  final int fid;
  final String name;
  final Color color;

  const ForumConfig({
    required this.fid,
    required this.name,
    required this.color,
  });
}

/// 浏览板块（首页列表采集源）
const List<ForumConfig> browseForums = [
  ForumConfig(fid: 15, name: '赚客大家谈', color: Color(0xFFE85D16)),
  ForumConfig(fid: 11, name: '做任务赚果果', color: Color(0xFF168B55)),
  ForumConfig(fid: 25, name: '赚品交换', color: Color(0xFF9A4B78)),
  ForumConfig(fid: 31, name: '果果换物', color: Color(0xFF4776B8)),
];

/// 板块色彩字典表（涵盖常见专区）
const Map<String, Color> knownForumColors = {
  '赚客大家谈': Color(0xFFFF5F15), // 品牌暖橙
  '大家谈': Color(0xFFFF5F15),
  '做任务赚果果': Color(0xFF00B578), // 翠绿
  '任务赚果': Color(0xFF00B578),
  '赚品交换': Color(0xFF9A4B78), // 紫罗兰
  '果果换物': Color(0xFF2072F3), // 科技蓝
  '邀请专区': Color(0xFFFA436B), // 珊瑚红（解决邀请专区颜色混淆）
  '红包话费': Color(0xFFF59A23), // 琥珀黄
  '淘淘专区': Color(0xFF0FC6C2), // 青蓝
  '互助专区': Color(0xFF722ED1), // 优雅深紫
};

/// 动态防撞调色盘（用于任意未知生僻专区，确保永不撞色）
const List<Color> dynamicForumPalette = [
  Color(0xFFFA436B), // 珊瑚红
  Color(0xFF00B578), // 翠绿
  Color(0xFF2072F3), // 科技蓝
  Color(0xFF9A4B78), // 紫罗兰
  Color(0xFF0FC6C2), // 青蓝
  Color(0xFFF59A23), // 琥珀黄
  Color(0xFF722ED1), // 优雅紫
  Color(0xFFD4380D), // 砖红
];

/// 根据 fid 与板块名称获取展示颜色（双重匹配 + 动态哈希防撞）
Color forumDisplayColor(int fid, [String name = '']) {
  final trimmedName = name.trim();
  if (trimmedName.isNotEmpty && knownForumColors.containsKey(trimmedName)) {
    return knownForumColors[trimmedName]!;
  }
  for (final f in browseForums) {
    if (f.fid == fid) return f.color;
  }
  if (trimmedName.isNotEmpty) {
    final hash = trimmedName.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return dynamicForumPalette[hash.abs() % dynamicForumPalette.length];
  }
  return const Color(0xFFFF5F15);
}

/// 板块门户入口 URL
String forumUrl(int fid) =>
    'http://www.zuanke8.com/forum.php?mod=forumdisplay&fid=$fid&mobile=2';

String mobileUrl(String url) {
  if (!url.contains('zuanke8.com')) return url;
  if (RegExp(r'([?&])mobile=').hasMatch(url)) return url;
  final separator = url.contains('?') ? '&' : '?';
  return '$url${separator}mobile=2';
}

/// 帖子详情 URL
String threadUrl(String tid) =>
    'http://www.zuanke8.com/forum.php?mod=viewthread&tid=$tid';

/// 帖子列表 URL
String forumListUrl({
  required int fid,
  required String filter,
  required String orderby,
  int page = 1,
}) =>
    'http://www.zuanke8.com/forum.php?mod=forumdisplay'
    '&fid=$fid&filter=$filter&orderby=$orderby&page=$page';

/// 排序模式
enum SortMode {
  latestPost(label: '新发布', filter: 'author', orderby: 'dateline'),
  latestReply(label: '新回复', filter: 'lastpost', orderby: 'lastpost'),
  hot(label: '热门', filter: 'heat', orderby: 'heats');

  final String label;
  final String filter;
  final String orderby;

  const SortMode({
    required this.label,
    required this.filter,
    required this.orderby,
  });
}

/// 基础域名
const String baseUrl = 'http://www.zuanke8.com';

/// 登录页 URL
const String loginUrl =
    'http://www.zuanke8.com/member.php?mod=logging&action=login';

/// 检测登录状态 URL
const String checkLoginUrl = 'http://www.zuanke8.com/member.php?mod=spacecp';

/// 用户主页 URL
const String myProfileUrl = 'http://www.zuanke8.com/home.php?mod=space';

/// 用户积分 URL
const String myCreditUrl =
    'http://www.zuanke8.com/home.php?mod=spacecp&ac=credit';

const String guoguoLogUrl =
    'http://www.zuanke8.com/home.php?mod=spacecp&ac=credit&op=log';

const String plusUrl = 'http://www.zuanke8.com/plugin.php?id=member:plus';

const String myThreadsUrl =
    'http://www.zuanke8.com/forum.php?mod=guide&view=my';

const String myRepliesUrl =
    'http://www.zuanke8.com/forum.php?mod=guide&view=my&type=reply';

const String myFavoritesUrl =
    'http://www.zuanke8.com/home.php?mod=space&do=favorite&view=me';

/// User-Agent (桌面版)
const String userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

/// User-Agent (手机版，用于 WebView 跳转)
const String mobileUserAgent =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/// 版本号
const String appVersion = '赚友吧 V7.0 开源版';
const String appVersionName = '7.0.0';

/// 远程配置 JSON 地址（可选，用于下发首页公告/广告等运营配置）。
/// 开源版本默认留空；如需使用请填入你自己的 HTTPS JSON 配置地址。
const String remoteConfigUrl = '';
