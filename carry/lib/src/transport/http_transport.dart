import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/operation.dart';
import 'transport.dart';

/// Exception thrown when HTTP transport fails.
class HttpTransportException implements Exception {
  HttpTransportException(this.message, {this.statusCode});

  /// HTTP status code.
  final int? statusCode;

  /// Error message.
  final String message;

  @override
  String toString() {
    if (statusCode != null) {
      return 'HttpTransportException: $statusCode - $message';
    }
    return 'HttpTransportException: $message';
  }
}

/// HTTP-based transport for server synchronization.
///
/// This implements a simple sync protocol:
/// - `GET /sync?since={token}&limit={n}` - Pull operations
/// - `POST /sync` - Push operations
///
/// Expected server response format for pull:
/// ```json
/// {
///   "operations": [...],
///   "syncToken": "token_value",
///   "hasMore": false
/// }
/// ```
///
/// Expected server response format for push:
/// ```json
/// {
///   "accepted": ["op_id_1", "op_id_2"],
///   "rejected": [{"opId": "op_3", "reason": "conflict"}],
///   "serverClock": 42
/// }
/// ```
class HttpTransport implements Transport {
  HttpTransport({
    required this.baseUrl,
    required this.nodeId,
    this.headers,
    http.Client? client,
    this.syncPath = '/sync',
    this.timeout = const Duration(seconds: 30),
    this.pullLimit = 100,
  }) : _client = client ?? http.Client();

  /// Node ID for this client (used in push requests).
  final String nodeId;

  /// Base URL for the sync API.
  final String baseUrl;

  /// Custom headers to include in requests.
  final Map<String, String>? headers;

  /// HTTP client (injectable for testing).
  final http.Client _client;

  /// Path for sync endpoint.
  final String syncPath;

  /// Timeout for HTTP requests.
  final Duration timeout;

  /// Maximum number of operations to pull at once.
  final int pullLimit;

  Uri _syncUri([Map<String, String>? queryParams]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: base.path + syncPath,
      queryParameters: queryParams,
    );
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...?headers,
      };

  @override
  Future<PullResult> pull(String? lastSyncToken) async {
    try {
      final queryParams = <String, String>{
        'limit': pullLimit.toString(),
      };
      if (lastSyncToken != null && lastSyncToken.isNotEmpty) {
        queryParams['since'] = lastSyncToken;
      }
      final uri = _syncUri(queryParams);

      final response =
          await _client.get(uri, headers: _headers).timeout(timeout);

      if (response.statusCode != 200) {
        throw HttpTransportException(
          'Failed to pull: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final operationsJson = json['operations'] as List<dynamic>? ?? [];
      final operations = operationsJson
          .map((op) => Operation.fromJson(op as Map<String, dynamic>))
          .toList();

      return PullResult(
        operations: operations,
        syncToken: json['syncToken'] as String?,
        hasMore: json['hasMore'] as bool? ?? false,
      );
    } on HttpTransportException {
      rethrow;
    } catch (e) {
      throw HttpTransportException('Network error: $e');
    }
  }

  @override
  Future<PushResult> push(List<Operation> operations) async {
    if (operations.isEmpty) {
      return PushResult.ok([]);
    }

    try {
      final uri = _syncUri();
      final body = jsonEncode({
        'nodeId': nodeId,
        'operations': operations.map((op) => op.toJson()).toList(),
      });

      final response = await _client
          .post(uri, headers: _headers, body: body)
          .timeout(timeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw HttpTransportException(
          'Failed to push: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      // Server returns 'accepted' for successfully processed operations
      final accepted = (json['accepted'] as List<dynamic>?)?.cast<String>() ??
          operations.map((op) => op.opId).toList();

      return PushResult.ok(accepted);
    } on HttpTransportException {
      rethrow;
    } catch (e) {
      return PushResult.failed('Network error: $e');
    }
  }

  /// Close the HTTP client.
  void close() => _client.close();
}
