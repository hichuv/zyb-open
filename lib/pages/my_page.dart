import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/constants.dart';
import '../models/zk_user_profile.dart';
import '../services/api_service.dart';
import '../services/haptic_service.dart';
import '../services/official_api_service.dart';
import '../services/remote_config_service.dart';
import '../state/login_state.dart';
import '../theme/app_theme.dart';
import '../state/theme_state.dart';
import '../services/deepseek_service.dart';
import '../widgets/deepseek_config_dialog.dart';
import '../widgets/zyb_confirm_dialog.dart';
import '../widgets/zyb_feedback.dart';
import '../widgets/zyb_avatar.dart';
import 'filter_settings_page.dart';
import 'forum_posts_page.dart';
import 'login_page.dart';
import 'my_lists_page.dart';
import 'private_messages_page.dart';
import 'webview_page.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => MyPageState();
}

class MyPageState extends State<MyPage> {
  final ApiService _api = ApiService();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  String _uid = '';
  String _username = '';
  ZkUserProfile? _profile;
  bool _isFetching = false;
  bool _plusEnabled = false;
  AuthorAd? _authorAd;
  bool _aiEnabled = false;
  bool get _isLoggedIn =>
      (_uid.isNotEmpty && _uid != '0') ||
      _profile?.displayName.isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    loginStateVersion.addListener(_loadLoginState);
    _loadLoginState();
    _loadRemoteConfig();
    _loadAiEnabled();
  }

  Future<void> _loadAiEnabled() async {
    final enabled = await DeepSeekService().isAiEnabled();
    if (mounted) setState(() => _aiEnabled = enabled);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    loginStateVersion.removeListener(_loadLoginState);
    super.dispose();
  }

  /// 滚回顶部并触发刷新（供底部导航栏二次点击调用）
  void scrollToTopAndRefresh() {
    if (_scrollController.hasClients) {
      if (_scrollController.offset > 60) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ).then((_) {
          if (mounted) _refreshIndicatorKey.currentState?.show();
        });
      } else {
        _refreshIndicatorKey.currentState?.show();
      }
    } else {
      _refreshIndicatorKey.currentState?.show();
    }
  }

  Future<void> _loadRemoteConfig() async {
    final config = await RemoteConfigService.load();
    if (!mounted) return;
    setState(() => _authorAd = config.authorAd);
  }

  Future<void> _handleAdTap(AuthorAd ad) async {
    if (ad.action == 'copy') {
      final text = ad.copyText.isNotEmpty ? ad.copyText : ad.url;
      if (text.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          HapticService.instance.lightImpact();
          _toast('复制成功');
        }
      }
      return;
    }
    if (ad.action == 'open') {
      final uri = Uri.tryParse(ad.url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (ad.action == 'webview' || ad.url.isNotEmpty) {
      _openMobileWeb(ad.title.isNotEmpty ? ad.title : '活动详情', ad.url);
    }
  }

  Future<void> _loadLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _uid = prefs.getString('uid') ?? prefs.getString('discuz_uid') ?? '';
      _username = prefs.getString('username') ?? '';
    });
    final loggedIn =
        await _api.isLoggedIn() || await OfficialApiService().isAnyLoggedIn();
    if (!mounted) return;
    if (loggedIn || _isLoggedIn) {
      await _fetchProfile();
      await _loadPlusStatus();
    } else {
      setState(() => _plusEnabled = false);
    }
  }

  Future<void> _loadPlusStatus() async {
    final enabled = await _api.fetchPlusEnabled();
    if (!mounted) return;
    setState(() => _plusEnabled = enabled);
  }

  Future<void> _fetchProfile() async {
    if (_isFetching) return;
    setState(() => _isFetching = true);

    try {
      final profile = await _api.fetchMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        if (profile != null) {
          _username = profile.displayName;
        }
        _isFetching = false;
      });
      if (profile != null) {
        final prefs = await SharedPreferences.getInstance();
        if (profile.displayName.isNotEmpty) {
          await prefs.setString('username', profile.displayName);
        }
        if (profile.avatarUrl.isNotEmpty) {
          await prefs.setString('avatar_url', profile.avatarUrl);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isFetching = false);
    }
  }

  Future<void> _handleRefresh() async {
    await Future.wait([
      _fetchProfile(),
      _loadPlusStatus(),
      _loadRemoteConfig(),
    ]);
    if (mounted) {
      HapticService.instance.lightImpact();
      _toast('刷新成功');
    }
  }

  Future<void> _clearLoginState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('uid');
    await prefs.remove('discuz_uid');
    await prefs.remove('username');
    await prefs.remove('avatar_url');
    await prefs.remove('logged_in');
    await _api.clearCookies();

    if (!mounted) return;
    setState(() {
      _uid = '';
      _username = '';
      _profile = null;
      _plusEnabled = false;
    });

    _toast('已退出登录');
    notifyLoginStateChanged();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showZybConfirmDialog(
      context: context,
      title: '确认退出登录？',
      confirmText: '退出',
      cancelText: '取消',
      isDanger: true,
    );
    if (confirmed == true) {
      await _clearLoginState();
    }
  }

  Future<void> _openLogin() async {
    final result = await Navigator.push<bool>(
      context,
      zybHorizontalPageRoute<bool>(builder: (_) => const LoginPage()),
    );
    if (result == true) {
      await _loadLoginState();
    }
  }

  void _openMobileWeb(String title, String url) {
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => WebViewPage(url: url, title: title),
      ),
    );
  }

  void _openFruitLog() {
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => const WebViewPage(
          url: '$guoguoLogUrl&mobile=no',
          title: '果果明细',
          initialDesktopMode: true,
        ),
      ),
    );
  }

  void _openMyList(MyListType type) {
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(builder: (_) => MyListsPage(type: type)),
    );
  }

  Future<void> _openForum(int fid, String title) async {
    // 做任务赚果果官方无手机版，直接以电脑版网页打开，跳过原生列表
    if (fid == 11) {
      await Navigator.push(
        context,
        zybHorizontalPageRoute<void>(
          builder: (_) => WebViewPage(
            url: 'http://www.zuanke8.com/forum.php?mod=forumdisplay&fid=11',
            title: title,
            initialDesktopMode: true,
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => ForumPostsPage(fid: fid, title: title),
      ),
    );
  }


  void _openPrivateMessages() {
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => const PrivateMessagesPage(),
      ),
    );
  }

  void _openFilterSettings() {
    Navigator.push(
      context,
      zybHorizontalPageRoute<void>(
        builder: (_) => const FilterSettingsPage(),
      ),
    );
  }

  void _toast(String msg) {
    showZybFeedback(context, msg);
  }


  @override
  Widget build(BuildContext context) {
    final effectiveName = _profile?.displayName ?? '';
    final displayName = effectiveName.isNotEmpty
        ? effectiveName
        : (_isLoggedIn
              ? (_username.isNotEmpty ? _username : 'UID $_uid')
              : '登录账号');

    final groupText = _profile?.groupName ?? (_isLoggedIn ? '正在同步账号信息' : '请使用赚客吧账号登录');
    final fruitValue = _profile?.guoguo ?? (_isLoggedIn ? '--' : '0');
    final avatarUrl = _profile?.avatarUrl ?? '';
    final colors = zybColors(context);

    return SafeArea(
      child: Container(
        color: colors.background,
        child: Column(
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colors.headerStart, colors.headerEnd],
                ),
                border: Border(
                  bottom: BorderSide(color: colors.divider, width: 0.7),
                ),
              ),
              child: Center(
                child: Text(
                  '个人中心',
                  style: TextStyle(
                    fontSize: 16,
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                key: _refreshIndicatorKey,
                color: colors.primary,
                onRefresh: _handleRefresh,
                child: ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  children: [
                    // 1. 用户基础信息卡片（完全保留不改动）
                    _MineUserCard(
                      displayName: displayName,
                      avatarUrl: avatarUrl,
                      uid: _uid,
                      groupText: groupText,
                      fruitValue: fruitValue,
                      isLoggedIn: _isLoggedIn,
                      loading: _isFetching,
                      onAction: _isLoggedIn ? _confirmLogout : _openLogin,
                      onPlus: () => _openMobileWeb('PLUS', plusUrl),
                      onFruit: _openFruitLog,
                      plusEnabled: _isLoggedIn && _plusEnabled,
                    ),
                    const SizedBox(height: 6),

                    // 2. 论坛与个人互动整合卡片（告别碎片化浮岛）
                    _SectionCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ForumGrid(onNativeOpen: _openForum),
                          const SizedBox(height: 8),
                          Divider(
                            height: 1,
                            color: colors.divider.withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 8),
                          _MineInfoGrid(
                            onNativeOpen: _openMyList,
                            onPrivateMessages: _openPrivateMessages,
                            unreadPm: _profile?.unreadPm,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // 3. 功能与系统设置卡片（AI 助手、屏蔽设置、夜间模式、触感反馈统一收拢）
                    _SectionCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 5,
                      ),
                      child: Column(
                        children: [
                          _ActionTile(
                            icon: Icons.shield_outlined,
                            title: '屏蔽设置',
                            onTap: _openFilterSettings,
                          ),
                          Divider(height: 1, color: colors.divider),
                          _ActionTile(
                            icon: Icons.smart_toy_outlined,
                            title: 'AI 助手',
                            trailing: Switch.adaptive(
                              value: _aiEnabled,
                              activeTrackColor: colors.primary,
                              onChanged: (val) async {
                                HapticService.instance.lightImpact();
                                await DeepSeekService().setAiEnabled(val);
                                setState(() => _aiEnabled = val);
                              },
                            ),
                            onTap: () async {
                              await showDeepSeekConfigSheet(context);
                              _loadAiEnabled();
                            },
                          ),
                          Divider(height: 1, color: colors.divider),
                          AnimatedBuilder(
                            animation: appThemeController,
                            builder: (context, _) {
                              final isDark = appThemeController.isDark(context);
                              return _ActionTile(
                                icon: isDark
                                    ? Icons.dark_mode_rounded
                                    : Icons.light_mode_rounded,
                                title: '夜间模式',
                                trailing: Switch.adaptive(
                                  value: isDark,
                                  activeTrackColor: colors.primary,
                                  onChanged: (val) {
                                    HapticService.instance.lightImpact();
                                    appThemeController.setMode(
                                      val
                                          ? AppThemeMode.dark
                                          : AppThemeMode.light,
                                    );
                                  },
                                ),
                                onTap: () {
                                  HapticService.instance.lightImpact();
                                  appThemeController.setMode(
                                    isDark
                                        ? AppThemeMode.light
                                        : AppThemeMode.dark,
                                  );
                                },
                              );
                            },
                          ),
                          Divider(height: 1, color: colors.divider),
                          AnimatedBuilder(
                            animation: HapticService.instance,
                            builder: (context, _) {
                              final enabled = HapticService.instance.enabled;
                              return _ActionTile(
                                icon: Icons.vibration_rounded,
                                title: '触感反馈',
                                trailing: Switch.adaptive(
                                  value: enabled,
                                  activeTrackColor: colors.primary,
                                  onChanged: (val) {
                                    HapticService.instance.setEnabled(val);
                                  },
                                ),
                                onTap: () {
                                  HapticService.instance.setEnabled(!enabled);
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // 3.5. 预留远程广告位（平时完全隐藏 0 像素，云端开启时优雅展示）
                    if (_authorAd != null && _authorAd!.visible) ...[
                      _AuthorAdBanner(
                        ad: _authorAd!,
                        onTap: () => _handleAdTap(_authorAd!),
                      ),
                      const SizedBox(height: 6),
                    ],

                    // 4. 版本信息
                    Center(
                      child: Text(
                        appVersion,
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MineUserCard extends StatelessWidget {
  final String displayName;
  final String avatarUrl;
  final String uid;
  final String groupText;
  final String fruitValue;
  final bool isLoggedIn;
  final bool loading;
  final VoidCallback onAction;
  final VoidCallback onPlus;
  final VoidCallback onFruit;
  final bool plusEnabled;

  const _MineUserCard({
    required this.displayName,
    required this.avatarUrl,
    required this.uid,
    required this.groupText,
    required this.fruitValue,
    required this.isLoggedIn,
    required this.loading,
    required this.onAction,
    required this.onPlus,
    required this.onFruit,
    required this.plusEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final initial = displayName.isNotEmpty ? displayName.characters.first : '?';
    final colors = zybColors(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isLoggedIn ? null : onAction,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surface, colors.surfaceWarm],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          isLoggedIn && (avatarUrl.isNotEmpty || uid.isNotEmpty)
              ? ZybAvatar(url: avatarUrl, uid: uid, name: displayName, size: 66, radius: 14)
              : _fallback(isLoggedIn ? initial : null, colors),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  groupText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                const SizedBox(height: 7),
                GestureDetector(
                  onTap: onFruit,
                  child: Container(
                    height: 25,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: colors.primarySoft,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '果果：',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          fruitValue,
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: colors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: onPlus,
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: plusEnabled ? null : colors.surfaceSoft,
                    gradient: plusEnabled
                        ? const LinearGradient(
                            colors: [Color(0xFFFFF0B5), Color(0xFFFFC34D)],
                          )
                        : null,
                    boxShadow: plusEnabled
                        ? [
                            BoxShadow(
                              color: const Color(
                                0xFFD99A18,
                              ).withValues(alpha: 0.22),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '✦ PLUS',
                    style: TextStyle(
                      color: plusEnabled
                          ? const Color(0xFF7A4A00)
                          : colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(68, 38),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: loading ? null : onAction,
                child: loading
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(isLoggedIn ? '退出' : '登录'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _fallback(String? initial, ZybColors colors) {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.15),
          width: 0.8,
        ),
      ),
      alignment: Alignment.center,
      child: initial != null && initial.isNotEmpty
          ? Text(
              initial,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            )
          : Icon(
              Icons.person_rounded,
              size: 38,
              color: colors.primary.withValues(alpha: 0.7),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SectionCard({required this.child, required this.padding});

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ForumGrid extends StatelessWidget {
  final Future<void> Function(int fid, String title) onNativeOpen;

  const _ForumGrid({required this.onNativeOpen});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _PortalTile(
                iconText: '谈',
                title: '赚客大家谈',
                color: forumDisplayColor(15),
                onTap: () => onNativeOpen(15, '赚客大家谈'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PortalTile(
                iconText: '任',
                title: '任务赚果',
                color: forumDisplayColor(11),
                onTap: () => onNativeOpen(11, '做任务赚果果'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _PortalTile(
                iconText: '换',
                title: '赚品交换',
                color: forumDisplayColor(25),
                onTap: () => onNativeOpen(25, '赚品交换'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _PortalTile(
                iconText: '果',
                title: '果果换物',
                color: forumDisplayColor(31),
                onTap: () => onNativeOpen(31, '果果换物'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MineInfoGrid extends StatelessWidget {
  final void Function(MyListType type) onNativeOpen;
  final VoidCallback onPrivateMessages;
  final String? unreadPm;

  const _MineInfoGrid({
    required this.onNativeOpen,
    required this.onPrivateMessages,
    this.unreadPm,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread =
        unreadPm != null && unreadPm != '0' && unreadPm!.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: _MineInfoTile(
            icon: Icons.edit_note_rounded,
            title: '发布',
            onTap: () => onNativeOpen(MyListType.threads),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MineInfoTile(
            icon: Icons.chat_bubble_outline_rounded,
            title: '回复',
            onTap: () => onNativeOpen(MyListType.replies),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MineInfoTile(
            icon: Icons.bookmark_outline_rounded,
            title: '收藏',
            onTap: () => onNativeOpen(MyListType.favorites),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MineInfoTile(
            icon: Icons.mail_outline_rounded,
            title: '私信',
            hasBadge: hasUnread,
            onTap: onPrivateMessages,
          ),
        ),
      ],
    );
  }
}

class _PortalTile extends StatelessWidget {
  final String iconText;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _PortalTile({
    required this.iconText,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.cardBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              _SoftIcon(text: iconText, color: color, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MineInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool hasBadge;

  const _MineInfoTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.hasBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          height: 44, // 降为 44px
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: colors.cardBorder),
          ),
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: colors.primary),
                  const SizedBox(width: 4),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (hasBadge)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    width: 6.5,
                    height: 6.5,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorAdBanner extends StatelessWidget {
  final AuthorAd ad;
  final VoidCallback onTap;

  const _AuthorAdBanner({
    required this.ad,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    final hasImage = ad.imageUrl.trim().isNotEmpty;
    final hasTitle = ad.title.trim().isNotEmpty;
    final hasText = ad.text.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.22),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasImage)
                Image.network(
                  ad.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              if (hasTitle || hasText)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasTitle)
                              Text(
                                ad.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                            if (hasText) ...[
                              if (hasTitle) const SizedBox(height: 2),
                              Text(
                                ad.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '查看',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
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

class _SoftIcon extends StatelessWidget {
  final String text;
  final Color color;
  final double size;

  const _SoftIcon({
    required this.text,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size >= 30 ? 11 : 9),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: size >= 34 ? 17 : (size >= 30 ? 15 : 14),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData? icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _ActionTile({
    this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = zybColors(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 45, // 每一个设置项总行高严格锁定为 45px
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon ?? Icons.settings_rounded,
                size: 18,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (trailing != null)
              SizedBox(
                height: 28,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: trailing!,
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textMuted,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
