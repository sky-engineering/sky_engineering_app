// lib/src/pages/subphases_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/models/subphase_template.dart';
import '../data/repositories/subphase_template_repository.dart';

import '../data/models/phase_template.dart';
import '../data/repositories/phase_template_repository.dart';

class SubphasesPage extends StatelessWidget {
  SubphasesPage({super.key});

  final _subRepo = SubphaseTemplateRepository();
  final _phaseRepo = PhaseTemplateRepository();

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view subphases')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Task Structure')),
      body: FutureBuilder<List<PhaseTemplate>>(
        future: _phaseRepo.getAllForUser(me.uid),
        builder: (context, phaseSnap) {
          final phases = (phaseSnap.data ?? const <PhaseTemplate>[]);
          // Fast lookup: phaseCode -> label (e.g., "02 - Preliminary Design")
          final phaseLabelByCode = {
            for (final p in phases)
              p.phaseCode: '${p.phaseCode} - ${p.phaseName}',
          };

          return StreamBuilder<List<SubphaseTemplate>>(
            stream: _subRepo.streamForUser(me.uid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snap.data ?? const <SubphaseTemplate>[];
              if (items.isEmpty) return const _Empty();

              // Group subphases by phaseCode
              final grouped = <String, List<SubphaseTemplate>>{};
              for (final t in items) {
                final key = (t.phaseCode.isNotEmpty)
                    ? t.phaseCode
                    : (t.subphaseCode.length >= 2
                          ? t.subphaseCode.substring(0, 2)
                          : '??');
                (grouped[key] ??= <SubphaseTemplate>[]).add(t);
              }
              final phaseKeys = grouped.keys.toList()
                ..sort((a, b) {
                  // If phases exist, use their sortOrder; else sort by code
                  final ai = phases.indexWhere((p) => p.phaseCode == a);
                  final bi = phases.indexWhere((p) => p.phaseCode == b);
                  if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
                  return a.compareTo(b);
                });

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: phaseKeys.length + 1, // +1 for bottom buttons row
                itemBuilder: (context, idx) {
                  if (idx == phaseKeys.length) {
                    // Bottom action buttons row
                    return Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 80),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _showAddDialog(context, me.uid),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Subphase'),
                          ),
                          FilledButton.icon(
                            onPressed: () =>
                                _showManagePhasesDialog(context, me.uid),
                            icon: const Icon(Icons.tune),
                            label: const Text('Manage Phases'),
                          ),
                        ],
                      ),
                    );
                  }

                  final phase = phaseKeys[idx];
                  final list = grouped[phase]!
                    ..sort((a, b) => a.subphaseCode.compareTo(b.subphaseCode));
                  final header =
                      phaseLabelByCode[phase] ?? '$phase - (Unnamed Phase)';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            header,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          ...list.map(
                            (t) =>
                                _RowTile(t: t, repo: _subRepo, meUid: me.uid),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  final SubphaseTemplate t;
  final SubphaseTemplateRepository repo;
  final String meUid;

  const _RowTile({required this.t, required this.repo, required this.meUid});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(t.subphaseCode),
      ),
      title: Text(
        t.subphaseName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      // No subtitle - keep compact
      trailing: IconButton(
        tooltip: 'Edit subphase',
        icon: const Icon(Icons.chevron_right),
        onPressed: () => _showEditDialog(context, t, meUid),
      ),
      onTap: () => _showEditDialog(context, t, meUid),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.view_list, size: 80),
            SizedBox(height: 12),
            Text('No subphases yet'),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAddDialog(BuildContext context, String ownerUid) async {
  final codeCtl = TextEditingController();
  final nameCtl = TextEditingController();
  final defaultsCtl = TextEditingController(); // one-per-line

  final formKey = GlobalKey<FormState>();
  final subRepo = SubphaseTemplateRepository();

  String? _validateCode(String? v) {
    final s = (v ?? '').trim();
    if (s.length != 4 || int.tryParse(s) == null)
      return 'Enter a 4-digit code (e.g., 0201)';
    return null;
  }

  List<String> _parseDefaults(String raw) {
    final set = <String>{};
    for (final line in raw.split('\n')) {
      final s = line.trim();
      if (s.isNotEmpty) set.add(s);
    }
    return set.toList();
  }

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add subphase'),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: codeCtl,
                        decoration: const InputDecoration(
                          labelText: 'Subphase code',
                          hintText: 'e.g., 0201',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: _validateCode,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: nameCtl,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          hintText: 'e.g., Concept Site Plan',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: defaultsCtl,
                        decoration: const InputDecoration(
                          labelText: 'Default tasks (one per line)',
                          hintText:
                              'e.g.\nKickoff meeting\nCollect survey\nPrelim grading',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 6,
                      ),
                    ],
                  ),
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

                  final code = codeCtl.text.trim();
                  final phaseCode = (code.length >= 2)
                      ? code.substring(0, 2)
                      : '';
                  final defaults = _parseDefaults(defaultsCtl.text);

                  final t = SubphaseTemplate(
                    id: '_',
                    ownerUid: ownerUid,
                    subphaseCode: code,
                    subphaseName: nameCtl.text.trim(),
                    phaseCode: phaseCode,
                    defaultTasks: defaults,
                  );
                  await subRepo.add(t);
                  // ignore: use_build_context_synchronously
                  Navigator.pop(context);
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

Future<void> _showEditDialog(
  BuildContext context,
  SubphaseTemplate t,
  String ownerUid,
) async {
  final codeCtl = TextEditingController(text: t.subphaseCode);
  final nameCtl = TextEditingController(text: t.subphaseName);
  final defaultsCtl = TextEditingController(text: t.defaultTasks.join('\n'));

  final formKey = GlobalKey<FormState>();
  final repo = SubphaseTemplateRepository();

  String? _validateCode(String? v) {
    final s = (v ?? '').trim();
    if (s.length != 4 || int.tryParse(s) == null)
      return 'Enter a 4-digit code (e.g., 0201)';
    return null;
  }

  List<String> _parseDefaults(String raw) {
    final set = <String>{};
    for (final line in raw.split('\n')) {
      final s = line.trim();
      if (s.isNotEmpty) set.add(s);
    }
    return set.toList();
  }

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit subphase'),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: codeCtl,
                        decoration: const InputDecoration(
                          labelText: 'Subphase code',
                          hintText: 'e.g., 0201',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: _validateCode,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: nameCtl,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: defaultsCtl,
                        decoration: const InputDecoration(
                          labelText: 'Default tasks (one per line)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete subphase?'),
                      content: const Text(
                        'This removes it from your template list.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await repo.delete(t.id);
                    // ignore: use_build_context_synchronously
                    Navigator.pop(context);
                  }
                },
                child: const Text('Delete'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;

                  final newCode = codeCtl.text.trim();
                  final newPhaseCode = (newCode.length >= 2)
                      ? newCode.substring(0, 2)
                      : '';
                  final defaults = _parseDefaults(defaultsCtl.text);

                  await repo.update(t.id, {
                    'subphaseCode': newCode,
                    'taskCode': newCode, // legacy mirror
                    'subphaseName': nameCtl.text.trim(),
                    'taskName': nameCtl.text.trim(), // legacy mirror
                    'phaseCode': newPhaseCode,
                    'defaultTasks': defaults,
                  });
                  // ignore: use_build_context_synchronously
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showManagePhasesDialog(
  BuildContext context,
  String ownerUid,
) async {
  final repo = PhaseTemplateRepository();
  List<PhaseTemplate> list;
  try {
    list = await repo.getAllForUser(ownerUid);
  } on FirebaseException catch (e) {
    if (!context.mounted) return;
    final message = (e.message != null && e.message!.trim().isNotEmpty)
        ? e.message!.trim()
        : e.code;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not load phases: $message')));
    return;
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not load phases')));
    return;
  }
  if (!context.mounted) return;
  final phases = [...list]; // mutable

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> _addPhase() async {
            final codeCtl = TextEditingController();
            final nameCtl = TextEditingController();
            final formKey = GlobalKey<FormState>();

            String? _validateCode(String? v) {
              final s = (v ?? '').trim();
              if (s.length != 2 || int.tryParse(s) == null)
                return 'Enter 2-digit code, e.g., 02';
              return null;
            }

            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Add Phase'),
                content: Form(
                  key: formKey,
                  child: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: codeCtl,
                          decoration: const InputDecoration(
                            labelText: 'Phase code',
                            hintText: 'e.g., 02',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          validator: _validateCode,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: nameCtl,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            hintText: 'e.g., Preliminary Design',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      final p = PhaseTemplate(
                        id: '_',
                        ownerUid: ownerUid,
                        phaseCode: codeCtl.text.trim(),
                        phaseName: nameCtl.text.trim(),
                        sortOrder: phases.length,
                      );
                      final newId = await repo.add(p);
                      setState(() => phases.add(p.copyWith(id: newId)));
                      // ignore: use_build_context_synchronously
                      Navigator.pop(ctx);
                    },
                    child: const Text('Create'),
                  ),
                ],
              ),
            );
          }

          Future<void> _deletePhase(PhaseTemplate p) async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete phase?'),
                content: Text('Remove "${p.phaseCode} - ${p.phaseName}"?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (ok == true) {
              await repo.delete(p.id);
              setState(() => phases.removeWhere((x) => x.id == p.id));
            }
          }

          return AlertDialog(
            title: const Text('Manage Phases'),
            content: SizedBox(
              width: 460,
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: phases.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final moved = phases.removeAt(oldIndex);
                  phases.insert(newIndex, moved);
                  setState(() {});
                  // Persist new order
                  for (var i = 0; i < phases.length; i++) {
                    if (phases[i].sortOrder != i) {
                      await repo.update(phases[i].id, {'sortOrder': i});
                      phases[i] = phases[i].copyWith(sortOrder: i);
                    }
                  }
                },
                itemBuilder: (context, i) {
                  final p = phases[i];
                  return ListTile(
                    key: ValueKey(p.id),
                    dense: true,
                    leading: const Icon(Icons.drag_indicator),
                    title: Text('${p.phaseCode} - ${p.phaseName}'),
                    trailing: IconButton(
                      tooltip: 'Delete phase',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deletePhase(p),
                    ),
                  );
                },
              ),
            ),
            actions: [
              FilledButton.icon(
                onPressed: _addPhase,
                icon: const Icon(Icons.add),
                label: const Text('Add Phase'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    },
  );
}
