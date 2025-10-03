// lib/src/pages/projects_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models/project.dart';
import '../data/models/client.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/client_repository.dart';
import '../utils/phone_utils.dart';
import 'project_detail_page.dart';
import '../integrations/dropbox/dropbox_auth.dart';
import '../integrations/dropbox/dropbox_api.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  bool _showArchived = false; // default OFF
  static const _accentYellow = Color(0xFFF1C400);

  final DropboxAuth _dropboxAuth = DropboxAuth();
  Set<String>? _dropboxFolderNames;
  bool _dropboxChecked = false;

  @override
  void initState() {
    super.initState();
    _loadDropboxFolders();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ProjectRepository();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          // Yellow text toggle (tiny, tappable)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: () => setState(() => _showArchived = !_showArchived),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: _accentYellow,
                ),
                child: Text(
                  _showArchived
                      ? 'Hide Archived Tasks'
                      : 'Show Archived Projects',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _accentYellow,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Project>>(
        // Show all projects; we'll filter by isArchived and sort client-side.
        stream: repo.streamAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          var items = snap.data ?? const <Project>[];

          // Filter by archived state unless toggle is ON
          if (!_showArchived) {
            items = items.where((p) => !(p.isArchived)).toList();
          }

          if (items.isEmpty) {
            return _Empty(onAdd: () => _showAddDialog(context));
          }

          // Natural sort by project number ascending, nulls last; tie-break by name
          final sorted = [...items]..sort(_byProjectNumberNaturalAscThenName);

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final p = sorted[i];

              final titleStyle = Theme.of(context).textTheme.titleMedium
                  ?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize:
                        (Theme.of(context).textTheme.titleMedium?.fontSize ??
                            16) +
                        1,
                  );

              return Card(
                margin: EdgeInsets.zero, // tighter vertical rhythm
                color: _subtleSurfaceTint(context),
                child: ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -2),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  // No leading avatar
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          (p.projectNumber != null &&
                                  p.projectNumber!.trim().isNotEmpty)
                              ? '${p.projectNumber} ${p.name}'
                              : p.name,
                          style: titleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _buildLinkStatusIcon(p, context),
                    ],
                  ),
                  subtitle: Text(
                    [
                      p.clientName,
                    ].where((s) => s.toString().trim().isNotEmpty).join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: p.isArchived
                      ? Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.archive,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProjectDetailPage(projectId: p.id),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('New Project'),
        backgroundColor: _accentYellow,
        foregroundColor: Colors.black87,
      ),
    );
  }

  Future<void> _loadDropboxFolders() async {
    try {
      final signedIn = await _dropboxAuth.isSignedIn();
      if (!mounted) return;
      if (!signedIn) {
        setState(() {
          _dropboxFolderNames = null;
          _dropboxChecked = true;
        });
        return;
      }
      final api = DropboxApi(_dropboxAuth);
      final entries = await api.listFolder(path: '/SKY/01 PRJT');
      if (!mounted) return;
      final folderNames = <String>{};
      for (final entry in entries) {
        if (!entry.isFolder) continue;
        final nameLower = entry.name.trim().toLowerCase();
        if (nameLower.isNotEmpty) folderNames.add(nameLower);
        final display = entry.pathDisplay.trim().toLowerCase();
        if (display.isNotEmpty) {
          folderNames.add(display);
          final segments = display
              .split('/')
              .where((segment) => segment.isNotEmpty)
              .toList();
          if (segments.isNotEmpty) {
            folderNames.add(segments.last);
          }
        }
      }
      setState(() {
        _dropboxFolderNames = folderNames;
        _dropboxChecked = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dropboxFolderNames = {};
        _dropboxChecked = true;
      });
    }
  }

  String? _normalizeDropboxFolderName(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final sanitized = trimmed.replaceAll('\\', '/');
    final segments = sanitized
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    final name = segments.isNotEmpty ? segments.last : sanitized;
    return name.trim().toLowerCase();
  }

  Widget _buildLinkStatusIcon(Project project, BuildContext context) {
    final theme = Theme.of(context);
    if (!_dropboxChecked) {
      return const SizedBox(width: 18, height: 18);
    }

    final normalized = _normalizeDropboxFolderName(project.folderName);
    final hasMatch =
        normalized != null &&
        (_dropboxFolderNames?.contains(normalized) ?? false);
    final unavailable = _dropboxFolderNames == null;
    final color = hasMatch
        ? Colors.green
        : unavailable
        ? theme.colorScheme.onSurfaceVariant.withOpacity(0.4)
        : theme.colorScheme.error;
    final icon = Icon(
      hasMatch ? Icons.link : Icons.link_off,
      size: 18,
      color: color,
    );

    Widget wrapped;
    if (hasMatch) {
      wrapped = IconButton(
        icon: icon,
        tooltip: 'Open Dropbox folder',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        splashRadius: 20,
        onPressed: () => _openProjectFolder(project),
      );
    } else if (unavailable) {
      wrapped = Tooltip(
        message: 'Connect Dropbox to check linked folders',
        child: icon,
      );
    } else {
      wrapped = Tooltip(message: 'Dropbox folder not linked', child: icon);
    }

    return Padding(padding: const EdgeInsets.only(left: 8), child: wrapped);
  }

  Future<void> _openProjectFolder(Project project) async {
    final folderPath = _resolveProjectDropboxPath(project);
    if (folderPath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project does not have a Dropbox folder configured.'),
        ),
      );
      return;
    }

    try {
      var signedIn = await _dropboxAuth.isSignedIn();
      if (!signedIn) {
        await _dropboxAuth.signIn();
        signedIn = await _dropboxAuth.isSignedIn();
      }
      if (!signedIn) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dropbox sign-in is required.')),
        );
        return;
      }

      final api = DropboxApi(_dropboxAuth);
      final sharedLink = await api.getOrCreateSharedLink(folderPath);
      final launched = await launchUrl(
        sharedLink,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Dropbox folder.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Dropbox folder: $e')),
      );
    }
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

  Color _subtleSurfaceTint(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Color.alphaBlend(const Color(0x14FFFFFF), surface);
  }

  // --- natural sorting helpers ---

  /// Natural (human) compare of project numbers like "026-01" vs "026-02".
  /// Compares by sequential numeric chunks first; non-digits lexicographically.
  static int _byProjectNumberNaturalAscThenName(Project a, Project b) {
    final pa = a.projectNumber?.trim();
    final pb = b.projectNumber?.trim();

    final hasA = pa != null && pa.isNotEmpty;
    final hasB = pb != null && pb.isNotEmpty;

    if (hasA && hasB) {
      final cmp = _naturalCompare(pa!, pb!);
      if (cmp != 0) return cmp;
    } else if (hasA && !hasB) {
      return -1; // non-null first
    } else if (!hasA && hasB) {
      return 1; // null/empty last
    }

    // tie-breaker: name A→Z
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// Tokenize into alternating numeric (int) and non-numeric (String) chunks.
  static List<Object> _tokenizeNatural(String s) {
    final tokens = <Object>[];
    final buf = StringBuffer();
    bool inNumber = false;

    void flush() {
      if (buf.isEmpty) return;
      final chunk = buf.toString();
      if (inNumber) {
        final n = int.tryParse(chunk);
        tokens.add(n ?? chunk);
      } else {
        tokens.add(chunk.toLowerCase());
      }
      buf.clear();
    }

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      final isDigit = ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39;
      if (isDigit) {
        if (!inNumber) {
          flush();
          inNumber = true;
        }
        buf.write(ch);
      } else {
        if (inNumber) {
          flush();
          inNumber = false;
        }
        buf.write(ch);
      }
    }
    flush();
    return tokens;
  }

  static int _naturalCompare(String a, String b) {
    final ta = _tokenizeNatural(a);
    final tb = _tokenizeNatural(b);
    final len = (ta.length < tb.length) ? ta.length : tb.length;

    for (var i = 0; i < len; i++) {
      final va = ta[i];
      final vb = tb[i];
      if (va == vb) continue;

      if (va is int && vb is int) {
        final c = va.compareTo(vb);
        if (c != 0) return c;
      } else {
        final sa = va.toString();
        final sb = vb.toString();
        final c = sa.compareTo(sb);
        if (c != 0) return c;
      }
    }
    // If all shared tokens equal, shorter token list comes first.
    return ta.length.compareTo(tb.length);
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.work_outline, size: 80),
            const SizedBox(height: 12),
            const Text('No projects yet'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Create your first project'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAddDialog(BuildContext context) async {
  final nameCtl = TextEditingController();
  final clientCtl = TextEditingController();
  final amountCtl = TextEditingController();
  final projectNumCtl = TextEditingController();
  final folderCtl = TextEditingController();
  final contactNameCtl = TextEditingController();
  final contactEmailCtl = TextEditingController();
  final contactPhoneCtl = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final repo = ProjectRepository();
  final me = FirebaseAuth.instance.currentUser;

  final clientRepo = ClientRepository();
  List<ClientRecord> clients = <ClientRecord>[];
  try {
    clients = await clientRepo.streamAll().first;
  } catch (_) {
    clients = <ClientRecord>[];
  }

  clients.sort((a, b) => a.code.toLowerCase().compareTo(b.code.toLowerCase()));

  if (!context.mounted) return;

  ClientRecord? selectedClient;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (innerContext, setState) {
          final mediaQuery = MediaQuery.of(innerContext);
          final bottomInset = mediaQuery.viewInsets.bottom;
          final maxHeight = mediaQuery.size.height * 0.85;

          void applyClientSelection(ClientRecord? client) {
            selectedClient = client;
            clientCtl.text = client?.name ?? '';
            contactNameCtl.text = client?.contactName ?? '';
            contactEmailCtl.text = client?.contactEmail ?? '';
            contactPhoneCtl.text = formatPhoneForDisplay(client?.contactPhone);
            if (client != null) {
              final prefix = client.code.trim();
              if (prefix.isNotEmpty) {
                projectNumCtl.text = '$prefix-';
                projectNumCtl.selection = TextSelection.fromPosition(
                  TextPosition(offset: projectNumCtl.text.length),
                );
              }
            }
          }

          Widget buildClientField() {
            if (clients.isEmpty) {
              return TextFormField(
                controller: clientCtl,
                decoration: const InputDecoration(
                  labelText: 'Client name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              );
            }

            return DropdownButtonFormField<ClientRecord>(
              initialValue: selectedClient,
              decoration: const InputDecoration(
                labelText: 'Client',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: clients
                  .map(
                    (c) => DropdownMenuItem<ClientRecord>(
                      value: c,
                      child: Text('${c.code} ${c.name}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => applyClientSelection(value));
              },
              validator: (value) => value == null ? 'Select a client' : null,
            );
          }

          return AlertDialog(
            title: const Text('New Project'),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: nameCtl,
                          decoration: const InputDecoration(
                            labelText: 'Project name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 10),
                        buildClientField(),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: projectNumCtl,
                          decoration: const InputDecoration(
                            labelText: 'Project number',
                            hintText: 'e.g., 026-01',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: folderCtl,
                          decoration: const InputDecoration(
                            labelText: 'Dropbox folder',
                            hintText: 'e.g., /2024/Project123',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Client Contact',
                            style: Theme.of(innerContext).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: contactNameCtl,
                          decoration: const InputDecoration(
                            labelText: 'Contact name',
                            hintText: 'e.g., Jane Smith',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: contactPhoneCtl,
                          decoration: const InputDecoration(
                            labelText: 'Contact phone',
                            hintText: 'e.g., (555) 123-4567',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.phone,
                          inputFormatters: const [UsPhoneInputFormatter()],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: contactEmailCtl,
                          decoration: const InputDecoration(
                            labelText: 'Contact email',
                            hintText: 'e.g., jane@example.com',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: amountCtl,
                          decoration: const InputDecoration(
                            labelText: 'Contract amount',
                            hintText: 'e.g., 75000',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!(formKey.currentState?.validate() ?? false)) {
                    return;
                  }

                  final clientName =
                      selectedClient?.name ?? clientCtl.text.trim();
                  if (clientName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Client is required.')),
                    );
                    return;
                  }

                  double? amt;
                  if (amountCtl.text.trim().isNotEmpty) {
                    amt = double.tryParse(amountCtl.text.trim());
                  }

                  String? nullIfEmpty(String value) {
                    final trimmed = value.trim();
                    return trimmed.isEmpty ? null : trimmed;
                  }

                  final project = Project(
                    id: '_',
                    name: nameCtl.text.trim(),
                    clientName: clientName,
                    status: 'Active',
                    contractAmount: amt,
                    contactName: nullIfEmpty(contactNameCtl.text),
                    contactEmail: nullIfEmpty(contactEmailCtl.text),
                    contactPhone: normalizePhone(contactPhoneCtl.text),
                    ownerUid: me?.uid,
                    projectNumber: nullIfEmpty(projectNumCtl.text),
                    folderName: nullIfEmpty(folderCtl.text),
                    createdAt: null,
                    isArchived: false,
                  );

                  await repo.add(project);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }

                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Project created.')),
                  );
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
    },
  );
}
