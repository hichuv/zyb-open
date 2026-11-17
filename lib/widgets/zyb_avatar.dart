import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../config/constants.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';

class ZybAvatar extends StatefulWidget {
  final String url;
  final String uid;
  final String name;
  final double size;
  final double radius;

  const ZybAvatar({
    super.key,
    required this.url,
    this.uid = '',
    this.name = '',
    required this.size,
    this.radius = 999,
  });

  @override
  State<ZybAvatar> createState() => _ZybAvatarState();
}

class _ZybAvatarState extends State<ZybAvatar> {
  late List<String> _candidates = _buildCandidates();
  int _index = 0;

  @override
  void didUpdateWidget(covariant ZybAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.uid != widget.uid) {
      _candidates = _buildCandidates();
      _index = 0;
    }
  }

  List<String> _buildCandidates() {
    final result = <String>[];
    void add(String value) {
      final normalized = absoluteUrl(value).trim();
      if (normalized.isNotEmpty && !result.contains(normalized)) {
        result.add(normalized);
      }
    }

    for (final source in avatarUrls(widget.url)) {
      // 官方客户端直接加载接口给出的原地址，优先保持这一行为。
      add(source);
      if (source.startsWith('http://')) {
        add(source.replaceFirst('http://', 'https://'));
      } else if (source.startsWith('https://')) {
        add(source.replaceFirst('https://', 'http://'));
      }
    }

    if (widget.uid.isNotEmpty) {
      for (final source in discuzAvatarUrls(widget.uid)) {
        add(source);
        if (source.startsWith('http://')) {
          add(source.replaceFirst('http://', 'https://'));
        }
      }
    }
    return result;
  }

  void _tryNext() {
    if (_index + 1 >= _candidates.length || !mounted) return;
    setState(() => _index++);
  }

  Color _avatarColor(String text) {
    const palette = [
      Color(0xFFFF641E), // 暖橙
      Color(0xFF2979FF), // 亮蓝
      Color(0xFF00B578), // 翠绿
      Color(0xFF722ED1), // 优雅紫
      Color(0xFFFA541C), // 珊瑚红
      Color(0xFF0FC6C2), // 青绿
      Color(0xFFEB2F96), // 玫红
      Color(0xFFFF9900), // 琥珀黄
    ];
    final hash = text.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return palette[hash.abs() % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final effectiveName = widget.name.trim();
    final initial = effectiveName.isNotEmpty
        ? effectiveName.characters.first.toUpperCase()
        : '';
    final color =
        initial.isNotEmpty ? _avatarColor(effectiveName) : colors.textMuted;
    final fallback = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: initial.isNotEmpty
            ? color.withValues(alpha: 0.18)
            : colors.surfaceSoft,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: initial.isNotEmpty
          ? Text(
              initial,
              style: TextStyle(
                fontSize: widget.size * 0.44,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            )
          : Icon(
              Icons.person_rounded,
              color: colors.textMuted,
              size: widget.size * .58,
            ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _candidates.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: _candidates[_index],
                cacheKey: _candidates[_index],
                httpHeaders: const {
                  'Referer': baseUrl,
                  'User-Agent': mobileUserAgent,
                },
                width: widget.size,
                height: widget.size,
                memCacheWidth: (widget.size * 2).toInt().clamp(60, 200),
                fit: BoxFit.cover,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => _tryNext());
                  return fallback;
                },
              ),
      ),
    );
  }
}
