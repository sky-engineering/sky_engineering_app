import 'package:flutter/material.dart';

import 'dropbox_api.dart';
import 'dropbox_auth.dart';

class DropboxFolderListPage extends StatefulWidget {
  const DropboxFolderListPage({
    super.key,
    required this.title,
    required this.path,
  });

  final String title;
  final String path;

  @override
  State<DropboxFolderListPage> createState() => _DropboxFolderListPageState();
}

class _DropboxFolderListPageState extends State<DropboxFolderListPage> {
  final DropboxAuth _auth = DropboxAuth();
  late final DropboxApi _api = DropboxApi(_auth);

  bool _checkingAuth = true;
  bool _signedIn = false;
  Future<List<DbxEntry>>? _foldersFuture;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final signedIn = await _auth.isSignedIn();
    if (!mounted) return;
    setState(() {
      _signedIn = signedIn;
      _checkingAuth = false;
    });
    if (signedIn) {
      _loadFolders();
    }
  }

  void _loadFolders() {
    final effectivePath = widget.path.startsWith('/')
        ? widget.path
        : '/${widget.path}';
    setState(() {
      _foldersFuture = _api
          .listFolder(path: effectivePath)
          .then((entries) => entries.where((e) => e.isFolder).toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_signedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: ElevatedButton(
            onPressed: _connect,
            child: const Text('Connect Dropbox'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: RefreshIndicator(
        onRefresh: () async => _loadFolders(),
        child: FutureBuilder<List<DbxEntry>>(
          future: _foldersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting ||
                _foldersFuture == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(
                message: 'Failed to load folders: ${snapshot.error}',
                onRetry: _loadFolders,
              );
            }
            final folders = snapshot.data ?? const <DbxEntry>[];
            if (folders.isEmpty) {
              return const Center(child: Text('No folders found.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: folders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = folders[index];
                final displayName = entry.name.isNotEmpty
                    ? entry.name
                    : entry.pathLower;
                return ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(displayName),
                  subtitle: entry.pathLower.isNotEmpty
                      ? Text(entry.pathLower)
                      : null,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _connect() async {
    try {
      await _auth.signIn();
      if (!mounted) return;
      setState(() => _signedIn = true);
      _loadFolders();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dropbox sign-in failed: $e')));
    }
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
