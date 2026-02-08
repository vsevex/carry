import 'dart:async';

import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../models/post.dart';
import '../store/buzz_store.dart';
import '../utils/time_format.dart';
import '../widgets/comment_tile.dart';
import '../widgets/like_button.dart';
import '../widgets/user_avatar.dart';

/// Full post view with comments and a comment composer.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.postId,
    this.onNavigateToProfile,
  });

  final String postId;
  final void Function(String userId)? onNavigateToProfile;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _store = BuzzStore.instance;
  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();

  Post? _post;
  List<Comment> _comments = [];

  StreamSubscription? _postsSub;
  StreamSubscription? _commentsSub;
  StreamSubscription? _likesSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _postsSub = _store.posts.watch().listen((_) => _loadData());
    _commentsSub = _store.comments.watch().listen((_) => _loadData());
    _likesSub = _store.likes.watch().listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _loadData() {
    if (!mounted) return;
    setState(() {
      _post = _store.posts.get(widget.postId);
      _comments = _store.comments.where((c) => c.postId == widget.postId)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
  }

  @override
  void dispose() {
    _postsSub?.cancel();
    _commentsSub?.cancel();
    _likesSub?.cancel();
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  void _submitComment() {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    _store.addComment(widget.postId, text);
    _commentCtrl.clear();
    _commentFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_post == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Post not found')),
      );
    }

    final author = _store.getUser(_post!.authorId);
    final likeCount = _store.getLikeCount(_post!.id);
    final isLiked = _store.hasLiked(_post!.id);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                // Post content
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Author
                      Row(
                        children: [
                          UserAvatar(
                            user: author,
                            radius: 22,
                            onTap: () => widget.onNavigateToProfile
                                ?.call(_post!.authorId),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(author?.name ?? 'Unknown',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15)),
                                Text(
                                  '@${author?.username ?? 'unknown'} · ${formatTimeAgo(_post!.createdAt)}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Content
                      Text(
                        _post!.content,
                        style: const TextStyle(fontSize: 16, height: 1.5),
                      ),
                      if (_post!.edited) ...[
                        const SizedBox(height: 4),
                        Text('(edited)',
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic)),
                      ],

                      const SizedBox(height: 16),

                      // Like row
                      Row(
                        children: [
                          LikeButton(
                            isLiked: isLiked,
                            count: likeCount,
                            onTap: () => _store.toggleLike(_post!.id, 'post'),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.chat_bubble_outline,
                              size: 19, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text('${_comments.length}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Comments header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'Comments',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant),
                  ),
                ),

                // Comments list
                if (_comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No comments yet. Be the first!',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  ..._comments.map((c) => CommentTile(
                        comment: c,
                        onAuthorTap: (userId) =>
                            widget.onNavigateToProfile?.call(userId),
                      )),
                const SizedBox(height: 80),
              ],
            ),
          ),

          // Comment composer
          _buildCommentInput(context),
        ],
      ),
    );
  }

  Widget _buildCommentInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentCtrl,
              focusNode: _commentFocus,
              decoration: InputDecoration(
                hintText: 'Write a comment...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _submitComment(),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send, color: colorScheme.primary),
            onPressed: _submitComment,
          ),
        ],
      ),
    );
  }
}
