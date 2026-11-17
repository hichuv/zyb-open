import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../utils/helpers.dart';

class BlacklistService {
  static const _uidsKey = 'official_blacklist_uids';
  static const _updatedKey = 'official_blacklist_updated_at';
  static const _maxAge = Duration(minutes: 10);

  Future<Set<String>> load({bool refresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = (prefs.getStringList(_uidsKey) ?? const []).toSet();
    final updated = prefs.getInt(_updatedKey) ?? 0;
    if (!refresh &&
        cached.isNotEmpty &&
        DateTime.now().millisecondsSinceEpoch - updated <
            _maxAge.inMilliseconds) {
      return cached;
    }
    try {
      final fresh = await _fetch();
      await prefs.setStringList(_uidsKey, fresh.toList()..sort());
      await prefs.setInt(_updatedKey, DateTime.now().millisecondsSinceEpoch);
      return fresh;
    } catch (_) {
      return cached;
    }
  }

  Future<Set<String>> _fetch() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri(baseUrl),
    );
    final header = cookies
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
    if (header.isEmpty) return <String>{};
    final pending = <Uri>[
      Uri.parse('$baseUrl/home.php?mod=space&do=friend&view=blacklist'),
    ];
    final visited = <String>{};
    final result = <String>{};
    while (pending.isNotEmpty && visited.length < 30) {
      final uri = pending.removeAt(0);
      if (!visited.add(uri.toString())) continue;
      final response = await http
          .get(uri, headers: {'Cookie': header, 'User-Agent': userAgent})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) break;
      final doc = html_parser.parse(decodeGbk(response.bodyBytes));
      for (final item in doc.querySelectorAll(r'[id^="friend_"][id$="_li"]')) {
        final match = RegExp(r'^friend_(\d+)_li$').firstMatch(item.id);
        if (match != null) result.add(match.group(1)!);
      }
      for (final link in doc.querySelectorAll(
        'a[href*="view=blacklist"][href*="start="]',
      )) {
        final href = link.attributes['href'];
        if (href != null)
          pending.add(uri.resolve(href.replaceAll('&amp;', '&')));
      }
    }
    return result;
  }
}
