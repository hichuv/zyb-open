import 'package:flutter/material.dart';

import '../config/constants.dart';
import '../models/zk_post.dart';
import '../services/official_api_service.dart';
import '../services/blacklist_service.dart';
import '../services/read_history_service.dart';
import '../theme/app_theme.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'thread_detail_page.dart';
import 'webview_page.dart';
import '../services/filter_service.dart';
import '../services/haptic_service.dart';
import '../widgets/zyb_confirm_dialog.dart';
import '../widgets/zyb_feedback.dart';

/// 我的列表类型
enum MyListType {
  threads(label: '我的发布'),
  replies(label: '我的回复'),
  favorites(label: '我的收藏');

  final String label;

  const MyListType({required this.label});
}

class MyListsPage extends StatefulWidget {
  final MyListType type;

  const MyListsPage({super.key, required this.type});

  @override
  State<MyListsPage> createState() => _MyListsPageState();
}

class _MyListsPageState extends State<MyListsPage> {
  final OfficialApiService _api = OfficialApiService();
  final BlacklistService _blacklist = BlacklistService();
  final ScrollController _scrollController = ScrollController();

  final List<ZkPost> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  bool _loggedIn = true;
  String _errorText = '';
  final Set<String> _locallyUnfavoritedTids = {};

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

  Future<List<ZkPost>> _fetch(int page) async {
    final blocked = await _blacklist.load();
    final posts = switch (widget.type) {
      MyListType.threads => await _api.fetchMyThreads(page: page),
      MyListType.replies => await _api.fetchMyReplies(page: page),
      MyListType.favorites => await _api.fetchMyFavorites(page: page),
    };
    return posts
        .where((post) =>
            !blocked.contains(post.authorId) &&
            !FilterService.instance.isPostBlocked(post) &&
            (widget.type != MyListType.favorites ||
                !_locallyUnfavoritedTids.contains(post.tid)))
        .toList();
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
      final loggedIn = await _isLoggedIn();
      if (!mounted) return;
      if (!loggedIn) {
        setState(() {
          _loggedIn = false;
          _loading = false;
          _posts.clear();
        });
        return;
      }
      setState(() => _loggedIn = true);
      final posts = await _fetch(1);
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(posts);
        _page = 1;
        _hasMore = posts.isNotEmpty;
        _loading = false;
      });
    } on OfficialApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (error.loginRequired) {
          _loggedIn = false;
        } else {
          _errorText = error.message;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = '加载失败：$error';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final posts = await _fetch(nextPage);
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

  Future<bool> _isLoggedIn() => _api.isAnyLoggedIn();

  Future<void> _openLogin() async {
    final success = await Navigator.push<bool>(
      context,
      zybHorizontalPageRoute<bool>(builder: (_) => const LoginPage()),
    );
    if (success == true) await _load(reset: true);
  }

  void _toast(String msg) => showZybFeedback(context, msg);

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
        if (widget.type == MyListType.favorites) {
          await _load(reset: true);
        } else {
          setState(() {});
        }
      }
      return;
    }
    final result = await Navigator.push<dynamic>(
      context,
      zybHorizontalPageRoute<dynamic>(
        builder: (_) => ThreadDetailPage(tid: post.tid, title: post.title),
      ),
    );
    if (mounted) {
      ReadHistoryService.instance.notifyReadChanged();
      if (widget.type == MyListType.favorites) {
        if (result is Map && result['favorited'] == false) {
          _locallyUnfavoritedTids.add(post.tid);
          setState(() {
            _posts.removeWhere((p) => p.tid == post.tid);
          });
        } else if (result is Map && result['favorited'] == true) {
          _locallyUnfavoritedTids.remove(post.tid);
        }
        await _load(reset: true);
      } else {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          widget.type.label,
          style: TextStyle(color: colors.textPrimary),
        ),
        backgroundColor: colors.surface,
        elevation: 0,
      ),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(ZybColors colors) {
    if (!_loggedIn) {
      return _LoginPrompt(
        colors: colors,
        onLogin: _openLogin,
        onRetry: () => _load(reset: true),
      );
    }
    if (_loading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_errorText.isNotEmpty && _posts.isEmpty) {
      return _ErrorView(
        message: _errorText,
        colors: colors,
        onRetry: () => _load(reset: true),
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
              '暂无${widget.type.label}',
              style: TextStyle(color: colors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 18),
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
          final card = Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: PostCard(
              post: post,
              mode: SortMode.latestPost,
              isRead: ReadHistoryService.instance.isRead(post.tid),
              onTap: () => _openPost(post),
            ),
          );

          if (widget.type == MyListType.favorites) {
            return Dismissible(
              key: ValueKey('fav_${post.tid}_${post.favId}'),
              direction: DismissDirection.endToStart,
              background: Container(
                margin: const EdgeInsets.only(bottom: 4),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 4),
                    Text(
                      '取消收藏',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              confirmDismiss: (_) async {
                return await showZybConfirmDialog(
                  context: context,
                  title: '取消收藏',
                  message: '确定移除《${post.title}》吗？',
                  confirmText: '移除',
                  isDanger: true,
                );
              },
              onDismissed: (_) async {
                final favId = post.favId;
                final tid = post.tid;
                _locallyUnfavoritedTids.add(tid);
                setState(() => _posts.removeAt(index));
                _toast('已取消收藏');
                try {
                  await _api.unfavoriteThread(favId: favId, tid: tid);
                } catch (_) {
                  _locallyUnfavoritedTids.remove(tid);
                  if (mounted) {
                    setState(() {
                      if (index <= _posts.length) {
                        _posts.insert(index, post);
                      } else {
                        _posts.add(post);
                      }
                    });
                    _toast('取消收藏失败，请检查网络');
                  }
                }
              },
              child: card,
            );
          }
          return card;
        },
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  final ZybColors colors;
  final VoidCallback onLogin;
  final VoidCallback onRetry;

  const _LoginPrompt({
    required this.colors,
    required this.onLogin,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.lock_outline_rounded,
              size: 30,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '登录后查看',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.primary,
              minimumSize: const Size(150, 44),
            ),
            onPressed: onLogin,
            child: const Text('去登录'),
          ),
          TextButton(onPressed: onRetry, child: const Text('重新检测登录')),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final ZybColors colors;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.colors,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
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
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
