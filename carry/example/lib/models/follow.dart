/// A follow relationship between two users.
class Follow {
  Follow({
    required this.id,
    required this.followerId,
    required this.followingId,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  factory Follow.fromJson(Map<String, dynamic> json) => Follow(
        id: json['id'] as String,
        followerId: json['followerId'] as String,
        followingId: json['followingId'] as String,
        createdAt: json['createdAt'] as int?,
      );

  final String id;
  final String followerId;
  final String followingId;
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'followerId': followerId,
        'followingId': followingId,
        'createdAt': createdAt,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Follow && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Follow($followerId -> $followingId)';
}
