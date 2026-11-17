import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../utils/helpers.dart';

class HomeNotice {
  final String text;
  final String url;
  final String action;
  final String title;
  final String content;

  const HomeNotice({
    required this.text,
    required this.url,
    required this.action,
    required this.title,
    required this.content,
  });

  bool get visible => text.trim().isNotEmpty;

  static HomeNotice? fromJson(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    final enabled = value['enabled'] == true;
    final text = normalize(value['text']?.toString() ?? '');
    if (!enabled || text.isEmpty || !_shouldShowForVersion(value)) return null;
    return HomeNotice(
      text: text,
      url: normalize(value['url']?.toString() ?? ''),
      action: normalize(value['action']?.toString() ?? 'none'),
      title: normalize(value['title']?.toString() ?? ''),
      content: value['content']?.toString().trim() ?? '',
    );
  }

  static bool _shouldShowForVersion(Map<String, dynamic> value) {
    final showBelowVersion = normalize(
      (value['showBelowVersion'] ?? value['maxVersionExclusive'])?.toString() ??
          '',
    );
    if (showBelowVersion.isNotEmpty &&
        _compareVersion(appVersionName, showBelowVersion) >= 0) {
      return false;
    }

    final showFromVersion = normalize(
      (value['showFromVersion'] ?? value['minVersionInclusive'])?.toString() ??
          '',
    );
    if (showFromVersion.isNotEmpty &&
        _compareVersion(appVersionName, showFromVersion) < 0) {
      return false;
    }

    return true;
  }

  static int _compareVersion(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (int i = 0; i < length; i++) {
      final a = i < leftParts.length ? leftParts[i] : 0;
      final b = i < rightParts.length ? rightParts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  static List<int> _versionParts(String version) {
    final core = version.split('+').first;
    return core
        .split('.')
        .map(
          (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .toList();
  }
}

class AuthorAd {
  final bool enabled;
  final String title;
  final String text;
  final String imageUrl;
  final String action;
  final String url;
  final String copyText;

  const AuthorAd({
    required this.enabled,
    required this.title,
    required this.text,
    required this.imageUrl,
    required this.action,
    required this.url,
    required this.copyText,
  });

  bool get visible =>
      enabled &&
      (title.trim().isNotEmpty ||
          text.trim().isNotEmpty ||
          imageUrl.trim().isNotEmpty);

  static AuthorAd empty() => const AuthorAd(
    enabled: false,
    title: '',
    text: '',
    imageUrl: '',
    action: 'none',
    url: '',
    copyText: '',
  );

  static AuthorAd fromJson(dynamic value) {
    if (value is! Map<String, dynamic>) return AuthorAd.empty();
    return AuthorAd(
      enabled: value['enabled'] == true,
      title: normalize(value['title']?.toString() ?? ''),
      text: normalize(value['text']?.toString() ?? ''),
      imageUrl: normalize(value['imageUrl']?.toString() ?? ''),
      action: normalize(value['action']?.toString() ?? 'none'),
      url: normalize(value['url']?.toString() ?? ''),
      copyText: normalize(value['copyText']?.toString() ?? ''),
    );
  }
}

class AppRemoteConfig {
  final HomeNotice? homeNotice;
  final AuthorAd authorAd;

  const AppRemoteConfig({
    required this.homeNotice,
    required this.authorAd,
  });

  static const fallback = AppRemoteConfig(
    homeNotice: null,
    authorAd: AuthorAd(
      enabled: false,
      title: '',
      text: '',
      imageUrl: '',
      action: 'none',
      url: '',
      copyText: '',
    ),
  );

  static AppRemoteConfig fromJson(Map<String, dynamic> data) {
    return AppRemoteConfig(
      homeNotice: HomeNotice.fromJson(data['homeNotice']),
      authorAd: AuthorAd.fromJson(data['authorAd']),
    );
  }
}

class RemoteConfigService {
  static const _cacheKey = 'remote_config_cache_2_0_0';
  static const _cacheTimeKey = 'remote_config_cache_time_2_0_0';
  static const _cacheDuration = Duration(minutes: 30);
  static AppRemoteConfig? _memoryConfig;
  static int _memoryConfigTime = 0;
  static Future<AppRemoteConfig>? _loading;

  static Future<AppRemoteConfig> load() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_memoryConfig != null &&
        now - _memoryConfigTime < _cacheDuration.inMilliseconds) {
      return Future.value(_memoryConfig);
    }
    final currentLoading = _loading;
    if (currentLoading != null) return currentLoading;
    final nextLoading = _load();
    _loading = nextLoading;
    return nextLoading.whenComplete(() => _loading = null);
  }

  static Future<AppRemoteConfig> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedText = prefs.getString(_cacheKey);
    final cachedTime = prefs.getInt(_cacheTimeKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 未配置远程地址时，保持离线模式并使用本地兜底配置。
    if (remoteConfigUrl.trim().isEmpty) {
      return _remember(AppRemoteConfig.fallback, now);
    }

    if (cachedText != null &&
        now - cachedTime < _cacheDuration.inMilliseconds) {
      final cached = _decode(cachedText);
      if (cached != null) return _remember(cached, cachedTime);
    }

    try {
      final response = await http
          .get(Uri.parse(remoteConfigUrl))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) {
        return _remember(
          _decode(cachedText) ?? AppRemoteConfig.fallback,
          cachedTime,
        );
      }
      final text = utf8.decode(response.bodyBytes);
      final config = _decode(text);
      if (config == null) {
        return _remember(
          _decode(cachedText) ?? AppRemoteConfig.fallback,
          cachedTime,
        );
      }
      await prefs.setString(_cacheKey, text);
      await prefs.setInt(_cacheTimeKey, now);
      return _remember(config, now);
    } catch (_) {
      return _remember(
        _decode(cachedText) ?? AppRemoteConfig.fallback,
        cachedTime,
      );
    }
  }

  static AppRemoteConfig _remember(AppRemoteConfig config, int time) {
    _memoryConfig = config;
    _memoryConfigTime = time > 0 ? time : DateTime.now().millisecondsSinceEpoch;
    return config;
  }

  static AppRemoteConfig? _decode(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      final data = jsonDecode(text);
      if (data is! Map<String, dynamic>) return null;
      return AppRemoteConfig.fromJson(data);
    } catch (_) {
      return null;
    }
  }
}
