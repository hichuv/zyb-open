import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../config/constants.dart';
import '../pages/thread_detail_page.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import 'image_viewer.dart';
import 'link_tools.dart';

class NativeHtmlContent extends StatefulWidget {
  final String html;
  final double fontSize;

  /// 收缩模式：用于私信气泡等需要宽度跟随文字的场景，
  /// 否则默认撑满父级宽度（帖子正文用默认）。
  final bool shrinkWrap;
  final List<String> galleryImages;
  final void Function(String author, String? dateline)? onQuoteTap;

  const NativeHtmlContent({
    super.key,
    required this.html,
    this.fontSize = 16,
    this.shrinkWrap = false,
    this.galleryImages = const [],
    this.onQuoteTap,
  });

  @override
  State<NativeHtmlContent> createState() => _NativeHtmlContentState();
}

class _NativeHtmlContentState extends State<NativeHtmlContent> {
  final List<TapGestureRecognizer> _recognizers = [];
  int _quoteDepth = 0;
  late dom.DocumentFragment _fragment;
  late List<String> _ownImages;

  @override
  void initState() {
    super.initState();
    _cacheParsedContent();
  }

  @override
  void didUpdateWidget(covariant NativeHtmlContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _disposeRecognizers();
      _cacheParsedContent();
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  void _cacheParsedContent() {
    _fragment = html_parser.parseFragment(widget.html);
    _ownImages = imageUrlsFromFragment(_fragment);
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recognizers.isNotEmpty) {
      final oldRecognizers = List<TapGestureRecognizer>.from(_recognizers);
      _recognizers.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final r in oldRecognizers) {
          r.dispose();
        }
      });
    }

    final colors = zybColors(context);
    final gallery = <String>{..._ownImages, ...widget.galleryImages}.toList();
    final blocks = <Widget>[];
    final spans = <InlineSpan>[];

    void appendPlainText(String text, TextStyle style) {
      if (text.isEmpty) return;
      final previous = spans.isEmpty || spans.last is! TextSpan
          ? ''
          : (spans.last as TextSpan).text ?? '';
      final value = previous.endsWith('\n')
          ? text.replaceFirst(RegExp(r'^\n+'), '')
          : text;
      if (value.isNotEmpty) spans.add(TextSpan(text: value, style: style));
    }

    TapGestureRecognizer linkRecognizer(DetectedLink link) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          final tid = extractZkThreadTid(link.value);
          if (tid != null) {
            Navigator.push(
              context,
              zybHorizontalPageRoute<void>(
                builder: (_) => ThreadDetailPage(
                  tid: tid,
                  title: '帖子详情',
                ),
              ),
            );
            return;
          }
          showLinkTools(context, link);
        };
      _recognizers.add(recognizer);
      return recognizer;
    }

    void appendText(String text, TextStyle style) {
      if (text.isEmpty) return;
      final matches = RegExp(
        r'(?:(?:https?://|www\.)[^\s<>"，。！？、]+|#?小程序://[^\s<>"，。！？、]+|￥[^￥\s]{4,80}￥)',
        caseSensitive: false,
      ).allMatches(text).toList();
      if (matches.isEmpty) {
        appendPlainText(text, style);
        return;
      }
      var cursor = 0;
      for (final match in matches) {
        appendPlainText(text.substring(cursor, match.start), style);
        final link = linkFromUrl(match.group(0)!);
        spans.add(
          TextSpan(
            text: link.value,
            style: style.merge(
              TextStyle(
                color: colors.primary,
                decoration: TextDecoration.underline,
                decorationColor: colors.primary,
              ),
            ),
            recognizer: linkRecognizer(link),
          ),
        );
        cursor = match.end;
      }
      appendPlainText(text.substring(cursor), style);
    }

    void appendBreak() {
      if (spans.isEmpty) return;
      final previous = spans.last is TextSpan
          ? (spans.last as TextSpan).text ?? ''
          : '';
      if (!previous.endsWith('\n')) spans.add(const TextSpan(text: '\n'));
    }

    void flushText() {
      if (spans.isEmpty) return;
      final clean = _collapseInlineSpans(spans);
      spans.clear();
      if (clean.isEmpty) return;
      blocks.add(
        SelectableText.rich(
          TextSpan(children: clean),
          contextMenuBuilder: _textContextMenu,
          // 让文本按最长行收缩宽度，避免在气泡等宽松约束下顶格占满
          textWidthBasis: TextWidthBasis.longestLine,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: widget.fontSize,
            height: 1.55,
          ),
        ),
      );
    }

    void walk(dom.Node node, {TextStyle style = const TextStyle()}) {
      if (node is dom.Text) {
        appendText(
          node.data
              .replaceAll('\u00a0', ' ')
              .replaceAll(RegExp(r'[ \t]+'), ' ')
              .replaceAll(RegExp(r'\n+'), ' '),
          style,
        );
        return;
      }
      if (node is! dom.Element) return;

      final tag = node.localName;
      if (tag == 'img') {
        final src = _imageUrl(node);
        if (_isSmiley(node, src)) {
          if (src.isNotEmpty) {
            spans.add(
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: CachedNetworkImage(
                    imageUrl: src,
                    width: widget.fontSize + 3,
                    height: widget.fontSize + 3,
                    memCacheWidth: 60,
                    fit: BoxFit.contain,
                    httpHeaders: const {
                      'Referer': baseUrl,
                      'User-Agent': mobileUserAgent,
                    },
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          }
          return;
        }
        flushText();
        if (src.isNotEmpty) {
          final widthAttr = double.tryParse(node.attributes['width'] ?? '');
          final heightAttr = double.tryParse(node.attributes['height'] ?? '');
          final hasDimensions = widthAttr != null &&
              heightAttr != null &&
              widthAttr > 0 &&
              heightAttr > 0;
          final double? aspectRatio = hasDimensions
              ? (widthAttr / heightAttr).clamp(0.35, 3.0)
              : null;

          Widget imageWidget = CachedNetworkImage(
            imageUrl: src,
            httpHeaders: const {
              'Referer': baseUrl,
              'User-Agent': mobileUserAgent,
            },
            fit: BoxFit.contain,
            memCacheWidth: 1080,
            placeholder: (context, url) => Container(
              height: aspectRatio != null ? null : 140,
              color: colors.surfaceSoft,
              alignment: Alignment.center,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              height: 72,
              color: colors.surfaceSoft,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '图片加载失败',
                    style: TextStyle(color: colors.textMuted),
                  ),
                ],
              ),
            ),
          );

          if (aspectRatio != null) {
            imageWidget = AspectRatio(
              aspectRatio: aspectRatio,
              child: imageWidget,
            );
          }

          blocks.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: InkWell(
                onTap: () => openImageViewer(
                  context,
                  gallery,
                  initialIndex: gallery
                      .indexOf(src)
                      .clamp(0, gallery.length - 1),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: imageWidget,
                ),
              ),
            ),
          );
          return;
        }
        return;
      }
      if (tag == 'br') {
        appendBreak();
        return;
      }

      var nextStyle = style;
      if (tag == 'b' || tag == 'strong') {
        nextStyle = nextStyle.merge(
          const TextStyle(fontWeight: FontWeight.w700),
        );
      } else if (tag == 'i' || tag == 'em') {
        nextStyle = nextStyle.merge(
          const TextStyle(fontStyle: FontStyle.italic),
        );
      } else if (tag == 'u') {
        nextStyle = nextStyle.merge(
          const TextStyle(decoration: TextDecoration.underline),
        );
      }

      // 全站双字号体系：小于官方默认字号（如 size="1"、small、微型字体、AI小尾巴）时采用精致辅助小字号 12px，
      // 其余 >= 默认字号的通通收拢为手机标准阅读字号 16px，严禁网页杂乱大号字破坏排版。
      if (_isSmallFont(node)) {
        nextStyle = nextStyle.merge(
          const TextStyle(fontSize: 12.0),
        );
      }

      final foreground =
          _parseColor(node.attributes['color']) ??
          _styleColor(node.attributes['style'], 'color');
      final background =
          _parseColor(node.attributes['bgcolor']) ??
          _styleColor(node.attributes['style'], 'background-color') ??
          _styleColor(node.attributes['style'], 'background');
      if (foreground != null) {
        nextStyle = nextStyle.merge(TextStyle(color: foreground));
      }
      if (background != null) {
        nextStyle = nextStyle.merge(TextStyle(backgroundColor: background));
      }

      if (tag == 'a') {
        final href = absoluteUrl(node.attributes['href'] ?? '');
        // 引用块内的链接不可点击（引用来源展示）
        if (_quoteDepth > 0) {
          spans.add(
            TextSpan(
              text: node.text,
              style: nextStyle.merge(
                TextStyle(
                  color: colors.textMuted,
                  fontSize: widget.fontSize - 1.5,
                  height: 1.4,
                ),
              ),
            ),
          );
          return;
        }
        spans.add(
          TextSpan(
            text: node.text,
            style: nextStyle.merge(
              TextStyle(
                color: colors.primary,
                decoration: TextDecoration.underline,
                decorationColor: colors.primary,
              ),
            ),
            recognizer: linkRecognizer(linkFromUrl(href)),
          ),
        );
        return;
      }

      final isQuoteElement = tag == 'blockquote' ||
          (tag == 'div' &&
              (node.className.contains('quote') ||
                  node.className.contains('reply_wrap')));

      if (isQuoteElement) {
        flushText();
        final bq = node.querySelector('blockquote');
        final targetNode = bq ?? node;
        final childBlocks = _renderQuote(targetNode, colors);
        blocks.addAll(childBlocks);
        return;
      }

      final block = const {
        'p',
        'div',
        'section',
        'article',
        'blockquote',
        'li',
        'table',
        'tr',
      }.contains(tag);
      if (block) appendBreak();
      for (final child in node.nodes) {
        walk(child, style: nextStyle);
      }
      if (block) appendBreak();
    }

    for (final node in _fragment.nodes) {
      walk(node);
    }
    flushText();

    if (blocks.isEmpty) {
      return Text(
        '暂无正文',
        style: TextStyle(color: colors.textMuted, fontSize: widget.fontSize),
      );
    }
    if (widget.shrinkWrap) {
      return IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: blocks,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }

  Widget _textContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    final colors = zybColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final buttons = <ContextMenuButtonItem>[];
    for (final item in editableTextState.contextMenuButtonItems) {
      if (item.type == ContextMenuButtonType.copy) {
        buttons.add(
          ContextMenuButtonItem(
            type: ContextMenuButtonType.copy,
            label: '复制',
            onPressed: () {
              final value = editableTextState.textEditingValue;
              final selected = value.selection.textInside(value.text).trim();
              item.onPressed?.call();
              _offerJdOpen(selected);
            },
          ),
        );
      } else if (item.type == ContextMenuButtonType.selectAll) {
        buttons.add(item.copyWith(label: '全选'));
      }
    }
    return TextSelectionToolbar(
      anchorAbove: editableTextState.contextMenuAnchors.primaryAnchor,
      anchorBelow: editableTextState.contextMenuAnchors.secondaryAnchor ??
          editableTextState.contextMenuAnchors.primaryAnchor,
      toolbarBuilder: (context, child) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2B2D31) : Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isDark ? const Color(0xFF3E4046) : const Color(0xFFE5E6EB),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
      children: [
        for (int i = 0; i < buttons.length; i++) ...[
          if (i > 0)
            Container(
              width: 0.6,
              height: 18,
              color: isDark ? const Color(0xFF3E4046) : const Color(0xFFE5E6EB),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: buttons[i].onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Text(
                  buttons[i].label ?? '',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _offerJdOpen(String selected) {
    if (!RegExp(r'^\d{6,16}$').hasMatch(selected)) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 310,
        duration: const Duration(seconds: 4),
        elevation: 5,
        backgroundColor: isDark ? const Color(0xFF2E1C12) : const Color(0xFFFFF1E8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark ? const Color(0x66FF5F15) : const Color(0xFFFFD6C0),
            width: .8,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '疑似京东编号',
              style: TextStyle(
                color: isDark ? const Color(0xFFFFB088) : const Color(0xFF5C3928),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              selected,
              style: TextStyle(
                color: isDark ? const Color(0xFFF7EBE3) : const Color(0xFF1B1715),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: '打开京东',
          textColor: const Color(0xFFE85219),
          onPressed: () => const MethodChannel(
            'zybapp/platform',
          ).invokeMethod<void>('openJdProduct', {'sku': selected}),
        ),
      ),
    );
  }

  /// 渲染引用块：左竖线 + 淡灰底，内部小字，链接不可点击
  List<Widget> _renderQuote(dom.Element node, ZybColors colors) {
    _quoteDepth++;
    final quoteSpans = <InlineSpan>[];
    final quoteBlocks = <Widget>[];
    var quoteText = '';

    void collect(dom.Node child) {
      if (child is dom.Text) {
        quoteText += child.data;
      } else if (child is dom.Element) {
        if (child.localName == 'br') {
          quoteText += '\n';
        }
        for (final grand in child.nodes) {
          collect(grand);
        }
      }
    }

    for (final child in node.nodes) {
      collect(child);
    }
    _quoteDepth--;

    final normalizedQuote = quoteText.trimLeft();
    final headMatch = RegExp(
      r'^(?:引用\s*[:：]?\s*)?([^\r\n]+?)\s+发表[于]?\s*[:：]?\s*([^\r\n]+?)(?:\r?\n|$)',
    ).firstMatch(normalizedQuote);
    final cleaned = headMatch == null
        ? normalizedQuote
        : normalizedQuote.substring(headMatch.end).trimLeft();

    if (headMatch != null) {
      final headerStyle = TextStyle(
        color: colors.textMuted,
        fontSize: widget.fontSize - 3,
        fontWeight: FontWeight.w500,
      );
      quoteSpans.addAll([
        TextSpan(text: '引用 ', style: headerStyle),
        TextSpan(
          text: headMatch.group(1)!.trim(),
          style: headerStyle.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        TextSpan(text: ' 发表于 ${headMatch.group(2)!.trim()}\n', style: headerStyle),
      ]);
    }

    final content = cleaned.trim();
    if (content.isNotEmpty) {
      quoteSpans.add(
        TextSpan(
          text: content,
          style: TextStyle(
            color: colors.textMuted,
            fontSize: widget.fontSize - 1.5,
            height: 1.4,
          ),
        ),
      );
    }

    if (quoteSpans.isNotEmpty) {
      quoteBlocks.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text.rich(
            TextSpan(children: quoteSpans),
            textWidthBasis: TextWidthBasis.longestLine,
            style: TextStyle(fontSize: widget.fontSize),
          ),
        ),
      );
    }

    final canJump = widget.onQuoteTap != null && headMatch != null;

    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: canJump
                ? () => widget.onQuoteTap!(
                    headMatch.group(1)!.trim(),
                    headMatch.group(2)?.trim(),
                  )
                : null,
            child: Container(
              padding: const EdgeInsets.fromLTRB(9, 5, 9, 5),
              decoration: BoxDecoration(
                color: colors.surfaceSoft.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(7),
                border: Border(
                  left: BorderSide(
                    color: colors.primary.withValues(alpha: 0.4),
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: quoteBlocks.isEmpty
                    ? [
                        Text(
                          quoteText.trim().isEmpty
                              ? '引用内容'
                              : quoteText.trim(),
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: widget.fontSize - 1.5,
                            height: 1.4,
                          ),
                        ),
                      ]
                    : quoteBlocks,
              ),
            ),
          ),
        ),
      ),
    ];
  }

  List<InlineSpan> _collapseInlineSpans(List<InlineSpan> source) {
    final output = <InlineSpan>[];
    var previousEndedWithBreak = false;
    for (final span in source) {
      if (span is! TextSpan) {
        output.add(span);
        previousEndedWithBreak = false;
        continue;
      }
      final textSpan = span;
      var text = textSpan.text ?? '';
      text = text.replaceAll(RegExp(r'\n[ \t]*\n+'), '\n');
      if (previousEndedWithBreak) text = text.replaceFirst(RegExp(r'^\n+'), '');
      if (text.isEmpty) continue;
      output.add(
        TextSpan(
          text: text,
          style: textSpan.style,
          recognizer: textSpan.recognizer,
        ),
      );
      previousEndedWithBreak = text.endsWith('\n');
    }
    while (output.isNotEmpty &&
        output.last is TextSpan &&
        (output.last as TextSpan).text == '\n') {
      output.removeLast();
    }
    return output;
  }

  String _imageUrl(dom.Element node) {
    for (final key in const ['zoomfile', 'file', 'data-original', 'src']) {
      final value = node.attributes[key] ?? '';
      if (value.isNotEmpty) return absoluteUrl(value);
    }
    return '';
  }

  bool _isSmiley(dom.Element node, String src) {
    final marker = '$src ${node.className} ${node.attributes['alt'] ?? ''}'
        .toLowerCase();
    if (marker.contains('smiley') ||
        marker.contains('smilie') ||
        marker.contains('emotion'))
      return true;
    final width = double.tryParse(
      (node.attributes['width'] ?? '').replaceAll('px', ''),
    );
    final height = double.tryParse(
      (node.attributes['height'] ?? '').replaceAll('px', ''),
    );
    return width != null && height != null && width <= 80 && height <= 80;
  }

  Color? _styleColor(String? rawStyle, String property) {
    if (rawStyle == null || rawStyle.trim().isEmpty) return null;
    final target = property.toLowerCase();
    for (final declaration in rawStyle.split(';')) {
      final separator = declaration.indexOf(':');
      if (separator <= 0) continue;
      final key = declaration.substring(0, separator).trim().toLowerCase();
      if (key != target) continue;
      final value = declaration.substring(separator + 1).trim();
      // background 的简写中可能还带图片、repeat 等值；先取第一个颜色值。
      return _parseColor(value.split(RegExp(r'\s+')).first);
    }
    return null;
  }

  Color? _parseColor(String? raw) {
    if (raw == null) return null;
    final source = raw.trim();
    if (source.isEmpty) return null;
    final value = source.toLowerCase();

    const named = <String, int>{
      'black': 0xFF000000,
      'white': 0xFFFFFFFF,
      'red': 0xFFFF0000,
      'green': 0xFF008000,
      'lime': 0xFF00FF00,
      'blue': 0xFF0000FF,
      'yellow': 0xFFFFFF00,
      'orange': 0xFFFFA500,
      'purple': 0xFF800080,
      'brown': 0xFFA52A2A,
      'pink': 0xFFFFC0CB,
      'gray': 0xFF808080,
      'grey': 0xFF808080,
      'silver': 0xFFC0C0C0,
      'maroon': 0xFF800000,
      'olive': 0xFF808000,
      'navy': 0xFF000080,
      'teal': 0xFF008080,
      'aqua': 0xFF00FFFF,
      'cyan': 0xFF00FFFF,
      'fuchsia': 0xFFFF00FF,
      'magenta': 0xFFFF00FF,
      'transparent': 0x00000000,
    };
    final namedValue = named[value];
    if (namedValue != null) return Color(namedValue);

    final rgb = RegExp(
      r'^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*([\d.]+))?\s*\)$',
    ).firstMatch(value);
    if (rgb != null) {
      final red = int.parse(rgb.group(1)!).clamp(0, 255);
      final green = int.parse(rgb.group(2)!).clamp(0, 255);
      final blue = int.parse(rgb.group(3)!).clamp(0, 255);
      final alphaRaw = rgb.group(4);
      final alpha = alphaRaw == null
          ? 255
          : (double.tryParse(alphaRaw) ?? 1).clamp(0, 1) * 255;
      return Color.fromARGB(alpha.round(), red, green, blue);
    }

    var hex = value.replaceFirst('#', '');
    if (hex.startsWith('0x')) hex = hex.substring(2);
    if (hex.length == 3) {
      hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
    }
    if (hex.length == 6) hex = 'ff$hex';
    if (hex.length != 8 || !RegExp(r'^[0-9a-f]{8}$').hasMatch(hex)) {
      return null;
    }
    return Color(int.parse(hex, radix: 16));
  }

  bool _isSmallFont(dom.Element node) {
    if (node.localName == 'small') return true;
    final sizeAttr = node.attributes['size']?.trim();
    if (sizeAttr == '1' || sizeAttr == '0') return true;
    final style = node.attributes['style'];
    if (style != null) {
      final lower = style.toLowerCase();
      if (lower.contains('xx-small') || lower.contains('x-small')) return true;
      final match =
          RegExp(r'font-size\s*:\s*(\d+(?:\.\d+)?)\s*px').firstMatch(lower);
      if (match != null) {
        final px = double.tryParse(match.group(1) ?? '');
        if (px != null && px < 13.5) return true;
      }
    }
    return false;
  }
}

String plainTextFromHtml(String html) => normalize(
  html_parser
          .parseFragment(html)
          .text
          ?.replaceAll(RegExp(r'\n[ \t]*\n+'), '\n') ??
      '',
);

List<String> imageUrlsFromHtml(String html) {
  return imageUrlsFromFragment(html_parser.parseFragment(html));
}

List<String> imageUrlsFromFragment(dom.DocumentFragment fragment) {
  final output = <String>[];
  for (final image in fragment.querySelectorAll('img')) {
    final marker = '${image.className} ${image.attributes['alt'] ?? ''}'
        .toLowerCase();
    if (marker.contains('smiley') ||
        marker.contains('smilie') ||
        marker.contains('emotion')) {
      continue;
    }
    var source = '';
    for (final key in const ['zoomfile', 'file', 'data-original', 'src']) {
      source = image.attributes[key] ?? '';
      if (source.isNotEmpty) break;
    }
    if (source.isEmpty) continue;
    final absolute = absoluteUrl(source);
    if (!output.contains(absolute)) output.add(absolute);
  }
  return output;
}
