import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Log levels for Carry logging system.
enum CarryLogLevel {
  /// Very detailed logs for tracing execution flow.
  verbose(0, 'VERBOSE'),

  /// Debug information useful during development.
  debug(1, 'DEBUG'),

  /// General information about significant events.
  info(2, 'INFO'),

  /// Potential issues that should be noted.
  warning(3, 'WARNING'),

  /// Errors that may affect functionality.
  error(4, 'ERROR'),

  /// No logging.
  none(5, 'NONE');

  const CarryLogLevel(this.priority, this.label);

  /// Priority for comparison (lower = more verbose).
  final int priority;

  /// Human-readable label.
  final String label;
}

/// Categories for filtering logs.
enum CarryLogCategory {
  /// FFI/Native engine operations.
  ffi('FFI'),

  /// WebSocket transport operations.
  websocket('WS'),

  /// HTTP transport operations.
  http('HTTP'),

  /// Sync operations (pull/push/reconcile).
  sync('SYNC'),

  /// Collection CRUD operations.
  collection('COLLECTION'),

  /// Persistence operations.
  persistence('PERSIST'),

  /// General store operations.
  store('STORE'),

  /// Conflict resolution.
  conflict('CONFLICT');

  const CarryLogCategory(this.label);

  /// Short label for log output.
  final String label;
}

/// A single log entry.
class CarryLogEntry {
  CarryLogEntry({
    required this.level,
    required this.category,
    required this.message,
    required this.timestamp,
    this.data,
    this.error,
    this.stackTrace,
  });

  /// Log level.
  final CarryLogLevel level;

  /// Log category.
  final CarryLogCategory category;

  /// Log message.
  final String message;

  /// Timestamp when the log was created.
  final DateTime timestamp;

  /// Additional structured data.
  final Map<String, dynamic>? data;

  /// Error object if this is an error log.
  final Object? error;

  /// Stack trace if available.
  final StackTrace? stackTrace;

  /// Format as a readable string.
  String format({bool includeTimestamp = true, bool includeData = true}) {
    final buffer = StringBuffer();

    if (includeTimestamp) {
      final time = timestamp.toIso8601String().substring(11, 23);
      buffer.write('[$time] ');
    }

    buffer
      ..write('[${level.label}] ')
      ..write('[${category.label}] ')
      ..write(message);

    if (includeData && data != null && data!.isNotEmpty) {
      buffer
        ..write(' ')
        ..write(jsonEncode(data));
    }

    if (error != null) {
      buffer.write(' | Error: $error');
    }

    return buffer.toString();
  }

  /// Convert to JSON for serialization.
  Map<String, dynamic> toJson() => {
        'level': level.name,
        'category': category.name,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
        if (data != null) 'data': data,
        if (error != null) 'error': error.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      };
}

/// Callback for custom log handlers.
typedef CarryLogHandler = void Function(CarryLogEntry entry);

/// Comprehensive logging system for Carry SDK.
///
/// Provides structured logging with levels, categories, and rich context.
///
/// ```dart
/// // Enable logging in debug mode
/// CarryLogger.instance
///   ..level = CarryLogLevel.debug
///   ..enabledCategories = CarryLogCategory.values.toSet();
///
/// // Or use the convenience method
/// CarryLogger.enableDebugLogging();
///
/// // Add custom handler
/// CarryLogger.instance.addHandler((entry) {
///   // Send to analytics, file, etc.
/// });
/// ```
class CarryLogger {
  CarryLogger._();

  /// Singleton instance.
  static final CarryLogger instance = CarryLogger._();

  /// Current minimum log level.
  CarryLogLevel level = kDebugMode ? CarryLogLevel.info : CarryLogLevel.none;

  /// Enabled categories. Empty means all categories.
  Set<CarryLogCategory> enabledCategories = {};

  /// Whether to include timestamps in console output.
  bool includeTimestamp = true;

  /// Whether to include structured data in console output.
  bool includeData = true;

  /// Whether to output to console.
  bool consoleOutput = true;

  /// Whether to output to dart:developer log.
  bool developerLog = true;

  /// Maximum number of entries to keep in history.
  int maxHistorySize = 500;

  final List<CarryLogEntry> _history = [];
  final List<CarryLogHandler> _handlers = [];
  final _streamController = StreamController<CarryLogEntry>.broadcast();

  /// Stream of log entries for real-time monitoring.
  Stream<CarryLogEntry> get stream => _streamController.stream;

  /// Log history (most recent first).
  List<CarryLogEntry> get history => List.unmodifiable(_history);

  /// Add a custom log handler.
  void addHandler(CarryLogHandler handler) => _handlers.add(handler);

  /// Remove a custom log handler.
  void removeHandler(CarryLogHandler handler) => _handlers.remove(handler);

  /// Clear all handlers.
  void clearHandlers() => _handlers.clear();

  /// Clear log history.
  void clearHistory() => _history.clear();

  /// Enable comprehensive debug logging.
  ///
  /// Sets level to [CarryLogLevel.debug] and enables all categories.
  static void enableDebugLogging() => instance
    ..level = CarryLogLevel.debug
    ..enabledCategories = CarryLogCategory.values.toSet()
    ..includeTimestamp = true
    ..includeData = true
    ..consoleOutput = true;

  /// Enable verbose logging (includes all details).
  static void enableVerboseLogging() => instance
    ..level = CarryLogLevel.verbose
    ..enabledCategories = CarryLogCategory.values.toSet()
    ..includeTimestamp = true
    ..includeData = true
    ..consoleOutput = true;

  /// Disable all logging.
  static void disableLogging() => instance.level = CarryLogLevel.none;

  /// Log a message.
  void log(
    CarryLogLevel level,
    CarryLogCategory category,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Check if we should log this
    if (level.priority < this.level.priority) {
      return;
    }

    if (enabledCategories.isNotEmpty && !enabledCategories.contains(category)) {
      return;
    }

    final entry = CarryLogEntry(
      level: level,
      category: category,
      message: message,
      timestamp: DateTime.now(),
      data: data,
      error: error,
      stackTrace: stackTrace,
    );

    // Add to history
    _history.insert(0, entry);
    if (_history.length > maxHistorySize) {
      _history.removeRange(maxHistorySize, _history.length);
    }

    // Output to stream
    _streamController.add(entry);

    // Output to console
    if (consoleOutput) {
      final formatted = entry.format(
        includeTimestamp: includeTimestamp,
        includeData: includeData,
      );
      // ignore: avoid_print
      print('[Carry] $formatted');
    }

    // Output to dart:developer
    if (developerLog) {
      developer.log(
        entry.message,
        name: 'Carry.${category.label}',
        level: _developerLogLevel(level),
        error: error,
        stackTrace: stackTrace,
      );
    }

    // Call custom handlers
    for (final handler in _handlers) {
      try {
        handler(entry);
      } catch (_) {
        // Don't let handler errors break logging
      }
    }
  }

  int _developerLogLevel(CarryLogLevel level) => switch (level) {
        CarryLogLevel.verbose => 300,
        CarryLogLevel.debug => 500,
        CarryLogLevel.info => 800,
        CarryLogLevel.warning => 900,
        CarryLogLevel.error => 1000,
        CarryLogLevel.none => 0,
      };

  // Convenience methods for each level

  /// Log verbose message.
  void verbose(
    CarryLogCategory category,
    String message, {
    Map<String, dynamic>? data,
  }) =>
      log(CarryLogLevel.verbose, category, message, data: data);

  /// Log debug message.
  void debug(
    CarryLogCategory category,
    String message, {
    Map<String, dynamic>? data,
  }) =>
      log(CarryLogLevel.debug, category, message, data: data);

  /// Log info message.
  void info(
    CarryLogCategory category,
    String message, {
    Map<String, dynamic>? data,
  }) =>
      log(CarryLogLevel.info, category, message, data: data);

  /// Log warning message.
  void warning(
    CarryLogCategory category,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
  }) =>
      log(CarryLogLevel.warning, category, message, data: data, error: error);

  /// Log error message.
  void e(
    CarryLogCategory category,
    String message, {
    Map<String, dynamic>? data,
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        CarryLogLevel.error,
        category,
        message,
        data: data,
        error: error,
        stackTrace: stackTrace,
      );

  /// Dispose the logger.
  void dispose() {
    _streamController.close();
    _handlers.clear();
    _history.clear();
  }
}

// Shorthand for common logging patterns

/// Log FFI operation.
void logFfi(
  String message, {
  CarryLogLevel level = CarryLogLevel.debug,
  Map<String, dynamic>? data,
}) =>
    CarryLogger.instance.log(level, CarryLogCategory.ffi, message, data: data);

/// Log WebSocket operation.
void logWebSocket(
  String message, {
  CarryLogLevel level = CarryLogLevel.debug,
  Map<String, dynamic>? data,
  Object? error,
}) =>
    CarryLogger.instance.log(
      level,
      CarryLogCategory.websocket,
      message,
      data: data,
      error: error,
    );

/// Log HTTP operation.
void logHttp(
  String message, {
  CarryLogLevel level = CarryLogLevel.debug,
  Map<String, dynamic>? data,
  Object? error,
}) =>
    CarryLogger.instance.log(
      level,
      CarryLogCategory.http,
      message,
      data: data,
      error: error,
    );

/// Log sync operation.
void logSync(
  String message, {
  CarryLogLevel level = CarryLogLevel.debug,
  Map<String, dynamic>? data,
  Object? error,
}) =>
    CarryLogger.instance.log(
      level,
      CarryLogCategory.sync,
      message,
      data: data,
      error: error,
    );

/// Log collection operation.
void logCollection(
  String message, {
  CarryLogLevel level = CarryLogLevel.debug,
  Map<String, dynamic>? data,
}) =>
    CarryLogger.instance
        .log(level, CarryLogCategory.collection, message, data: data);

/// Log persistence operation.
void logPersistence(
  String message, {
  CarryLogLevel level = CarryLogLevel.debug,
  Map<String, dynamic>? data,
  Object? error,
}) =>
    CarryLogger.instance.log(
      level,
      CarryLogCategory.persistence,
      message,
      data: data,
      error: error,
    );

/// Log store operation.
void logStore(
  String message, {
  CarryLogLevel level = CarryLogLevel.debug,
  Map<String, dynamic>? data,
  Object? error,
}) =>
    CarryLogger.instance.log(
      level,
      CarryLogCategory.store,
      message,
      data: data,
      error: error,
    );

/// Log conflict.
void logConflict(
  String message, {
  CarryLogLevel level = CarryLogLevel.info,
  Map<String, dynamic>? data,
}) =>
    CarryLogger.instance
        .log(level, CarryLogCategory.conflict, message, data: data);
