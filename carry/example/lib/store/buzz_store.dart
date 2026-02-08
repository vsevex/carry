import 'dart:async';
import 'dart:io';

import 'package:carry/carry.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/comment.dart';
import '../models/follow.dart';
import '../models/like.dart';
import '../models/notification.dart';
import '../models/post.dart';
import '../models/user.dart';
import 'schema.dart';

/// Server URL - use localhost for desktop, 10.0.2.2 for Android emulator.
const kServerUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'http://localhost:3000',
);

/// WebSocket URL derived from server URL.
String get kWebSocketUrl {
  final uri = Uri.parse(kServerUrl);
  final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
  return '$wsScheme://${uri.host}:${uri.port}/sync/ws';
}

const _uuid = Uuid();

/// Singleton store managing all Buzz data via the Carry SDK.
class BuzzStore {
  BuzzStore._();

  static BuzzStore? _instance;

  /// Get the singleton instance.
  static BuzzStore get instance {
    _instance ??= BuzzStore._();
    return _instance!;
  }

  SyncStore? _store;
  String _nodeId = '';
  String? _currentUserId;
  Directory? _dataDir;
  WebSocketTransport? _wsTransport;

  // Connection state
  final _connectionController =
      StreamController<WebSocketConnectionState>.broadcast();
  StreamSubscription<WebSocketConnectionState>? _connectionSub;
  WebSocketConnectionState _connectionState =
      WebSocketConnectionState.disconnected;

  // Typed collections
  late Collection<User> users;
  late Collection<Post> posts;
  late Collection<Comment> comments;
  late Collection<Like> likes;
  late Collection<Follow> follows;
  late Collection<BuzzNotification> notifications;

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------

  bool get isInitialized => _store != null;
  String get nodeId => _nodeId;
  String? get currentUserId => _currentUserId;
  SyncStore? get store => _store;
  WebSocketConnectionState get connectionState => _connectionState;
  Stream<WebSocketConnectionState> get connectionStateStream =>
      _connectionController.stream;
  int get pendingCount => _store?.pendingCount ?? 0;

  /// Current user profile, or null if not yet set up.
  User? get currentUser =>
      _currentUserId != null ? users.get(_currentUserId!) : null;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_store != null) {
      return;
    }

    // 1. App data directory
    final appDir = await getApplicationDocumentsDirectory();
    _dataDir = Directory('${appDir.path}/buzz_data');
    if (!await _dataDir!.exists()) {
      await _dataDir!.create(recursive: true);
    }

    // 2. Persistent node ID
    final nodeIdFile = File('${_dataDir!.path}/node_id.txt');
    if (await nodeIdFile.exists()) {
      _nodeId = await nodeIdFile.readAsString();
    } else {
      _nodeId = 'device_${_uuid.v4().substring(0, 8)}';
      await nodeIdFile.writeAsString(_nodeId);
    }

    // 3. Load persisted current user ID
    final userIdFile = File('${_dataDir!.path}/user_id.txt');
    if (await userIdFile.exists()) {
      _currentUserId = await userIdFile.readAsString();
    }

    // 4. Transport
    _wsTransport = WebSocketTransport(
      url: kWebSocketUrl,
      nodeId: _nodeId,
    );
    _connectionSub = _wsTransport!.connectionState.listen((state) {
      _connectionState = state;
      _connectionController.add(state);
    });

    // 5. SyncStore
    _store = SyncStore(
      schema: buzzSchema,
      nodeId: _nodeId,
      persistence: FilePersistenceAdapter(directory: _dataDir!),
      transport: _wsTransport,
    );

    await _store!.init();

    // 6. Collections
    _initCollections();

    // 7. Connect WebSocket
    try {
      await _store!.connectWebSocket();
    } catch (_) {
      // Offline is fine
    }
  }

  void _initCollections() {
    users = _store!.collection<User>(
      'users',
      fromJson: User.fromJson,
      toJson: (u) => u.toJson(),
      getId: (u) => u.id,
    );
    posts = _store!.collection<Post>(
      'posts',
      fromJson: Post.fromJson,
      toJson: (p) => p.toJson(),
      getId: (p) => p.id,
    );
    comments = _store!.collection<Comment>(
      'comments',
      fromJson: Comment.fromJson,
      toJson: (c) => c.toJson(),
      getId: (c) => c.id,
    );
    likes = _store!.collection<Like>(
      'likes',
      fromJson: Like.fromJson,
      toJson: (l) => l.toJson(),
      getId: (l) => l.id,
    );
    follows = _store!.collection<Follow>(
      'follows',
      fromJson: Follow.fromJson,
      toJson: (f) => f.toJson(),
      getId: (f) => f.id,
    );
    notifications = _store!.collection<BuzzNotification>(
      'notifications',
      fromJson: BuzzNotification.fromJson,
      toJson: (n) => n.toJson(),
      getId: (n) => n.id,
    );
  }

  // ---------------------------------------------------------------------------
  // Profile Management
  // ---------------------------------------------------------------------------

  /// Create the local user profile (first-time setup).
  Future<User> createProfile({
    required String username,
    required String displayName,
  }) async {
    final user = User(
      id: _uuid.v4(),
      username: username,
      displayName: displayName,
    );
    users.insert(user);

    _currentUserId = user.id;
    final userIdFile = File('${_dataDir!.path}/user_id.txt');
    await userIdFile.writeAsString(user.id);

    return user;
  }

  /// Update the current user's profile.
  void updateProfile({String? displayName, String? bio}) {
    final user = currentUser;
    if (user == null) {
      return;
    }
    users.update(
      user.copyWith(
        displayName: displayName ?? user.displayName,
        bio: bio ?? user.bio,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Posts
  // ---------------------------------------------------------------------------

  /// Create a new post.
  Post createPost(String content) {
    final post = Post(
      id: _uuid.v4(),
      authorId: _currentUserId!,
      content: content,
    );
    posts.insert(post);
    return post;
  }

  /// Edit a post's content.
  void editPost(String postId, String newContent) {
    final post = posts.get(postId);
    if (post == null) {
      return;
    }
    posts.update(post.copyWith(content: newContent, edited: true));
  }

  /// Delete a post and its related likes and comments.
  void deletePost(String postId) {
    // Delete related comments
    for (final c in comments.where((c) => c.postId == postId)) {
      comments.delete(c.id);
    }
    // Delete related likes
    for (final l
        in likes.where((l) => l.targetId == postId && l.targetType == 'post')) {
      likes.delete(l.id);
    }
    posts.delete(postId);
  }

  // ---------------------------------------------------------------------------
  // Likes
  // ---------------------------------------------------------------------------

  /// Whether the current user has liked the given target.
  bool hasLiked(String targetId) {
    return likes
        .where((l) => l.userId == _currentUserId && l.targetId == targetId)
        .isNotEmpty;
  }

  /// Get like count for a target.
  int getLikeCount(String targetId) {
    return likes.where((l) => l.targetId == targetId).length;
  }

  /// Toggle like on a post or comment.
  void toggleLike(String targetId, String targetType) {
    final existing = likes
        .where((l) => l.userId == _currentUserId && l.targetId == targetId);

    if (existing.isNotEmpty) {
      // Unlike
      likes.delete(existing.first.id);
    } else {
      // Like
      likes.insert(
        Like(
          id: _uuid.v4(),
          userId: _currentUserId!,
          targetId: targetId,
          targetType: targetType,
        ),
      );

      // Create notification for target author
      if (targetType == 'post') {
        final post = posts.get(targetId);
        if (post != null && post.authorId != _currentUserId) {
          _createNotification(
            userId: post.authorId,
            type: 'like',
            targetId: targetId,
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Comments
  // ---------------------------------------------------------------------------

  /// Get comment count for a post.
  int getCommentCount(String postId) {
    return comments.where((c) => c.postId == postId).length;
  }

  /// Add a comment to a post.
  Comment addComment(String postId, String content) {
    final comment = Comment(
      id: _uuid.v4(),
      postId: postId,
      authorId: _currentUserId!,
      content: content,
    );
    comments.insert(comment);

    // Notify post author
    final post = posts.get(postId);
    if (post != null && post.authorId != _currentUserId) {
      _createNotification(
        userId: post.authorId,
        type: 'comment',
        targetId: postId,
      );
    }

    return comment;
  }

  /// Delete a comment.
  void deleteComment(String commentId) {
    comments.delete(commentId);
  }

  // ---------------------------------------------------------------------------
  // Follows
  // ---------------------------------------------------------------------------

  /// Whether the current user follows the given user.
  bool isFollowing(String userId) {
    return follows
        .where((f) => f.followerId == _currentUserId && f.followingId == userId)
        .isNotEmpty;
  }

  /// Get follower count for a user.
  int getFollowerCount(String userId) {
    return follows.where((f) => f.followingId == userId).length;
  }

  /// Get following count for a user.
  int getFollowingCount(String userId) {
    return follows.where((f) => f.followerId == userId).length;
  }

  /// Toggle follow on a user.
  void toggleFollow(String userId) {
    final existing = follows.where(
      (f) => f.followerId == _currentUserId && f.followingId == userId,
    );

    if (existing.isNotEmpty) {
      // Unfollow
      follows.delete(existing.first.id);
    } else {
      // Follow
      follows.insert(
        Follow(
          id: _uuid.v4(),
          followerId: _currentUserId!,
          followingId: userId,
        ),
      );

      // Notify
      if (userId != _currentUserId) {
        _createNotification(
          userId: userId,
          type: 'follow',
          targetId: _currentUserId,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  /// Get unread notification count for the current user.
  int get unreadNotificationCount {
    return notifications
        .where((n) => n.userId == _currentUserId && !n.read)
        .length;
  }

  /// Mark all notifications as read for the current user.
  void markAllNotificationsRead() {
    final unread =
        notifications.where((n) => n.userId == _currentUserId && !n.read);
    for (final n in unread) {
      notifications.update(n.copyWith(read: true));
    }
  }

  void _createNotification({
    required String userId,
    required String type,
    String? targetId,
  }) {
    notifications.insert(
      BuzzNotification(
        id: _uuid.v4(),
        userId: userId,
        type: type,
        actorId: _currentUserId,
        targetId: targetId,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Computed Queries
  // ---------------------------------------------------------------------------

  /// Look up a user by ID.
  User? getUser(String userId) => users.get(userId);

  /// Get posts by a specific user, newest first.
  List<Post> getPostsByUser(String userId) {
    return posts.where((p) => p.authorId == userId)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Get post count for a user.
  int getPostCount(String userId) {
    return posts.where((p) => p.authorId == userId).length;
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  /// Trigger a manual sync with the server.
  Future<SyncResult> sync() async {
    if (_store == null) {
      return SyncResult.failed('Store not initialized');
    }
    return _store!.sync();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> close() async {
    _connectionSub?.cancel();
    _connectionController.close();
    await _store?.close();
    _store = null;
    _instance = null;
  }
}
