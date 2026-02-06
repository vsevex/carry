import '../core/operation.dart';

/// Result of pulling operations from the server.
class PullResult {
  PullResult({
    required this.operations,
    this.syncToken,
    this.hasMore = false,
  });

  /// Operations received from the server.
  final List<Operation> operations;

  /// Token to use for the next pull (for pagination/incremental sync).
  final String? syncToken;

  /// Whether there are more operations to fetch.
  final bool hasMore;
}

/// Result of pushing operations to the server.
class PushResult {
  PushResult({
    required this.success,
    required this.acknowledgedIds,
    this.error,
  });

  /// Create a failed push result.
  factory PushResult.failed(String error) => PushResult(
        success: false,
        acknowledgedIds: [],
        error: error,
      );

  /// Create a successful push result.
  factory PushResult.ok(List<String> acknowledgedIds) => PushResult(
        success: true,
        acknowledgedIds: acknowledgedIds,
      );

  /// Whether the push was successful.
  final bool success;

  /// IDs of operations that were acknowledged by the server.
  final List<String> acknowledgedIds;

  /// Error message if push failed.
  final String? error;
}

/// Interface for server communication.
///
/// Implement this interface to provide custom transport for your backend.
/// The SDK includes [HttpTransport] as a reference implementation.
abstract interface class Transport {
  /// Pull operations from the server.
  ///
  /// [lastSyncToken] is the token from the previous sync, or null for
  /// the first sync.
  Future<PullResult> pull(String? lastSyncToken);

  /// Push operations to the server.
  ///
  /// Returns which operations were acknowledged.
  Future<PushResult> push(List<Operation> operations);
}
