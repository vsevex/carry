import 'package:flutter/material.dart';

import '../models/comment.dart';
import '../store/buzz_store.dart';
import '../utils/time_format.dart';
import 'user_avatar.dart';

/// A single comment displayed in a list.
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    this.onAuthorTap,
  });

  final Comment comment;
  final void Function(String userId)? onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final store = BuzzStore.instance;
    final author = store.getUser(comment.authorId);
    final isOwn = comment.authorId == store.currentUserId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            user: author,
            radius: 16,
            onTap: () => onAuthorTap?.call(comment.authorId),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      author?.name ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatTimeAgo(comment.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  comment.content,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          if (isOwn)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => store.deleteComment(comment.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 16,
              tooltip: 'Delete comment',
            ),
        ],
      ),
    );
  }
}
