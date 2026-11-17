import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/private_message.dart';
import '../services/haptic_service.dart';
import '../services/official_api_service.dart';
import '../services/blacklist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/native_html_content.dart';
import '../widgets/zyb_feedback.dart';
import '../widgets/zyb_avatar.dart';
import 'login_page.dart';
import 'other_user_profile_page.dart';

class PrivateMessagesPage extends StatefulWidget {
  /// 内嵌模式（作为消息中心 Tab 的内容区，不包 Scaffold/AppBar）
  final bool embedded;

  const PrivateMessagesPage({super.key, this.embedded = false});

  @override
  State<PrivateMessagesPage> createState() => _PrivateMessagesPageState();
}

class _PrivateMessagesPageState extends State<PrivateMessagesPage> {
  final _api = OfficialApiService();
  final _blacklist = BlacklistService();
  List<PrivateConversation> _items = const [];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.fetchConversations(),
        _blacklist.load(),
      ]);
      final blocked = results[1] as Set<String>;
      final items = (results[0] as List<PrivateConversation>)
          .where((item) => !blocked.contains(item.userId))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _login() async {
    final result = await Navigator.push<bool>(
      context,
      zybHorizontalPageRoute<bool>(builder: (_) => const LoginPage()),
    );
    if (result == true) await _load();
  }

  Future<void> _open(PrivateConversation item) async {
    await Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => PrivateChatPage(
          userId: item.userId,
          userName: item.userName,
          avatar: item.avatar,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final body = _buildBody(colors);
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('我的私信'),
        centerTitle: true,
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
      body: body,
    );
  }

  Widget _buildBody(ZybColors colors) {
    if (_loading && _items.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_error != null && _items.isEmpty) {
      final loginRequired =
          _error is OfficialApiException &&
          (_error as OfficialApiException).loginRequired;
      return _EmptyState(
        icon: loginRequired
            ? Icons.lock_outline_rounded
            : Icons.mark_email_unread_outlined,
        message: _error.toString(),
        actionLabel: loginRequired ? '登录' : '重试',
        onAction: loginRequired ? _login : _load,
      );
    }
    if (_items.isEmpty) {
      return _EmptyState(
        icon: Icons.mail_outline_rounded,
        message: '暂无私信',
        actionLabel: '刷新',
        onAction: _load,
      );
    }
    return RefreshIndicator(
      color: colors.primary,
      onRefresh: () async {
        await _load();
        if (mounted) {
          HapticService.instance.lightImpact();
          showZybFeedback(context, '刷新成功');
        }
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: isDark ? colors.surface : Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _open(item),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.cardBorder,
                      width: 0.6,
                    ),
                    boxShadow: isDark
                        ? [
                            BoxShadow(
                              color: colors.shadow,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : const [
                            BoxShadow(color: Colors.transparent),
                          ],
                  ),
                  child: Row(
                    children: [
                      ZybAvatar(
                        url: item.avatar,
                        uid: item.userId,
                        name: item.userName,
                        size: 44,
                        radius: 12,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.userName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 14.8,
                                      height: 1.22,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  item.lastDateline,
                                  style: TextStyle(
                                    color: colors.textMuted,
                                    fontSize: 11.5,
                                    height: 1.15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    plainTextFromHtml(item.messageHtml),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 13,
                                      height: 1.15,
                                    ),
                                  ),
                                ),
                                if (item.unread > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    height: 16,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: colors.primary,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${item.unread}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class PrivateChatPage extends StatefulWidget {
  final String userId;
  final String userName;
  final String avatar;
  final String myUid;
  final String myName;
  final String myAvatar;

  const PrivateChatPage({
    super.key,
    required this.userId,
    required this.userName,
    this.avatar = '',
    this.myUid = '',
    this.myName = '',
    this.myAvatar = '',
  });

  @override
  State<PrivateChatPage> createState() => _PrivateChatPageState();
}

class _PrivateChatPageState extends State<PrivateChatPage> {
  final _api = OfficialApiService();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  List<PrivateMessage> _messages = const [];
  Object? _error;
  bool _loading = true;
  bool _sending = false;
  bool _hasInput = false;
  late String _myUid = widget.myUid;
  late String _myName = widget.myName;
  late String _myAvatar = widget.myAvatar;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_handleInputChanged);
    _initMyInfo();
    _load();
  }

  Future<void> _initMyInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString('uid') ?? prefs.getString('discuz_uid') ?? '';
      final name = prefs.getString('username') ?? '';
      final avatar = prefs.getString('avatar_url') ?? '';
      if (!mounted) return;
      setState(() {
        if (_myUid.isEmpty) _myUid = uid;
        if (_myName.isEmpty) _myName = name;
        if (_myAvatar.isEmpty) _myAvatar = avatar;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _inputController.removeListener(_handleInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleInputChanged() {
    final value = _inputController.text.trim().isNotEmpty;
    if (value != _hasInput && mounted) setState(() => _hasInput = value);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await _api.fetchMessages(widget.userId);
      if (!mounted) return;
      setState(() {
        _messages = messages;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final message = _inputController.text.trim();
    if (message.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.sendPrivateMessage(userId: widget.userId, message: message);
      _inputController.clear();
      // 乐观追加并立即滑动到底部（正确带上本人头像与信息，杜绝混淆对方头像）
      final tempMsg = PrivateMessage(
        toUserId: widget.userId,
        toUserName: widget.userName,
        fromAvatar: _myAvatar,
        toAvatar: widget.avatar,
        messageHtml: message,
        dateline: '刚刚',
        conversationId: '',
      );
      if (mounted) {
        setState(() {
          _messages = [..._messages, tempMsg];
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        HapticService.instance.lightImpact();
        _toast('发送成功');
      }
      // 并在后台拉取最新官方私信对齐（智能保留本地刚刚发送且服务端尚未缓存的消息）
      final refreshed = await _api.fetchMessages(widget.userId);
      if (mounted && refreshed.isNotEmpty) {
        setState(() {
          final refreshedTexts =
              refreshed.map((m) => m.messageHtml.trim()).toSet();
          final unsynced = _messages
              .where(
                (m) =>
                    m.dateline == '刚刚' &&
                    !refreshedTexts.contains(m.messageHtml.trim()),
              )
              .toList();
          _messages = [...refreshed, ...unsynced];
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } on OfficialApiException catch (error) {
      if (mounted) _toast(error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _toast(String message) {
    final isError = message.contains('失败') ||
        message.contains('敏感词') ||
        message.contains('修改') ||
        message.contains('空') ||
        message.contains('请');
    if (isError) {
      HapticService.instance.errorImpact();
    }
    showZybFeedback(context, message, error: isError);
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? colors.background : const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: Text(
          widget.userName.isEmpty ? '私信' : widget.userName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _buildBody(colors)),
            _buildInputBar(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(ZybColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      decoration: BoxDecoration(
        color: colors.navBackground,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              decoration: BoxDecoration(
                color: colors.surfaceSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                cursorColor: colors.primary,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14.5,
                  height: 1.3,
                ),
                decoration: InputDecoration(
                  hintText: '输入私信内容...',
                  hintStyle: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13.5,
                  ),
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: _hasInput ? colors.primary : colors.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _sending || !_hasInput ? null : _send,
              child: Container(
                width: 44,
                height: 40,
                alignment: Alignment.center,
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        Icons.send_rounded,
                        color: _hasInput ? Colors.white : colors.textMuted,
                        size: 20,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ZybColors colors) {
    if (_loading && _messages.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_error != null && _messages.isEmpty) {
      return _EmptyState(
        icon: Icons.error_outline_rounded,
        message: _error.toString(),
        actionLabel: '重试',
        onAction: _load,
      );
    }
    return RefreshIndicator(
      color: colors.primary,
      onRefresh: () async {
        await _load();
        if (mounted) {
          HapticService.instance.lightImpact();
          showZybFeedback(context, '刷新成功');
        }
      },
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          final mine =
              widget.userId.isNotEmpty && message.toUserId == widget.userId;
          final avatar = mine
              ? (message.fromAvatar.isNotEmpty ? message.fromAvatar : _myAvatar)
              : (message.fromAvatar.isNotEmpty ? message.fromAvatar : widget.avatar);
          final uid = mine ? _myUid : widget.userId;
          final userName = mine
              ? (_myName.isNotEmpty ? _myName : '我')
              : widget.userName;
          return _MessageBubble(
            message: message,
            mine: mine,
            avatar: avatar,
            uid: uid,
            userName: userName,
            onAvatarTap: mine
                ? null
                : () {
                    final targetUid = widget.userId.trim();
                    if (targetUid.isNotEmpty) {
                      Navigator.push(
                        context,
                        zybHorizontalPageRoute<void>(
                          builder: (_) => OtherUserProfilePage(
                            userId: targetUid,
                            userName: widget.userName,
                            avatar: widget.avatar,
                          ),
                        ),
                      );
                    }
                  },
          );
        },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final PrivateMessage message;
  final bool mine;
  final String avatar;
  final String uid;
  final String userName;
  final VoidCallback? onAvatarTap;

  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.avatar,
    this.uid = '',
    this.userName = '',
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            GestureDetector(
              onTap: onAvatarTap,
              child: ZybAvatar(
                url: avatar,
                uid: uid,
                name: userName,
                size: 36,
                radius: 10,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 290),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: mine
                    ? (isDark ? colors.primarySoft : const Color(0xFFFFEFE6))
                    : (isDark ? colors.surface : Colors.white),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                border: Border.all(
                  color: mine
                      ? colors.primary.withValues(alpha: 0.38)
                      : (isDark ? colors.cardBorder : const Color(0xFFE2E4EB)),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                    blurRadius: 5,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: NativeHtmlContent(
                html: message.messageHtml,
                fontSize: 14.5,
                shrinkWrap: true,
              ),
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 8),
            ZybAvatar(
              url: avatar,
              uid: uid,
              name: userName,
              size: 36,
              radius: 10,
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colors.textMuted),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors.primary),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
