import 'package:flutter/material.dart';

import '../store/buzz_store.dart';
import '../widgets/user_avatar.dart';

/// Screen for composing a new post.
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _textCtrl = TextEditingController();
  final _maxLength = 500;

  bool get _canPost => _textCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _post() {
    final content = _textCtrl.text.trim();
    if (content.isEmpty) return;

    BuzzStore.instance.createPost(content);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final store = BuzzStore.instance;
    final user = store.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Post'),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _canPost ? _post : null,
              child: const Text('Post'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // User info row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(user: user, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'You',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${user?.username ?? ''}',
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

            // Text input
            Expanded(
              child: TextField(
                controller: _textCtrl,
                maxLength: _maxLength,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'What\'s on your mind?',
                  border: InputBorder.none,
                  counterText: '',
                ),
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 16, height: 1.5),
                onChanged: (_) => setState(() {}),
              ),
            ),

            // Character counter
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_textCtrl.text.length} / $_maxLength',
                  style: TextStyle(
                    fontSize: 12,
                    color: _textCtrl.text.length > _maxLength * 0.9
                        ? Colors.orange
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
