// lib/src/pages/task_templates_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/task_template.dart';
import '../data/repositories/task_template_repository.dart';
import '../widgets/form_helpers.dart';

class TaskTemplatesPage extends StatelessWidget {
  TaskTemplatesPage({super.key});

  final _repo = TaskTemplateRepository();
  static const _roles = [
    'Civil',
    'Owner',
    'Surveyor',
    'Architect',
    'MEP',
    'Structural',
    'Geotechnical',
    'Landscape',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view templates')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Task Templates')),
      body: StreamBuilder<List<TaskTemplate>>(
        stream: _repo.streamForUser(me.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <TaskTemplate>[];
          if (items.isEmpty) {
            return _Empty(
              onAdd: () => _showAddDialog(context, me.uid),
              onSeed: () => _seedStarterList(context, me.uid),
            );
          }

          // Group by contract phase (first 2 digits)
          final grouped = <String, List<TaskTemplate>>{};
          for (final t in items) {
            final phase = (t.taskCode.length >= 2)
                ? t.taskCode.substring(0, 2)
                : '00';
            grouped.putIfAbsent(phase, () => []).add(t);
          }

          final orderedPhaseKeys = grouped.keys.toList()
            ..sort((a, b) => _phaseOrder(a).compareTo(_phaseOrder(b)));

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount:
                orderedPhaseKeys.length + 1, // +1 for bottom "New" button
            itemBuilder: (context, index) {
              if (index == orderedPhaseKeys.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: () => _showAddDialog(context, me.uid),
                      icon: const Icon(Icons.add),
                      label: const Text('New Template Task'),
                    ),
                  ),
                );
              }

              final phase = orderedPhaseKeys[index];
              final tasks = List<TaskTemplate>.from(
                grouped[phase] ?? const <TaskTemplate>[],
              )..sort((a, b) => a.taskCode.compareTo(b.taskCode));

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _phaseLabel(phase),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemBuilder: (context, i) {
                          final task = tasks[i];
                          final subtitleParts = <String>[
                            'Code ${task.taskCode}',
                            task.taskResponsibility,
                            if (task.isDeliverable) 'Deliverable',
                          ];
                          final projectNumber = task.projectNumber?.trim();
                          if (projectNumber != null &&
                              projectNumber.isNotEmpty) {
                            subtitleParts.add('Proj $projectNumber');
                          }
                          final note = task.taskNote?.trim();

                          return ListTile(
                            title: Text(task.taskName),
                            subtitle: Text(
                              [
                                subtitleParts.join(' • '),
                                if (note != null && note.isNotEmpty) note,
                              ].where((e) => e.isNotEmpty).join('\n'),
                            ),
                            isThreeLine: note != null && note.isNotEmpty,
                            trailing: const Icon(Icons.edit),
                            onTap: () => _showEditDialog(context, task),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemCount: tasks.length,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static int _phaseOrder(String phase) {
    switch (phase) {
      case '01':
        return 1;
      case '02':
        return 2;
      case '03':
        return 3;
      case '04':
        return 4;
      default:
        return 99;
    }
  }

  static String _phaseLabel(String phase) {
    switch (phase) {
      case '01':
        return '01 — Land Use';
      case '02':
        return '02 — Preliminary Design';
      case '03':
        return '03 — Construction Design';
      case '04':
        return '04 — Construction Management';
      default:
        return '$phase — Other';
    }
  }
}

// ---------- Empty state ----------
class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onSeed;
  const _Empty({required this.onAdd, required this.onSeed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.list_alt, size: 80),
            const SizedBox(height: 12),
            const Text('No template tasks yet'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('New Template Task'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onSeed,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Seed starter list'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Dialogs ----------
Future<void> _showAddDialog(BuildContext context, String ownerUid) async {
  final codeCtl = TextEditingController();
  final projNumCtl = TextEditingController();
  final nameCtl = TextEditingController();
  final noteCtl = TextEditingController();
  String responsibility = 'Civil';
  bool isDeliverable = false;

  final formKey = GlobalKey<FormState>();
  final repo = TaskTemplateRepository();

  String? validateCode(String? value) {
    final s = (value ?? '').trim();
    if (s.length != 4 || int.tryParse(s) == null) return 'Enter a 4-digit code';
    final phase = s.substring(0, 2);
    if (!['01', '02', '03', '04'].contains(phase)) {
      return 'Phase must be 01, 02, 03, or 04';
    }
    return null;
  }

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('New Template Task'),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      appTextField(
                        'Task Code (4 digits)',
                        codeCtl,
                        required: true,
                        hint: 'e.g., 0101',
                      ),
                      const SizedBox(height: 10),
                      appTextField(
                        'Task Name',
                        nameCtl,
                        required: true,
                        hint: 'e.g., Zoning Research',
                      ),
                      const SizedBox(height: 10),
                      appTextField(
                        'Task Note',
                        noteCtl,
                        hint: 'optional notes',
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: responsibility,
                        items: TaskTemplatesPage._roles
                            .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => responsibility = v ?? 'Civil'),
                        decoration: const InputDecoration(
                          labelText: 'Responsibility',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Is Deliverable'),
                        value: isDeliverable,
                        onChanged: (v) => setState(() => isDeliverable = v),
                      ),
                      const SizedBox(height: 10),
                      appTextField(
                        'Default Project Number',
                        projNumCtl,
                        hint: 'optional (e.g., 24017)',
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
                  if (!(formKey.currentState?.validate() ?? true)) return;

                  final code = codeCtl.text.trim();
                  final name = nameCtl.text.trim();
                  if (code.isEmpty || name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code and Name are required.'),
                      ),
                    );
                    return;
                  }
                  if (validateCode(code) != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(validateCode(code)!)),
                    );
                    return;
                  }

                  final t = TaskTemplate(
                    id: '_',
                    taskCode: code,
                    taskName: name,
                    taskNote: noteCtl.text.trim().isEmpty
                        ? null
                        : noteCtl.text.trim(),
                    taskResponsibility: responsibility,
                    isDeliverable: isDeliverable,
                    projectNumber: projNumCtl.text.trim().isEmpty
                        ? null
                        : projNumCtl.text.trim(),
                    ownerUid: ownerUid,
                  );
                  await repo.add(t);
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

Future<void> _showEditDialog(BuildContext context, TaskTemplate t) async {
  final codeCtl = TextEditingController(text: t.taskCode);
  final projNumCtl = TextEditingController(text: t.projectNumber ?? '');
  final nameCtl = TextEditingController(text: t.taskName);
  final noteCtl = TextEditingController(text: t.taskNote ?? '');
  String responsibility = t.taskResponsibility;
  bool isDeliverable = t.isDeliverable;

  final formKey = GlobalKey<FormState>();
  final repo = TaskTemplateRepository();

  String? validateCode(String? value) {
    final s = (value ?? '').trim();
    if (s.length != 4 || int.tryParse(s) == null) return 'Enter a 4-digit code';
    final phase = s.substring(0, 2);
    if (!['01', '02', '03', '04'].contains(phase)) {
      return 'Phase must be 01, 02, 03, or 04';
    }
    return null;
  }

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Edit ${t.taskCode}'),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      appTextField(
                        'Task Code (4 digits)',
                        codeCtl,
                        required: true,
                      ),
                      const SizedBox(height: 10),
                      appTextField('Task Name', nameCtl, required: true),
                      const SizedBox(height: 10),
                      appTextField('Task Note', noteCtl),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: responsibility,
                        items: TaskTemplatesPage._roles
                            .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => responsibility = v ?? 'Civil'),
                        decoration: const InputDecoration(
                          labelText: 'Responsibility',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Is Deliverable'),
                        value: isDeliverable,
                        onChanged: (v) => setState(() => isDeliverable = v),
                      ),
                      const SizedBox(height: 10),
                      appTextField('Default Project Number', projNumCtl),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final ok = await confirmDialog(
                    context,
                    'Delete this template task?',
                  );
                  if (!ok) return;
                  await repo.delete(t.id);
                  // ignore: use_build_context_synchronously
                  Navigator.pop(context);
                },
                child: const Text('Delete'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final code = codeCtl.text.trim();
                  final name = nameCtl.text.trim();
                  if (code.isEmpty || name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Code and Name are required.'),
                      ),
                    );
                    return;
                  }
                  final err = validateCode(code);
                  if (err != null) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(err)));
                    return;
                  }
                  await repo.update(t.id, {
                    'taskCode': code,
                    'taskName': name,
                    'taskNote': noteCtl.text.trim().isEmpty
                        ? null
                        : noteCtl.text.trim(),
                    'taskResponsibility': responsibility,
                    'isDeliverable': isDeliverable,
                    'projectNumber': projNumCtl.text.trim().isEmpty
                        ? null
                        : projNumCtl.text.trim(),
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

// ---------- Seeder ----------
Future<void> _seedStarterList(BuildContext context, String ownerUid) async {
  final repo = TaskTemplateRepository();
  final starters = <TaskTemplate>[
    // 01 — Land Use
    TaskTemplate(
      id: '_',
      taskCode: '0101',
      taskName: 'Zoning Research',
      taskNote: 'Confirm zoning, overlays, variances',
      taskResponsibility: 'Civil',
      isDeliverable: false,
      ownerUid: ownerUid,
    ),
    TaskTemplate(
      id: '_',
      taskCode: '0102',
      taskName: 'Utility Locator (811)',
      taskNote: 'Request locates; map conflicts',
      taskResponsibility: 'Civil',
      isDeliverable: false,
      ownerUid: ownerUid,
    ),
    TaskTemplate(
      id: '_',
      taskCode: '0103',
      taskName: 'Pre-App Meeting',
      taskNote: 'Schedule/attend with AHJ',
      taskResponsibility: 'Owner',
      isDeliverable: false,
      ownerUid: ownerUid,
    ),

    // 02 — Preliminary Design
    TaskTemplate(
      id: '_',
      taskCode: '0201',
      taskName: 'Topographic Survey',
      taskNote: 'Obtain topo + boundary',
      taskResponsibility: 'Surveyor',
      isDeliverable: true,
      ownerUid: ownerUid,
    ),
    TaskTemplate(
      id: '_',
      taskCode: '0202',
      taskName: 'Concept Site Plan',
      taskNote: 'Layout and grading concept',
      taskResponsibility: 'Civil',
      isDeliverable: true,
      ownerUid: ownerUid,
    ),
    TaskTemplate(
      id: '_',
      taskCode: '0203',
      taskName: 'Geotechnical Report',
      taskNote: 'Soils borings + recommendations',
      taskResponsibility: 'Geotechnical',
      isDeliverable: true,
      ownerUid: ownerUid,
    ),

    // 03 — Construction Design
    TaskTemplate(
      id: '_',
      taskCode: '0301',
      taskName: 'Civil CDs',
      taskNote: 'Grading, drainage, utilities',
      taskResponsibility: 'Civil',
      isDeliverable: true,
      ownerUid: ownerUid,
    ),
    TaskTemplate(
      id: '_',
      taskCode: '0302',
      taskName: 'Architectural CDs',
      taskNote: 'Coordinate site/building',
      taskResponsibility: 'Architect',
      isDeliverable: true,
      ownerUid: ownerUid,
    ),
    TaskTemplate(
      id: '_',
      taskCode: '0303',
      taskName: 'MEP CDs',
      taskNote: 'Utility connections + loads',
      taskResponsibility: 'MEP',
      isDeliverable: true,
      ownerUid: ownerUid,
    ),

    // 04 — Construction Management
    TaskTemplate(
      id: '_',
      taskCode: '0401',
      taskName: 'Preconstruction Meeting',
      taskNote: 'Contractor kickoff',
      taskResponsibility: 'Owner',
      isDeliverable: false,
      ownerUid: ownerUid,
    ),
    TaskTemplate(
      id: '_',
      taskCode: '0402',
      taskName: 'RFIs & Submittals',
      taskNote: 'Track and respond',
      taskResponsibility: 'Civil',
      isDeliverable: false,
      ownerUid: ownerUid,
    ),
    TaskTemplate(
      id: '_',
      taskCode: '0403',
      taskName: 'As-Builts',
      taskNote: 'Record drawings',
      taskResponsibility: 'Surveyor',
      isDeliverable: true,
      ownerUid: ownerUid,
    ),
  ];
  final messenger = ScaffoldMessenger.of(context);

  for (final t in starters) {
    await repo.add(t);
  }

  messenger.showSnackBar(
    const SnackBar(content: Text('Seeded starter templates.')),
  );
}
