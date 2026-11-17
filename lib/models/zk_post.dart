/// 帖子列表项
class ZkPost {
  final String tid;
  final String title;
  final String url;
  final String author;
  final String authorId;
  final String postTime;
  final String lastReplyTime;
  final int replies;
  final int views;
  final int fid;
  final String forumName;
  final String favId;

  const ZkPost({
    required this.tid,
    required this.title,
    required this.url,
    required this.author,
    this.authorId = '',
    required this.postTime,
    required this.lastReplyTime,
    required this.replies,
    required this.views,
    required this.fid,
    required this.forumName,
    this.favId = '',
  });
}
