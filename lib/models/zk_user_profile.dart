/// 用户资料
class ZkUserProfile {
  final String displayName;
  final String avatarUrl;
  final String groupName;
  final String guoguo;
  final String threads;
  final String replies;
  final String favorites;
  final String unreadPm;

  const ZkUserProfile({
    required this.displayName,
    required this.avatarUrl,
    required this.groupName,
    required this.guoguo,
    required this.threads,
    required this.replies,
    required this.favorites,
    required this.unreadPm,
  });
}
