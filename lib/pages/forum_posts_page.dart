import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/zk_post.dart';
import '../services/api_service.dart';
import '../services/blacklist_service.dart';
import '../services/official_api_service.dart';
import '../services/read_history_service.dart';
import '../theme/app_theme.dart';
import '../services/filter_service.dart';
import '../services/haptic_service.dart';
import '../widgets/zyb_feedback.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'thread_detail_page.dart';
import 'webview_page.dart';

/// 板块原生帖子列表页（赚客大家谈/任务赚果/赚品交换/果果换物）
class ForumPostsPage extends StatefulWidget {
  final int fid;
  final String title;

  const ForumPostsPage({super.key, required this.fid, required this.title});

  @override
  State<ForumPostsPage> createState() => _ForumPostsPageState();
}

class _ForumPostsPageState extends State<ForumPostsPage> {
  final ApiService _api = ApiService();
  final BlacklistService _blacklist = BlacklistService();
  Set<String> _blockedUids = const {};
  final ScrollController _scrollController = ScrollController();

  final List<ZkPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  bool _loggedIn = true;
  String _errorText = '';

  SortMode _mode = SortMode.latestPost;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    ReadHistoryService.instance.addListener(_handleReadHistoryChanged);
    FilterService.instance.addListener(_handleFilterChanged);
    _load(reset: true);
  }

  void _handleReadHistoryChanged() {
    if (mounted) setState(() {});
  }

  void _handleFilterChanged() {
    if (!mounted) return;
    setState(() {
      _posts.removeWhere((post) => FilterService.instance.isPostBlocked(post));
    });
  }

  @override
  void dispose() {
    FilterService.instance.removeListener(_handleFilterChanged);
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
        _errorText = '';
        _page = 1;
        _hasMore = true;
      });
    }
    try {
      // 登录态决定能否用 HTML 解析（任务/交换/换物板块需登录）
      final loggedIn = await _isLoggedIn();
      if (!mounted) return;
      setState(() => _loggedIn = loggedIn);
      final posts = await _fetchPosts(1);
      if (!mounted) return;
      setState(() {
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
        _loading = false;
        _errorText = '加载失败：$error';
      });
    }
  }

  Future<List<ZkPost>> _fetchPosts(int page) async {
    await _api.refreshCookie();
    _blockedUids = await _blacklist.load();
    final posts = await _api.fetchForumList(
      fid: widget.fid,
      sortMode: _mode,
      page: page,
    );
    return posts
        .where((post) =>
            !_blockedUids.contains(post.authorId) &&
            !FilterService.instance.isPostBlocked(post))
        .toList();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final posts = await _fetchPosts(nextPage);
      if (!mounted) return;
      final existing = _posts.map((post) => post.tid).toSet();
      setState(() {
        _posts.addAll(posts.where((post) => existing.add(post.tid)));
        _page = nextPage;
        _hasMore = posts.isNotEmpty;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<bool> _isLoggedIn() => OfficialApiService().isAnyLoggedIn();

  Future<void> _openLogin() async {
    final success = await Navigator.push<bool>(
      context,
      zybHorizontalPageRoute<bool>(builder: (_) => const LoginPage()),
    );
    if (success == true) await _load(reset: true);
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

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(widget.title, style: TextStyle(color: colors.textPrimary)),
        backgroundColor: colors.surface,
        elevation: 0,
      ),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(ZybColors colors) {
    if (_loading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_errorText.isNotEmpty && _posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: colors.textMuted.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                _errorText,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => _load(reset: true),
                    child: const Text('重试'),
                  ),
                  const SizedBox(width: 12),
                  if (!_loggedIn)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.primary,
                      ),
                      onPressed: _openLogin,
                      child: const Text('去登录'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (_posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 52,
              color: colors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              _loggedIn ? '暂无帖子' : '该板块需要登录后查看',
              style: TextStyle(color: colors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 18),
            if (!_loggedIn)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: colors.primary),
                onPressed: _openLogin,
                child: const Text('去登录'),
              )
            else
              OutlinedButton(
                onPressed: () => _load(reset: true),
                child: const Text('刷新'),
              ),
          ],
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
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        itemCount: _posts.length + 1,
        itemBuilder: (context, index) {
          if (index == _posts.length) {
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
          }
          final post = _posts[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: PostCard(
              post: post,
              mode: _mode,
              isRead: ReadHistoryService.instance.isRead(post.tid),
              onTap: () => _openPost(post),
            ),
          );
        },
      ),
    );
  }
}
