import 'package:timeago/timeago.dart' as timeago;

/// Format a millisecond timestamp as a relative time string.
String formatTimeAgo(int timestampMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  return timeago.format(date);
}

/// Format a millisecond timestamp as a short relative time string.
String formatTimeAgoShort(int timestampMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  return timeago.format(date, locale: 'en_short');
}
