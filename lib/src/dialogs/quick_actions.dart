// lib/src/dialogs/quick_actions.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/models/project.dart';
import '../data/models/task.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/task_repository.dart';
import '../widgets/invoices_section.dart';

Future<List<Project>> _loadProjectsForCurrentUser() async {
  final me = FirebaseAuth.instance.currentUser;
  final repo = ProjectRepository();
  try {
    final all = await repo.streamAll().first;
    if (me == null) {
      return all;
    }
    return all.where((p) => (p.ownerUid ?? '') == me.uid).toList();
  } catch (_) {
    return const <Project>[];
  }
}

String _projectDisplay(Project project) {
  final number = (project.projectNumber ?? '').trim();
  return number.isNotEmpty ? '$number ${project.name}' : project.name;
}

Future<void> showQuickAddInvoiceDialog(BuildContext context) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sign in to create invoices.')),
    );
    return;
  }

  final projects = await _loadProjectsForCurrentUser()
    ..sort(
      (a, b) => _projectDisplay(a)
          .toLowerCase()
          .compareTo(_projectDisplay(b).toLowerCase()),
    );
  if (!context.mounted) return;
  if (projects.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Add a project before creating an invoice.'),
      ),
    );
    return;
  }

  final initial = projects.first;
  await showAddInvoiceDialog(
    context,
    initial.id,
    defaultProjectNumber: initial.projectNumber,
    projectChoices: projects,
  );
}

Future<void> showQuickAddTaskDialog(BuildContext context) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sign in to create tasks.')));
    return;
  }

  final projects = await _loadProjectsForCurrentUser()
    ..sort(
      (a, b) => _projectDisplay(a)
          .toLowerCase()
          .compareTo(_projectDisplay(b).toLowerCase()),
    );
  if (!context.mounted) return;
  if (projects.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a project before creating a task.')),
    );
    return;
  }

  Project selectedProject = projects.first;
  String selectedProjectId = selectedProject.id;
  String? selectedTaskCode =
      (selectedProject.selectedSubphases?.isNotEmpty ?? false)
      ? selectedProject.selectedSubphases!.first.code
      : null;

  final titleCtl = TextEditingController();
  final notesCtl = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final repo = TaskRepository();

  String? nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (innerContext, setState) {
          final subphases =
              selectedProject.selectedSubphases ?? const <SelectedSubphase>[];

          return AlertDialog(
            title: const Text('New Task'),
            scrollable: true,
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedProjectId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Project',
                      border: OutlineInputBorder(),
                    ),
                    items: projects
                        .map(
                          (project) => DropdownMenuItem<String>(
                            value: project.id,
                            child: Text(_projectDisplay(project)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        selectedProjectId = value;
                        selectedProject = projects.firstWhere(
                          (project) => project.id == value,
                        );
                        final nextSubphases =
                            selectedProject.selectedSubphases ??
                            const <SelectedSubphase>[];
                        selectedTaskCode = nextSubphases.isNotEmpty
                            ? nextSubphases.first.code
                            : null;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  if (subphases.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: selectedTaskCode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Project code',
                        border: OutlineInputBorder(),
                      ),
                      items: subphases
                          .map(
                            (s) => DropdownMenuItem<String>(
                              value: s.code,
                              child: Text('${s.code} ${s.name}'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => selectedTaskCode = value),
                    ),
                  ] else ...[
                    TextFormField(
                      enabled: false,
                      decoration: const InputDecoration(
                        labelText: 'Project code',
                        hintText: 'No codes for this project',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: titleCtl,
                    decoration: const InputDecoration(
                      labelText: 'Task title',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: notesCtl,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;

                  final task = TaskItem(
                    id: '_',
                    projectId: selectedProjectId,
                    ownerUid: me.uid,
                    title: titleCtl.text.trim(),
                    description: nullIfEmpty(notesCtl.text),
                    assigneeName: null,
                    dueDate: null,
                    taskStatus: 'In Progress',
                    isStarred: false,
                    taskCode: (selectedTaskCode?.trim().isNotEmpty ?? false)
                        ? selectedTaskCode
                        : null,
                    createdAt: null,
                    updatedAt: null,
                  );

                  try {
                    await repo.add(task);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Task created.')),
                      );
                    }
                  } catch (e) {
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Failed to create task: $e')),
                    );
                  }
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
