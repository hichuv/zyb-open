import 'dart:convert';
import 'package:charset/charset.dart';
import 'package:html/parser.dart' as html_parser;

/// 文本清理
String normalize(String text) {
  return text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
      .replaceAll(RegExp(r'\n\s+'), '\n')
      .trim();
}

/// 相对 URL 转绝对 URL
String absoluteUrl(String href) {
  final fixed = href.replaceAll('&amp;', '&').trim();
  if (fixed.isEmpty) return '';
  if (fixed.startsWith('//')) return 'http:$fixed';
  if (fixed.startsWith('http://') || fixed.startsWith('https://')) {
    return fixed;
  }
  if (fixed.contains('://')) return fixed;
  if (fixed.startsWith('/')) return 'http://www.zuanke8.com$fixed';
  return 'http://www.zuanke8.com/$fixed';
}

/// 将官方接口中的头像值统一转换成可加载的图片地址。
/// 接口有时直接给 URL，有时给的是 `<img ...>`，并且懒加载地址可能放在
/// data-echo、data-original 等属性中。
List<String> avatarUrls(String value) {
  final output = <String>[];

  void add(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty ||
        trimmed.contains('<') ||
        trimmed.toLowerCase().startsWith('javascript:')) {
      return;
    }
    final lower = trimmed.toLowerCase();
    // 拦截 1 像素透明 GIF 等占位图，杜绝空白假图蒙混过关
    if (lower.contains('none.gif') ||
        lower.contains('noavatar') ||
        lower.contains('spacer.gif')) {
      return;
    }
    final url = absoluteUrl(trimmed);
    if (url.isNotEmpty && !output.contains(url)) output.add(url);
  }

  final raw = value.trim();
  if (raw.isEmpty) return output;
  if (!raw.contains('<')) add(raw);

  final fragment = html_parser.parseFragment(raw);
  for (final image in fragment.querySelectorAll('img')) {
    for (final key in const [
      'data-echo',
      'data-original',
      'data-src',
      'data-lazyload',
      'file',
      'src',
    ]) {
      add(image.attributes[key] ?? '');
    }
    final srcSet = image.attributes['srcset'] ?? '';
    if (srcSet.isNotEmpty) add(srcSet.split(',').first.trim().split(' ').first);
  }
  return output;
}

/// 根据 Discuz UID 生成官方标准分层静态镜像源与动态镜像源
List<String> discuzAvatarUrls(String uid) {
  final clean = uid.trim();
  if (clean.isEmpty || clean == '0') return const [];
  final urls = <String>[
    'http://www.zuanke8.com/uc_server/avatar.php?uid=$clean&size=middle',
    'http://www.zuanke8.com/uc_server/avatar.php?uid=$clean&size=small',
  ];
  if (clean.length <= 9 && int.tryParse(clean) != null) {
    final padded = clean.padLeft(9, '0');
    final d1 = padded.substring(0, 3);
    final d2 = padded.substring(3, 5);
    final d3 = padded.substring(5, 7);
    final d4 = padded.substring(7, 9);
    urls.add(
      'http://www.zuanke8.com/uc_server/data/avatar/$d1/$d2/$d3/${d4}_avatar_middle.jpg',
    );
  }
  return urls;
}

String avatarUrl(String value) {
  final urls = avatarUrls(value);
  return urls.isEmpty ? '' : urls.first;
}

/// Discuz 用户组 ID 映射（用于移动端未下发或丢失 grouptitle 时的安全降级）
String discuzUserGroupTitle(String gid) {
  switch (gid.trim()) {
    case '1':
      return '管理员';
    case '2':
      return '超级版主';
    case '3':
      return '版主';
    case '4':
      return '禁止发言';
    case '5':
      return '禁止访问';
    case '6':
      return 'IP禁止';
    case '7':
      return '游客';
    case '8':
      return '等待验证会员';
    case '10':
      return '新手赚客';
    case '11':
      return '初级赚客';
    case '12':
      return '中级赚客';
    case '13':
      return '高级赚客';
    case '14':
      return '金牌赚客';
    case '15':
      return '论坛元老';
    default:
      return '';
  }
}

/// 字符串转整数（处理 "1.2万", "3k" 等格式）
int toInt(String text) {
  final value = normalize(text).replaceAll(',', '').toLowerCase();
  if (value.isEmpty) return 0;
  final unitMatch = RegExp(r'(\d+(?:\.\d+)?)\s*([万wk])').firstMatch(value);
  if (unitMatch != null) {
    final number = double.tryParse(unitMatch.group(1)!) ?? 0;
    final unit = unitMatch.group(2)!;
    final multiplier = (unit == '万' || unit == 'w') ? 10000 : 1000;
    return (number * multiplier).round();
  }
  return int.tryParse(RegExp(r'\d+').firstMatch(value)?.group(0) ?? '') ?? 0;
}

/// GBK 解码
String decodeGbk(List<int> bytes) {
  try {
    return gbk.decode(bytes);
  } catch (_) {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// GBK URL 编码
String urlEncodeGbk(String value) {
  final bytes = gbk.encode(value);
  return bytes
      .map((b) => '%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}')
      .join();
}

/// GBK 表单编码
String formEncodeGbk(Map<String, String> fields) {
  return fields.entries
      .map((e) => '${urlEncodeGbk(e.key)}=${urlEncodeGbk(e.value)}')
      .join('&');
}
