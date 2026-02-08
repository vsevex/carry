import 'package:flutter/material.dart';

import '../models/user.dart';

/// A list of colors used for user avatars, picked by hashing the user ID.
const _avatarColors = [
  Color(0xFF6C63FF),
  Color(0xFFFF6584),
  Color(0xFF43AA8B),
  Color(0xFFF9C74F),
  Color(0xFFF3722C),
  Color(0xFF577590),
  Color(0xFF90BE6D),
  Color(0xFFF94144),
  Color(0xFF277DA1),
  Color(0xFFA855F7),
];

/// Colored circle avatar showing the user's initial.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.user,
    this.radius = 20,
    this.onTap,
  });

  final User? user;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = user?.initial ?? '?';
    final color = _colorForId(user?.id ?? '');

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.85,
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: avatar);
    }
    return avatar;
  }

  Color _colorForId(String id) {
    if (id.isEmpty) {
      return _avatarColors[0];
    }
    final hash = id.codeUnits.fold<int>(0, (sum, c) => sum + c);
    return _avatarColors[hash % _avatarColors.length];
  }
}
