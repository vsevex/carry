import 'package:flutter/material.dart';

import '../models/post.dart';
import '../models/user.dart';
import '../store/buzz_store.dart';
import '../utils/time_format.dart';
import 'like_button.dart';
import 'user_avatar.dart';

/// A card displaying a single post in the feed.
class PostCard extends StatelessWidget {
  const PostCard({
    required this.post,
    this.onTap,
    this.onAuthorTap,
    super.key,
  });

  final Post post;
  final VoidCallback? onTap;
  final void Function(String userId)? onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final store = BuzzStore.instance;
    final author = store.getUser(post.authorId);
    final likeCount = store.getLikeCount(post.id);
    final commentCount = store.getCommentCount(post.id);
    final isLiked = store.hasLiked(post.id);
    final isOwn = post.authorId == store.currentUserId;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author row
              _buildAuthorRow(context, author, isOwn),
              const SizedBox(height: 12),

              // Content
              Text(
                post.content,
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
              if (post.edited) ...[
                const SizedBox(height: 4),
                Text(
                  '(edited)',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Action row
              Row(
                children: [
                  LikeButton(
                    isLiked: isLiked,
                    count: likeCount,
                    onTap: () => store.toggleLike(post.id, 'post'),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 19,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          if (commentCount > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '$commentCount',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthorRow(BuildContext context, User? author, bool isOwn) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        UserAvatar(
          user: author,
          radius: 18,
          onTap: () => onAuthorTap?.call(post.authorId),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => onAuthorTap?.call(post.authorId),
                child: Text(
                  author?.name ?? 'Unknown',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '@${author?.username ?? 'unknown'} · ${formatTimeAgo(post.createdAt)}',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (isOwn)
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_horiz,
              color: colorScheme.onSurfaceVariant,
              size: 20,
            ),
            onSelected: (value) {
              if (value == 'delete') {
                BuzzStore.instance.deletePost(post.id);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}
