/// A comment on a post.
class Comment {
  Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.content,
    this.replyToId,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
        id: json['id'] as String,
        postId: json['postId'] as String,
        authorId: json['authorId'] as String,
        content: json['content'] as String,
        replyToId: json['replyToId'] as String?,
        createdAt: json['createdAt'] as int?,
      );

  final String id;
  final String postId;
  final String authorId;
  final String content;
  final String? replyToId;
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'postId': postId,
        'authorId': authorId,
        'content': content,
        'replyToId': replyToId,
        'createdAt': createdAt,
      };

  Comment copyWith({
    String? id,
    String? postId,
    String? authorId,
    String? content,
    String? replyToId,
    int? createdAt,
  }) =>
      Comment(
        id: id ?? this.id,
        postId: postId ?? this.postId,
        authorId: authorId ?? this.authorId,
        content: content ?? this.content,
        replyToId: replyToId ?? this.replyToId,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Comment && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Comment($id on $postId)';
}
