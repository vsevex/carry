import 'dart:async';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'panels/collections_panel.dart';
import 'panels/conflicts_panel.dart';
import 'panels/pending_ops_panel.dart';
import 'panels/sync_status_panel.dart';

/// Debug information returned from the Carry service extension.
class CarryDebugInfo {
  CarryDebugInfo({
    required this.registered,
    required this.nodeId,
    required this.isInitialized,
    required this.hasTransport,
    required this.hasWebSocketTransport,
    required this.connectionState,
    required this.pendingCount,
    required this.pendingOps,
    required this.syncHistory,
    required this.conflictHistory,
    required this.collections,
    required this.schema,
    required this.timestamp,
    this.error,
  });

  factory CarryDebugInfo.fromJson(Map<String, dynamic> json) => CarryDebugInfo(
        registered: json['registered'] as bool? ?? false,
        nodeId: json['nodeId'] as String? ?? 'unknown',
        isInitialized: json['isInitialized'] as bool? ?? false,
        hasTransport: json['hasTransport'] as bool? ?? false,
        hasWebSocketTransport: json['hasWebSocketTransport'] as bool? ?? false,
        connectionState: json['connectionState'] as String? ?? 'unknown',
        pendingCount: json['pendingCount'] as int? ?? 0,
        pendingOps: (json['pendingOps'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
        syncHistory: (json['syncHistory'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
        conflictHistory: (json['conflictHistory'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
        collections: (json['collections'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
        schema: json['schema'] as Map<String, dynamic>? ?? {},
        timestamp: json['timestamp'] as String? ?? '',
        error: json['error'] as String?,
      );

  factory CarryDebugInfo.empty() => CarryDebugInfo(
        registered: false,
        nodeId: '',
        isInitialized: false,
        hasTransport: false,
        hasWebSocketTransport: false,
        connectionState: 'none',
        pendingCount: 0,
        pendingOps: [],
        syncHistory: [],
        conflictHistory: [],
        collections: [],
        schema: {},
        timestamp: '',
      );

  final bool registered;
  final String nodeId;
  final bool isInitialized;
  final bool hasTransport;
  final bool hasWebSocketTransport;
  final String connectionState;
  final int pendingCount;
  final List<Map<String, dynamic>> pendingOps;
  final List<Map<String, dynamic>> syncHistory;
  final List<Map<String, dynamic>> conflictHistory;
  final List<Map<String, dynamic>> collections;
  final Map<String, dynamic> schema;
  final String timestamp;
  final String? error;
}

/// Main debug panel for the Carry DevTools extension.
class CarryDebugPanel extends StatefulWidget {
  const CarryDebugPanel({super.key});

  @override
  State<CarryDebugPanel> createState() => _CarryDebugPanelState();
}

class _CarryDebugPanelState extends State<CarryDebugPanel> {
  CarryDebugInfo _debugInfo = CarryDebugInfo.empty();
  bool _loading = true;
  String? _error;
  Timer? _refreshTimer;
  bool _autoRefresh = true;

  @override
  void initState() {
    super.initState();
    _fetchDebugInfo();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    if (_autoRefresh) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _fetchDebugInfo(),
      );
    }
  }

  Future<void> _fetchDebugInfo() async {
    try {
      final response = await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.carry.getDebugInfo',
      );

      if (response.json != null) {
        final json = response.json!;
        setState(() {
          _debugInfo = CarryDebugInfo.fromJson(json);
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _triggerSync() async {
    try {
      await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.carry.triggerSync',
      );
      await _fetchDebugInfo();
    } catch (e) {
      setState(() {
        _error = 'Sync failed: $e';
      });
    }
  }

  Future<void> _clearHistory() async {
    try {
      await serviceManager.callServiceExtensionOnMainIsolate(
        'ext.carry.clearHistory',
      );
      await _fetchDebugInfo();
    } catch (e) {
      setState(() {
        _error = 'Clear failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && !_debugInfo.registered) {
      return _buildErrorView();
    }

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildErrorView() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sync_disabled, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Carry Debug Service Not Available',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Make sure your app is using the Carry SDK',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchDebugInfo,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );

  Widget _buildToolbar() => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            // Node ID
            Chip(
              avatar: const Icon(Icons.devices, size: 16),
              label: Text('Node: ${_debugInfo.nodeId}'),
            ),
            const SizedBox(width: 8),

            // Connection state indicator
            _buildConnectionIndicator(),
            const SizedBox(width: 8),

            const Spacer(),

            // Auto-refresh toggle
            Row(
              children: [
                const Text('Auto-refresh'),
                Switch(
                  value: _autoRefresh,
                  onChanged: (value) {
                    setState(() {
                      _autoRefresh = value;
                    });
                    _startAutoRefresh();
                  },
                ),
              ],
            ),
            const SizedBox(width: 8),

            // Manual refresh
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchDebugInfo,
              tooltip: 'Refresh',
            ),

            // Trigger sync
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _debugInfo.hasTransport ? _triggerSync : null,
              tooltip: 'Trigger Sync',
            ),

            // Clear history
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearHistory,
              tooltip: 'Clear History',
            ),
          ],
        ),
      );

  Widget _buildConnectionIndicator() {
    Color color;
    String label;

    switch (_debugInfo.connectionState) {
      case 'connected':
        color = Colors.green;
        label = 'Connected';
        break;
      case 'connecting':
      case 'reconnecting':
        color = Colors.orange;
        label = _debugInfo.connectionState == 'connecting'
            ? 'Connecting'
            : 'Reconnecting';
        break;
      case 'disconnected':
        color = Colors.red;
        label = 'Disconnected';
        break;
      case 'http':
        color = Colors.blue;
        label = 'HTTP';
        break;
      default:
        color = Colors.grey;
        label = 'No Transport';
    }

    return Chip(
      avatar: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
      label: Text(label),
    );
  }

  Widget _buildContent() => DefaultTabController(
        length: 4,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Sync Status'),
                Tab(text: 'Pending Ops'),
                Tab(text: 'Conflicts'),
                Tab(text: 'Collections'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  SyncStatusPanel(debugInfo: _debugInfo),
                  PendingOpsPanel(pendingOps: _debugInfo.pendingOps),
                  ConflictsPanel(conflicts: _debugInfo.conflictHistory),
                  CollectionsPanel(
                    collections: _debugInfo.collections,
                    schema: _debugInfo.schema,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
