import 'dart:io';
import 'package:flutter/material.dart';

import '../services/haptic_service.dart';
import '../services/official_api_service.dart';
import '../services/platform_service.dart';
import '../services/read_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/image_viewer.dart';
import '../widgets/zyb_confirm_dialog.dart';
import '../widgets/zyb_feedback.dart';
import 'login_page.dart';
import 'thread_detail_page.dart';
import 'webview_page.dart';

/// 可供发帖的官方专区配置
class PostingForum {
  final String fid;
  final String name;
  final Color color;
  final IconData icon;

  const PostingForum({
    required this.fid,
    required this.name,
    required this.color,
    required this.icon,
  });
}

const List<PostingForum> availablePostingForums = [
  PostingForum(
    fid: '15',
    name: '赚客大家谈',
    color: Color(0xFFFF5F15),
    icon: Icons.forum_rounded,
  ),
  PostingForum(
    fid: '25',
    name: '赚品交换',
    color: Color(0xFF9A4B78),
    icon: Icons.swap_horiz_rounded,
  ),
  PostingForum(
    fid: '31',
    name: '果果换物',
    color: Color(0xFF2072F3),
    icon: Icons.card_giftcard_rounded,
  ),
];

class NewThreadPage extends StatefulWidget {
  const NewThreadPage({super.key});

  @override
  State<NewThreadPage> createState() => _NewThreadPageState();
}

class _NewThreadPageState extends State<NewThreadPage> {
  final _api = OfficialApiService();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _subjectFocus = FocusNode();

  PostingForum _selectedForum = availablePostingForums[0];
  List<PostingThreadType> _threadTypes = [];
  String _selectedTypeId = '13'; // 大家谈默认：13 (大家谈谈)

  bool _loading = true;
  bool _loadingTypes = false;
  bool _publishing = false;
  bool _loginRequired = false;
  String _error = '';
  final List<String> _images = [];

  bool get _hasContent =>
      _subjectController.text.trim().isNotEmpty ||
      _messageController.text.trim().isNotEmpty ||
      _images.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _subjectFocus.dispose();
    super.dispose();
  }

  Future<void> _prepare({bool initial = true}) async {
    setState(() {
      if (initial) {
        _loading = true;
        _loginRequired = false;
      } else {
        _loadingTypes = true;
      }
      _error = '';
    });
    try {
      final preparation = await _api.prepareNewThread(_selectedForum.fid);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingTypes = false;
        _threadTypes = preparation.threadTypes;

        // 若当前选中的分类不在新板块列表中，自动对齐到新板块第一个分类
        final hasType = _threadTypes.any((type) => type.id == _selectedTypeId);
        if (!hasType && _threadTypes.isNotEmpty) {
          _selectedTypeId = _threadTypes.first.id;
        } else if (_threadTypes.isEmpty) {
          _selectedTypeId = '';
        }
      });
      if (initial && _error.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _subjectFocus.requestFocus(),
        );
      }
    } on OfficialApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingTypes = false;
        _loginRequired = error.loginRequired;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingTypes = false;
        _error = '发帖页面加载失败，请重试';
      });
    }
  }

  Future<void> _login() async {
    final success = await Navigator.push<bool>(
      context,
      zybHorizontalPageRoute<bool>(builder: (_) => const LoginPage()),
    );
    if (success == true) await _prepare();
  }

  void _openWebPost() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => WebViewPage(
          url: 'http://www.zuanke8.com/forum.php?mod=post&action=newthread&fid=${_selectedForum.fid}&mobile=2',
          title: '网页发帖 - ${_selectedForum.name}',
        ),
      ),
    );
  }

  Future<void> _publish() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (_loading || _error.isNotEmpty) return;
    if (subject.isEmpty) return _toast('请输入标题');
    if (message.isEmpty) return _toast('请输入正文');
    if ([...subject.runes, ...message.runes].any((code) => code > 0xFFFF)) {
      return _toast('暂不支持手机 Emoji');
    }
    if (_publishing) return;

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _publishing = true);
    try {
      final result = await _api.publishThread(
        fid: _selectedForum.fid,
        subject: subject,
        message: message,
        typeId: _selectedTypeId,
        imagePaths: _images,
      );
      if (!mounted) return;
      ReadHistoryService.instance.markRead(result.tid);
      HapticService.instance.lightImpact();
      showZybFeedback(context, '发布成功');
      Navigator.pushReplacement(
        context,
        zybHorizontalPageRoute<void>(
          builder: (_) => ThreadDetailPage(tid: result.tid, title: subject),
        ),
      );
    } on OfficialApiException catch (error) {
      if (!mounted) return;
      if (error.loginRequired) setState(() => _loginRequired = true);
      _toast(error.message);
    } catch (_) {
      if (mounted) _toast('发布失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _pickImages() async {
    try {
      final paths = await PlatformService.pickImages();
      if (!mounted || paths.isEmpty) return;
      setState(() {
        for (final path in paths) {
          if (_images.length < 9 && !_images.contains(path)) _images.add(path);
        }
      });
    } catch (_) {
      if (mounted) _toast('读取图片失败');
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_hasContent || _publishing) return true;
    final result = await showZybConfirmDialog(
      context: context,
      title: '放弃未发布内容？',
      message: '当前标题、正文或图片尚未发布。',
      cancelText: '继续编辑',
      confirmText: '放弃内容',
      isDanger: true,
    );
    return result == true;
  }

  Future<void> _preview() async {
    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();
    if (subject.isEmpty) return _toast('请输入标题');
    if (message.isEmpty && _images.isEmpty) return _toast('请输入正文或添加图片');
    FocusManager.instance.primaryFocus?.unfocus();
    final confirmed = await Navigator.push<bool>(
      context,
      zybHorizontalPageRoute<bool>(
        builder: (_) => _PostPreview(
          subject: subject,
          message: message,
          images: List.unmodifiable(_images),
          forumName: _selectedForum.name,
          typeName: _currentTypeName,
        ),
      ),
    );
    if (confirmed == true) await _publish();
  }

  String get _currentTypeName {
    final matched = _threadTypes.where((t) => t.id == _selectedTypeId);
    return matched.isNotEmpty ? matched.first.name : '';
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final isError =
        message.contains('失败') ||
        message.contains('请输入') ||
        message.contains('不支持') ||
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_hasContent || _publishing,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _confirmLeave() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: isDark ? colors.background : Colors.white,
        appBar: AppBar(
          title: const Text('发帖'),
          actions: [
            TextButton.icon(
              onPressed: _openWebPost,
              icon: Icon(
                Icons.language_rounded,
                size: 16,
                color: colors.textSecondary,
              ),
              label: Text(
                '网页发帖',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: FilledButton(
                  onPressed: _loading || _publishing || _error.isNotEmpty
                      ? null
                      : _publish,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    disabledBackgroundColor: isDark
                        ? colors.surfaceSoft
                        : const Color(0xFFE5E6EB),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: colors.textMuted,
                    minimumSize: const Size(66, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _publishing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '发布',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: colors.primary))
            : _loginRequired
            ? _LoginRequired(onLogin: _login)
            : _error.isNotEmpty && _threadTypes.isEmpty
            ? _ErrorState(message: _error, onRetry: _prepare)
            : SafeArea(
                top: false,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                  children: [
                    // 1. 原地气泡下拉选择栏（板块 + 分类，统一10px圆角与精致比例）
                    Row(
                      children: [
                        // 原地板块下拉菜单
                        PopupMenuButton<PostingForum>(
                          onSelected: (forum) {
                            if (forum.fid != _selectedForum.fid) {
                              setState(() => _selectedForum = forum);
                              _prepare(initial: false);
                            }
                          },
                          elevation: 4,
                          constraints: const BoxConstraints(
                            minWidth: 130,
                            maxWidth: 136,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isDark
                                  ? colors.cardBorder
                                  : const Color(0xFFE2E4EB),
                              width: 0.6,
                            ),
                          ),
                          offset: const Offset(0, 42),
                          itemBuilder: (context) => [
                            for (final forum in availablePostingForums)
                              PopupMenuItem<PostingForum>(
                                value: forum,
                                height: 38,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      forum.icon,
                                      size: 16,
                                      color: forum.color,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      forum.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: forum.fid == _selectedForum.fid
                                            ? colors.primary
                                            : colors.textPrimary,
                                        fontWeight:
                                            forum.fid == _selectedForum.fid
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                          child: Container(
                            height: 36,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: colors.surfaceSoft,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark
                                    ? colors.cardBorder
                                    : const Color(0xFFE2E4EB),
                                width: 0.6,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _selectedForum.icon,
                                  size: 15,
                                  color: _selectedForum.color,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _selectedForum.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(
                                  Icons.arrow_drop_down_rounded,
                                  size: 18,
                                  color: colors.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_threadTypes.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          // 原地子分类下拉菜单
                          PopupMenuButton<PostingThreadType>(
                            onSelected: (type) {
                              setState(() => _selectedTypeId = type.id);
                            },
                            elevation: 4,
                            constraints: const BoxConstraints(
                              minWidth: 98,
                              maxWidth: 106,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: isDark
                                    ? colors.cardBorder
                                    : const Color(0xFFE2E4EB),
                                width: 0.6,
                              ),
                            ),
                            offset: const Offset(0, 42),
                            itemBuilder: (context) => [
                              for (final type in _threadTypes)
                                PopupMenuItem<PostingThreadType>(
                                  value: type,
                                  height: 38,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    '# ${type.name}',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: type.id == _selectedTypeId
                                          ? colors.primary
                                          : colors.textPrimary,
                                      fontWeight: type.id == _selectedTypeId
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                            child: Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: colors.surfaceSoft,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? colors.cardBorder
                                      : const Color(0xFFE2E4EB),
                                  width: 0.6,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_loadingTypes)
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                      ),
                                    )
                                  else ...[
                                    Text(
                                      '# ${_currentTypeName.isEmpty ? '选择分类' : _currentTypeName}',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: colors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.arrow_drop_down_rounded,
                                      size: 18,
                                      color: colors.primary,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        // 轻量预览
                        TextButton.icon(
                          onPressed: _hasContent ? _preview : null,
                          icon: Icon(
                            Icons.visibility_outlined,
                            size: 15,
                            color: _hasContent
                                ? colors.textSecondary
                                : colors.textMuted.withValues(alpha: 0.4),
                          ),
                          label: Text(
                            '预览',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: _hasContent
                                  ? colors.textSecondary
                                  : colors.textMuted.withValues(alpha: 0.4),
                            ),
                          ),
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 2. 纯净平整一体画板（彻底关闭灰色补丁色块，留白呼吸自然）
                    TextField(
                      controller: _subjectController,
                      focusNode: _subjectFocus,
                      maxLength: 80,
                      cursorColor: colors.primary,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18.5,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入标题',
                        hintStyle: TextStyle(
                          color: colors.textMuted,
                          fontSize: 18,
                          fontWeight: FontWeight.normal,
                        ),
                        counterText: '',
                        filled: false,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Divider(
                      height: 1,
                      thickness: 0.6,
                      color: isDark ? colors.divider : const Color(0xFFEEEEEE),
                    ),
                    const SizedBox(height: 10),

                    // 正文自然输入流（纯净通透，无灰色背景）
                    TextField(
                      controller: _messageController,
                      minLines: 7,
                      maxLines: 18,
                      cursorColor: colors.primary,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15.5,
                        height: 1.55,
                      ),
                      decoration: InputDecoration(
                        hintText: '分享值得讨论的内容、线报或心得...',
                        hintStyle: TextStyle(
                          color: colors.textMuted,
                          fontSize: 15,
                        ),
                        filled: false,
                        fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. 传图区域（自然延展九宫格，16px 充裕呼吸边距，彻底杜绝压线）
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (int i = 0; i < _images.length; i++)
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                InkWell(
                                  onTap: () => openImageViewer(
                                    context,
                                    _images,
                                    initialIndex: i,
                                    local: true,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.file(
                                      File(_images[i]),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: InkWell(
                                    onTap: () => setState(
                                      () => _images.removeAt(i),
                                    ),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.65,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close_rounded,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (_images.length < 9)
                          InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _pickImages,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: colors.surfaceSoft,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? colors.cardBorder
                                      : const Color(0xFFE2E4EB),
                                  width: 0.6,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate_outlined,
                                    color: colors.primary,
                                    size: 26,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_images.length}/9',
                                    style: TextStyle(
                                      color: colors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 36),

                    // 4. 精炼规范提示文案（严格按指定格式）
                    Center(
                      child: Column(
                        children: [
                          Text(
                            '请遵守赚客吧社区规范，禁止发布违规内容',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textMuted,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '复杂格式推荐使用“网页发帖”',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PostPreview extends StatelessWidget {
  final String subject;
  final String message;
  final List<String> images;
  final String forumName;
  final String typeName;

  const _PostPreview({
    required this.subject,
    required this.message,
    required this.images,
    required this.forumName,
    required this.typeName,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? colors.background : const Color(0xFFF6F7F9),
      appBar: AppBar(title: const Text('发布效果预览')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? colors.surface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? colors.cardBorder : const Color(0xFFE2E4EB),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (forumName.isNotEmpty) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          typeName.isNotEmpty ? '$forumName · $typeName' : forumName,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  subject,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15.5,
                    height: 1.55,
                  ),
                ),
                for (var i = 0; i < images.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: InkWell(
                      onTap: () => openImageViewer(
                        context,
                        images,
                        initialIndex: i,
                        local: true,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(File(images[i]), fit: BoxFit.contain),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('返回编辑'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确认发布'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginRequired extends StatelessWidget {
  final VoidCallback onLogin;

  const _LoginRequired({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.login_rounded, color: colors.primary, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              '登录后发布帖子',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onLogin,
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                minimumSize: const Size(168, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: const Text('网页登录'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: colors.textMuted,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}
