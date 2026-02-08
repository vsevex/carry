import 'dart:async';

import 'package:carry/carry.dart';
import 'package:flutter/material.dart';

import 'screens/create_post_screen.dart';
import 'screens/feed_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/post_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/search_screen.dart';
import 'store/buzz_store.dart';
import 'widgets/sync_indicator.dart';

void main() => runApp(const BuzzApp());

// ---------------------------------------------------------------------------
// Root App
// ---------------------------------------------------------------------------

class BuzzApp extends StatelessWidget {
  const BuzzApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Buzz',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C63FF),
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6C63FF),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const BuzzHome(),
      );
}

// ---------------------------------------------------------------------------
// Home - Init flow & routing
// ---------------------------------------------------------------------------

class BuzzHome extends StatefulWidget {
  const BuzzHome({super.key});

  @override
  State<BuzzHome> createState() => _BuzzHomeState();
}

class _BuzzHomeState extends State<BuzzHome> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await BuzzStore.instance.init();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();
    if (BuzzStore.instance.currentUserId == null) {
      return ProfileSetupScreen(onComplete: () => setState(() {}));
    }
    return const AppShell();
  }

  Widget _buildLoading() => const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Starting Buzz...'),
            ],
          ),
        ),
      );

  Widget _buildError() => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Failed to initialize',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _init();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Profile Setup (first launch)
// ---------------------------------------------------------------------------

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  bool _creating = false;

  bool get _canCreate =>
      _usernameCtrl.text.trim().isNotEmpty &&
      _displayNameCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    setState(() => _creating = true);

    try {
      await BuzzStore.instance.createProfile(
        username: _usernameCtrl.text.trim().toLowerCase().replaceAll(' ', '_'),
        displayName: _displayNameCtrl.text.trim(),
      );
      widget.onComplete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _creating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 72, color: colorScheme.primary),
                const SizedBox(height: 16),
                Text('Welcome to Buzz',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  'Set up your profile to get started',
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 16),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _displayNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    hintText: 'John Doe',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    hintText: 'johndoe',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _canCreate && !_creating ? _create : null,
                    child: _creating
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Create Profile',
                            style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App Shell (bottom navigation)
// ---------------------------------------------------------------------------

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentTab = 0;
  final _store = BuzzStore.instance;
  WebSocketConnectionState _connectionState =
      WebSocketConnectionState.disconnected;
  StreamSubscription<WebSocketConnectionState>? _connSub;
  StreamSubscription? _notifSub;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _connectionState = _store.connectionState;
    _connSub = _store.connectionStateStream.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    });
    _notifSub = _store.notifications.watch().listen((all) {
      if (mounted) {
        setState(() {
          _unreadCount = all
              .where((n) => n.userId == _store.currentUserId && !n.read)
              .length;
        });
      }
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _notifSub?.cancel();
    super.dispose();
  }

  void _navigateToProfile(String userId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(elevation: 0),
        body: ProfileScreen(
          userId: userId,
          onNavigateToPost: _navigateToPost,
          onNavigateToProfile: _navigateToProfile,
        ),
      ),
    ));
  }

  void _navigateToPost(String postId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PostDetailScreen(
        postId: postId,
        onNavigateToProfile: _navigateToProfile,
      ),
    ));
  }

  void _createPost() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );
    if (result == true && mounted) {
      setState(() => _currentTab = 0); // Go to feed after posting
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Buzz',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        actions: [
          SyncIndicator(state: _connectionState),
          const SizedBox(width: 8),
          IconButton(
            icon: Badge(
              isLabelVisible: _store.pendingCount > 0,
              label: Text('${_store.pendingCount}'),
              child: const Icon(Icons.sync),
            ),
            onPressed: () async {
              try {
                await _store.sync();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Synced successfully'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Sync failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
              if (mounted) setState(() {});
            },
            tooltip: 'Sync',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          FeedScreen(
            onNavigateToProfile: _navigateToProfile,
            onNavigateToPost: _navigateToPost,
          ),
          SearchScreen(onNavigateToProfile: _navigateToProfile),
          NotificationsScreen(
            onNavigateToPost: _navigateToPost,
            onNavigateToProfile: _navigateToProfile,
          ),
          ProfileScreen(
            userId: _store.currentUserId!,
            onNavigateToPost: _navigateToPost,
            onNavigateToProfile: _navigateToProfile,
          ),
        ],
      ),
      floatingActionButton: _currentTab == 0
          ? FloatingActionButton(
              onPressed: _createPost,
              child: const Icon(Icons.edit),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Feed',
          ),
          const NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _unreadCount > 0,
              label: Text('$_unreadCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: _unreadCount > 0,
              label: Text('$_unreadCount'),
              child: const Icon(Icons.notifications),
            ),
            label: 'Notifications',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
