// lib/src/pages/projects_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';
import 'project_detail_page.dart';
import '../dialogs/select_subphases_dialog.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  bool _showArchived = false; // default OFF
  static const _accentYellow = Color(0xFFF1C400);

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
                child: ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -2),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  // No leading avatar
                  title: Text(
                    (p.projectNumber != null &&
                            p.projectNumber!.trim().isNotEmpty)
                        ? '${p.projectNumber} ${p.name}'
                        : p.name,
                    style: titleStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
  final formKey = GlobalKey<FormState>();
  final repo = ProjectRepository();
  final me = FirebaseAuth.instance.currentUser;

  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('New Project'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                    labelText: 'Project name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: clientCtl,
                  decoration: const InputDecoration(
                    labelText: 'Client name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: projectNumCtl,
                  decoration: const InputDecoration(
                    labelText: 'Project number (optional)',
                    hintText: 'e.g., 026-01',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: amountCtl,
                  decoration: const InputDecoration(
                    labelText: 'Contract amount (optional)',
                    hintText: 'e.g., 75000',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;

              double? amt;
              if (amountCtl.text.trim().isNotEmpty) {
                amt = double.tryParse(amountCtl.text.trim());
              }

              final p = Project(
                id: '_',
                name: nameCtl.text.trim(),
                clientName: clientCtl.text.trim(),
                status: 'Active',
                contractAmount: amt,
                ownerUid: me?.uid,
                projectNumber: projectNumCtl.text.trim().isEmpty
                    ? null
                    : projectNumCtl.text.trim(),
                createdAt: null,
                // Explicit default: not archived
                isArchived: false,
              );

              final id = await repo.add(p);
              // ignore: use_build_context_synchronously
              Navigator.pop(context);

              // Follow-up: Select subphases for the new project
              if (me != null) {
                await showSelectSubphasesDialog(
                  context,
                  projectId: id,
                  ownerUid: me.uid,
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Project created. Sign in to select subphases.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      );
    },
  );
}
