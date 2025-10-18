// lib/src/pages/phase_manager_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/models/phase_template.dart';
import '../data/repositories/phase_template_repository.dart';

class PhaseManagerPage extends StatelessWidget {
  const PhaseManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Phases'),
        actions: const [_AddPhaseButton()],
      ),
      body: const _PhaseList(),
      floatingActionButton: const _FabAddPhase(),
    );
  }
}

class _PhaseList extends StatelessWidget {
  const _PhaseList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final me = authSnap.data;
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (me == null) {
          return const Center(child: Text('Please sign in to manage phases'));
        }

        // IMPORTANT: no orderBy here → avoids needing a composite index
        final query = FirebaseFirestore.instance
            .collection('phases')
            .where('ownerUid', isEqualTo: me.uid);

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorBox(
                message: 'Could not load phases.',
                details: snap.error.toString(),
              );
            }

            final docs = snap.data?.docs ?? const [];
            // Prefer using your model factory if available
            final phases = docs.map(PhaseTemplate.fromDoc).toList()
              ..sort((a, b) {
                final bySort = a.sortOrder.compareTo(b.sortOrder);
                if (bySort != 0) return bySort;
                final ai = int.tryParse(a.phaseCode) ?? 999;
                final bi = int.tryParse(b.phaseCode) ?? 999;
                return ai.compareTo(bi);
              });

            if (phases.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.tune, size: 80),
                      SizedBox(height: 12),
                      Text('No phases yet'),
                      SizedBox(height: 8),
                      _AddPhaseInline(),
                    ],
                  ),
                ),
              );
            }

            return ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: phases.length,
              onReorder: (oldIndex, newIndex) =>
                  _persistReorder(context, phases, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final p = phases[index];
                return ListTile(
                  key: ValueKey(p.id),
                  dense: true,
                  title: Text('${p.phaseCode} — ${p.phaseName}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editPhaseDialog(context, p),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await PhaseTemplateRepository().delete(p.id);
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AddPhaseButton extends StatelessWidget {
  const _AddPhaseButton();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => _addPhaseDialog(context),
      child: const Text('Add Phase'),
    );
  }
}

class _AddPhaseInline extends StatelessWidget {
  const _AddPhaseInline();

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _addPhaseDialog(context),
      icon: const Icon(Icons.add),
      label: const Text('Add Phase'),
    );
  }
}

class _FabAddPhase extends StatelessWidget {
  const _FabAddPhase();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () => _addPhaseDialog(context),
      child: const Icon(Icons.add),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.details});
  final String message;
  final String details;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64),
            const SizedBox(height: 12),
            Text(message),
            const SizedBox(height: 8),
            Text(
              details,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// =====================
// Dialogs
// =====================

Future<void> _addPhaseDialog(BuildContext context) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Please sign in')));
    return;
  }

  final codeCtl = TextEditingController();
  final nameCtl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  String? validateCode(String s) {
    if (s.length != 2 || int.tryParse(s) == null) {
      return 'Enter a 2-digit code (e.g., 02)';
    }
    return null;
  }

  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Add Phase'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: codeCtl,
              decoration: const InputDecoration(
                labelText: 'Phase Code (2 digits, e.g., 02)',
              ),
              validator: (v) => validateCode((v ?? '').trim()),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Phase Name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
          ],
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
            final navigator = Navigator.of(context);
            await PhaseTemplateRepository().add(
              PhaseTemplate(
                id: '',
                ownerUid: me.uid,
                phaseCode: codeCtl.text.trim(),
                phaseName: nameCtl.text.trim(),
                sortOrder: 999, // large default; sortable client-side
                createdAt: null,
                updatedAt: null,
              ),
            );
            navigator.pop();
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<void> _editPhaseDialog(BuildContext context, PhaseTemplate p) async {
  final codeCtl = TextEditingController(text: p.phaseCode);
  final nameCtl = TextEditingController(text: p.phaseName);
  final formKey = GlobalKey<FormState>();

  String? validateCode(String s) {
    if (s.length != 2 || int.tryParse(s) == null) {
      return 'Enter a 2-digit code (e.g., 02)';
    }
    return null;
  }

  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('${p.phaseCode} — Edit Phase'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: codeCtl,
              decoration: const InputDecoration(
                labelText: 'Phase Code (2 digits, e.g., 02)',
              ),
              validator: (v) => validateCode((v ?? '').trim()),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Phase Name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
          ],
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
            final navigator = Navigator.of(context);
            await PhaseTemplateRepository().update(p.id, {
              'phaseCode': codeCtl.text.trim(),
              'phaseName': nameCtl.text.trim(),
              'updatedAt': DateTime.now(),
            });
            if (navigator.canPop()) navigator.pop();
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// =====================
// Reorder persistence
// =====================

Future<void> _persistReorder(
  BuildContext context,
  List<PhaseTemplate> phases,
  int oldIndex,
  int newIndex,
) async {
  if (newIndex > oldIndex) newIndex -= 1;
  final moved = phases.removeAt(oldIndex);
  phases.insert(newIndex, moved);

  final repo = PhaseTemplateRepository();
  for (var i = 0; i < phases.length; i++) {
    await repo.update(phases[i].id, {
      'sortOrder': i,
      'updatedAt': DateTime.now(),
    });
  }
}
