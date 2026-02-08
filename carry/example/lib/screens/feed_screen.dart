import 'dart:async';

import 'package:flutter/material.dart';

import '../models/post.dart';
import '../store/buzz_store.dart';
import '../widgets/post_card.dart';

/// The main home feed showing all posts, newest first.
class FeedScreen extends StatefulWidget {
  const FeedScreen(
      {super.key, this.onNavigateToProfile, this.onNavigateToPost});

  final void Function(String userId)? onNavigateToProfile;
  final void Function(String postId)? onNavigateToPost;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _store = BuzzStore.instance;
  List<Post> _posts = [];
  StreamSubscription? _postsSub;
  StreamSubscription? _likesSub;
  StreamSubscription? _commentsSub;

  @override
  void initState() {
    super.initState();
    _postsSub = _store.posts.watch().listen((posts) {
      if (mounted) {
        setState(() {
          _posts = posts..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
      }
    });
    // Rebuild when likes/comments change to update counts in PostCards.
    _likesSub = _store.likes.watch().listen((_) {
      if (mounted) setState(() {});
    });
    _commentsSub = _store.comments.watch().listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _postsSub?.cancel();
    _likesSub?.cancel();
    _commentsSub?.cancel();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    try {
      await _store.sync();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_posts.isEmpty) {
      return _buildEmpty(context);
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          return PostCard(
            post: post,
            onTap: () => widget.onNavigateToPost?.call(post.id),
            onAuthorTap: (userId) => widget.onNavigateToProfile?.call(userId),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dynamic_feed_outlined,
              size: 72,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No posts yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to share something!',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
