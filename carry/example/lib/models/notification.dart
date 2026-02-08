/// A notification for user activity (likes, comments, follows).
///
/// Named [BuzzNotification] to avoid conflict with Flutter's Notification class.
class BuzzNotification {
  BuzzNotification({
    required this.id,
    required this.userId,
    this.type,
    this.actorId,
    this.targetId,
    this.read = false,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  factory BuzzNotification.fromJson(Map<String, dynamic> json) =>
      BuzzNotification(
        id: json['id'] as String,
        userId: json['userId'] as String,
        type: json['type'] as String?,
        actorId: json['actorId'] as String?,
        targetId: json['targetId'] as String?,
        read: json['read'] as bool? ?? false,
        createdAt: json['createdAt'] as int?,
      );

  final String id;

  /// The user who receives this notification.
  final String userId;

  /// Notification type: 'like', 'comment', or 'follow'.
  final String? type;

  /// The user who triggered this notification.
  final String? actorId;

  /// The target (post ID for like/comment, user ID for follow).
  final String? targetId;

  /// Whether this notification has been read.
  final bool read;

  final int createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'type': type,
        'actorId': actorId,
        'targetId': targetId,
        'read': read,
        'createdAt': createdAt,
      };

  BuzzNotification copyWith({
    String? id,
    String? userId,
    String? type,
    String? actorId,
    String? targetId,
    bool? read,
    int? createdAt,
  }) =>
      BuzzNotification(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        type: type ?? this.type,
        actorId: actorId ?? this.actorId,
        targetId: targetId ?? this.targetId,
        read: read ?? this.read,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BuzzNotification && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'BuzzNotification($id: $type from $actorId)';
}
