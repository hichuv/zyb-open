import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import '../models/zk_post.dart';
import '../services/api_service.dart';
import '../services/blacklist_service.dart';
import '../services/filter_service.dart';
import '../services/haptic_service.dart';
import '../services/official_api_service.dart';
import '../services/read_history_service.dart';
import '../services/remote_config_service.dart';
import '../state/login_state.dart';
import '../theme/app_theme.dart';
import '../utils/time_parser.dart';
import '../widgets/zyb_feedback.dart';
import 'new_thread_page.dart';
import 'thread_detail_page.dart';
import 'webview_page.dart';

const _homeModes = [SortMode.hot, SortMode.latestPost];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class _HomeFeedState {
  final ScrollController scrollController = ScrollController();
  bool loading = false;
  bool loadingMore = false;
  bool loaded = false;
  bool hasMore = true;
  int currentPage = 1;
  String errorText = '';
  List<ZkPost> posts = [];
  ForumFeedAggregator? aggregator;

  void dispose() {
    scrollController.dispose();
  }
}

class _LessSensitivePageScrollPhysics extends PageScrollPhysics {
  const _LessSensitivePageScrollPhysics({super.parent});

  @override
  _LessSensitivePageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _LessSensitivePageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 42;

  @override
  double get minFlingVelocity => 650;
}

class HomePageState extends State<HomePage> {
  final _blacklist = BlacklistService();
  final _filter = FilterService.instance;
  Set<String> _blockedUids = const {};
  final ApiService _api = ApiService();

  late final PageController _pageController;
  late final Map<SortMode, _HomeFeedState> _feeds;
  late final Map<SortMode, GlobalKey<RefreshIndicatorState>> _refreshKeys;

  SortMode _mode = SortMode.hot;
  HomeNotice? _homeNotice;
  bool _hideHomeNoticeThisSession = false;


  late List<bool> _forumEnabled;
  static const _prefKey = 'forum_enabled';

  @override
  void initState() {
    super.initState();
    _forumEnabled = List.filled(browseForums.length, true);
    _pageController = PageController(initialPage: _homeModes.indexOf(_mode));
    _feeds = {for (final mode in _homeModes) mode: _HomeFeedState()};
    _refreshKeys = {
      for (final mode in _homeModes) mode: GlobalKey<RefreshIndicatorState>(),
    };
    for (final entry in _feeds.entries) {
      entry.value.scrollController.addListener(() => _handleScroll(entry.key));
    }
    _feeds[_mode]!.loading = true;
    loginStateVersion.addListener(_handleLoginChanged);
    _filter.load();
    _filter.addListener(_handleFilterChanged);
    ReadHistoryService.instance.addListener(_handleReadHistoryChanged);
    _loadForumPrefs();
    _loadRemoteConfig();
    _loadBlacklist();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _loadPosts(mode: _mode),
    );
  }

  void _handleReadHistoryChanged() {
    if (mounted) setState(() {});
  }

  void _handleFilterChanged() {
    if (!mounted) return;
    setState(() {
      for (final feed in _feeds.values) {
        feed.posts.removeWhere((post) => _filter.isPostBlocked(post));
      }
    });
  }

  Future<void> _loadBlacklist({bool refresh = false}) async {
    final values = await _blacklist.load(refresh: refresh);
    if (mounted) {
      setState(() {
        _blockedUids = values;
        for (final feed in _feeds.values) {
          feed.posts.removeWhere(
            (post) =>
                values.contains(post.authorId) || _filter.isPostBlocked(post),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    loginStateVersion.removeListener(_handleLoginChanged);
    _filter.removeListener(_handleFilterChanged);
    ReadHistoryService.instance.removeListener(_handleReadHistoryChanged);
    for (final feed in _feeds.values) {
      feed.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  void _handleLoginChanged() {
    if (!mounted) return;
    for (final feed in _feeds.values) {
      feed.loaded = false;
    }
    _loadPosts(mode: _mode, jumpTop: true);
  }

  List<int> _selectedFids() => [
    for (int i = 0; i < browseForums.length; i++)
      if (_forumEnabled[i]) browseForums[i].fid,
  ];

  void _handleScroll(SortMode mode) {
    final feed = _feeds[mode]!;
    final controller = feed.scrollController;
    if (!controller.hasClients ||
        feed.loading ||
        feed.loadingMore ||
        !feed.hasMore) {
      return;
    }
    if (controller.position.pixels >=
        controller.position.maxScrollExtent - 360) {
      _loadMore(mode);
    }
  }

  Future<void> _loadForumPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && saved.length == browseForums.length) {
      for (int i = 0; i < browseForums.length; i++) {
        _forumEnabled[i] = saved[i] == '1';
      }
    }
  }

  Future<void> _saveForumPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      _forumEnabled.map((e) => e ? '1' : '0').join(),
    );
  }

  Future<void> _loadRemoteConfig() async {
    final config = await RemoteConfigService.load();
    if (!mounted) return;
    setState(() => _homeNotice = config.homeNotice);
  }

  Future<void> _refreshHome(SortMode mode) async {
    await Future.wait([
      _loadRemoteConfig(),
      _loadBlacklist(refresh: true),
      _loadPosts(mode: mode, jumpTop: true),
    ]);
    if (mounted) {
      HapticService.instance.lightImpact();
      showZybFeedback(context, '刷新成功');
    }
  }

  Future<void> _loadPosts({
    required SortMode mode,
    bool jumpTop = false,
  }) async {
    final feed = _feeds[mode]!;
    setState(() {
      feed.loading = true;
      feed.loadingMore = false;
      feed.hasMore = true;
      feed.currentPage = 1;
      feed.errorText = '';
    });

    final controller = feed.scrollController;
    if (jumpTop && controller.hasClients) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }

    try {
      final fids = mode == SortMode.hot ? [15] : _selectedFids();
      if (fids.isEmpty) {
        setState(() {
          feed.posts = [];
          feed.loading = false;
          feed.loaded = true;
        });
        return;
      }
      feed.aggregator = ForumFeedAggregator(
        api: _api,
        sortMode: mode,
        fids: fids,
      );

      // 若开屏期间已静默预加载好热门帖子，优先直出（秒开零等待）
      final preloaded = (mode == SortMode.hot && !jumpTop)
          ? _api.consumePreloadedHotPosts
          : null;
      final result = (preloaded != null && preloaded.isNotEmpty)
          ? preloaded
          : await feed.aggregator!.nextBatch();

      if (!mounted) return;
      setState(() {
        feed.posts = result
            .where(
              (post) =>
                  !_blockedUids.contains(post.authorId) &&
                  !_filter.isPostBlocked(post),
            )
            .toList();
        feed.loading = false;
        feed.loaded = true;
        feed.hasMore = result.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        feed.loading = false;
        feed.loaded = true;
        feed.errorText = '加载失败：$e';
      });
    }
  }

  Future<void> _loadMore(SortMode mode) async {
    final feed = _feeds[mode]!;
    if (feed.loading || feed.loadingMore || !feed.hasMore) return;
    setState(() => feed.loadingMore = true);

    try {
      feed.aggregator ??= ForumFeedAggregator(
        api: _api,
        sortMode: mode,
        fids: mode == SortMode.hot ? [15] : _selectedFids(),
      );
      final result = await feed.aggregator!.nextBatch();
      if (!mounted) return;
      setState(() {
        feed.currentPage += 1;
        final existing = feed.posts.map((post) => post.tid).toSet();
        feed.posts.addAll(
          result.where(
            (post) =>
                !_blockedUids.contains(post.authorId) &&
                !_filter.isPostBlocked(post) &&
                existing.add(post.tid),
          ),
        );
        feed.loadingMore = false;
        feed.hasMore = result.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => feed.loadingMore = false);
    }
  }

  Future<void> _changeMode(SortMode nextMode) async {
    HapticService.instance.lightImpact();
    if (_mode == nextMode) {
      await _loadPosts(mode: nextMode, jumpTop: true);
      return;
    }
    _activateMode(nextMode, animatePage: true);
  }

  void _handlePageChanged(int index) {
    _activateMode(_homeModes[index], animatePage: false);
  }

  void _activateMode(SortMode nextMode, {required bool animatePage}) {
    if (_mode != nextMode) {
      setState(() => _mode = nextMode);
    }

    final nextIndex = _homeModes.indexOf(nextMode);
    if (animatePage && _pageController.hasClients) {
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }

    final feed = _feeds[nextMode]!;
    if (!feed.loading && !feed.loaded && feed.errorText.isEmpty) {
      _loadPosts(mode: nextMode);
    }
  }

  Route<void> _postRoute(ZkPost post, List<ZkPost> posts, int index) {
    return zybHorizontalPageRoute<void>(
      builder: (_) => ThreadDetailPage(tid: post.tid, title: post.title),
    );
  }

  Future<void> _openPost(ZkPost post, int index) async {
    final posts = _feeds[_mode]!.posts;
    // 点击时静默记录到已读 Set，不立即打断转场动画
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
    await Navigator.push(context, _postRoute(post, posts, index));
    if (!mounted) return;
    ReadHistoryService.instance.notifyReadChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _showForumFilter() async {
    if (_mode == SortMode.hot) {
      HapticService.instance.lightImpact();
      showZybFeedback(context, '板块筛选仅对「新发布」生效');
      return;
    }
    final draft = List<bool>.from(_forumEnabled);
    final colors = zybColors(context);
    final result = await showModalBottomSheet<List<bool>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.cardBorder, width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '筛选板块',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final allSelected = draft.every((e) => e);
                        setSheetState(() {
                          for (int i = 0; i < draft.length; i++) {
                            draft[i] = !allSelected;
                          }
                        });
                      },
                      child: Text(
                        draft.every((e) => e) ? '清空' : '全选',
                        style: TextStyle(color: colors.primary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 8) / 2;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final i in [0, 2, 1, 3])
                          SizedBox(
                            width: itemWidth,
                            child: _ForumFilterChip(
                              forum: browseForums[i],
                              selected: draft[i],
                              onTap: () =>
                                  setSheetState(() => draft[i] = !draft[i]),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          foregroundColor: colors.textSecondary,
                          side: BorderSide(color: colors.cardBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          backgroundColor: colors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, draft),
                        child: const Text('确定'),
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

    if (result != null) {
      setState(() {
        _forumEnabled = result;
        for (final entry in _feeds.entries) {
          entry.value.posts = [];
          entry.value.currentPage = 1;
          entry.value.hasMore = true;
          entry.value.errorText = '';
          entry.value.loaded = false;
        }
      });
      await _saveForumPrefs();
      _loadPosts(mode: _mode, jumpTop: true);
    }
  }

  /// 滚回顶部并触发刷新（供底部导航栏二次点击调用）
  void scrollToTopAndRefresh() {
    final feed = _feeds[_mode];
    if (feed != null && feed.scrollController.hasClients) {
      if (feed.scrollController.offset > 60) {
        feed.scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ).then((_) {
          if (mounted) _refreshKeys[_mode]?.currentState?.show();
        });
      } else {
        _refreshKeys[_mode]?.currentState?.show();
      }
    } else {
      _refreshKeys[_mode]?.currentState?.show();
    }
  }

  Future<void> _openPublish() async {
    await Navigator.push(
      context,
      zybHorizontalPageRoute<void>(builder: (_) => const NewThreadPage()),
    );
    if (mounted) {
      _refreshKeys[_mode]?.currentState?.show();
    }
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SearchSheet(
        onSubmit: (keyword) {
          Navigator.push(
            context,
            zybHorizontalPageRoute<void>(
              builder: (_) => NativeSearchPage(keyword: keyword),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleNoticeTap(HomeNotice notice) async {
    if (notice.action == 'popup' || notice.action == 'dialog') {
      _showUpgradeDialog(notice);
      return;
    }
    if (notice.url.isEmpty) return;
    if (notice.action == 'copy') {
      await Clipboard.setData(ClipboardData(text: notice.url));
      HapticService.instance.lightImpact();
      _toast('复制成功');
      return;
    }
    if (notice.action == 'open') {
      final uri = Uri.tryParse(notice.url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  void _showUpgradeDialog(HomeNotice notice) {
    final colors = zybColors(context);
    final title = notice.title.isNotEmpty ? notice.title : notice.text;
    final rawContent = notice.content.isNotEmpty ? notice.content : notice.text;
    final hasUrl = notice.url.isNotEmpty;
    final content = hasUrl && !rawContent.contains(notice.url)
        ? '$rawContent\n\n下载地址：${notice.url}'
        : rawContent;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.28),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.48,
                ),
                child: SingleChildScrollView(
                  child: Text(
                    content,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.55,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (hasUrl)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                          foregroundColor: colors.textSecondary,
                          side: BorderSide(color: colors.cardBorder),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                          backgroundColor: colors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: notice.url),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          HapticService.instance.lightImpact();
                          _toast('复制成功');
                        },
                        child: const Text('复制'),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                      backgroundColor: colors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('我已了解'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String msg) {
    showZybFeedback(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? colors.background : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            _BrowseTopBar(
              mode: _mode,
              pageController: _pageController,
              onModeChanged: _changeMode,
              onSearch: _openSearch,
              onFilter: _showForumFilter,
              onPublish: _openPublish,
            ),
            Expanded(
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pageController,
                    physics: const _LessSensitivePageScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    itemCount: _homeModes.length,
                    onPageChanged: _handlePageChanged,
                    itemBuilder: (context, index) {
                      final mode = _homeModes[index];
                      return RefreshIndicator(
                        key: _refreshKeys[mode],
                        color: colors.primary,
                        onRefresh: () => _refreshHome(mode),
                        child: _buildContent(mode),
                      );
                    },
                  ),
                  Positioned(
                    right: 14,
                    bottom: 18,
                    child: _FloatingCircleButton(
                      icon: Icons.refresh_rounded,
                      onTap: () => _refreshKeys[_mode]?.currentState?.show(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(SortMode mode) {
    final colors = zybColors(context);
    final feed = _feeds[mode]!;
    if ((feed.loading || !feed.loaded) && feed.posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 180),
          Center(child: CircularProgressIndicator(color: colors.primary)),
          const SizedBox(height: 14),
          Center(
            child: Text('正在加载帖子...', style: TextStyle(color: colors.textMuted)),
          ),
        ],
      );
    }

    if (feed.errorText.isNotEmpty && feed.posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.error_outline, size: 42, color: colors.primary),
          const SizedBox(height: 14),
          Text(
            feed.errorText,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 18),
          Center(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors.primary),
              onPressed: () => _loadPosts(mode: mode, jumpTop: true),
              child: const Text('重新加载'),
            ),
          ),
        ],
      );
    }

    if (feed.posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 180),
          Center(
            child: Text(
              '暂无帖子，下拉刷新试试',
              style: TextStyle(color: colors.textMuted),
            ),
          ),
        ],
      );
    }

    final notice = _homeNotice;
    final showNotice =
        notice != null && notice.visible && !_hideHomeNoticeThisSession;
    final extraCount = (showNotice ? 1 : 0) + (feed.loadingMore ? 1 : 0);

    return ListView.builder(
      controller: feed.scrollController,
      cacheExtent: 160,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 86),
      itemCount: feed.posts.length + extraCount,
      itemBuilder: (context, index) {
        if (showNotice && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _HomeNoticeCard(
              notice: notice,
              onTap: () => _handleNoticeTap(notice),
              onClose: () => setState(() => _hideHomeNoticeThisSession = true),
            ),
          );
        }

        final postIndex = index - (showNotice ? 1 : 0);
        if (postIndex >= feed.posts.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              ),
            ),
          );
        }
        final post = feed.posts[postIndex];
        final isRead = ReadHistoryService.instance.isRead(post.tid);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: PostCard(
            post: post,
            mode: mode,
            isRead: isRead,
            onTap: () => _openPost(post, postIndex),
          ),
        );
      },
    );
  }
}

class _FloatingCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _FloatingCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primarySoft,
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.28),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: colors.primary, size: 23),
        ),
      ),
    );
  }
}

// ─── 顶部 Tab 栏 ──────────────────────────────────────────

class _BrowseTopBar extends StatelessWidget {
  final SortMode mode;
  final PageController pageController;
  final ValueChanged<SortMode> onModeChanged;
  final VoidCallback onSearch;
  final VoidCallback onFilter;
  final VoidCallback onPublish;

  const _BrowseTopBar({
    required this.mode,
    required this.pageController,
    required this.onModeChanged,
    required this.onSearch,
    required this.onFilter,
    required this.onPublish,
  });

  double _currentPageValue() {
    final fallback = _homeModes.indexOf(mode).toDouble();
    if (!pageController.hasClients) return fallback;
    final page = pageController.page;
    if (page == null) return fallback;
    return page.clamp(0.0, (_homeModes.length - 1).toDouble()).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Container(
      height: 62,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.headerStart, colors.headerEnd],
        ),
        border: Border(bottom: BorderSide(color: colors.divider, width: 0.7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.22),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedBuilder(
                    animation: pageController,
                    builder: (context, _) {
                      final tabWidth = constraints.maxWidth / _homeModes.length;
                      final page = _currentPageValue();
                      return Stack(
                        children: [
                          Positioned(
                            left: page * tabWidth,
                            top: 0,
                            bottom: 0,
                            width: tabWidth,
                            child: Container(
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (int i = 0; i < _homeModes.length; i++)
                                Expanded(
                                  child: _TopTab(
                                    text: _homeModes[i].label,
                                    selectedAmount: (1 - (page - i).abs())
                                        .clamp(0.0, 1.0)
                                        .toDouble(),
                                    onTap: () => onModeChanged(_homeModes[i]),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 9),
          _TopCircleButton(icon: Icons.tune_rounded, onTap: onFilter),
          const SizedBox(width: 8),
          _TopCircleButton(icon: Icons.search_rounded, onTap: onSearch),
          const SizedBox(width: 8),
          _TopCircleButton(icon: Icons.edit_rounded, onTap: onPublish),
        ],
      ),
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopCircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Material(
      color: colors.primarySoft,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 20, color: colors.primary),
        ),
      ),
    );
  }
}


class _TopTab extends StatelessWidget {
  final String text;
  final double selectedAmount;
  final VoidCallback onTap;

  const _TopTab({
    required this.text,
    required this.selectedAmount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final activeColor = Color.lerp(
      colors.textSecondary,
      Colors.white,
      selectedAmount,
    )!;
    final weight = selectedAmount > 0.5 ? FontWeight.w700 : FontWeight.w600;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: weight,
            color: activeColor,
          ),
        ),
      ),
    );
  }
}

class _HomeNoticeCard extends StatelessWidget {
  final HomeNotice notice;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _HomeNoticeCard({
    required this.notice,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final clickable =
        notice.action == 'popup' ||
        notice.action == 'dialog' ||
        (notice.url.isNotEmpty &&
            (notice.action == 'open' || notice.action == 'copy'));
    final colors = zybColors(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: clickable ? onTap : null,
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.22),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.campaign_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  notice.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭公告',
                onPressed: onClose,
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: colors.textMuted,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                splashRadius: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 帖子卡片 ─────────────────────────────────────────────

class _ForumFilterChip extends StatelessWidget {
  final ForumConfig forum;
  final bool selected;
  final VoidCallback onTap;

  const _ForumFilterChip({
    required this.forum,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Material(
      color: selected
          ? forum.color.withValues(alpha: 0.14)
          : colors.surfaceSoft,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? forum.color.withValues(alpha: 0.42)
                  : colors.cardBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 15,
                color: selected ? forum.color : colors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                forum.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? forum.color : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  final ZkPost post;
  final SortMode mode;
  final bool isRead;
  final bool centerTime;
  final VoidCallback onTap;

  const PostCard({
    super.key,
    required this.post,
    required this.mode,
    required this.isRead,
    this.centerTime = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isRead ? colors.textMuted : colors.textPrimary;
    final authorColor = colors.textSecondary;
    final subColor = colors.textMuted;
    final forumColor = forumDisplayColor(post.fid, post.forumName);
    final forumDisplayName = post.forumName.trim().isNotEmpty
        ? post.forumName.trim()
        : (post.fid > 0
            ? (browseForums.where((f) => f.fid == post.fid).isNotEmpty
                ? browseForums.firstWhere((f) => f.fid == post.fid).name
                : '')
            : '');

    return Material(
      color: isDark ? colors.surface : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
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
                : [
                    const BoxShadow(color: Colors.transparent),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                post.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.8,
                  height: 1.22,
                  fontWeight: FontWeight.w500,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      post.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.15,
                        color: authorColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 75,
                    child: _ForumPill(name: forumDisplayName, color: forumColor),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 75,
                    child: Text(
                      _displayTime(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: centerTime ? TextAlign.center : TextAlign.left,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.15,
                        color: subColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${post.replies}/${post.views}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.15,
                        color: subColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayTime() {
    if (mode == SortMode.latestReply) {
      final lastReply = formatTime(parseZkTime(post.lastReplyTime));
      return lastReply.isNotEmpty
          ? lastReply
          : formatTime(parseZkTime(post.postTime));
    }
    return _absoluteTime(post.postTime);
  }

  String _absoluteTime(String raw) {
    final dt = parseZkTime(raw);
    if (dt == null) return raw;
    final trimmed = raw.trim();
    final hasTimePart = RegExp(r'\d{1,2}:\d{2}').hasMatch(trimmed);
    if (!hasTimePart) {
      return '${dt.month}-${dt.day}';
    }
    return '${dt.month}-${dt.day} ${_pad2(dt.hour)}:${_pad2(dt.minute)}';
  }

  String _pad2(int value) => value.toString().padLeft(2, '0');
}

class _ForumPill extends StatelessWidget {
  final String name;
  final Color color;

  const _ForumPill({required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        name.trim(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.15,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class NativeSearchPage extends StatefulWidget {
  final String keyword;

  const NativeSearchPage({super.key, required this.keyword});

  @override
  State<NativeSearchPage> createState() => _NativeSearchPageState();
}

class _NativeSearchPageState extends State<NativeSearchPage> {
  final _api = OfficialApiService();
  final _blacklist = BlacklistService();
  final _scrollController = ScrollController();
  final List<ZkPost> _posts = [];
  String _searchId = '';
  String _errorText = '';
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    FilterService.instance.addListener(_handleFilterChanged);
    _load(reset: true);
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
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _errorText = '';
        _page = 1;
        _searchId = '';
        _hasMore = true;
      });
    } else {
      if (_loadingMore || !_hasMore) return;
      setState(() => _loadingMore = true);
    }

    final requestedPage = reset ? 1 : _page + 1;
    try {
      final results = await Future.wait([
        _api.searchPosts(
          keyword: widget.keyword,
          page: requestedPage,
          searchId: reset ? '' : _searchId,
        ),
        _blacklist.load(),
      ]);
      final result = results[0] as SearchPostsResult;
      final blocked = results[1] as Set<String>;
      if (!mounted) return;
      final existing = reset
          ? <String>{}
          : _posts.map((post) => post.tid).toSet();
      final fresh = result.posts
          .where((post) =>
              !blocked.contains(post.authorId) &&
              !FilterService.instance.isPostBlocked(post))
          .where((post) => existing.add(post.tid))
          .toList();
      setState(() {
        if (reset) _posts.clear();
        _posts.addAll(fresh);
        _searchId = result.searchId;
        _page = requestedPage;
        _hasMore = result.posts.isNotEmpty && result.searchId.isNotEmpty;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _errorText = error.toString();
      });
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

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text('搜索: ${widget.keyword}')),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(ZybColors colors) {
    if (_loading && _posts.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }
    if (_errorText.isNotEmpty && _posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 48, color: colors.textMuted),
              const SizedBox(height: 12),
              Text(
                _errorText,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => _load(reset: true),
                child: const Text('重试'),
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
              Icons.manage_search_rounded,
              size: 52,
              color: colors.textMuted,
            ),
            const SizedBox(height: 12),
            Text('没有找到相关帖子', style: TextStyle(color: colors.textMuted)),
          ],
        ),
      );
    }
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
              mode: SortMode.latestPost,
              isRead: ReadHistoryService.instance.isRead(post.tid),
              onTap: () => _openPost(post),
            ),
          );
        },
      ),
    );
  }
}

// ─── 搜索弹窗 ─────────────────────────────────────────────

class _SearchSheet extends StatefulWidget {
  final ValueChanged<String> onSubmit;
  const _SearchSheet({required this.onSubmit});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _controller = TextEditingController();
  List<String> _history = [];
  static const _historyKey = 'zyb_search_history';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey);
    if (list != null && mounted) {
      setState(() {
        _history = list;
      });
    }
  }

  Future<void> _saveHistory(String keyword) async {
    final next = List<String>.from(_history);
    next.remove(keyword);
    next.insert(0, keyword);
    if (next.length > 10) {
      next.removeRange(10, next.length);
    }
    setState(() {
      _history = next;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, next);
  }

  Future<void> _clearHistory() async {
    HapticService.instance.lightImpact();
    setState(() {
      _history = [];
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? text]) {
    final keyword = (text ?? _controller.text).trim();
    if (keyword.isEmpty) return;
    _saveHistory(keyword);
    Navigator.pop(context);
    widget.onSubmit(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '搜索帖子',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _submit(),
                  style: TextStyle(color: colors.textPrimary),
                  cursorColor: colors.primary,
                  decoration: InputDecoration(
                    hintText: '输入关键词',
                    hintStyle: TextStyle(color: colors.textMuted),
                    filled: true,
                    fillColor: colors.surfaceSoft,
                    prefixIcon: Icon(Icons.search_rounded, color: colors.textMuted),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.clear_rounded,
                              size: 18,
                              color: colors.textMuted,
                            ),
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _submit(),
                    child: const Text(
                      '搜索',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '历史搜索',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textMuted,
                        ),
                      ),
                      GestureDetector(
                        onTap: _clearHistory,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                size: 14,
                                color: colors.textMuted,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '清空',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _history.map((item) {
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            HapticService.instance.selectionClick();
                            _submit(item);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceSoft,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: colors.divider.withValues(alpha: 0.6),
                                width: 0.6,
                              ),
                            ),
                            child: Text(
                              item,
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
