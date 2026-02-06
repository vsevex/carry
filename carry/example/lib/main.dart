import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:carry/carry.dart';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'models/todo.dart';

/// Server URL - use localhost for iOS Simulator, 10.0.2.2 for Android Emulator
const kServerUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'http://localhost:3000',
);

void main() => runApp(const CarryTodoApp());

class CarryTodoApp extends StatelessWidget {
  const CarryTodoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Carry Todo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const TodoListPage(),
      );
}

class TodoListPage extends StatefulWidget {
  const TodoListPage({super.key});

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

class _TodoListPageState extends State<TodoListPage> {
  SyncStore? _store;
  Collection<Todo>? _todos;
  List<Todo> _todoList = [];
  StreamSubscription<List<Todo>>? _subscription;
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _error;
  String? _syncError;
  DateTime? _lastSyncTime;
  final _uuid = const Uuid();
  HttpTransport? _transport;
  String _nodeId = '';

  @override
  void initState() {
    super.initState();
    _initStore();
  }

  Future<void> _initStore() async {
    try {
      // Define schema
      final schema = Schema.v(1).collection('todos', [
        Field.string('id', required: true),
        Field.string('title', required: true),
        Field.bool_('completed'),
        Field.int_('createdAt'),
      ]).build();

      // Get app documents directory for persistence
      final appDir = await getApplicationDocumentsDirectory();
      final dataDir = Directory('${appDir.path}/carry_todo');
      if (!await dataDir.exists()) {
        await dataDir.create(recursive: true);
      }

      // Generate or load persistent node ID
      _nodeId = 'device_${_uuid.v4().substring(0, 8)}';

      // Create HTTP transport for server sync
      _transport = HttpTransport(
        baseUrl: kServerUrl,
        nodeId: _nodeId,
      );

      // Create store with persistence and hooks
      final store = SyncStore(
        schema: schema,
        nodeId: _nodeId,
        persistence: FilePersistenceAdapter(directory: dataDir),
        transport: _transport,
        hooks: StoreHooks(
          afterInsert: (ctx, record) =>
              debugPrint('Created todo: ${ctx.recordId}'),
          afterUpdate: (ctx, record) =>
              debugPrint('Updated todo: ${ctx.recordId}'),
          afterDelete: (ctx) => debugPrint('Deleted todo: ${ctx.recordId}'),
        ),
      );

      await store.init();
      _store = store;

      // Get typed collection
      _todos = _store!.collection<Todo>(
        'todos',
        fromJson: Todo.fromJson,
        toJson: (t) => t.toJson(),
        getId: (t) => t.id,
      );

      // Watch for changes
      _subscription = _todos!.watch().listen(
            (todos) => setState(
              () => _todoList = todos
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
            ),
          );

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _store?.close();
    _transport?.close();
    super.dispose();
  }

  Future<void> _sync() async {
    if (_store == null || _isSyncing) {
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncError = null;
    });

    try {
      await _store!.sync();
      setState(() => _lastSyncTime = DateTime.now());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Synced successfully'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _syncError = e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  void _addTodo() => showDialog(
        context: context,
        builder: (context) => _AddTodoDialog(
          onAdd: (title) {
            final todo = Todo(
              id: _uuid.v4(),
              title: title,
            );
            _todos!.insert(todo);
          },
        ),
      );

  void _toggleTodo(Todo todo) =>
      _todos!.update(todo.copyWith(completed: !todo.completed));

  void _deleteTodo(Todo todo) => _todos!.delete(todo.id);

  void _editTodo(Todo todo) => showDialog(
        context: context,
        builder: (context) => _EditTodoDialog(
          todo: todo,
          onSave: (title) => _todos!.update(todo.copyWith(title: title)),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Carry Todo'),
          actions: [
            if (!_isLoading && _store != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(
                  child: Text(
                    '${_todoList.where((t) => !t.completed).length} pending',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              // Sync button
              IconButton(
                icon: _isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Badge(
                        isLabelVisible: _store!.pendingCount > 0,
                        label: Text('${_store!.pendingCount}'),
                        child: const Icon(Icons.sync),
                      ),
                onPressed: _isSyncing ? null : _sync,
                tooltip: _store!.pendingCount > 0
                    ? 'Sync (${_store!.pendingCount} pending)'
                    : 'Sync with server',
              ),
            ],
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showInfoDialog(),
            ),
          ],
        ),
        body: _buildBody(),
        floatingActionButton: _isLoading || _error != null
            ? null
            : FloatingActionButton.extended(
                onPressed: _addTodo,
                icon: const Icon(Icons.add),
                label: const Text('Add Todo'),
              ),
      );

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing store...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Failed to initialize',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              const Text(
                'Make sure libcarry_engine is built and available.',
                textAlign: TextAlign.center,
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      );
    }

    if (_todoList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 80,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No todos yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the button below to add one',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _todoList.length,
      itemBuilder: (context, index) {
        final todo = _todoList[index];
        return _TodoTile(
          todo: todo,
          onToggle: () => _toggleTodo(todo),
          onEdit: () => _editTodo(todo),
          onDelete: () => _deleteTodo(todo),
        );
      },
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Carry Todo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This example demonstrates the Carry SDK with server sync.',
            ),
            const SizedBox(height: 16),
            if (_store != null) ...[
              Text('Node ID: $_nodeId'),
              const Text('Server: $kServerUrl'),
              const Divider(),
              Text('Pending operations: ${_store!.pendingCount}'),
              Text('Total todos: ${_todoList.length}'),
              Text('Completed: ${_todoList.where((t) => t.completed).length}'),
              const Divider(),
              Text(
                'Last sync: ${_lastSyncTime != null ? _formatTime(_lastSyncTime!) : 'Never'}',
              ),
              if (_syncError != null)
                Text(
                  'Last error: $_syncError',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    return '${diff.inHours}h ago';
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Todo todo;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Dismissible(
        key: Key(todo.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Colors.red,
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => onDelete(),
        child: ListTile(
          leading: Checkbox(
            value: todo.completed,
            onChanged: (_) => onToggle(),
          ),
          title: Text(
            todo.title,
            style: TextStyle(
              decoration: todo.completed ? TextDecoration.lineThrough : null,
              color: todo.completed
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
            ),
          ),
          subtitle: Text(
            _formatDate(todo.createdAt),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
          onTap: onToggle,
        ),
      );

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) {
          return 'Just now';
        }
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}

class _AddTodoDialog extends StatefulWidget {
  const _AddTodoDialog({required this.onAdd});

  final void Function(String title) onAdd;

  @override
  State<_AddTodoDialog> createState() => _AddTodoDialogState();
}

class _AddTodoDialogState extends State<_AddTodoDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isNotEmpty) {
      widget.onAdd(title);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New Todo'),
        content: TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: const InputDecoration(
            hintText: 'What needs to be done?',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('Add'),
          ),
        ],
      );
}

class _EditTodoDialog extends StatefulWidget {
  const _EditTodoDialog({required this.todo, required this.onSave});

  final Todo todo;
  final void Function(String title) onSave;

  @override
  State<_EditTodoDialog> createState() => _EditTodoDialogState();
}

class _EditTodoDialogState extends State<_EditTodoDialog> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.todo.title);
    Future.microtask(() {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isNotEmpty && title != widget.todo.title) {
      widget.onSave(title);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit Todo'),
        content: TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: const InputDecoration(
            hintText: 'Todo title',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('Save'),
          ),
        ],
      );
}
