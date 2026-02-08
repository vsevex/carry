import 'dart:async';

import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/user.dart';
import '../store/buzz_store.dart';
import '../widgets/follow_button.dart';
import '../widgets/post_card.dart';
import '../widgets/user_avatar.dart';

/// Profile screen showing user info, stats, and their posts.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.userId,
    this.onNavigateToPost,
    this.onNavigateToProfile,
  });

  final String userId;
  final void Function(String postId)? onNavigateToPost;
  final void Function(String userId)? onNavigateToProfile;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _store = BuzzStore.instance;
  User? _user;
  List<Post> _posts = [];
  StreamSubscription? _usersSub;
  StreamSubscription? _postsSub;
  StreamSubscription? _followsSub;
  StreamSubscription? _likesSub;
  StreamSubscription? _commentsSub;

  bool get _isOwnProfile => widget.userId == _store.currentUserId;

  @override
  void initState() {
    super.initState();
    _loadData();
    _usersSub = _store.users.watch().listen((_) => _loadData());
    _postsSub = _store.posts.watch().listen((_) => _loadData());
    _followsSub = _store.follows.watch().listen((_) {
      if (mounted) setState(() {});
    });
    _likesSub = _store.likes.watch().listen((_) {
      if (mounted) setState(() {});
    });
    _commentsSub = _store.comments.watch().listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _loadData() {
    if (!mounted) return;
    setState(() {
      _user = _store.getUser(widget.userId);
      _posts = _store.getPostsByUser(widget.userId);
    });
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _postsSub?.cancel();
    _followsSub?.cancel();
    _likesSub?.cancel();
    _commentsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Center(child: Text('User not found'));
    }

    final followerCount = _store.getFollowerCount(widget.userId);
    final followingCount = _store.getFollowingCount(widget.userId);
    final postCount = _posts.length;

    return CustomScrollView(
      slivers: [
        // Profile header
        SliverToBoxAdapter(
          child: _buildHeader(context, followerCount, followingCount, postCount),
        ),
        // Divider
        const SliverToBoxAdapter(child: Divider(height: 1)),
        // Posts
        if (_posts.isEmpty)
          SliverFillRemaining(child: _buildEmptyPosts(context))
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => PostCard(
                post: _posts[index],
                onTap: () =>
                    widget.onNavigateToPost?.call(_posts[index].id),
                onAuthorTap: (userId) =>
                    widget.onNavigateToProfile?.call(userId),
              ),
              childCount: _posts.length,
            ),
          ),
        // Bottom padding
        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }

  Widget _buildHeader(
      BuildContext context, int followers, int following, int posts) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Avatar and stats row
          Row(
            children: [
              UserAvatar(user: _user, radius: 40),
              const SizedBox(width: 24),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStat(context, '$posts', 'Posts'),
                    _buildStat(context, '$followers', 'Followers'),
                    _buildStat(context, '$following', 'Following'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Name and bio
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _user!.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '@${_user!.username}',
                  style:
                      TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
                ),
                if (_user!.bio != null && _user!.bio!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_user!.bio!, style: const TextStyle(fontSize: 14)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Action button
          SizedBox(
            width: double.infinity,
            child: _isOwnProfile
                ? OutlinedButton(
                    onPressed: () => _showEditProfile(context),
                    child: const Text('Edit Profile'),
                  )
                : FollowButton(
                    isFollowing: _store.isFollowing(widget.userId),
                    onTap: () {
                      _store.toggleFollow(widget.userId);
                      setState(() {});
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(BuildContext context, String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12)),
      ],
    );
  }

  Widget _buildEmptyPosts(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.article_outlined,
              size: 48,
              color:
                  Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text(
            _isOwnProfile ? 'You haven\'t posted yet' : 'No posts yet',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _showEditProfile(BuildContext context) {
    final nameCtrl = TextEditingController(text: _user?.displayName ?? '');
    final bioCtrl = TextEditingController(text: _user?.bio ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bioCtrl,
              decoration: const InputDecoration(
                labelText: 'Bio',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              _store.updateProfile(
                displayName: nameCtrl.text.trim(),
                bio: bioCtrl.text.trim(),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
