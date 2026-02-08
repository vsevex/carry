/// A like on a post or comment.
class Like {
  Like({
    required this.id,
    required this.userId,
    required this.targetId,
    this.targetType = 'post',
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  factory Like.fromJson(Map<String, dynamic> json) => Like(
        id: json['id'] as String,
        userId: json['userId'] as String,
        targetId: json['targetId'] as String,
        targetType: json['targetType'] as String? ?? 'post',
        createdAt: json['createdAt'] as int?,
      );

  final String id;
  final String userId;
  final String targetId;

  /// 'post' or 'comment'
  final String targetType;
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'targetId': targetId,
        'targetType': targetType,
        'createdAt': createdAt,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Like && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Like($id: $userId -> $targetId)';
}
