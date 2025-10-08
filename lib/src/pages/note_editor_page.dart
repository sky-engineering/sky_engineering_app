// lib/src/pages/note_editor_page.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';
import '../integrations/dropbox/dropbox_api.dart';
import '../integrations/dropbox/dropbox_auth.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final TextEditingController _controller = TextEditingController();
  final ProjectRepository _projectRepository = ProjectRepository();
  final DropboxAuth _dropboxAuth = DropboxAuth();

  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Note'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _handleDone,
            child: _saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Done'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Start typing...',
          ),
          autofocus: true,
          cursorColor: Theme.of(context).colorScheme.onPrimary,
          maxLines: null,
          keyboardType: TextInputType.multiline,
        ),
      ),
    );
  }

  Future<void> _handleDone() async {
    final content = _controller.text;
    if (content.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some text before saving.')),
      );
      return;
    }

    final selectedProject = await _promptForProject();
    if (selectedProject == null || !mounted) {
      return;
    }

    setState(() => _saving = true);

    var progressClosed = false;
    void closeProgress() {
      if (progressClosed) return;
      progressClosed = true;
      Navigator.of(context, rootNavigator: true).pop();
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SavingNoteDialog(),
    );

    try {
      await _saveNoteToDropbox(selectedProject, content);
      closeProgress();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note saved to Dropbox.')));
      Navigator.of(context).pop();
    } catch (e) {
      closeProgress();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save note: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<Project?> _promptForProject() async {
    try {
      final projects = await _projectRepository.streamAll().first;
      final eligible = projects
          .where((p) => (p.folderName?.trim().isNotEmpty ?? false))
          .toList();
      eligible.sort((a, b) {
        if (a.isArchived != b.isArchived) {
          return a.isArchived ? 1 : -1;
        }
        final numA = (a.projectNumber ?? '').trim();
        final numB = (b.projectNumber ?? '').trim();
        if (numA.isNotEmpty && numB.isNotEmpty) {
          final cmp = numA.compareTo(numB);
          if (cmp != 0) return cmp;
        } else if (numA.isNotEmpty || numB.isNotEmpty) {
          return numA.isEmpty ? 1 : -1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (eligible.isEmpty) {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No projects with Dropbox folders found.'),
          ),
        );
        return null;
      }

      if (!mounted) return null;
      return showDialog<Project>(
        context: context,
        builder: (_) => _ProjectPickerDialog(projects: eligible),
      );
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to load projects: $e')));
      return null;
    }
  }

  Future<void> _saveNoteToDropbox(Project project, String content) async {
    final projectRoot = _resolveProjectDropboxPath(project);
    if (projectRoot == null) {
      throw Exception('Selected project is missing a Dropbox folder.');
    }

    var signedIn = await _dropboxAuth.isSignedIn();
    if (!signedIn) {
      await _dropboxAuth.signIn();
      signedIn = await _dropboxAuth.isSignedIn();
    }
    if (!signedIn) {
      throw Exception('Dropbox sign-in is required.');
    }

    final api = DropboxApi(_dropboxAuth);

    await _ensureNotesFolders(api, projectRoot);

    final notesFolder = _stripTrailingSlashes('$projectRoot/00 PRMG/05 NOTE');
    final fileName = DateFormat('yyyy-MM-dd_HHmmss').format(DateTime.now());
    final filePath = '$notesFolder/$fileName.txt';
    final bytes = Uint8List.fromList(utf8.encode(content));

    await api.upload(
      path: filePath,
      bytes: bytes,
      mode: 'overwrite',
      autorename: false,
    );
  }

  Future<void> _ensureNotesFolders(DropboxApi api, String projectRoot) async {
    final normalizedRoot = _stripTrailingSlashes(projectRoot);
    final prmg = '$normalizedRoot/00 PRMG';
    final notes = '$prmg/05 NOTE';
    await api.ensureFolder(normalizedRoot);
    await api.ensureFolder(prmg);
    await api.ensureFolder(notes);
  }

  String? _resolveProjectDropboxPath(Project project) {
    final raw = project.folderName;
    if (raw == null) return null;
    var sanitized = raw.replaceAll('\\', '/').trim();
    if (sanitized.isEmpty) return null;
    sanitized = sanitized.replaceAll(RegExp(r'/+'), '/');
    if (sanitized.startsWith('/')) {
      sanitized = sanitized.substring(1);
    }
    if (!sanitized.toUpperCase().startsWith('SKY/')) {
      sanitized = 'SKY/01 PRJT/$sanitized';
    }
    sanitized = sanitized.replaceAll(RegExp(r'/+'), '/');
    sanitized = sanitized.replaceAll(RegExp(r'/+$'), '');
    return '/$sanitized';
  }

  String _stripTrailingSlashes(String value) {
    final collapsed = value.replaceAll(RegExp(r'/+'), '/');
    return collapsed.replaceAll(RegExp(r'/+$'), '');
  }
}

class _ProjectPickerDialog extends StatefulWidget {
  const _ProjectPickerDialog({required this.projects});

  final List<Project> projects;

  @override
  State<_ProjectPickerDialog> createState() => _ProjectPickerDialogState();
}

class _ProjectPickerDialogState extends State<_ProjectPickerDialog> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Project'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Scrollbar(
          child: ListView.builder(
            itemCount: widget.projects.length,
            itemBuilder: (context, index) {
              final project = widget.projects[index];
              final label = _projectLabel(project);
              return RadioListTile<String>(
                value: project.id,
                groupValue: _selectedId,
                onChanged: (value) => setState(() => _selectedId = value),
                title: Text(label),
                subtitle: project.folderName != null
                    ? Text(
                        project.folderName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedId == null
              ? null
              : () {
                  final project = widget.projects.firstWhere(
                    (p) => p.id == _selectedId,
                  );
                  Navigator.of(context).pop(project);
                },
          child: const Text('Select'),
        ),
      ],
    );
  }

  String _projectLabel(Project project) {
    final number = (project.projectNumber ?? '').trim();
    if (number.isEmpty) {
      return project.name;
    }
    return '$number ${project.name}';
  }
}

class _SavingNoteDialog extends StatelessWidget {
  const _SavingNoteDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Saving to Dropbox...'),
          ],
        ),
      ),
    );
  }
}
