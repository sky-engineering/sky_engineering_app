// lib/src/pages/subphases_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/models/subphase_template.dart';
import '../data/repositories/subphase_template_repository.dart';

import '../data/models/phase_template.dart';
import '../data/repositories/phase_template_repository.dart';
import '../app/shell.dart';

const _accentYellow = Color(0xFFF1C400);

class SubphasesPage extends StatefulWidget {
  const SubphasesPage({super.key});

  @override
  State<SubphasesPage> createState() => _SubphasesPageState();
}

class _SubphasesPageState extends State<SubphasesPage> {
  final _subRepo = SubphaseTemplateRepository();
  final _phaseRepo = PhaseTemplateRepository();
  List<String>? _phaseOrder;
  bool _fabExpanded = false;

  void _refreshPhases() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _persistPhaseOrder(
    List<String> orderedKeys,
    List<PhaseTemplate> phases,
  ) async {
    for (var i = 0; i < orderedKeys.length; i++) {
      final code = orderedKeys[i];
      final match = phases.firstWhere(
        (p) => p.phaseCode == code,
        orElse: () => phases[i % phases.length],
      );
      if (match.sortOrder != i) {
        await _phaseRepo.update(match.id, {'sortOrder': i});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view subphases')),
      );
    }

    final isOwner = me.uid.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Task Structure')),
      bottomNavigationBar: const ShellBottomNav(popCurrentRoute: true),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: isOwner ? _buildFab(me.uid) : null,
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
              if (items.isEmpty) {
                return const _Empty();
              }

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
                  if (ai >= 0 && bi >= 0) {
                    return ai.compareTo(bi);
                  }
                  return a.compareTo(b);
                });

              return _buildPhaseList(
                context: context,
                ownerUid: me.uid,
                phases: phases,
                phaseLabelByCode: phaseLabelByCode,
                grouped: grouped,
                orderedPhaseKeys: phaseKeys,
                isOwner: isOwner,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPhaseList({
    required BuildContext context,
    required String ownerUid,
    required List<PhaseTemplate> phases,
    required Map<String, String> phaseLabelByCode,
    required Map<String, List<SubphaseTemplate>> grouped,
    required List<String> orderedPhaseKeys,
    required bool isOwner,
  }) {
    final keys = _phaseOrder ?? orderedPhaseKeys;
    final normalizedKeys = <String>[
      ...keys.where(grouped.containsKey),
      ...orderedPhaseKeys.where((code) => !keys.contains(code)),
    ];

    if (isOwner && _phaseOrder == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _phaseOrder = List<String>.from(normalizedKeys));
        }
      });
    }

    Widget buildPhaseCard(String phase) {
      final list = grouped[phase]!
        ..sort((a, b) => a.subphaseCode.compareTo(b.subphaseCode));
      final header = phaseLabelByCode[phase] ?? '$phase - (Unnamed Phase)';
      final template = phases.firstWhere(
        (p) => p.phaseCode == phase,
        orElse: () => PhaseTemplate(
          id: '',
          ownerUid: ownerUid,
          phaseCode: phase,
          phaseName: header,
          sortOrder: 0,
        ),
      );

      return Card(
        key: ValueKey('phase-$phase'),
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: template.id.isEmpty
                    ? null
                    : () => _showEditPhaseDialog(
                          context,
                          template,
                          _phaseRepo,
                          _refreshPhases,
                        ),
                child: Text(
                  header,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 6),
              ...list.map(
                (t) => _RowTile(t: t, repo: _subRepo, meUid: ownerUid),
              ),
            ],
          ),
        ),
      );
    }

    final padding = const EdgeInsets.fromLTRB(12, 12, 12, 120);
    if (isOwner) {
      return ReorderableListView.builder(
        padding: padding,
        buildDefaultDragHandles: false,
        itemCount: normalizedKeys.length,
        onReorder: (oldIndex, newIndex) async {
          if (newIndex > normalizedKeys.length) {
            newIndex = normalizedKeys.length;
          }
          final updated = List<String>.from(normalizedKeys);
          final moved = updated.removeAt(oldIndex);
          updated.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, moved);
          setState(() => _phaseOrder = updated);
          await _persistPhaseOrder(updated, phases);
        },
        itemBuilder: (context, index) {
          final phase = normalizedKeys[index];
          return ReorderableDelayedDragStartListener(
            key: ValueKey('phase-$phase'),
            index: index,
            child: buildPhaseCard(phase),
          );
        },
      );
    }

    return ListView(
      padding: padding,
      children: normalizedKeys.map(buildPhaseCard).toList(),
    );
  }

  Widget _buildFab(String ownerUid) {
    return SizedBox(
      width: 200,
      height: _fabExpanded ? 200 : 80,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          if (_fabExpanded) ...[
            Positioned(
              right: 56,
              bottom: 70,
              child: _FabOptionButton(
                label: 'Phase',
                icon: Icons.layers_outlined,
                onTap: () {
                  setState(() => _fabExpanded = false);
                  _showAddPhaseDialog(
                    context,
                    _phaseRepo,
                    ownerUid,
                    _refreshPhases,
                  );
                },
              ),
            ),
            Positioned(
              right: 16,
              bottom: 120,
              child: _FabOptionButton(
                label: 'Subphase',
                icon: Icons.timeline_outlined,
                onTap: () {
                  setState(() => _fabExpanded = false);
                  _showAddDialog(context, ownerUid);
                },
              ),
            ),
          ],
          FloatingActionButton(
            heroTag: 'subphases-fab',
            backgroundColor: _accentYellow,
            foregroundColor: Colors.black,
            onPressed: () => setState(() => _fabExpanded = !_fabExpanded),
            child: Icon(_fabExpanded ? Icons.close : Icons.add),
          ),
        ],
      ),
    );
  }
}

class _FabOptionButton extends StatelessWidget {
  const _FabOptionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
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

  String? validateCode(String? value) {
    final s = (value ?? '').trim();
    if (s.length != 4 || int.tryParse(s) == null) {
      return 'Enter a 4-digit code (e.g., 0201)';
    }
    return null;
  }

  List<String> parseDefaults(String raw) {
    final set = <String>{};
    for (final line in raw.split('\n')) {
      final s = line.trim();
      if (s.isNotEmpty) {
        set.add(s);
      }
    }
    return set.toList();
  }

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Subphase'),
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
                        validator: validateCode,
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
                  if (!(formKey.currentState?.validate() ?? false)) {
                    return;
                  }

                  final code = codeCtl.text.trim();
                  final phaseCode =
                      (code.length >= 2) ? code.substring(0, 2) : '';
                  final defaults = parseDefaults(defaultsCtl.text);

                  final t = SubphaseTemplate(
                    id: '_',
                    ownerUid: ownerUid,
                    subphaseCode: code,
                    subphaseName: nameCtl.text.trim(),
                    phaseCode: phaseCode,
                    defaultTasks: defaults,
                  );
                  await subRepo.add(t);
                  if (!context.mounted) {
                    return;
                  }
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

Future<void> _showAddPhaseDialog(
  BuildContext context,
  PhaseTemplateRepository repo,
  String ownerUid,
  VoidCallback onCreated,
) async {
  final codeCtl = TextEditingController();
  final nameCtl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  String? validateCode(String? value) {
    final s = (value ?? '').trim();
    if (s.length != 2 || int.tryParse(s) == null) {
      return 'Enter a 2-digit code (e.g., 02)';
    }
    return null;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
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
                  validator: validateCode,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g., Preliminary Design',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Required'
                      : null,
                ),
              ],
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
              final phase = PhaseTemplate(
                id: '_',
                ownerUid: ownerUid,
                phaseCode: codeCtl.text.trim(),
                phaseName: nameCtl.text.trim(),
                sortOrder: 0,
              );
              await repo.add(phase);
              if (context.mounted) {
                Navigator.pop(dialogContext);
                onCreated();
              }
            },
            child: const Text('Create'),
          ),
        ],
      );
    },
  );
}

Future<void> _showEditPhaseDialog(
  BuildContext context,
  PhaseTemplate phase,
  PhaseTemplateRepository repo,
  VoidCallback onUpdated,
) async {
  final codeCtl = TextEditingController(text: phase.phaseCode);
  final nameCtl = TextEditingController(text: phase.phaseName);
  final formKey = GlobalKey<FormState>();

  String? validateCode(String? value) {
    final s = (value ?? '').trim();
    if (s.length != 2 || int.tryParse(s) == null) {
      return 'Enter a 2-digit code (e.g., 02)';
    }
    return null;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Edit Phase'),
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
                  validator: validateCode,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: nameCtl,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g., Preliminary Design',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Required'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: dialogContext,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete phase?'),
                  content:
                      Text('Remove "${phase.phaseCode} - ${phase.phaseName}"?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await repo.delete(phase.id);
                if (context.mounted) {
                  Navigator.pop(dialogContext);
                  onUpdated();
                }
              }
            },
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) {
                return;
              }
              await repo.update(phase.id, {
                'phaseCode': codeCtl.text.trim(),
                'phaseName': nameCtl.text.trim(),
              });
              if (context.mounted) {
                Navigator.pop(dialogContext);
                onUpdated();
              }
            },
            child: const Text('Save'),
          ),
        ],
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

  String? validateCode(String? value) {
    final s = (value ?? '').trim();
    if (s.length != 4 || int.tryParse(s) == null) {
      return 'Enter a 4-digit code (e.g., 0201)';
    }
    return null;
  }

  List<String> parseDefaults(String raw) {
    final set = <String>{};
    for (final line in raw.split('\n')) {
      final s = line.trim();
      if (s.isNotEmpty) {
        set.add(s);
      }
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
                        validator: validateCode,
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
                style: TextButton.styleFrom(foregroundColor: Colors.red),
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
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await repo.delete(t.id);
                    if (!context.mounted) {
                      return;
                    }
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
                  if (!(formKey.currentState?.validate() ?? false)) {
                    return;
                  }

                  final newCode = codeCtl.text.trim();
                  final newPhaseCode =
                      (newCode.length >= 2) ? newCode.substring(0, 2) : '';
                  final defaults = parseDefaults(defaultsCtl.text);

                  await repo.update(t.id, {
                    'subphaseCode': newCode,
                    'taskCode': newCode, // legacy mirror
                    'subphaseName': nameCtl.text.trim(),
                    'taskName': nameCtl.text.trim(), // legacy mirror
                    'phaseCode': newPhaseCode,
                    'defaultTasks': defaults,
                  });
                  if (!context.mounted) {
                    return;
                  }
                  Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    },
  );
}
