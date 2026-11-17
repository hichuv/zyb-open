import '../utils/helpers.dart';

class PrivateConversation {
  final String userId;
  final String userName;
  final String avatar;
  final String messageHtml;
  final String lastDateline;
  final int unread;
  final int messageCount;
  final int conversationId;

  const PrivateConversation({
    required this.userId,
    required this.userName,
    required this.avatar,
    required this.messageHtml,
    required this.lastDateline,
    required this.unread,
    required this.messageCount,
    required this.conversationId,
  });

  factory PrivateConversation.fromJson(Map<String, dynamic> json) =>
      PrivateConversation(
        userId: _text(json['touid']),
        userName: _text(json['tousername']),
        avatar: _avatar(json['toavatar'] ?? json['fromavatar']),
        messageHtml: _text(json['message']),
        lastDateline: _text(json['lastdateline']),
        unread: toInt(_text(json['noread'])),
        messageCount: toInt(_text(json['pmnum'])),
        conversationId: toInt(_text(json['plid'])),
      );
}

class PrivateMessage {
  final String toUserId;
  final String toUserName;
  final String fromAvatar;
  final String toAvatar;
  final String messageHtml;
  final String dateline;
  final String conversationId;

  const PrivateMessage({
    required this.toUserId,
    required this.toUserName,
    required this.fromAvatar,
    required this.toAvatar,
    required this.messageHtml,
    required this.dateline,
    required this.conversationId,
  });

  factory PrivateMessage.fromJson(Map<String, dynamic> json) => PrivateMessage(
    toUserId: _text(json['touid']),
    toUserName: _text(json['tousername']),
    fromAvatar: _avatar(json['fromavatar']),
    toAvatar: _avatar(json['toavatar']),
    messageHtml: _text(json['message']),
    dateline: _text(json['lastdateline']),
    conversationId: _text(json['plid']),
  );
}

String _text(dynamic value) => value?.toString() ?? '';

String _avatar(dynamic value) {
  if (value is Map) {
    for (final key in const [
      'data-echo',
      'data-original',
      'data-src',
      'data-lazyload',
      'file',
      'src',
      'url',
      'avatar',
    ]) {
      final candidate = avatarUrl(_text(value[key]));
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }

  return avatarUrl(_text(value));
}
