/// 时间字符串解析
///
/// 支持格式: 刚刚, X分钟前, X小时前, 今天 HH:mm, 昨天 HH:mm,
/// MM-DD HH:mm, YYYY-MM-DD HH:mm
DateTime? parseZkTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final now = DateTime.now();

  if (text == '刚刚') return now;

  final secMatch = RegExp(r'(\d+)\s*秒前').firstMatch(text);
  if (secMatch != null) {
    final secs = int.tryParse(secMatch.group(1)!) ?? 0;
    return now.subtract(Duration(seconds: secs));
  }

  final minMatch = RegExp(r'(\d+)\s*分钟前').firstMatch(text);
  if (minMatch != null) {
    final mins = int.tryParse(minMatch.group(1)!) ?? 0;
    return now.subtract(Duration(minutes: mins));
  }

  final hourMatch = RegExp(r'(\d+)\s*小时前').firstMatch(text);
  if (hourMatch != null) {
    final hours = int.tryParse(hourMatch.group(1)!) ?? 0;
    return now.subtract(Duration(hours: hours));
  }

  final dayMatch = RegExp(r'(\d+)\s*天前').firstMatch(text);
  if (dayMatch != null) {
    final days = int.tryParse(dayMatch.group(1)!) ?? 0;
    return now.subtract(Duration(days: days));
  }

  if (text.startsWith('今天')) {
    final timePart = text.replaceFirst('今天', '').trim();
    final hm = _parseHM(timePart);
    if (hm != null) {
      return DateTime(now.year, now.month, now.day, hm.$1, hm.$2);
    }
  }

  if (text.startsWith('昨天')) {
    final timePart = text.replaceFirst('昨天', '').trim();
    final hm = _parseHM(timePart);
    final yesterday = now.subtract(const Duration(days: 1));
    if (hm != null) {
      return DateTime(
        yesterday.year,
        yesterday.month,
        yesterday.day,
        hm.$1,
        hm.$2,
      );
    }
  }

  if (text.startsWith('前天')) {
    final timePart = text.replaceFirst('前天', '').trim();
    final hm = _parseHM(timePart);
    final dayBefore = now.subtract(const Duration(days: 2));
    if (hm != null) {
      return DateTime(
        dayBefore.year,
        dayBefore.month,
        dayBefore.day,
        hm.$1,
        hm.$2,
      );
    }
  }

  // YYYY-MM-DD HH:mm:ss or YYYY-MM-DD HH:mm or YYYY-MM-DD
  final fullMatch = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  ).firstMatch(text);
  if (fullMatch != null) {
    final year = int.tryParse(fullMatch.group(1)!) ?? now.year;
    final month = int.tryParse(fullMatch.group(2)!) ?? 1;
    final day = int.tryParse(fullMatch.group(3)!) ?? 1;
    final hour = fullMatch.group(4) != null ? int.tryParse(fullMatch.group(4)!) ?? 0 : 0;
    final minute = fullMatch.group(5) != null ? int.tryParse(fullMatch.group(5)!) ?? 0 : 0;
    final second = fullMatch.group(6) != null ? int.tryParse(fullMatch.group(6)!) ?? 0 : 0;
    return DateTime(year, month, day, hour, minute, second);
  }

  // MM-DD HH:mm:ss or MM-DD HH:mm or MM-DD
  final mdMatch = RegExp(
    r'^(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  ).firstMatch(text);
  if (mdMatch != null) {
    final month = int.tryParse(mdMatch.group(1)!) ?? 1;
    final day = int.tryParse(mdMatch.group(2)!) ?? 1;
    final hour = mdMatch.group(3) != null ? int.tryParse(mdMatch.group(3)!) ?? 0 : 0;
    final minute = mdMatch.group(4) != null ? int.tryParse(mdMatch.group(4)!) ?? 0 : 0;
    final second = mdMatch.group(5) != null ? int.tryParse(mdMatch.group(5)!) ?? 0 : 0;
    return DateTime(now.year, month, day, hour, minute, second);
  }

  return null;
}

(int, int)? _parseHM(String text) {
  final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(text);
  if (match == null) return null;
  return (
    int.tryParse(match.group(1)!) ?? 0,
    int.tryParse(match.group(2)!) ?? 0,
  );
}

/// 格式化时间为友好显示
String formatTime(DateTime? dt) {
  if (dt == null) return '';
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 2) return '昨天 ${_pad(dt.hour)}:${_pad(dt.minute)}';

  if (dt.year == now.year) {
    return '${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }
  return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
}

String _pad(int n) => n.toString().padLeft(2, '0');

/// 格式化用户注册时间为简洁年月日 (如: 2021-08-15)
String formatRegDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';

  // 1. 若为数字时间戳（秒或毫秒）
  final asInt = int.tryParse(text);
  if (asInt != null && asInt > 100000000) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      asInt > 10000000000 ? asInt : asInt * 1000,
    );
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
  }

  // 2. 若包含 YYYY-MM-DD 或 YYYY/MM/DD
  final dateMatch =
      RegExp(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(text);
  if (dateMatch != null) {
    final y = dateMatch.group(1)!;
    final m = int.parse(dateMatch.group(2)!).toString().padLeft(2, '0');
    final d = int.parse(dateMatch.group(3)!).toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  return text;
}

/// 格式化加果/评分记录时间为 MM-dd HH:mm (非当年带年份 yyyy-MM-dd HH:mm)
String formatRatingTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return '';

  final now = DateTime.now();

  // 1. 若为数字时间戳（秒或毫秒）
  final asInt = int.tryParse(text);
  if (asInt != null && asInt > 100000000) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      asInt > 10000000000 ? asInt : asInt * 1000,
    );
    if (dt.year == now.year) {
      return '${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
    }
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  // 2. 尝试 parseZkTime
  final dt = parseZkTime(text);
  if (dt != null) {
    if (dt.year == now.year) {
      return '${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
    }
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  // 3. 常见 YYYY-MM-DD HH:mm 格式匹配
  final fullMatch =
      RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\s+(\d{1,2}):(\d{2})')
          .firstMatch(text);
  if (fullMatch != null) {
    final y = int.parse(fullMatch.group(1)!);
    final m = _pad(int.parse(fullMatch.group(2)!));
    final d = _pad(int.parse(fullMatch.group(3)!));
    final h = _pad(int.parse(fullMatch.group(4)!));
    final min = _pad(int.parse(fullMatch.group(5)!));
    if (y == now.year) {
      return '$m-$d $h:$min';
    }
    return '$y-$m-$d $h:$min';
  }

  // 4. 常见 MM-DD HH:mm 格式匹配
  final mdMatch =
      RegExp(r'^(\d{1,2})[-/.](\d{1,2})\s+(\d{1,2}):(\d{2})').firstMatch(text);
  if (mdMatch != null) {
    final m = _pad(int.parse(mdMatch.group(1)!));
    final d = _pad(int.parse(mdMatch.group(2)!));
    final h = _pad(int.parse(mdMatch.group(3)!));
    final min = _pad(int.parse(mdMatch.group(4)!));
    return '$m-$d $h:$min';
  }

  return text;
}
