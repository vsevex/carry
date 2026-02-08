import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../store/buzz_store.dart';
import '../widgets/follow_button.dart';
import '../widgets/user_avatar.dart';

/// Discover screen showing all users with search filtering.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.onNavigateToProfile});

  final void Function(String userId)? onNavigateToProfile;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _store = BuzzStore.instance;
  final _searchCtrl = TextEditingController();
  List<User> _allUsers = [];
  List<User> _filtered = [];
  StreamSubscription? _usersSub;
  StreamSubscription? _followsSub;

  @override
  void initState() {
    super.initState();
    _usersSub = _store.users.watch().listen((users) {
      if (!mounted) return;
      setState(() {
        _allUsers = users
            .where((u) => u.id != _store.currentUserId)
            .toList()
          ..sort((a, b) => a.username.compareTo(b.username));
        _applyFilter();
      });
    });
    _followsSub = _store.follows.watch().listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _applyFilter() {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      _filtered = _allUsers;
    } else {
      _filtered = _allUsers
          .where((u) =>
              u.username.toLowerCase().contains(query) ||
              u.name.toLowerCase().contains(query))
          .toList();
    }
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _followsSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search users...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _applyFilter());
                      },
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (_) => setState(() => _applyFilter()),
          ),
        ),

        // User list
        Expanded(
          child: _filtered.isEmpty
              ? _buildEmpty(context)
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final user = _filtered[index];
                    return _buildUserTile(context, user);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildUserTile(BuildContext context, User user) {
    final isFollowing = _store.isFollowing(user.id);
    final followerCount = _store.getFollowerCount(user.id);

    return ListTile(
      leading: UserAvatar(user: user, radius: 24),
      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '@${user.username} · $followerCount follower${followerCount == 1 ? '' : 's'}',
        style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      trailing: FollowButton(
        isFollowing: isFollowing,
        onTap: () {
          _store.toggleFollow(user.id);
          setState(() {});
        },
      ),
      onTap: () => widget.onNavigateToProfile?.call(user.id),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final hasSearch = _searchCtrl.text.isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasSearch ? Icons.search_off : Icons.people_outline,
            size: 72,
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch ? 'No users found' : 'No other users yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            hasSearch
                ? 'Try a different search term'
                : 'Others will appear here when they join',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
