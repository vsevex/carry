import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/operation.dart';
import 'transport.dart';

/// Exception thrown when WebSocket transport fails.
class WebSocketTransportException implements Exception {
  WebSocketTransportException(this.message);

  /// Error message.
  final String message;

  @override
  String toString() => 'WebSocketTransportException: $message';
}

/// Connection state for WebSocket transport.
enum WebSocketConnectionState {
  /// Not connected.
  disconnected,

  /// Connecting to server.
  connecting,

  /// Connected and ready.
  connected,

  /// Connection lost, attempting to reconnect.
  reconnecting,
}

/// WebSocket-based transport for real-time synchronization.
///
/// This implements a bidirectional sync protocol over WebSocket:
/// - `pull` - Request operations since a sync token
/// - `push` - Push operations to the server
/// - `ops_available` - Receive push notifications for new operations
///
/// The transport automatically handles:
/// - Connection management with auto-reconnection
/// - Request/response correlation via request IDs
/// - Incoming operation notifications via stream
class WebSocketTransport implements Transport {
  WebSocketTransport({
    required this.url,
    required this.nodeId,
    this.headers,
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.requestTimeout = const Duration(seconds: 30),
  });

  /// WebSocket URL (e.g., ws://localhost:8080/sync/ws).
  final String url;

  /// Node ID for this client.
  final String nodeId;

  /// Additional headers for the WebSocket connection.
  final Map<String, String>? headers;

  /// Initial delay before reconnection attempts.
  final Duration reconnectDelay;

  /// Maximum delay between reconnection attempts.
  final Duration maxReconnectDelay;

  /// Timeout for request/response operations.
  final Duration requestTimeout;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  int _reconnectAttempts = 0;
  bool _shouldReconnect = true;

  final _connectionStateController =
      StreamController<WebSocketConnectionState>.broadcast();
  final _incomingOpsController = StreamController<List<Operation>>.broadcast();
  final _pendingRequests = <String, Completer<Map<String, dynamic>>>{};

  WebSocketConnectionState _connectionState =
      WebSocketConnectionState.disconnected;

  /// Stream of connection state changes.
  Stream<WebSocketConnectionState> get connectionState =>
      _connectionStateController.stream;

  /// Current connection state.
  WebSocketConnectionState get currentState => _connectionState;

  /// Stream of incoming operations pushed from the server.
  ///
  /// Subscribe to this stream to receive real-time updates when other clients
  /// push operations to the server.
  Stream<List<Operation>> get incomingOperations =>
      _incomingOpsController.stream;

  /// Whether the transport is currently connected.
  bool get isConnected =>
      _connectionState == WebSocketConnectionState.connected;

  /// Connect to the WebSocket server.
  ///
  /// This must be called before using [pull] or [push].
  Future<void> connect() async {
    if (_connectionState == WebSocketConnectionState.connected ||
        _connectionState == WebSocketConnectionState.connecting) {
      return;
    }

    _shouldReconnect = true;
    await _connect();
  }

  Future<void> _connect() async {
    _setConnectionState(WebSocketConnectionState.connecting);

    try {
      final uri = Uri.parse(url);

      _channel = WebSocketChannel.connect(
        uri,
        protocols: ['carry-sync'],
      );

      // Wait for connection to be ready
      await _channel!.ready;

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      _reconnectAttempts = 0;
      _setConnectionState(WebSocketConnectionState.connected);
    } catch (e) {
      _setConnectionState(WebSocketConnectionState.disconnected);
      _scheduleReconnect();
      throw WebSocketTransportException('Failed to connect: $e');
    }
  }

  void _setConnectionState(WebSocketConnectionState state) {
    if (_connectionState != state) {
      _connectionState = state;
      _connectionStateController.add(state);
    }
  }

  void _handleMessage(dynamic message) {
    if (message is! String) {
      return;
    }

    try {
      final json = jsonDecode(message) as Map<String, dynamic>;
      final type = json['type'] as String?;

      switch (type) {
        case 'pull_response':
        case 'push_response':
        case 'error':
          // Response to a request - complete the pending future
          final requestId = json['request_id'] as String?;
          if (requestId != null && _pendingRequests.containsKey(requestId)) {
            _pendingRequests[requestId]!.complete(json);
            _pendingRequests.remove(requestId);
          }
          break;

        case 'ops_available':
          // Push notification - emit to stream
          final operationsJson = json['operations'] as List<dynamic>? ?? [];
          final operations = operationsJson
              .map((op) => Operation.fromJson(op as Map<String, dynamic>))
              .toList();
          if (operations.isNotEmpty) {
            _incomingOpsController.add(operations);
          }
          break;

        case 'pong':
          // Heartbeat response - could track latency
          break;

        default:
          // Unknown message type
          break;
      }
    } catch (e) {
      // Failed to parse message
    }
  }

  void _handleError(Object error) {
    _setConnectionState(WebSocketConnectionState.disconnected);

    // Fail all pending requests
    for (final completer in _pendingRequests.values) {
      completer.completeError(
        WebSocketTransportException('Connection error: $error'),
      );
    }
    _pendingRequests.clear();

    _scheduleReconnect();
  }

  void _handleDone() {
    _setConnectionState(WebSocketConnectionState.disconnected);

    // Fail all pending requests
    for (final completer in _pendingRequests.values) {
      completer.completeError(WebSocketTransportException('Connection closed'));
    }
    _pendingRequests.clear();

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) {
      return;
    }

    _setConnectionState(WebSocketConnectionState.reconnecting);

    // Exponential backoff with jitter
    final delay = Duration(
      milliseconds: min(
        maxReconnectDelay.inMilliseconds,
        reconnectDelay.inMilliseconds * pow(2, _reconnectAttempts).toInt(),
      ),
    );
    _reconnectAttempts++;

    // Add jitter
    final jitter =
        Duration(milliseconds: Random().nextInt(delay.inMilliseconds ~/ 2));

    Future.delayed(delay + jitter, () async {
      if (_shouldReconnect) {
        try {
          await _connect();
        } catch (_) {
          // Will retry again via _scheduleReconnect
        }
      }
    });
  }

  /// Disconnect from the WebSocket server.
  Future<void> disconnect() async {
    _shouldReconnect = false;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _setConnectionState(WebSocketConnectionState.disconnected);

    // Fail all pending requests
    for (final completer in _pendingRequests.values) {
      completer.completeError(WebSocketTransportException('Disconnected'));
    }
    _pendingRequests.clear();
  }

  /// Generate a unique request ID.
  String _generateRequestId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';

  /// Send a message and wait for response.
  Future<Map<String, dynamic>> _sendRequest(
    Map<String, dynamic> message,
  ) async {
    if (!isConnected) {
      throw WebSocketTransportException('Not connected');
    }

    final requestId = _generateRequestId();
    message['request_id'] = requestId;

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;

    try {
      _channel!.sink.add(jsonEncode(message));

      // Wait for response with timeout
      return await completer.future.timeout(
        requestTimeout,
        onTimeout: () {
          _pendingRequests.remove(requestId);
          throw WebSocketTransportException('Request timeout');
        },
      );
    } catch (e) {
      _pendingRequests.remove(requestId);
      rethrow;
    }
  }

  @override
  Future<PullResult> pull(String? lastSyncToken) async {
    try {
      final response = await _sendRequest({
        'type': 'pull',
        'since': lastSyncToken,
        'limit': 100,
      });

      if (response['type'] == 'error') {
        throw WebSocketTransportException(
          response['message'] as String? ?? 'Unknown error',
        );
      }

      final operationsJson = response['operations'] as List<dynamic>? ?? [];
      final operations = operationsJson
          .map((op) => Operation.fromJson(op as Map<String, dynamic>))
          .toList();

      return PullResult(
        operations: operations,
        syncToken: response['sync_token'] as String?,
        hasMore: response['has_more'] as bool? ?? false,
      );
    } on WebSocketTransportException {
      rethrow;
    } catch (e) {
      throw WebSocketTransportException('Pull failed: $e');
    }
  }

  @override
  Future<PushResult> push(List<Operation> operations) async {
    if (operations.isEmpty) {
      return PushResult.ok([]);
    }

    try {
      final response = await _sendRequest({
        'type': 'push',
        'node_id': nodeId,
        'operations': operations.map((op) => op.toJson()).toList(),
      });

      if (response['type'] == 'error') {
        return PushResult.failed(
          response['message'] as String? ?? 'Unknown error',
        );
      }

      final accepted =
          (response['accepted'] as List<dynamic>?)?.cast<String>() ??
              operations.map((op) => op.opId).toList();

      return PushResult.ok(accepted);
    } on WebSocketTransportException catch (e) {
      return PushResult.failed(e.message);
    } catch (e) {
      return PushResult.failed('Push failed: $e');
    }
  }

  /// Send a ping to keep the connection alive.
  void ping() {
    if (isConnected) {
      _channel?.sink.add(jsonEncode({'type': 'ping'}));
    }
  }

  /// Close the transport and release resources.
  Future<void> close() async {
    await disconnect();
    await _connectionStateController.close();
    await _incomingOpsController.close();
  }
}
