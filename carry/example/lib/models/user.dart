import 'dart:convert';

/// A user profile in the Buzz social app.
class User {
  User({
    required this.id,
    required this.username,
    this.displayName,
    this.bio,
    this.avatarUrl,
    Map<String, dynamic>? stats,
    int? createdAt,
  })  : stats = stats ?? {'followers': 0, 'following': 0, 'posts': 0},
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
        bio: json['bio'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        stats: _decodeJsonMap(json['stats']),
        createdAt: json['createdAt'] as int?,
      );

  final String id;
  final String username;
  final String? displayName;
  final String? bio;
  final String? avatarUrl;
  final Map<String, dynamic> stats;
  final int createdAt;

  /// Display name or fallback to username.
  String get name => displayName?.isNotEmpty == true ? displayName! : username;

  /// First letter of display name for avatar.
  String get initial => name.isNotEmpty ? name[0].toUpperCase() : '?';

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'displayName': displayName,
        'bio': bio,
        'avatarUrl': avatarUrl,
        'stats': stats,
        'createdAt': createdAt,
      };

  User copyWith({
    String? id,
    String? username,
    String? displayName,
    String? bio,
    String? avatarUrl,
    Map<String, dynamic>? stats,
    int? createdAt,
  }) =>
      User(
        id: id ?? this.id,
        username: username ?? this.username,
        displayName: displayName ?? this.displayName,
        bio: bio ?? this.bio,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        stats: stats ?? this.stats,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is User && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'User($id: @$username)';

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
}
