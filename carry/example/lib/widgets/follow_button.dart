import 'package:flutter/material.dart';

/// A button that toggles between "Follow" and "Following" states.
class FollowButton extends StatelessWidget {
  const FollowButton({
    required this.isFollowing,
    required this.onTap,
    super.key,
  });

  final bool isFollowing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isFollowing) {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: colorScheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          'Following',
          style: TextStyle(color: colorScheme.onSurface),
        ),
      );
    }

    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
      child: const Text('Follow'),
    );
  }
}
