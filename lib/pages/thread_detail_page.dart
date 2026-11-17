import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/constants.dart';
import '../models/thread_detail.dart';
import '../services/haptic_service.dart';
import '../services/official_api_service.dart';
import '../services/deepseek_service.dart';
import '../services/blacklist_service.dart';
import '../services/platform_service.dart';
import '../theme/app_theme.dart';
import '../widgets/image_viewer.dart';
import '../widgets/native_html_content.dart';
import '../widgets/zyb_feedback.dart';
import '../widgets/zyb_avatar.dart';
import 'login_page.dart';
import 'other_user_profile_page.dart';
import 'private_messages_page.dart';
import 'webview_page.dart';
import '../utils/time_parser.dart';

class ThreadDetailPage extends StatefulWidget {
  final String tid;
  final String title;

  const ThreadDetailPage({super.key, required this.tid, required this.title});

  @override
  State<ThreadDetailPage> createState() => _ThreadDetailPageState();
}

class _ThreadDetailPageState extends State<ThreadDetailPage> {
  final _api = OfficialApiService();
  final _scrollController = ScrollController();
  ThreadDetail? _detail;
  final List<ThreadFloor> _floors = [];
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _onlyAuthor = false;
  bool _sortDesc = false;
  bool _aiBusy = false;
  bool _isFavorited = false;
  String _favId = '';
  bool _showAppbarTitle = false;
  bool _showBackToTop = false;
  final ValueNotifier<bool> _scrolling = ValueNotifier(false);
  int _scrollSignal = 0;
  Offset? _aiOffset;
  Set<String> _blockedUids = const {};
  int _page = 1;
  int _totalPage = 1;
  bool _isPopping = false;
  bool _aiEnabled = false;
  String? _highlightedPid;
  final Map<String, GlobalKey> _floorItemKeys = {};
  final GlobalKey _mainArticleKey = GlobalKey();
  final GlobalKey _commentHeaderKey = GlobalKey();
  double _cacheExtent = 3500.0;
  String? _authorRegDate;
  String? _authorGroupTitle;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    BlacklistService().load().then((value) {
      if (mounted) setState(() => _blockedUids = value);
    });
    _loadAiEnabled();
    _load(reset: true);
  }

  Future<void> _loadAiEnabled() async {
    final enabled = await DeepSeekService().isAiEnabled();
    if (mounted) setState(() => _aiEnabled = enabled);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _scrolling.dispose();
    super.dispose();
  }

  void _popWithResult() {
    if (_isPopping) return;
    setState(() => _isPopping = true);
    Navigator.of(context).pop({
      'favorited': _isFavorited,
      'tid': widget.tid,
    });
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    HapticService.instance.lightImpact();
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleScroll() {
    if (!mounted) return;
    final signal = ++_scrollSignal;
    if (!_scrolling.value) _scrolling.value = true;
    Future<void>.delayed(const Duration(milliseconds: 240), () {
      if (mounted && signal == _scrollSignal)
        _scrolling.value = false;
    });
    final showTitle = _scrollController.hasClients && _scrollController.offset > 60;
    if (showTitle != _showAppbarTitle) {
      setState(() => _showAppbarTitle = showTitle);
    }
    final showBackToTop = _scrollController.hasClients && _scrollController.offset > 550;
    if (showBackToTop != _showBackToTop) {
      setState(() => _showBackToTop = showBackToTop);
    }
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        _page >= _totalPage) {
      return;
    }
    if (_scrollController.position.extentAfter < 420) {
      _loadNextPage();
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _authorRegDate = null;
        _authorGroupTitle = null;
      });
    }
    try {
      final result = await _api.fetchThread(
        tid: widget.tid,
        page: 1,
        authorId: _onlyAuthor ? _detail?.authorId : null,
      );
      if (!mounted) return;
      if (result.fid == '11') {
        _redirectToDesktopWeb(result.subject);
        return;
      }
      final authorId = result.authorId.isNotEmpty
          ? result.authorId
          : (result.floors.where((f) => f.first).firstOrNull?.authorId ?? '');
      final cachedProfile = _api.getCachedUserProfile(authorId);
      final initialRegDate = cachedProfile != null ? formatRegDate(cachedProfile.registeredAt) : null;
      final initialGroupTitle = (cachedProfile?.groupTitle.isNotEmpty == true)
          ? cachedProfile!.groupTitle
          : (result.floors.where((f) => f.first).firstOrNull?.groupTitle ?? '');

      setState(() {
        _detail = result;
        _isFavorited = result.favorite;
        _favId = result.favId;
        _floors
          ..clear()
          ..addAll(result.floors);
        _floorItemKeys.clear();
        _page = 1;
        _totalPage = result.totalPage;
        _loading = false;
        if (initialRegDate != null && initialRegDate.isNotEmpty) {
          _authorRegDate = initialRegDate;
        }
        if (initialGroupTitle.isNotEmpty) {
          _authorGroupTitle = initialGroupTitle;
        }
      });
      _fetchAuthorInfo(authorId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleScroll();
      });
    } catch (error) {
      if (!mounted) return;
      final errorStr = error.toString();
      if (errorStr.contains('电脑版') ||
          errorStr.contains('请使用电脑版') ||
          errorStr.contains('做任务赚果果')) {
        _redirectToDesktopWeb();
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _redirectToDesktopWeb([String? title]) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => WebViewPage(
          url: threadUrl(widget.tid),
          title: title ?? widget.title,
          initialDesktopMode: true,
        ),
      ),
    );
  }

  void _fetchAuthorInfo(String authorId) {
    if (authorId.isEmpty) return;
    _api.fetchUserProfile(authorId).then((profile) {
      if (!mounted) return;
      final group = profile.groupTitle.trim();
      final reg = formatRegDate(profile.registeredAt).trim();
      if (_detail?.authorId == authorId ||
          _floors.any((f) => f.first && f.authorId == authorId)) {
        setState(() {
          if (group.isNotEmpty) _authorGroupTitle = group;
          if (reg.isNotEmpty) _authorRegDate = reg;
        });
      }
    }).catchError((_) {
      // Ignore background fetch error
    });
  }

  Future<void> _toggleFavorite() async {
    if (_detail == null) return;
    HapticService.instance.lightImpact();
    final target = !_isFavorited;
    setState(() => _isFavorited = target);
    try {
      if (target) {
        final favId = await _api.favoriteThread(widget.tid);
        if (favId.isNotEmpty) _favId = favId;
        if (!mounted) return;
        _toast('收藏成功');
      } else {
        await _api.unfavoriteThread(favId: _favId, tid: widget.tid);
        _favId = '';
        if (!mounted) return;
        _toast('已取消收藏');
      }
    } on OfficialApiException catch (error) {
      if (!mounted) return;
      if (error.loginRequired) {
        setState(() => _isFavorited = !target);
        _loginAndRetry();
        return;
      }
      setState(() => _isFavorited = !target);
      _toast(target ? '收藏失败：${error.message}' : '取消收藏失败：${error.message}');
    } catch (_) {
      if (mounted) {
        setState(() => _isFavorited = !target);
        _toast(target ? '收藏失败' : '取消收藏失败');
      }
    }
  }

  void _toggleOnlyAuthor() {
    HapticService.instance.lightImpact();
    setState(() => _onlyAuthor = !_onlyAuthor);
    _load(reset: true);
  }

  Future<void> _loadNextPage() async {
    if (_loadingMore || _page >= _totalPage || _detail == null) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final result = await _api.fetchThread(
        tid: widget.tid,
        page: nextPage,
        authorId: _onlyAuthor ? _detail!.authorId : null,
      );
      if (!mounted) return;
      final existing = _floors.map((floor) => floor.pid).toSet();
      setState(() {
        _floors.addAll(result.floors.where((floor) => existing.add(floor.pid)));
        _page = nextPage;
        _totalPage = result.totalPage;
        _loadingMore = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleScroll();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _toast(error.toString());
    }
  }

  Future<void> _loginAndRetry() async {
    final success = await Navigator.push<bool>(
      context,
      zybHorizontalPageRoute<bool>(builder: (_) => const LoginPage()),
    );
    if (success == true) await _load(reset: true);
  }

  void _openWeb({bool desktop = false}) {
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => WebViewPage(
          url: threadUrl(widget.tid),
          title: widget.title,
          initialDesktopMode: desktop,
        ),
      ),
    );
  }

  Future<void> _copyThread() async {
    HapticService.instance.lightImpact();
    final text = _threadShareText();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast('复制成功');
  }

  String _threadShareText() {
    final detail = _detail;
    final first = _floors.where((floor) => floor.first).firstOrNull;
    final lines = <String>[
      detail?.subject ?? widget.title,
      if (detail?.author.isNotEmpty == true) '作者：${detail!.author}',
      if (first != null && plainTextFromHtml(first.messageHtml).isNotEmpty) ...[
        '',
        plainTextFromHtml(first.messageHtml),
      ],
      '',
      threadUrl(widget.tid),
    ];
    return lines.join('\n');
  }

  Future<bool> _configureDeepSeek() async {
    final service = DeepSeekService();
    final current = await service.token() ?? '';
    if (!mounted) return false;
    final controller = TextEditingController(text: current);
    var obscure = true;
    var saving = false;
    String error = '';
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final colors = zybColors(context);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: colors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'DeepSeek Token',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (current.isNotEmpty)
                          IconButton(
                            tooltip: '删除 Token',
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: colors.textMuted,
                            ),
                            onPressed: saving
                                ? null
                                : () async {
                                    await service.deleteToken();
                                    if (sheetContext.mounted)
                                      Navigator.pop(sheetContext, false);
                                  },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      obscureText: obscure,
                      autocorrect: false,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'sk-...',
                        filled: true,
                        fillColor: colors.surfaceSoft,
                        errorText: error.isEmpty ? null : error,
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setSheetState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(13),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Token 仅加密保存在本机。分析时只发送帖子标题和楼主文字。',
                      style: TextStyle(
                        color: colors.textMuted,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 15),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              setSheetState(() {
                                saving = true;
                                error = '';
                              });
                              try {
                                await service.validateAndSave(controller.text);
                                if (sheetContext.mounted)
                                  Navigator.pop(sheetContext, true);
                              } catch (e) {
                                setSheetState(() {
                                  saving = false;
                                  error = e.toString();
                                });
                              }
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '验证并保存',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
    return saved == true;
  }

  Future<void> _runAi() async {
    if (_aiBusy || _detail == null) return;
    final service = DeepSeekService();
    if ((await service.token())?.isNotEmpty != true) {
      if (!await _configureDeepSeek()) return;
    }
    final first = _floors.where((floor) => floor.first).firstOrNull;
    if (first == null) return;
    setState(() => _aiBusy = true);
    try {
      final answer = await service.analyze(
        title: _detail!.subject,
        text: plainTextFromHtml(first.messageHtml),
        url: threadUrl(widget.tid),
      );
      if (!mounted) return;
      final hasImages =
          first.attachments.isNotEmpty ||
          RegExp(r'<img\b', caseSensitive: false).hasMatch(first.messageHtml);
      await _showAiResult(answer, hasImages: hasImages);
    } catch (e) {
      if (mounted) showZybFeedback(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  String _aiReplyMessage(String answer) {
    return '${answer.trim()}\n\n'
        '[size=1][color=Gray][此回复由 AI 生成，仅供参考][/size][/color]';
  }

  Future<void> _showAiResult(String answer, {required bool hasImages}) async {
    var posting = false;
    var panelMessage = '';
    var panelError = false;
    final replied = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭帖子分析',
      barrierColor: Colors.black.withValues(alpha: .38),
      transitionDuration: ZybDesign.motion,
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: ZybDesign.motionCurve,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, _) {
        final colors = zybColors(ctx);
        return StatefulBuilder(
          builder: (ctx, setPanelState) => Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 44,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: MediaQuery.sizeOf(ctx).height * .78,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Ai 总结/解答',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Material(
                          color: colors.primarySoft,
                          borderRadius: BorderRadius.circular(9),
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              _configureDeepSeek();
                            },
                            borderRadius: BorderRadius.circular(9),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.settings_rounded,
                                    size: 16,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '设置',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: colors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: colors.surfaceSoft,
                          borderRadius: BorderRadius.circular(9),
                          child: InkWell(
                            onTap: () => Navigator.pop(ctx),
                            borderRadius: BorderRadius.circular(9),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (panelMessage.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: panelError
                              ? Colors.red.withValues(alpha: .09)
                              : colors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          panelMessage,
                          style: TextStyle(
                            color: panelError
                                ? Colors.red.shade700
                                : colors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    if (hasImages)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: colors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '本帖包含图片，以下分析仅基于标题和文字内容，图片未参与分析。',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    Flexible(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: colors.surfaceSoft,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.cardBorder),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            answer,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15.5,
                              height: 1.7,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: answer),
                              );
                              HapticService.instance.lightImpact();
                              if (ctx.mounted) {
                                showZybFeedback(ctx, '复制成功');
                              }
                            },
                            icon: Icon(
                              Icons.copy_rounded,
                              size: 15,
                              color: colors.primary,
                            ),
                            label: Text(
                              '复制',
                              style: TextStyle(
                                color: colors.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: colors.primary.withValues(alpha: 0.45),
                                width: 1.0,
                              ),
                              backgroundColor:
                                  colors.primarySoft.withValues(alpha: 0.3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 13,
                          child: FilledButton.icon(
                            onPressed: posting
                                ? null
                                : () async {
                                    setPanelState(() {
                                      posting = true;
                                      panelMessage = '';
                                    });
                                    try {
                                      await _api.replyThread(
                                        tid: widget.tid,
                                        message: _aiReplyMessage(answer),
                                      );
                                      if (ctx.mounted) Navigator.pop(ctx, true);
                                    } on OfficialApiException catch (error) {
                                      if (!ctx.mounted) return;
                                      setPanelState(() {
                                        posting = false;
                                        panelMessage = error.message;
                                        panelError = true;
                                      });
                                    } catch (_) {
                                      if (!ctx.mounted) return;
                                      setPanelState(() {
                                        posting = false;
                                        panelMessage = '回复失败，请稍后重试';
                                        panelError = true;
                                      });
                                    }
                                  },
                            icon: posting
                                ? const SizedBox(
                                    width: 17,
                                    height: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded, size: 16),
                            label: Text(
                              posting ? '正在回复…' : '一键回复',
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (replied == true && mounted) {
      HapticService.instance.lightImpact();
      _toast('回复成功');
      await _load(reset: true);
    }
  }

  Widget _aiButton(ZybColors colors, BoxConstraints constraints) {
    final position =
        _aiOffset ??
        Offset(constraints.maxWidth - 54, constraints.maxHeight * .38);
    final left = position.dx.clamp(8.0, constraints.maxWidth - 46);
    final top = position.dy.clamp(8.0, constraints.maxHeight - 46);
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (details) =>
            setState(() => _aiOffset = Offset(left, top) + details.delta),
        onLongPress: _configureDeepSeek,
        child: ValueListenableBuilder<bool>(
          valueListenable: _scrolling,
          child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _runAi,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow,
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _aiBusy
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'AI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
          builder: (context, scrolling, child) => AnimatedScale(
            scale: scrolling ? .82 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: scrolling ? .38 : .78,
              duration: const Duration(milliseconds: 180),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showComposer({ThreadFloor? floor, bool comment = false}) async {
    final colors = zybColors(context);
    final controller = TextEditingController();
    final composerImages = <String>[];
    final isQuoteReply = !comment && floor != null && !floor.first;
    var isSubmitting = false;
    bool? submitted;
    try {
      submitted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => StatefulBuilder(
          builder: (sheetCtx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: comment
                                      ? '点评 '
                                      : (floor == null || floor.first
                                          ? '回复帖子'
                                          : '回复 '),
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (floor != null && !floor.first)
                                  TextSpan(
                                    text: floor.author,
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                if (floor != null && floor.first && comment)
                                  TextSpan(
                                    text: '楼主',
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            HapticService.instance.lightImpact();
                            const reportMentions =
                                '@赚小客 @社区管理员 @公共秩序员 @值班编辑 @恩迪凡德 @超管 @古尘 ';
                            final cur = controller.text;
                            final next = cur.isEmpty
                                ? reportMentions
                                : (cur.endsWith(' ')
                                    ? '$cur$reportMentions'
                                    : '$cur $reportMentions');
                            controller.value = TextEditingValue(
                              text: next,
                              selection: TextSelection.collapsed(
                                offset: next.length,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceSoft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '一键举报',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Material(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: isSubmitting
                                ? null
                                : () async {
                                    var message = controller.text.trim();
                                    if (message.isEmpty) {
                                      if (composerImages.isNotEmpty) {
                                        message = '分享图片';
                                      } else {
                                        HapticService.instance.errorImpact();
                                        showZybFeedback(
                                          sheetCtx,
                                          '请输入内容',
                                          error: true,
                                        );
                                        return;
                                      }
                                    }
                                    if ([...message.runes]
                                        .any((code) => code > 0xFFFF)) {
                                      HapticService.instance.errorImpact();
                                      showZybFeedback(
                                        sheetCtx,
                                        '暂不支持手机 Emoji',
                                        error: true,
                                      );
                                      return;
                                    }

                                    setSheetState(() => isSubmitting = true);
                                    try {
                                      if (comment && floor != null) {
                                        await _api.commentFloor(
                                          tid: widget.tid,
                                          pid: floor.pid,
                                          message: message,
                                        );
                                      } else if (isQuoteReply) {
                                        await _api.replyThread(
                                          tid: widget.tid,
                                          message: message,
                                          repquote: floor.pid,
                                          repAuthor: floor.author,
                                          repDateline: floor.dateline,
                                          repMessage: floor.messageHtml,
                                          imagePaths: composerImages,
                                        );
                                      } else {
                                        await _api.replyThread(
                                          tid: widget.tid,
                                          message: message,
                                          imagePaths: composerImages,
                                        );
                                      }
                                      if (sheetCtx.mounted) {
                                        Navigator.pop(sheetCtx, true);
                                      }
                                    } on OfficialApiException catch (error) {
                                      if (!sheetCtx.mounted) return;
                                      setSheetState(() => isSubmitting = false);
                                      HapticService.instance.errorImpact();
                                      if (error.loginRequired) {
                                        Navigator.pop(sheetCtx, false);
                                        _loginAndRetry();
                                        return;
                                      }
                                      showZybFeedback(
                                        sheetCtx,
                                        error.message,
                                        error: true,
                                      );
                                    } catch (_) {
                                      if (!sheetCtx.mounted) return;
                                      setSheetState(() => isSubmitting = false);
                                      HapticService.instance.errorImpact();
                                      showZybFeedback(
                                        sheetCtx,
                                        '发送失败，请稍后重试',
                                        error: true,
                                      );
                                    }
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 6,
                              ),
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      '发送',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: 3,
                      maxLines: 6,
                      style: TextStyle(color: colors.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: '请输入内容',
                        hintStyle: TextStyle(color: colors.textMuted),
                        filled: true,
                        fillColor: colors.surfaceSoft,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    if (composerImages.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 68,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: composerImages.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, idx) {
                            final imgPath = composerImages[idx];
                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(imgPath),
                                    width: 68,
                                    height: 68,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 68,
                                      height: 68,
                                      color: colors.surfaceSoft,
                                      child: Icon(
                                        Icons.broken_image,
                                        size: 24,
                                        color: colors.textMuted,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      HapticService.instance.lightImpact();
                                      setSheetState(() {
                                        composerImages.removeAt(idx);
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                    if (!comment) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: composerImages.length >= 9
                                ? () {
                                    HapticService.instance.selection();
                                    showZybFeedback(
                                      sheetCtx,
                                      '最多添加 9 张图片',
                                      error: true,
                                    );
                                  }
                                : () async {
                                    HapticService.instance.lightImpact();
                                    try {
                                      final picked =
                                          await PlatformService.pickImages();
                                      if (picked.isEmpty) return;
                                      setSheetState(() {
                                        for (final p in picked) {
                                          if (composerImages.length < 9 &&
                                              !composerImages.contains(p)) {
                                            composerImages.add(p);
                                          }
                                        }
                                      });
                                    } catch (_) {
                                      if (sheetCtx.mounted) {
                                        showZybFeedback(
                                          sheetCtx,
                                          '读取图片失败',
                                          error: true,
                                        );
                                      }
                                    }
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceSoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 18,
                                    color: composerImages.length >= 9
                                        ? colors.textMuted
                                        : colors.primary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    composerImages.isEmpty
                                        ? '添加图片'
                                        : '添加图片 (${composerImages.length}/9)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: composerImages.length >= 9
                                          ? colors.textMuted
                                          : colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (composerImages.isNotEmpty)
                            Text(
                              '已选 ${composerImages.length}/9 张',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
    if (submitted == true) {
      HapticService.instance.lightImpact();
      _toast(comment ? '点评成功' : '回复成功');
      await _load(reset: true);
    }
  }

  Future<void> _showRating(ThreadFloor floor) async {
    try {
      final range = await _api.fetchRatingRange(
        tid: widget.tid,
        pid: floor.pid,
      );
      if (!mounted) return;
      final controller = TextEditingController(text: '1');
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      final colors = zybColors(context);
      bool? submitted;
      try {
        submitted = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
        builder: (ctx) {
          var isSubmitting = false;
          return StatefulBuilder(
            builder: (ctx, setSheetState) => Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: '评分 ',
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                children: [
                                  TextSpan(
                                    text: floor.first ? '楼主' : floor.author,
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: isSubmitting
                                ? null
                                : () async {
                                    HapticService.instance.lightImpact();
                                    setSheetState(() => isSubmitting = true);
                                    try {
                                      await _api.rateFloor(
                                        tid: widget.tid,
                                        pid: floor.pid,
                                        score: 1,
                                      );
                                      if (ctx.mounted) Navigator.pop(ctx, true);
                                    } on OfficialApiException catch (error) {
                                      if (ctx.mounted) {
                                        setSheetState(() => isSubmitting = false);
                                        HapticService.instance.errorImpact();
                                        showZybFeedback(ctx, error.message, error: true);
                                      }
                                    } catch (_) {
                                      if (ctx.mounted) {
                                        setSheetState(() => isSubmitting = false);
                                        HapticService.instance.errorImpact();
                                        showZybFeedback(ctx, '评分失败，请稍后重试', error: true);
                                      }
                                    }
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceSoft,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    size: 14,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '+1果',
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Material(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: isSubmitting
                                  ? null
                                  : () async {
                                      final score =
                                          int.tryParse(controller.text.trim());
                                      if (score == null ||
                                          score < range.minimum ||
                                          score > range.maximum) {
                                        HapticService.instance.errorImpact();
                                        showZybFeedback(
                                          ctx,
                                          '请输入 ${range.minimum}-${range.maximum} 之间的数字',
                                          error: true,
                                        );
                                        return;
                                      }
                                      HapticService.instance.lightImpact();
                                      setSheetState(() => isSubmitting = true);
                                      try {
                                        await _api.rateFloor(
                                          tid: widget.tid,
                                          pid: floor.pid,
                                          score: score,
                                        );
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx, true);
                                        }
                                      } on OfficialApiException catch (error) {
                                        if (ctx.mounted) {
                                          setSheetState(
                                              () => isSubmitting = false);
                                          HapticService.instance.errorImpact();
                                          showZybFeedback(ctx, error.message,
                                              error: true);
                                        }
                                      } catch (_) {
                                        if (ctx.mounted) {
                                          setSheetState(
                                              () => isSubmitting = false);
                                          HapticService.instance.errorImpact();
                                          showZybFeedback(ctx, '评分失败，请稍后重试',
                                              error: true);
                                        }
                                      }
                                    },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 6,
                                ),
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        '发送',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '今日剩余 ${range.remaining} 次  可加 ${range.minimum}-${range.maximum}',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: TextStyle(color: colors.textPrimary),
                        decoration: InputDecoration(
                          hintText: '请输入果果数量',
                          hintStyle: TextStyle(color: colors.textMuted),
                          filled: true,
                          fillColor: colors.surfaceSoft,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        );
      } finally {
        controller.dispose();
      }
      if (submitted == true) {
        HapticService.instance.lightImpact();
        _toast('评分成功');
        await _load(reset: true);
      }
    } on OfficialApiException catch (error) {
      if (mounted) _handleApiError(error);
    }
  }

  Future<void> _reportFloor(ThreadFloor floor) async {
    HapticService.instance.lightImpact();
    try {
      await _api.reportFloor(
        tid: widget.tid,
        pid: floor.pid,
      );
      if (!mounted) return;
      showZybFeedback(context, '举报已提交，待管理处理！');
    } on OfficialApiException catch (error) {
      if (!mounted) return;
      if (error.loginRequired) {
        _loginAndRetry();
        return;
      }
      HapticService.instance.errorImpact();
      showZybFeedback(context, error.message, error: true);
    } catch (_) {
      if (!mounted) return;
      HapticService.instance.errorImpact();
      showZybFeedback(context, '举报提交失败，请稍后重试', error: true);
    }
  }

  Future<void> _jumpToQuotedFloor(String author, String? dateline) async {
    HapticService.instance.lightImpact();
    ThreadFloor? target;
    // 优先：同时匹配作者和发帖时间
    if (dateline != null && dateline.trim().isNotEmpty) {
      final cleanDate = dateline.replaceAll(RegExp(r'\s+'), ' ').trim();
      for (final f in _floors) {
        if (f.author == author) {
          final fDate = f.dateline.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (fDate.contains(cleanDate) || cleanDate.contains(fDate)) {
            target = f;
            break;
          }
        }
      }
    }
    // 次优：匹配作者名
    if (target == null) {
      for (final f in _floors) {
        if (f.author == author) {
          target = f;
          break;
        }
      }
    }
    // 检查是否楼主
    if (target == null && (_detail?.author == author)) {
      target = _floors.where((f) => f.first).firstOrNull ?? _floors.firstOrNull;
    }

    if (target == null) {
      showZybFeedback(context, '原发言在其他页面或暂未加载');
      return;
    }

    String targetPid = target.pid;

    // 单次物理阻尼平滑滑行直达（绝无二次顿挫抽动）
    if (target.first) {
      targetPid = target.pid.isNotEmpty ? target.pid : 'first_post';
      await _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.fastOutSlowIn,
      );
    } else {
      final replyFloors = _floors
          .where((f) => !f.first && !_blockedUids.contains(f.authorId))
          .toList();
      final orderedFloors =
          _sortDesc ? replyFloors.reversed.toList() : replyFloors;
      final index = orderedFloors.indexOf(target);

      if (index >= 0) {
        final targetKey =
            _floorItemKeys.putIfAbsent(target.pid, () => GlobalKey());

        // 如果该卡片不在当前渲染树中（超远距离），暂时拉大预渲染区域，触发 Flutter 在下一帧内完成布局挂载
        if (targetKey.currentContext == null) {
          if (mounted) {
            setState(() => _cacheExtent = 35000.0);
            await WidgetsBinding.instance.endOfFrame.timeout(
              const Duration(milliseconds: 50),
              onTimeout: () {},
            );
          }
        }

        // 基于目标卡片在滚动视口内的实际物理坐标计算精确到达偏移（带触底防遮挡保护与黄金区对齐）
        double? targetOffset = _computeAccurateScrollOffset(targetKey);

        if (targetOffset != null) {
          await _scrollController.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 450),
            curve: Curves.fastOutSlowIn,
          );
        } else {
          // 兜底动态估算：使用真实测量的主楼高度与各楼层平均测量高度，绝不使用 155px 死公式
          final fallbackOffset = _estimateScrollOffset(index);
          await _scrollController.animateTo(
            fallbackOffset,
            duration: const Duration(milliseconds: 450),
            curve: Curves.fastOutSlowIn,
          );
        }

        // 滑行结束后若 cacheExtent 曾被临时放大，恢复为默认的 3500.0 以降低日常内存占用
        if (mounted && _cacheExtent != 3500.0) {
          setState(() => _cacheExtent = 3500.0);
        }
      }
    }

    // 滑动到位后触发左侧 3px 橙色微光条：停留 0.5s，随后 0.3s 平滑渐隐淡出
    if (mounted) {
      setState(() => _highlightedPid = targetPid);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _highlightedPid == targetPid) {
          setState(() => _highlightedPid = null);
        }
      });
    }
  }

  /// 方案 2.1 核心：基于 Flutter 真实渲染几何体系计算精确像素级滑行偏移
  /// 包含触底保护与黄金阅读区（12%）对齐，确保目标楼层顶部与底部按钮均完整呈现，绝不切半
  double? _computeAccurateScrollOffset(GlobalKey targetKey,
      {double topFraction = 0.12}) {
    final targetContext = targetKey.currentContext;
    if (targetContext == null) return null;
    final targetBox = targetContext.findRenderObject() as RenderBox?;
    if (targetBox == null || !targetBox.hasSize) return null;

    final scrollableState = Scrollable.maybeOf(targetContext);
    if (scrollableState == null) return null;
    final scrollBox = scrollableState.context.findRenderObject() as RenderBox?;
    if (scrollBox == null || !scrollBox.hasSize) return null;

    // 目标卡片当前相对于滚动视口顶部的物理距离
    final targetOffsetInViewport =
        targetBox.localToGlobal(Offset.zero, ancestor: scrollBox).dy;
    final viewportHeight = scrollBox.size.height;
    final cardHeight = targetBox.size.height;

    // 黄金阅读区理想距顶高度（约占屏幕 12%，限制在 50~100px 舒适区间）
    final idealTop = (viewportHeight * topFraction).clamp(50.0, 100.0);

    // 触底与溢出保护：为卡片底部留出至少 24px 安全缓冲，确保回复、评分按钮 100% 完整可见
    const bottomSafetyMargin = 24.0;
    final maxCardTop = viewportHeight - bottomSafetyMargin - cardHeight;

    double chosenTop;
    if (cardHeight + idealTop + bottomSafetyMargin <= viewportHeight) {
      // 普通高度卡片：完美停在偏上 12% 黄金阅读区
      chosenTop = idealTop;
    } else if (maxCardTop >= 12.0) {
      // 稍长卡片：自适应适度上移，确保底部操作按钮完整露在视口内，绝不切半
      chosenTop = maxCardTop;
    } else {
      // 超长卡片（比整个屏幕还高）：从视口顶部 12px 起步，保证从卡片第一行读起，绝不截断头部
      chosenTop = 12.0;
    }

    final currentOffset = _scrollController.offset;
    final desiredOffset = currentOffset + (targetOffsetInViewport - chosenTop);
    final maxScroll = _scrollController.position.maxScrollExtent;

    return desiredOffset.clamp(0.0, maxScroll);
  }

  /// 动态估算：聚合当前页面已挂载卡片的实际物理测量高度，彻底弃用 155px 死公式
  double _estimateScrollOffset(int index) {
    double totalKnownHeight = 0;
    int knownCount = 0;
    for (final entry in _floorItemKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize && box.size.height > 20) {
          totalKnownHeight += box.size.height;
          knownCount++;
        }
      }
    }
    final avgFloorHeight =
        knownCount > 0 ? (totalKnownHeight / knownCount) : 180.0;

    final mainBox =
        _mainArticleKey.currentContext?.findRenderObject() as RenderBox?;
    final mainHeight =
        (mainBox != null && mainBox.hasSize) ? mainBox.size.height : 420.0;

    final estimated = mainHeight + 44.0 + index * avgFloorHeight;
    return estimated.clamp(0.0, _scrollController.position.maxScrollExtent);
  }

  void _openPrivateMessage(ThreadFloor floor) {
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => PrivateChatPage(
          userId: floor.authorId,
          userName: floor.author,
          avatar: floor.avatar,
        ),
      ),
    );
  }

  void _openUserProfile(ThreadFloor floor) {
    final uid = floor.authorId.trim();
    if (uid.isEmpty) {
      _toast('未获取到该用户的主页信息');
      return;
    }
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => OtherUserProfilePage(
          userId: uid,
          userName: floor.author,
          avatar: floor.avatar,
        ),
      ),
    );
  }

  void _handleApiError(OfficialApiException error) {
    if (error.loginRequired) {
      _loginAndRetry();
    } else {
      _toast(error.message);
    }
  }

  void _toast(String message) {
    final isError =
        message.contains('失败') ||
        message.contains('错误') ||
        message.contains('请输入') ||
        message.contains('敏感词') ||
        message.contains('修改');
    if (isError) {
      HapticService.instance.errorImpact();
    }
    showZybFeedback(
      context,
      message,
      error: isError,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return PopScope(
      canPop: _isPopping,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _popWithResult();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          flexibleSpace: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: _scrollToTop,
          ),
          leadingWidth: 46,
          leading: Center(
            child: Material(
              color: colors.surfaceSoft,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _popWithResult,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.arrow_back_rounded,
                    color: colors.textSecondary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: _scrollToTop,
            child: AnimatedOpacity(
              opacity: _showAppbarTitle ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Text(
                _detail?.subject ?? widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          centerTitle: true,
          actions: [
            Center(
              child: Container(
                height: 32,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.divider.withValues(alpha: .6),
                    width: .6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AppBarActionIcon(
                      tooltip: '复制内容',
                      icon: Icons.copy_rounded,
                      size: 17,
                      colors: colors,
                      onTap: _copyThread,
                    ),
                    Container(
                      width: 0.6,
                      height: 12,
                      color: colors.divider.withValues(alpha: .7),
                    ),
                    _AppBarActionIcon(
                      tooltip: '网页版打开',
                      icon: Icons.open_in_browser_rounded,
                      size: 18,
                      colors: colors,
                      onTap: () => _openWeb(),
                    ),
                    Container(
                      width: 0.6,
                      height: 12,
                      color: colors.divider.withValues(alpha: .7),
                    ),
                    _AppBarActionIcon(
                      tooltip: '电脑版打开',
                      icon: Icons.desktop_windows_outlined,
                      size: 17,
                      colors: colors,
                      onTap: () => _openWeb(desktop: true),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      floatingActionButton: _showBackToTop
          ? Material(
              color: colors.surface,
              elevation: 4,
              shadowColor: Colors.black26,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _scrollToTop,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.cardBorder,
                      width: 0.8,
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 20,
                    color: colors.primary,
                  ),
                ),
              ),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(child: _buildBody(colors)),
            if (_detail != null && _aiEnabled) _aiButton(colors, constraints),
          ],
        ),
      ),
      bottomNavigationBar: _detail == null
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                decoration: BoxDecoration(
                  color: colors.navBackground,
                  border: Border(top: BorderSide(color: colors.divider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _showComposer,
                        child: Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          decoration: BoxDecoration(
                            color: colors.surfaceSoft,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: colors.cardBorder.withValues(alpha: 0.5),
                              width: 0.6,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                size: 17,
                                color: colors.textMuted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '说点什么…',
                                style: TextStyle(
                                  color: colors.textMuted,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: _isFavorited ? colors.primarySoft : colors.surfaceSoft,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _toggleFavorite,
                        child: Container(
                          height: 40,
                          width: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _isFavorited
                                  ? colors.primary.withValues(alpha: 0.35)
                                  : colors.cardBorder.withValues(alpha: 0.5),
                              width: 0.6,
                            ),
                          ),
                          child: Icon(
                            _isFavorited
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 22,
                            color: _isFavorited
                                ? colors.primary
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildBody(ZybColors colors) {
    if (_loading && _detail == null) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_error != null && _detail == null) {
      final error = _error;
      final loginRequired =
          error is OfficialApiException && error.loginRequired;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: loginRequired
                        ? [
                            colors.primary.withValues(alpha: 0.14),
                            colors.primary.withValues(alpha: 0.05),
                          ]
                        : [
                            colors.surface,
                            colors.surfaceSoft,
                          ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: loginRequired
                        ? colors.primary.withValues(alpha: 0.25)
                        : colors.cardBorder,
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Icon(
                  loginRequired ? Icons.lock_outline_rounded : Icons.cloud_off_rounded,
                  size: 36,
                  color: loginRequired ? colors.primary : colors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                loginRequired ? '需要登录账号' : '加载失败',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                loginRequired
                    ? '该帖子需验证登录状态，登录后将自动返回'
                    : error.toString().replaceFirst('Exception: ', ''),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Material(
                color: colors.primary,
                borderRadius: BorderRadius.circular(22),
                elevation: 0,
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () {
                    HapticService.instance.lightImpact();
                    if (loginRequired) {
                      _loginAndRetry();
                    } else {
                      _load(reset: true);
                    }
                  },
                  child: Container(
                    height: 44,
                    constraints: const BoxConstraints(minWidth: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          loginRequired ? Icons.login_rounded : Icons.refresh_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          loginRequired ? '立即登录' : '重新加载',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!loginRequired) ...[
                const SizedBox(height: 12),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textMuted,
                    minimumSize: const Size(60, 36),
                  ),
                  onPressed: _openWeb,
                  child: const Text(
                    '暂用网页版打开',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final detail = _detail!;
    // 评论楼层（排除楼主1楼），按 _sortDesc 决定顺序
    final replyFloors = _floors
        .where(
          (floor) => !floor.first && !_blockedUids.contains(floor.authorId),
        )
        .toList();
    final orderedFloors = _sortDesc
        ? replyFloors.reversed.toList()
        : replyFloors;
    final firstFloor = _floors
        .where((floor) => floor.first && !_blockedUids.contains(floor.authorId))
        .firstOrNull;

    return RefreshIndicator(
      color: colors.primary,
      onRefresh: () async {
        HapticService.instance.lightImpact();
        await _load(reset: true);
        if (mounted) {
          showZybFeedback(context, '刷新成功');
        }
      },
      child: ListView.builder(
        controller: _scrollController,
        cacheExtent: _cacheExtent,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: 2 + orderedFloors.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _MainArticleCard(
              key: _mainArticleKey,
              detail: detail,
              firstFloor: firstFloor,
              authorGroupTitle: _authorGroupTitle,
              authorRegDate: _authorRegDate,
              highlighted: _highlightedPid != null &&
                  ((firstFloor != null && firstFloor.pid == _highlightedPid) ||
                      detail.authorId == _highlightedPid ||
                      _highlightedPid == 'first_post'),
              onReply: () => _showComposer(floor: firstFloor),
              onRate: firstFloor != null
                  ? () => _showRating(firstFloor)
                  : () {},
              onMessage: firstFloor != null
                  ? () => _openPrivateMessage(firstFloor)
                  : () {},
              onOpenProfile: firstFloor != null
                  ? () => _openUserProfile(firstFloor)
                  : () {},
              onReport: firstFloor != null
                  ? () => _reportFloor(firstFloor)
                  : () {},
              onQuoteTap: _jumpToQuotedFloor,
              blockedUids: _blockedUids,
            );
          }
          if (index == 1) {
            return _CommentSectionHeader(
              key: _commentHeaderKey,
              colors: colors,
              count: replyFloors.length,
              desc: _sortDesc,
              onlyAuthor: _onlyAuthor,
              onToggle: () {
                HapticService.instance.lightImpact();
                setState(() => _sortDesc = !_sortDesc);
              },
              onToggleOnlyAuthor: _toggleOnlyAuthor,
            );
          }
          if (index == orderedFloors.length + 2) {
            return _LoadMoreFooter(
              loading: _loadingMore,
              hasMore: _page < _totalPage,
              onLoadMore: _loadNextPage,
            );
          }
          final floor = orderedFloors[index - 2];
          final originalPos = _floors.indexOf(floor);
          final floorNumber = originalPos >= 0 ? (originalPos + 1) : index;
          return _FloorCard(
            key: _floorItemKeys.putIfAbsent(floor.pid, () => GlobalKey()),
            floor: floor,
            floorNumber: floorNumber,
            highlighted: _highlightedPid == floor.pid,
            threadAuthorId: detail.authorId,
            onReply: () => _showComposer(floor: floor),
            onRate: () => _showRating(floor),
            onMessage: () => _openPrivateMessage(floor),
            onOpenProfile: () => _openUserProfile(floor),
            onReport: () => _reportFloor(floor),
            onQuoteTap: _jumpToQuotedFloor,
            blockedUids: _blockedUids,
          );
        },
      ),
    );
  }
}

class _AppBarActionIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final double size;
  final ZybColors colors;
  final VoidCallback onTap;

  const _AppBarActionIcon({
    required this.tooltip,
    required this.icon,
    required this.size,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 32,
          child: Center(
            child: Icon(
              icon,
              size: size,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentSectionHeader extends StatelessWidget {
  final ZybColors colors;
  final int count;
  final bool desc;
  final bool onlyAuthor;
  final VoidCallback onToggle;
  final VoidCallback onToggleOnlyAuthor;

  const _CommentSectionHeader({
    super.key,
    required this.colors,
    required this.count,
    required this.desc,
    required this.onlyAuthor,
    required this.onToggle,
    required this.onToggleOnlyAuthor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.cardBorder,
          width: 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            '评论',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
          ],
          const Spacer(),
          // 只看楼主
          Material(
            color: onlyAuthor ? colors.primarySoft : colors.surfaceSoft,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: onToggleOnlyAuthor,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: onlyAuthor
                        ? colors.primary.withValues(alpha: 0.35)
                        : colors.cardBorder.withValues(alpha: 0.5),
                    width: 0.6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      onlyAuthor ? Icons.person_rounded : Icons.person_outline_rounded,
                      size: 13,
                      color: onlyAuthor ? colors.primary : colors.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '只看楼主',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: onlyAuthor ? FontWeight.w700 : FontWeight.w500,
                        color: onlyAuthor ? colors.primary : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 默认排序 / 倒序
          Material(
            color: desc ? colors.primarySoft : colors.surfaceSoft,
            borderRadius: BorderRadius.circular(4),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: onToggle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: desc
                        ? colors.primary.withValues(alpha: 0.35)
                        : colors.cardBorder.withValues(alpha: 0.5),
                    width: 0.6,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      desc
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 13,
                      color: desc ? colors.primary : colors.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      desc ? '倒序' : '默认排序',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: desc ? FontWeight.w700 : FontWeight.w500,
                        color: desc ? colors.primary : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MainArticleCard extends StatelessWidget {
  final ThreadDetail detail;
  final ThreadFloor? firstFloor;
  final String? authorGroupTitle;
  final String? authorRegDate;
  final VoidCallback onReply;
  final VoidCallback onRate;
  final VoidCallback onMessage;
  final VoidCallback onOpenProfile;
  final VoidCallback onReport;
  final void Function(String author, String? dateline)? onQuoteTap;
  final Set<String> blockedUids;
  final bool highlighted;

  const _MainArticleCard({
    super.key,
    required this.detail,
    required this.firstFloor,
    this.authorGroupTitle,
    this.authorRegDate,
    required this.onReply,
    required this.onRate,
    required this.onMessage,
    required this.onOpenProfile,
    required this.onReport,
    this.onQuoteTap,
    required this.blockedUids,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final floor = firstFloor;
    final groupTitle = (authorGroupTitle?.trim().isNotEmpty == true
            ? authorGroupTitle!.trim()
            : (floor?.groupTitle.isNotEmpty == true ? floor!.groupTitle : ''))
        .trim();
    final regDate = authorRegDate?.trim() ?? '';
    final dateText = _formatForumTime(
      floor != null && floor.dateline.isNotEmpty ? floor.dateline : detail.dateline,
    );
    final visibleComments = floor != null
        ? floor.comments
            .where((comment) => !blockedUids.contains(comment.authorId))
            .toList()
        : const <ThreadComment>[];

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder, width: 0.6),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: highlighted
                      ? colors.primary.withValues(alpha: 0.16)
                      : colors.shadow,
                  blurRadius: highlighted ? 12 : 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: highlighted
                      ? colors.primary.withValues(alpha: 0.16)
                      : Colors.black.withValues(alpha: 0.02),
                  blurRadius: highlighted ? 12 : 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13.4),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 14, 15, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          // 1. 帖子主标题
          Text(
            detail.subject,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18.5,
              height: 1.34,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          // 2. 浏览数与回复数统计
          Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 14,
                color: colors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                '${detail.views}',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
              const SizedBox(width: 14),
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 14,
                color: colors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                '${detail.replies}',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
              if (dateText.isNotEmpty) ...[
                const Spacer(),
                Text(
                  dateText,
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
            ],
          ),
          Divider(
            height: 20,
            thickness: 0.6,
            color: colors.divider.withValues(alpha: 0.6),
          ),
          // 3. 楼主作者栏
          Row(
            children: [
              GestureDetector(
                onTap: onOpenProfile,
                child: ZybAvatar(
                  url: floor?.avatar ?? detail.avatar,
                  uid: floor?.authorId ?? detail.authorId,
                  name: floor?.author ?? detail.author,
                  size: 38,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: onOpenProfile,
                            child: Text(
                              floor?.author ?? detail.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 14.5,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '楼主',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (groupTitle.isNotEmpty || regDate.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (groupTitle.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primarySoft,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: colors.primary.withValues(alpha: 0.25),
                                  width: 0.6,
                                ),
                              ),
                              child: Text(
                                groupTitle,
                                style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          if (groupTitle.isNotEmpty && regDate.isNotEmpty)
                            const SizedBox(width: 6),
                          if (regDate.isNotEmpty)
                            Text(
                              regDate,
                              style: TextStyle(
                                color: colors.textMuted,
                                fontSize: 11.5,
                                height: 1.15,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (floor != null) ...[
            const SizedBox(height: 10),
            // 4. 正文富文本
            NativeHtmlContent(
              html: floor.messageHtml,
              fontSize: 15.5,
              galleryImages: floor.attachments,
              onQuoteTap: onQuoteTap,
            ),
            for (final attachment in floor.attachments)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: InkWell(
                  onTap: () {
                    final gallery = <String>{
                      ...imageUrlsFromHtml(floor.messageHtml),
                      ...floor.attachments,
                    }.toList();
                    openImageViewer(
                      context,
                      gallery,
                      initialIndex: gallery.indexOf(attachment),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: attachment,
                      httpHeaders: const {
                        'Referer': baseUrl,
                        'User-Agent': mobileUserAgent,
                      },
                      fit: BoxFit.contain,
                      memCacheWidth: 1080,
                      placeholder: (_, _) => const SizedBox(
                        height: 120,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            _FloorRatingBadge(floor: floor, tid: detail.tid),
            if (visibleComments.isNotEmpty) ...[
              const SizedBox(height: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: colors.surfaceSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < visibleComments.length; i++) ...[
                      _buildCommentLine(
                        visibleComments[i],
                        detail.authorId,
                        colors,
                      ),
                      if (i != visibleComments.length - 1)
                        const SizedBox(height: 3),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            Divider(height: 1, color: colors.divider),
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  _FloorAction(
                    icon: Icons.outlined_flag_rounded,
                    label: '举报',
                    onTap: onReport,
                  ),
                  _actionDivider(colors),
                  _FloorAction(
                    icon: Icons.mail_outline_rounded,
                    label: '私信',
                    onTap: onMessage,
                  ),
                  _actionDivider(colors),
                  _FloorAction(
                    icon: Icons.reply_rounded,
                    label: '回复',
                    onTap: onReply,
                  ),
                  _actionDivider(colors),
                  _FloorAction(
                    icon: Icons.workspace_premium_outlined,
                    label: floor.totalRate == 0
                        ? '评分'
                        : '评分 ${floor.totalRate}',
                    onTap: onRate,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
    Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 3.5,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        opacity: highlighted ? 1.0 : 0.0,
        child: Container(
          color: colors.primary,
        ),
      ),
    ),
  ],
),
),
);
  }

  Widget _buildCommentLine(
    ThreadComment comment,
    String threadAuthorId,
    ZybColors colors,
  ) {
    final isThreadAuthor =
        threadAuthorId.isNotEmpty && comment.authorId == threadAuthorId;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Text(
              comment.author,
              style: TextStyle(
                color: colors.primary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isThreadAuthor) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                margin: const EdgeInsets.only(left: 4, right: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 0.5,
                ),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '楼主',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const TextSpan(text: '：'),
          ],
          TextSpan(
            text: comment.message,
            style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
      style: const TextStyle(height: 1.35),
    );
  }
}

class _FloorCard extends StatelessWidget {
  final ThreadFloor floor;
  final int floorNumber;
  final String threadAuthorId;
  final VoidCallback onReply;
  final VoidCallback onRate;
  final VoidCallback onMessage;
  final VoidCallback onOpenProfile;
  final VoidCallback onReport;
  final void Function(String author, String? dateline)? onQuoteTap;
  final Set<String> blockedUids;
  final bool highlighted;

  const _FloorCard({
    super.key,
    required this.floor,
    required this.floorNumber,
    required this.threadAuthorId,
    required this.onReply,
    required this.onRate,
    required this.onMessage,
    required this.onOpenProfile,
    required this.onReport,
    this.onQuoteTap,
    required this.blockedUids,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateText = _formatForumTime(floor.dateline);
    final visibleComments = floor.comments
        .where((comment) => !blockedUids.contains(comment.authorId))
        .toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.cardBorder, width: 0.6),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: highlighted
                      ? colors.primary.withValues(alpha: 0.16)
                      : colors.shadow,
                  blurRadius: highlighted ? 12 : 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: highlighted
                      ? colors.primary.withValues(alpha: 0.16)
                      : Colors.black.withValues(alpha: 0.02),
                  blurRadius: highlighted ? 12 : 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11.4),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          Row(
            children: [
              GestureDetector(
                onTap: onOpenProfile,
                child: ZybAvatar(
                  url: floor.avatar,
                  uid: floor.authorId,
                  name: floor.author,
                  size: 34,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: onOpenProfile,
                            child: Text(
                              floor.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 14.5,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        if ((floor.authorId.isNotEmpty &&
                                floor.authorId == threadAuthorId) ||
                            floor.first) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '楼主',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        if (floor.groupTitle.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primarySoft,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: colors.primary.withValues(alpha: 0.25),
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              floor.groupTitle,
                              style: TextStyle(
                                color: colors.primary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (dateText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        dateText,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 11,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '$floorNumber楼',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 7),
          NativeHtmlContent(
            html: floor.messageHtml,
            fontSize: 15.5,
            galleryImages: floor.attachments,
            onQuoteTap: onQuoteTap,
          ),
          for (final attachment in floor.attachments)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                onTap: () {
                  final gallery = <String>{
                    ...imageUrlsFromHtml(floor.messageHtml),
                    ...floor.attachments,
                  }.toList();
                  openImageViewer(
                    context,
                    gallery,
                    initialIndex: gallery.indexOf(attachment),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: attachment,
                    httpHeaders: const {
                      'Referer': baseUrl,
                      'User-Agent': mobileUserAgent,
                    },
                    fit: BoxFit.contain,
                    memCacheWidth: 1080,
                    placeholder: (_, _) => const SizedBox(
                      height: 120,
                      child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ),
                    ),
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          _FloorRatingBadge(floor: floor, tid: floor.tid),
          if (visibleComments.isNotEmpty) ...[
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: colors.surfaceSoft,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < visibleComments.length; i++) ...[
                    _buildCommentLine(visibleComments[i], colors),
                    if (i != visibleComments.length - 1)
                      const SizedBox(height: 3),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Divider(height: 1, color: colors.divider),
          SizedBox(
            height: 30,
            child: Row(
              children: [
                _FloorAction(
                  icon: Icons.outlined_flag_rounded,
                  label: '举报',
                  onTap: onReport,
                ),
                _actionDivider(colors),
                _FloorAction(
                  icon: Icons.mail_outline_rounded,
                  label: '私信',
                  onTap: onMessage,
                ),
                _actionDivider(colors),
                _FloorAction(
                  icon: Icons.reply_rounded,
                  label: '回复',
                  onTap: onReply,
                ),
                _actionDivider(colors),
                _FloorAction(
                  icon: Icons.workspace_premium_outlined,
                  label: floor.totalRate == 0 ? '评分' : '评分 ${floor.totalRate}',
                  onTap: onRate,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: 3.5,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        opacity: highlighted ? 1.0 : 0.0,
        child: Container(
          color: colors.primary,
        ),
      ),
    ),
  ],
),
),
);
  }

  Widget _buildCommentLine(ThreadComment comment, ZybColors colors) {
    final isThreadAuthor =
        threadAuthorId.isNotEmpty && comment.authorId == threadAuthorId;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Text(
              '${comment.author}',
              style: TextStyle(
                color: colors.primary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isThreadAuthor)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                margin: const EdgeInsets.only(left: 4, right: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 0.5,
                ),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '楼主',
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          const TextSpan(text: '：'),
          TextSpan(
            text: '${comment.message}',
            style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
      style: const TextStyle(height: 1.35),
    );
  }
}

Widget _actionDivider(ZybColors colors) => Container(
      width: 0.8,
      height: 12,
      color: colors.divider.withValues(alpha: 0.7),
    );

class _FloorAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FloorAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;

  const _LoadMoreFooter({
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return InkWell(
      onTap: loading || !hasMore ? null : onLoadMore,
      child: SizedBox(
        height: 48,
        child: Center(
          child: loading
              ? SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                )
              : Text(
                  hasMore ? '继续下滑或点击加载更多' : '已加载全部回复',
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
        ),
      ),
    );
  }
}

String _formatForumTime(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final timestamp = int.tryParse(value);
  if (timestamp == null || value.length < 10) return value;
  final milliseconds = value.length >= 13 ? timestamp : timestamp * 1000;
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}

class _FloorRatingBadge extends StatelessWidget {
  final ThreadFloor floor;
  final String tid;
  const _FloorRatingBadge({required this.floor, this.tid = ''});

  @override
  Widget build(BuildContext context) {
    if (floor.ratings.isEmpty) return const SizedBox.shrink();
    final colors = zybColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalCount = floor.ratings.length;
    final totalScore = floor.ratings.fold<int>(0, (sum, r) => sum + r.score);
    final displayScore = totalScore > 0 ? totalScore : floor.totalRate;
    final scoreText = displayScore > 0 ? '+$displayScore果' : '';
    final scoreLabel = scoreText.isNotEmpty ? '$scoreText · $totalCount人' : '$totalCount人';
    final effectiveTid = tid.isNotEmpty ? tid : floor.tid;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: colors.primarySoft,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              HapticService.instance.lightImpact();
              if (effectiveTid.isNotEmpty && floor.pid.isNotEmpty) {
                OfficialApiService.instance.fetchRatingDetails(
                  tid: effectiveTid,
                  pid: floor.pid,
                );
              }
              _showRatingDetailSheet(context, floor, effectiveTid);
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.18),
                  width: 0.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final r in floor.ratings.take(10))
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark ? colors.surface : Colors.white,
                                    width: 1,
                                  ),
                                ),
                                child: ClipOval(
                                  child: ZybAvatar(
                                    url: r.avatar,
                                    uid: r.userId,
                                    name: r.userName,
                                    size: 18,
                                    radius: 9,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    scoreLabel,
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showRatingDetailSheet(
  BuildContext context,
  ThreadFloor floor, [
  String tid = '',
]) {
  final effectiveTid = tid.isNotEmpty ? tid : floor.tid;
  final effectivePid = floor.pid;

  final colors = zybColors(context);
  final totalScore = floor.ratings.fold<int>(0, (sum, r) => sum + r.score);
  final displayScore = totalScore > 0 ? totalScore : floor.totalRate;

  final initialRecords = OfficialApiService.instance.getCachedRatingDetails(
    effectiveTid,
    effectivePid,
  );

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final records = OfficialApiService.instance.getCachedRatingDetails(
                effectiveTid,
                effectivePid,
              ) ??
              initialRecords;

          if (records == null &&
              effectiveTid.isNotEmpty &&
              effectivePid.isNotEmpty) {
            OfficialApiService.instance
                .fetchRatingDetails(tid: effectiveTid, pid: effectivePid)
                .then((loaded) {
              if (sheetCtx.mounted && loaded.isNotEmpty) {
                setSheetState(() {});
              }
            });
          }

          final recordMap = <String, String>{};
          if (records != null) {
            for (final rec in records) {
              if (rec.userName.isNotEmpty) {
                recordMap[rec.userName] = rec.time;
              }
              if (rec.userId.isNotEmpty) {
                recordMap['uid_${rec.userId}'] = rec.time;
              }
            }
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.65,
            ),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: Row(
                      children: [
                        Text(
                          '加果记录',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primarySoft,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${floor.ratings.length}人 · ${displayScore >= 0 ? '+' : ''}${displayScore}果',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: colors.textMuted,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          splashRadius: 18,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: colors.divider),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      itemCount: floor.ratings.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: colors.divider.withValues(alpha: 0.5),
                      ),
                      itemBuilder: (context, index) {
                        final r = floor.ratings[index];
                        final rawTime = recordMap[r.userName] ??
                            recordMap['uid_${r.userId}'] ??
                            r.dateline;
                        final ratingTime = formatRatingTime(rawTime);
                        return InkWell(
                          onTap: () {
                            if (r.userId.isNotEmpty && r.userId != '0') {
                              Navigator.push(
                                context,
                                zybHorizontalPageRoute<void>(
                                  builder: (_) => OtherUserProfilePage(
                                    userId: r.userId,
                                    userName: r.userName,
                                    avatar: r.avatar,
                                  ),
                                ),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Row(
                              children: [
                                ZybAvatar(
                                  url: r.avatar,
                                  uid: r.userId,
                                  name: r.userName,
                                  size: 34,
                                  radius: 17,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.userName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (ratingTime.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          ratingTime,
                                          style: TextStyle(
                                            color: colors.textMuted,
                                            fontSize: 11.5,
                                            height: 1.15,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.primarySoft,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${r.score >= 0 ? '+' : ''}${r.score} 果',
                                    style: TextStyle(
                                      color: colors.primary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
