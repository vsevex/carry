import 'package:carry/carry.dart';

/// The Buzz app schema with 6 collections.
final buzzSchema = Schema.v(1).collection('users', [
  Field.string('id', required: true),
  Field.string('username', required: true),
  Field.string('displayName'),
  Field.string('bio'),
  Field.string('avatarUrl'),
  Field.json('stats'),
  Field.int_('createdAt'),
]).collection('posts', [
  Field.string('id', required: true),
  Field.string('authorId', required: true),
  Field.string('content', required: true),
  Field.json('media'),
  Field.json('stats'),
  Field.bool_('edited'),
  Field.int_('createdAt'),
]).collection('comments', [
  Field.string('id', required: true),
  Field.string('postId', required: true),
  Field.string('authorId', required: true),
  Field.string('content', required: true),
  Field.string('replyToId'),
  Field.int_('createdAt'),
]).collection('likes', [
  Field.string('id', required: true),
  Field.string('userId', required: true),
  Field.string('targetId', required: true),
  Field.string('targetType'),
  Field.int_('createdAt'),
]).collection('follows', [
  Field.string('id', required: true),
  Field.string('followerId', required: true),
  Field.string('followingId', required: true),
  Field.int_('createdAt'),
]).collection('notifications', [
  Field.string('id', required: true),
  Field.string('userId', required: true),
  Field.string('type'),
  Field.string('actorId'),
  Field.string('targetId'),
  Field.bool_('read'),
  Field.int_('createdAt'),
]).build();
