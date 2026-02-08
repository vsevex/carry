import 'dart:async';

import 'package:flutter/material.dart';

import '../models/notification.dart';
import '../store/buzz_store.dart';
import '../utils/time_format.dart';
import '../widgets/user_avatar.dart';

/// Activity feed showing likes, comments, and follow notifications.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.onNavigateToPost,
    this.onNavigateToProfile,
  });

  final void Function(String postId)? onNavigateToPost;
  final void Function(String userId)? onNavigateToProfile;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _store = BuzzStore.instance;
  List<BuzzNotification> _notifications = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _store.notifications.watch().listen((all) {
      if (!mounted) return;
      final mine = all
          .where((n) => n.userId == _store.currentUserId)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() => _notifications = mine);
    });

    // Mark notifications as read after a short delay.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _store.markAllNotificationsRead();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_notifications.isEmpty) {
      return _buildEmpty(context);
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final n = _notifications[index];
        return _buildNotificationTile(context, n);
      },
    );
  }

  Widget _buildNotificationTile(BuildContext context, BuzzNotification n) {
    final actor = n.actorId != null ? _store.getUser(n.actorId!) : null;
    final colorScheme = Theme.of(context).colorScheme;

    final (icon, color, text) = switch (n.type) {
      'like' => (
          Icons.favorite,
          Colors.redAccent,
          '${actor?.name ?? 'Someone'} liked your post'
        ),
      'comment' => (
          Icons.chat_bubble,
          colorScheme.primary,
          '${actor?.name ?? 'Someone'} commented on your post'
        ),
      'follow' => (
          Icons.person_add,
          Colors.teal,
          '${actor?.name ?? 'Someone'} started following you'
        ),
      _ => (
          Icons.notifications,
          colorScheme.onSurfaceVariant,
          'New notification'
        ),
    };

    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          UserAvatar(user: actor, radius: 22),
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 14, color: color),
            ),
          ),
        ],
      ),
      title: Text(text, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        formatTimeAgo(n.createdAt),
        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
      ),
      tileColor: n.read ? null : colorScheme.primaryContainer.withValues(alpha: 0.1),
      onTap: () {
        if (n.type == 'follow' && n.actorId != null) {
          widget.onNavigateToProfile?.call(n.actorId!);
        } else if (n.targetId != null) {
          widget.onNavigateToPost?.call(n.targetId!);
        }
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_none,
            size: 72,
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text('No notifications yet',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Activity from others will appear here',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
