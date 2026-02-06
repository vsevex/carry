import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/operation.dart';
import '../debug/logger.dart';
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
    logHttp(
      'Pull request',
      data: {'since': lastSyncToken, 'limit': pullLimit},
    );

    try {
      final queryParams = <String, String>{
        'limit': pullLimit.toString(),
      };
      if (lastSyncToken != null && lastSyncToken.isNotEmpty) {
        queryParams['since'] = lastSyncToken;
      }
      final uri = _syncUri(queryParams);

      logHttp('GET $uri', level: CarryLogLevel.verbose);

      final response =
          await _client.get(uri, headers: _headers).timeout(timeout);

      logHttp(
        'Pull response',
        level: CarryLogLevel.verbose,
        data: {
          'status': response.statusCode,
          'bodyLength': response.body.length,
        },
      );

      if (response.statusCode != 200) {
        logHttp(
          'Pull failed',
          level: CarryLogLevel.error,
          data: {'status': response.statusCode, 'body': response.body},
        );
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

      logHttp(
        'Pull completed',
        level: CarryLogLevel.info,
        data: {
          'count': operations.length,
          'syncToken': json['syncToken'],
          'hasMore': json['hasMore'],
        },
      );

      return PullResult(
        operations: operations,
        syncToken: json['syncToken'] as String?,
        hasMore: json['hasMore'] as bool? ?? false,
      );
    } on HttpTransportException {
      rethrow;
    } catch (e) {
      logHttp(
        'Pull failed with network error',
        level: CarryLogLevel.error,
        error: e,
      );
      throw HttpTransportException('Network error: $e');
    }
  }

  @override
  Future<PushResult> push(List<Operation> operations) async {
    if (operations.isEmpty) {
      logHttp('Push skipped - no operations');
      return PushResult.ok([]);
    }

    logHttp(
      'Push request',
      data: {
        'count': operations.length,
        'opIds': operations.map((op) => op.opId).toList(),
      },
    );

    try {
      final uri = _syncUri();
      final body = jsonEncode({
        'nodeId': nodeId,
        'operations': operations.map((op) => op.toJson()).toList(),
      });

      logHttp('POST $uri', level: CarryLogLevel.verbose);

      final response = await _client
          .post(uri, headers: _headers, body: body)
          .timeout(timeout);

      logHttp(
        'Push response',
        level: CarryLogLevel.verbose,
        data: {
          'status': response.statusCode,
          'bodyLength': response.body.length,
        },
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        logHttp(
          'Push failed',
          level: CarryLogLevel.error,
          data: {'status': response.statusCode, 'body': response.body},
        );
        throw HttpTransportException(
          'Failed to push: ${response.body}',
          statusCode: response.statusCode,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      // Server returns 'accepted' for successfully processed operations
      final accepted = (json['accepted'] as List<dynamic>?)?.cast<String>() ??
          operations.map((op) => op.opId).toList();
      final rejected = json['rejected'] as List<dynamic>? ?? [];

      logHttp(
        'Push completed',
        level: CarryLogLevel.info,
        data: {
          'accepted': accepted.length,
          'rejected': rejected.length,
          'serverClock': json['serverClock'],
        },
      );

      return PushResult.ok(accepted);
    } on HttpTransportException {
      rethrow;
    } catch (e) {
      logHttp(
        'Push failed with network error',
        level: CarryLogLevel.error,
        error: e,
      );
      return PushResult.failed('Network error: $e');
    }
  }

  /// Close the HTTP client.
  void close() => _client.close();
}
