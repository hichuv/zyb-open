import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/zk_post.dart';
import '../services/filter_service.dart';
import '../services/haptic_service.dart';
import '../services/official_api_service.dart';
import '../services/read_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/zyb_avatar.dart';
import '../widgets/zyb_confirm_dialog.dart';
import '../widgets/zyb_feedback.dart';
import 'home_page.dart';
import 'private_messages_page.dart';
import 'thread_detail_page.dart';
import 'webview_page.dart';
import '../utils/time_parser.dart';

/// 原生他人主页：只提供私信与其发布的主题帖。
class OtherUserProfilePage extends StatefulWidget {
  final String userId;
  final String userName;
  final String avatar;

  const OtherUserProfilePage({
    super.key,
    required this.userId,
    this.userName = '',
    this.avatar = '',
  });

  @override
  State<OtherUserProfilePage> createState() => _OtherUserProfilePageState();
}

class _OtherUserProfilePageState extends State<OtherUserProfilePage> {
  final _api = OfficialApiService();
  final _scrollController = ScrollController();
  final List<ZkPost> _posts = [];

  OfficialUserProfile? _profile;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    FilterService.instance.load();
    ReadHistoryService.instance.addListener(_handleReadHistoryChanged);
    _load(reset: true);
  }

  void _handleReadHistoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ReadHistoryService.instance.removeListener(_handleReadHistoryChanged);
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    }
    try {
      final result = await Future.wait<dynamic>([
        _api.fetchUserProfile(widget.userId),
        _api.fetchUserThreads(userId: widget.userId),
      ]);
      if (!mounted) return;
      final posts = result[1] as List<ZkPost>;
      setState(() {
        _profile = result[0] as OfficialUserProfile;
        _posts
          ..clear()
          ..addAll(posts);
        _page = 1;
        _hasMore = posts.isNotEmpty;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final posts = await _api.fetchUserThreads(
        userId: widget.userId,
        page: nextPage,
      );
      if (!mounted) return;
      final existing = _posts.map((post) => post.tid).toSet();
      setState(() {
        _posts.addAll(posts.where((post) => existing.add(post.tid)));
        _page = nextPage;
        _hasMore = posts.isNotEmpty;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openPost(ZkPost post) async {
    ReadHistoryService.instance.markRead(post.tid, notify: false);
    if (post.fid == 11) {
      await Navigator.push(
        context,
        zybHorizontalPageRoute<void>(
          builder: (_) => WebViewPage(
            url: threadUrl(post.tid),
            title: post.title,
            initialDesktopMode: true,
          ),
        ),
      );
      if (mounted) {
        ReadHistoryService.instance.notifyReadChanged();
        setState(() {});
      }
      return;
    }
    await Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => ThreadDetailPage(tid: post.tid, title: post.title),
      ),
    );
    if (mounted) {
      ReadHistoryService.instance.notifyReadChanged();
      setState(() {});
    }
  }

  void _openPrivateMessage() {
    final profile = _profile;
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => PrivateChatPage(
          userId: widget.userId,
          userName: profile?.userName.isNotEmpty == true
              ? profile!.userName
              : widget.userName,
          avatar: profile?.avatar.isNotEmpty == true ? profile!.avatar : widget.avatar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('用户主页'),
      ),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(ZybColors colors) {
    if (_loading && _profile == null) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_error != null && _profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 46, color: colors.textMuted),
              const SizedBox(height: 12),
              Text(
                '主页加载失败：$_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => _load(reset: true), child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: colors.primary,
      onRefresh: () async {
        await _load(reset: true);
        if (mounted) {
          HapticService.instance.lightImpact();
          showZybFeedback(context, '刷新成功');
        }
      },
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        itemCount: 2 + _posts.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _ProfileHeader(
            profile: _profile,
            fallbackName: widget.userName,
            fallbackAvatar: widget.avatar,
            userId: widget.userId,
            onMessage: _openPrivateMessage,
          );
          if (index == 1) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
              child: Text(
                'TA 的发帖',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }
          final postIndex = index - 2;
          if (postIndex < _posts.length) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: PostCard(
                post: _posts[postIndex],
                mode: SortMode.latestPost,
                isRead: ReadHistoryService.instance.isRead(_posts[postIndex].tid),
                centerTime: true,
                onTap: () => _openPost(_posts[postIndex]),
              ),
            );
          }
          if (_posts.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 42),
              child: Center(
                child: Text(
                  'TA 暂未发布帖子',
                  style: TextStyle(color: colors.textMuted, fontSize: 14),
                ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: _loadingMore
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    )
                  : Text(
                      _hasMore ? '继续下滑加载更多' : '已加载全部',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final OfficialUserProfile? profile;
  final String fallbackName;
  final String fallbackAvatar;
  final String userId;
  final VoidCallback onMessage;

  const _ProfileHeader({
    required this.profile,
    required this.fallbackName,
    required this.fallbackAvatar,
    required this.userId,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final name = profile?.userName.isNotEmpty == true
        ? profile!.userName
        : (fallbackName.isEmpty ? '用户' : fallbackName);
    final avatar = profile?.avatar.isNotEmpty == true
        ? profile!.avatar
        : fallbackAvatar;
    final group = profile?.groupTitle ?? '';
    final regDate = formatRegDate(profile?.registeredAt ?? '');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(ZybDesign.radiusLarge),
        border: Border.all(color: colors.cardBorder, width: .7),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.primary.withValues(alpha: .35)),
            ),
            child: ZybAvatar(url: avatar, uid: userId, name: name, size: 52),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (group.isNotEmpty)
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
                    group,
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ),
              if (group.isNotEmpty && regDate.isNotEmpty)
                const SizedBox(width: 8),
              if (regDate.isNotEmpty)
                Text(
                  regDate,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    height: 1.15,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 104,
                height: 36,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onMessage,
                  icon: const Icon(Icons.mail_outline_rounded, size: 16),
                  label: const Text(
                    '私信',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AnimatedBuilder(
                animation: FilterService.instance,
                builder: (context, _) {
                  final isBlocked = FilterService.instance.isAuthorBlocked(name);
                  return SizedBox(
                    width: 104,
                    height: 36,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: isBlocked
                            ? (Theme.of(context).brightness == Brightness.dark
                                ? const Color(0x28F53F3F)
                                : const Color(0xFFFFF1F0))
                            : colors.surfaceSoft,
                        foregroundColor: isBlocked
                            ? const Color(0xFFF53F3F)
                            : colors.textSecondary,
                        side: BorderSide(
                          color: isBlocked
                              ? const Color(0xFFFFCCC7)
                              : colors.cardBorder,
                          width: 0.8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _confirmToggleBlock(context, name),
                      icon: Icon(
                        isBlocked
                            ? Icons.block_rounded
                            : Icons.do_not_disturb_on_outlined,
                        size: 16,
                        color: isBlocked
                            ? const Color(0xFFF53F3F)
                            : colors.textSecondary,
                      ),
                      label: Text(
                        isBlocked ? '已拉黑' : '拉黑',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isBlocked
                              ? const Color(0xFFF53F3F)
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmToggleBlock(
    BuildContext context,
    String userName,
  ) async {
    if (userName.trim().isEmpty) return;
    final isBlocked = FilterService.instance.isAuthorBlocked(userName);
    final message = isBlocked
        ? '确定解除对用户“$userName”的拉黑吗？'
        : '确定要拉黑用户“$userName”吗？';
    final actionText = isBlocked ? '确定解除' : '确定拉黑';

    final confirmed = await showZybConfirmDialog(
      context: context,
      title: message,
      confirmText: actionText,
      isDanger: !isBlocked,
    );

    if (confirmed == true && context.mounted) {
      HapticService.instance.lightImpact();
      if (isBlocked) {
        await FilterService.instance.removeAuthor(userName);
        if (context.mounted) {
          showZybFeedback(context, '拉黑解除');
        }
      } else {
        await FilterService.instance.addAuthor(userName);
        if (context.mounted) {
          showZybFeedback(context, '拉黑成功');
        }
      }
    }
  }
}
