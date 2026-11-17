import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pages/thread_detail_page.dart';
import '../services/haptic_service.dart';
import '../theme/app_theme.dart';
import 'zyb_feedback.dart';

enum LinkKind { web, jd, taobao, miniProgram, command, zkThread }

class DetectedLink {
  final String value;
  final LinkKind kind;

  const DetectedLink({required this.value, required this.kind});

  String get label => switch (kind) {
    LinkKind.jd => '京东链接',
    LinkKind.taobao => '淘宝链接',
    LinkKind.miniProgram => '微信小程序码',
    LinkKind.command => '购物口令',
    LinkKind.zkThread => '赚客吧帖子',
    LinkKind.web => '网页链接',
  };

  IconData get icon => switch (kind) {
    LinkKind.jd => Icons.shopping_bag_outlined,
    LinkKind.taobao => Icons.shopping_cart_outlined,
    LinkKind.miniProgram => Icons.apps_rounded,
    LinkKind.command => Icons.content_paste_go_outlined,
    LinkKind.zkThread => Icons.article_outlined,
    LinkKind.web => Icons.link_rounded,
  };

  bool get canOpen => kind != LinkKind.command && kind != LinkKind.miniProgram;
}

/// 提取赚客吧站内帖子 ID (tid)
String? extractZkThreadTid(String text) {
  final normalized = text.trim();
  final hasZkDomain = normalized.contains('zuanke8.com') ||
      normalized.contains('zuanke8.net') ||
      normalized.contains('zuanke8.cn') ||
      (!normalized.startsWith('http://') && !normalized.startsWith('https://'));
  if (!hasZkDomain) return null;
  final rewrite = RegExp(r'(?:^|[/?#&])thread-(\d+)-', caseSensitive: false).firstMatch(normalized);
  if (rewrite != null) return rewrite.group(1);
  final tidMatch = RegExp(r'(?:mod=viewthread[^\s&]*[&?]tid=|(?:\?|&)tid=)(\d+)', caseSensitive: false).firstMatch(normalized);
  if (tidMatch != null) return tidMatch.group(1);
  return null;
}

List<DetectedLink> detectLinks(String text) {
  final found = <DetectedLink>[];
  final seen = <String>{};

  void add(String value, LinkKind kind) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty && seen.add(trimmed)) {
      found.add(DetectedLink(value: trimmed, kind: kind));
    }
  }

  for (final match in RegExp(
    r'(?:(?:https?://|www\.)[^\s<>"，。！？、]+)',
    caseSensitive: false,
  ).allMatches(text)) {
    final value = match.group(0)!;
    final lowered = value.toLowerCase();
    final tid = extractZkThreadTid(value);
    final isJd = lowered.contains('jd.com') ||
        lowered.contains('3.cn') ||
        lowered.contains('jingdong.com');
    final isTaobao = lowered.contains('taobao.com') ||
        lowered.contains('tmall.com') ||
        lowered.contains('tb.cn') ||
        lowered.contains('etao.com');
    if (tid != null) {
      add(value, LinkKind.zkThread);
    } else {
      add(
        value,
        isJd
            ? LinkKind.jd
            : isTaobao
            ? LinkKind.taobao
            : LinkKind.web,
      );
    }
  }
  for (final match in RegExp(r'#?小程序://[^\s<>"，。！？、]+').allMatches(text)) {
    add(match.group(0)!, LinkKind.miniProgram);
  }
  for (final match in RegExp(r'￥[^￥\s]{4,80}￥').allMatches(text)) {
    add(match.group(0)!, LinkKind.command);
  }
  return found;
}

DetectedLink linkFromUrl(String value) {
  final detected = detectLinks(value);
  if (detected.isNotEmpty) return detected.first;
  final tid = extractZkThreadTid(value);
  if (tid != null) return DetectedLink(value: value, kind: LinkKind.zkThread);
  return DetectedLink(value: value, kind: LinkKind.web);
}

Future<void> showLinkTools(BuildContext context, DetectedLink link) async {
  // 如果是赚客吧站内帖子链接，直接在应用内打开原生详情页，无需弹窗及跳网页重新登录
  if (link.kind == LinkKind.zkThread) {
    final tid = extractZkThreadTid(link.value);
    if (tid != null) {
      Navigator.push(
        context,
        zybHorizontalPageRoute<void>(
          builder: (_) => ThreadDetailPage(tid: tid, title: '帖子详情'),
        ),
      );
      return;
    }
  }

  // 淘宝、京东等外部电商链接：直接尝试唤起原生官方 APP！
  if (link.kind == LinkKind.taobao || link.kind == LinkKind.jd) {
    HapticService.instance.lightImpact();
    final openedApp = await _tryLaunchNativeApp(link);
    if (openedApp) {
      if (context.mounted) {
        showZybFeedback(context, '正在跳转${link.label}...');
      }
      return;
    }
    // 未安装原生 APP 或未能唤起，在外部浏览器打开
    final openedWeb = await _openInExternal(link.value);
    if (context.mounted && !openedWeb) {
      showZybFeedback(context, '无法打开，请复制链接', error: true);
    }
    return;
  }

  final copied = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final colors = zybColors(sheetContext);
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: colors.cardBorder,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(link.icon, color: colors.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          link.label,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          link.kind == LinkKind.miniProgram
                              ? '复制后可在微信中打开'
                              : '可复制或使用外部应用打开',
                          style: TextStyle(color: colors.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: colors.surfaceSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  link.value,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 10),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                leading: Icon(Icons.copy_rounded, color: colors.primary),
                title: const Text('复制'),
                onTap: () => Navigator.pop(sheetContext, true),
              ),
              if (link.canOpen)
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  leading: Icon(Icons.open_in_new_rounded, color: colors.primary),
                  title: const Text('外部应用打开'),
                  onTap: () => Navigator.pop(sheetContext, false),
                ),
            ],
          ),
        ),
      );
    },
  );

  if (!context.mounted || copied == null) return;
  if (copied) {
    await Clipboard.setData(ClipboardData(text: link.value));
    if (context.mounted) {
      HapticService.instance.lightImpact();
      showZybFeedback(context, '复制成功');
    }
    return;
  }
  final appSuccess = await _tryLaunchNativeApp(link);
  if (!appSuccess) {
    final opened = await _openInExternal(link.value);
    if (!opened && context.mounted) {
      showZybFeedback(context, '无法打开，请先复制链接', error: true);
    }
  }
}

Future<bool> _openInExternal(String rawValue) async {
  var value = rawValue.trim();
  if (value.startsWith('www.')) value = 'https://$value';
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    value = 'https://$value';
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

String _extractJdSku(String url) {
  final match = RegExp(r'(?:item\.jd\.com|item\.m\.jd\.com)/(\d+)\.html').firstMatch(url);
  return match?.group(1) ?? '';
}

Future<bool> _tryLaunchNativeApp(DetectedLink link) async {
  var rawUrl = link.value.trim();
  if (rawUrl.startsWith('www.')) rawUrl = 'https://$rawUrl';
  if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
    rawUrl = 'https://$rawUrl';
  }

  if (link.kind == LinkKind.taobao) {
    final tbSchemes = [
      'tbopen://m.taobao.com/getWay?url=${Uri.encodeComponent(rawUrl)}',
      'taobao://${rawUrl.replaceFirst(RegExp(r'^https?://'), '')}',
    ];
    for (final s in tbSchemes) {
      final uri = Uri.tryParse(s);
      if (uri != null) {
        try {
          if (await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication)) {
            return true;
          }
        } catch (_) {}
      }
    }
  } else if (link.kind == LinkKind.jd) {
    final sku = _extractJdSku(rawUrl);
    final jdSchemes = [
      if (sku.isNotEmpty)
        'openapp.jdmobile://virtual?params={"category":"jump","des":"productDetail","skuId":"$sku"}',
      'openapp.jdmobile://virtual?params={"category":"jump","des":"m","url":"$rawUrl"}',
      'openapp.jdmobile://virtual?params={"sourceValue":"0","sourceType":"custom","action":"to","des":"m","url":"$rawUrl"}',
    ];
    for (final s in jdSchemes) {
      final uri = Uri.tryParse(s);
      if (uri != null) {
        try {
          if (await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication)) {
            return true;
          }
        } catch (_) {}
      }
    }
  }

  return false;
}
