// lib/src/pages/note_editor_page.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:super_clipboard/super_clipboard.dart';

import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';
import '../integrations/dropbox/dropbox_api.dart';
import '../integrations/dropbox/dropbox_auth.dart';

class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({super.key});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteAttachment {
  _NoteAttachment({required this.id, required this.bytes});

  final String id;
  final Uint8List bytes;
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final TextEditingController _controller = TextEditingController();
  final ProjectRepository _projectRepository = ProjectRepository();
  final DropboxAuth _dropboxAuth = DropboxAuth();
  final ImagePicker _picker = ImagePicker();

  bool _saving = false;
  bool _hasChanges = false;
  bool _isPickingImage = false;
  final List<_NoteAttachment> _attachments = <_NoteAttachment>[];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    _updateHasChanges();
  }

  void _updateHasChanges() {
    final hasText = _controller.text.trim().isNotEmpty;
    final dirty = hasText || _attachments.isNotEmpty;
    if (dirty != _hasChanges && !_saving) {
      setState(() => _hasChanges = dirty);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        if (_attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildAttachmentStrip(),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Start typing...',
              ),
              autofocus: true,
              cursorColor: Theme.of(context).colorScheme.onSurface,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              contextMenuBuilder: (context, EditableTextState state) {
                final items = state.contextMenuButtonItems
                    .map((item) {
                      if (item.type == ContextMenuButtonType.paste) {
                        final original = item.onPressed;
                        return ContextMenuButtonItem(
                          type: item.type,
                          onPressed: () async {
                            Navigator.of(context).pop();
                            final handled = await _handlePaste();
                            if (!handled) {
                              original?.call();
                            }
                          },
                        );
                      }
                      return item;
                    })
                    .toList(growable: false);
                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: state.contextMenuAnchors,
                  buttonItems: items,
                );
              },
            ),
          ),
        ),
      ],
    );

    return PopScope(
      canPop: !_hasChanges || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        final navigator = Navigator.of(context);
        final shouldLeave = await _confirmDiscard();
        if (!mounted) return;
        if (shouldLeave) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Note'),
          leading: BackButton(onPressed: _handleBack),
          actions: [
            IconButton(
              tooltip: 'Add photo',
              onPressed: (_saving || _isPickingImage)
                  ? null
                  : _showImageSourceSheet,
              icon: _isPickingImage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.add_a_photo_outlined),
            ),
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
        body: body,
      ),
    );
  }

  Future<void> _showImageSourceSheet() async {
    FocusScope.of(context).unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from library'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || source == null) return;
    await _pickImage(source);
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _isPickingImage = true);
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 80);
      if (!mounted || file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _attachments.add(
          _NoteAttachment(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            bytes: bytes,
          ),
        );
        _isPickingImage = false;
      });
      _updateHasChanges();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add image: $e')));
      setState(() => _isPickingImage = false);
    }
  }

  void _removeAttachment(String id) {
    setState(() {
      _attachments.removeWhere((attachment) => attachment.id == id);
    });
    _updateHasChanges();
  }

  Future<bool> _handlePaste() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return false;
    }

    try {
      final reader = await clipboard.read();
      final imageFormats = <FileFormat>[
        Formats.png,
        Formats.jpeg,
        Formats.heic,
        Formats.heif,
        Formats.gif,
        Formats.webp,
        Formats.tiff,
        Formats.bmp,
      ];

      for (final format in imageFormats) {
        if (!reader.canProvide(format)) {
          continue;
        }

        final completer = Completer<Uint8List?>();
        final progress = reader.getFile(
          format,
          (file) async {
            try {
              final data = await file.readAll();
              if (!completer.isCompleted) {
                completer.complete(data);
              }
            } catch (error) {
              if (!completer.isCompleted) {
                completer.completeError(error);
              }
            }
          },
          onError: (error) {
            if (!completer.isCompleted) {
              completer.completeError(error);
            }
          },
        );

        if (progress == null && !completer.isCompleted) {
          completer.complete(null);
        }

        try {
          final bytes = await completer.future.timeout(
            const Duration(seconds: 5),
            onTimeout: () => null,
          );
          if (bytes != null && bytes.isNotEmpty) {
            if (!mounted) return true;
            setState(() {
              _attachments.add(
                _NoteAttachment(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  bytes: bytes,
                ),
              );
            });
            _updateHasChanges();
            return true;
          }
        } catch (_) {
          // Continue checking other formats on errors.
        }
      }
    } catch (e) {
      debugPrint('Clipboard paste failed: $e');
    }

    return false;
  }

  Widget _buildAttachmentStrip() {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final attachment = _attachments[index];
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Image.memory(attachment.bytes, fit: BoxFit.cover),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _removeAttachment(attachment.id),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: _attachments.length,
      ),
    );
  }

  String _projectDisplayLabel(Project project) {
    final number = (project.projectNumber ?? '').trim();
    if (number.isEmpty) {
      return project.name;
    }
    return '$number ${project.name}';
  }

  Future<void> _handleBack() async {
    if (_saving) return;
    final navigator = Navigator.of(context);
    final shouldLeave = await _confirmDiscard();
    if (!mounted) return;
    if (shouldLeave) {
      navigator.pop();
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text(
            'Proceed without saving and all changes will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Go back to editor'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Proceed without saving'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _handleDone() async {
    final content = _controller.text;
    if (content.trim().isEmpty && _attachments.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add some text or attach at least one image.'),
        ),
      );
      return;
    }

    final overlayNavigator = Navigator.of(context, rootNavigator: true);
    final pageNavigator = Navigator.of(context);

    final selectedProject = await _promptForProject();
    if (!mounted || selectedProject == null) {
      return;
    }

    setState(() => _saving = true);

    var progressClosed = false;
    void closeProgress() {
      if (progressClosed) return;
      progressClosed = true;
      if (overlayNavigator.canPop()) {
        overlayNavigator.pop();
      }
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SavingNoteDialog(),
    );
    await Future<void>.delayed(Duration.zero);

    final attachments = List<_NoteAttachment>.from(_attachments);

    try {
      await _saveNoteToDropbox(selectedProject, content, attachments);
      if (!mounted) {
        closeProgress();
        return;
      }
      closeProgress();
      setState(() {
        _attachments.clear();
        _hasChanges = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note saved to Dropbox.')));
      pageNavigator.pop();
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

  Future<void> _saveNoteToDropbox(
    Project project,
    String content,
    List<_NoteAttachment> attachments,
  ) async {
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
    final timestamp = DateTime.now();
    final fileName = DateFormat('yyyy-MM-dd_HHmmss').format(timestamp);
    final filePath = '$notesFolder/$fileName.pdf';
    final pdfBytes = await _buildPdfBytes(
      project: project,
      content: content,
      attachments: attachments,
      timestamp: timestamp,
    );

    await api.upload(
      path: filePath,
      bytes: pdfBytes,
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

  Future<Uint8List> _buildPdfBytes({
    required Project project,
    required String content,
    required List<_NoteAttachment> attachments,
    required DateTime timestamp,
  }) async {
    final doc = pw.Document();
    final projectLabel = _projectDisplayLabel(project);
    final formattedDate = DateFormat('MMMM d, yyyy h:mm a').format(timestamp);
    final noteText = content.trim();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 40),
        build: (context) {
          final widgets = <pw.Widget>[
            pw.Text(
              'Field Note',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              projectLabel,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              formattedDate,
              style: pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
          ];

          if (noteText.isNotEmpty) {
            widgets.add(
              pw.Text(
                noteText,
                style: pw.TextStyle(fontSize: 12, height: 1.35),
              ),
            );
            widgets.add(pw.SizedBox(height: 18));
          }

          if (attachments.isNotEmpty) {
            widgets.add(
              pw.Text(
                'Photos',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 10));
            for (var i = 0; i < attachments.length; i++) {
              final attachment = attachments[i];
              widgets.add(
                pw.Text(
                  'Photo \${i + 1}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              );
              widgets.add(pw.SizedBox(height: 6));
              widgets.add(
                pw.Container(
                  width: double.infinity,
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                  ),
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Image(
                    pw.MemoryImage(attachment.bytes),
                    fit: pw.BoxFit.contain,
                  ),
                ),
              );
              if (i != attachments.length - 1) {
                widgets.add(pw.SizedBox(height: 16));
              }
            }
          }

          return widgets;
        },
      ),
    );

    return doc.save();
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
              final selected = project.id == _selectedId;
              return ListTile(
                onTap: () => setState(() => _selectedId = project.id),
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(label),
                subtitle: project.folderName != null
                    ? Text(
                        project.folderName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                selected: selected,
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
