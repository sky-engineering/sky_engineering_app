import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'dropbox_api.dart';
import 'dropbox_auth.dart';

class DropboxPage extends StatefulWidget {
  const DropboxPage({super.key, this.path = ''});

  final String path;

  @override
  State<DropboxPage> createState() => _DropboxPageState();
}

class _DropboxPageState extends State<DropboxPage> {
  final DropboxAuth _auth = DropboxAuth();
  late final DropboxApi _api = DropboxApi(_auth);

  bool _checkingAuth = true;
  bool _signedIn = false;
  bool _connecting = false;
  bool _uploading = false;
  Future<List<DbxEntry>>? _entriesFuture;

  @override
  void initState() {
    super.initState();
    _evaluateSession();
  }

  Future<void> _evaluateSession() async {
    final signedIn = await _auth.isSignedIn();
    if (!mounted) return;
    setState(() {
      _signedIn = signedIn;
      _checkingAuth = false;
    });
    if (signedIn) {
      _refreshEntries();
    }
  }

  void _refreshEntries() {
    setState(() {
      _entriesFuture = _api.listFolder(path: widget.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dropbox')),
        body: Center(
          child: ElevatedButton(
            onPressed: _connecting ? null : _connect,
            child: _connecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Connect Dropbox'),
          ),
        ),
      );
    }

    final title = widget.path.isEmpty ? 'Dropbox' : 'Dropbox - ${widget.path}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: FutureBuilder<List<DbxEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting ||
              _entriesFuture == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Failed to load: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _refreshEntries,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          final entries = snapshot.data ?? const <DbxEntry>[];
          if (entries.isEmpty) {
            return const Center(child: Text('Folder is empty.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                leading: Icon(
                  entry.isFolder ? Icons.folder : Icons.insert_drive_file,
                ),
                title: Text(entry.name),
                subtitle: !entry.isFolder && entry.size != null
                    ? Text('${_formatSize(entry.size!)} KB')
                    : null,
                onTap: () =>
                    entry.isFolder ? _openFolder(entry) : _download(entry),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: entries.length,
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _uploadSample,
        icon: _uploading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.upload),
        label: const Text('Upload'),
      ),
    );
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      await _auth.signIn();
      if (!mounted) return;
      setState(() {
        _signedIn = true;
      });
      _refreshEntries();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dropbox sign-in failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    setState(() {
      _signedIn = false;
      _entriesFuture = null;
    });
  }

  Future<void> _openFolder(DbxEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DropboxPage(path: entry.pathLower)),
    );
    if (!mounted) return;
    _refreshEntries();
  }

  Future<void> _download(DbxEntry entry) async {
    try {
      final bytes = await _api.download(entry.pathLower);
      if (!mounted) return;
      final sizeKb = (bytes.length / 1024).toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded ${entry.name} ($sizeKb KB)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Future<void> _uploadSample() async {
    setState(() => _uploading = true);
    final fileName = 'sky_test_${DateTime.now().millisecondsSinceEpoch}.txt';
    final targetPath = _joinPath(fileName);
    final bytes = Uint8List.fromList('hello from app'.codeUnits);
    try {
      await _api.upload(path: targetPath, bytes: bytes);
      if (!mounted) return;
      _refreshEntries();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Uploaded $fileName')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  String _joinPath(String name) {
    if (widget.path.isEmpty || widget.path == '/') {
      return '/$name';
    }
    return widget.path.endsWith('/')
        ? '${widget.path}$name'
        : '${widget.path}/$name';
  }

  String _formatSize(int size) {
    final kb = size / 1024;
    return kb >= 10 ? kb.toStringAsFixed(0) : kb.toStringAsFixed(1);
  }
}
