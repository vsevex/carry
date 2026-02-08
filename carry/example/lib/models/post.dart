import 'dart:convert';

/// A post in the Buzz social feed.
class Post {
  Post({
    required this.id,
    required this.authorId,
    required this.content,
    this.media,
    Map<String, dynamic>? stats,
    this.edited = false,
    int? createdAt,
  })  : stats = stats ?? {'likes': 0, 'comments': 0},
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'] as String,
        authorId: json['authorId'] as String,
        content: json['content'] as String,
        media: _decodeJsonList(json['media']),
        stats: _decodeJsonMap(json['stats']),
        edited: json['edited'] as bool? ?? false,
        createdAt: json['createdAt'] as int?,
      );

  final String id;
  final String authorId;
  final String content;
  final List<dynamic>? media;
  final Map<String, dynamic> stats;
  final bool edited;
  final int createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorId': authorId,
        'content': content,
        'media': media,
        'stats': stats,
        'edited': edited,
        'createdAt': createdAt,
      };

  Post copyWith({
    String? id,
    String? authorId,
    String? content,
    List<dynamic>? media,
    Map<String, dynamic>? stats,
    bool? edited,
    int? createdAt,
  }) =>
      Post(
        id: id ?? this.id,
        authorId: authorId ?? this.authorId,
        content: content ?? this.content,
        media: media ?? this.media,
        stats: stats ?? this.stats,
        edited: edited ?? this.edited,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Post && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Post($id by $authorId)';

  /// Decode a JSON field that may come back as a String or Map from the engine.
  static Map<String, dynamic>? _decodeJsonMap(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is String) {
      try {
        return Map<String, dynamic>.from(jsonDecode(value) as Map);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Decode a JSON field that may come back as a String or List from the engine.
  static List<dynamic>? _decodeJsonList(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is List) {
      return value;
    }
    if (value is String) {
      try {
        return jsonDecode(value) as List<dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
