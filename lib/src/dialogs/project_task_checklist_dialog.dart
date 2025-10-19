// lib/src/dialogs/project_task_checklist_dialog.dart
import 'package:flutter/material.dart';

import '../data/models/checklist.dart';
import '../data/models/project.dart';

Future<ProjectTaskChecklistDialogResult?> showProjectTaskChecklistDialog(
  BuildContext context, {
  required List<Checklist> templates,
  required List<Project> projects,
}) {
  return showDialog<ProjectTaskChecklistDialogResult?>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _ProjectTaskChecklistDialog(
        templates: templates,
        projects: projects,
      );
    },
  );
}

class ProjectTaskChecklistDialogResult {
  ProjectTaskChecklistDialogResult({
    required this.name,
    required this.checklistId,
    required this.projectId,
  });

  final String name;
  final String checklistId;
  final String projectId;
}

class _ProjectTaskChecklistDialog extends StatefulWidget {
  const _ProjectTaskChecklistDialog({
    required this.templates,
    required this.projects,
  });

  final List<Checklist> templates;
  final List<Project> projects;

  @override
  State<_ProjectTaskChecklistDialog> createState() =>
      _ProjectTaskChecklistDialogState();
}

class _ProjectTaskChecklistDialogState
    extends State<_ProjectTaskChecklistDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String? _selectedChecklistId;
  String? _selectedProjectId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    if (widget.templates.isNotEmpty) {
      _selectedChecklistId = widget.templates.first.id;
    }
    if (widget.projects.isNotEmpty) {
      final sorted = _sortedProjects();
      _selectedProjectId = sorted.first.id;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ProjectTaskChecklistDialog oldWidget) {
    super.didUpdateWidget(oldWidget);

    String? nextChecklistId = _selectedChecklistId;
    if (widget.templates.isEmpty) {
      nextChecklistId = null;
    } else if (nextChecklistId == null ||
        !widget.templates.any((template) => template.id == nextChecklistId)) {
      nextChecklistId = widget.templates.first.id;
    }

    final sortedProjects = _sortedProjects();
    String? nextProjectId = _selectedProjectId;
    if (sortedProjects.isEmpty) {
      nextProjectId = null;
    } else if (nextProjectId == null ||
        !sortedProjects.any((project) => project.id == nextProjectId)) {
      nextProjectId = sortedProjects.first.id;
    }

    if (nextChecklistId != _selectedChecklistId ||
        nextProjectId != _selectedProjectId) {
      setState(() {
        _selectedChecklistId = nextChecklistId;
        _selectedProjectId = nextProjectId;
      });
    }
  }

  bool get _canSubmit {
    return (_formKey.currentState?.validate() ?? false) &&
        _selectedChecklistId != null &&
        _selectedProjectId != null;
  }

  List<Project> _sortedProjects() {
    final sorted = [...widget.projects];
    sorted.sort(
      (a, b) => _projectLabel(
        a,
      ).toLowerCase().compareTo(_projectLabel(b).toLowerCase()),
    );
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final templates = widget.templates;
    final sortedProjects = _sortedProjects();
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Create Project Task Checklist'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Project task checklist name',
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: templates.isEmpty ? null : _selectedChecklistId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Source checklist',
                ),
                items: templates
                    .map(
                      (template) => DropdownMenuItem<String>(
                        value: template.id,
                        child: Text(template.title),
                      ),
                    )
                    .toList(growable: false),
                onChanged: templates.isEmpty
                    ? null
                    : (value) => setState(() {
                        _selectedChecklistId = value;
                      }),
              ),
              if (templates.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Create a checklist first before making a project task checklist.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: sortedProjects.isEmpty ? null : _selectedProjectId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Project'),
                items: sortedProjects
                    .map(
                      (project) => DropdownMenuItem<String>(
                        value: project.id,
                        child: Text(_projectLabel(project)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: sortedProjects.isEmpty
                    ? null
                    : (value) => setState(() {
                        _selectedProjectId = value;
                      }),
              ),
              if (sortedProjects.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No projects available. Add a project before continuing.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_canSubmit) {
              _formKey.currentState?.validate();
              return;
            }
            Navigator.of(context).pop(
              ProjectTaskChecklistDialogResult(
                name: _nameController.text.trim(),
                checklistId: _selectedChecklistId!,
                projectId: _selectedProjectId!,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

String _projectLabel(Project project) {
  final number = project.projectNumber?.trim();
  final name = project.name.trim();
  if (number != null && number.isNotEmpty) {
    return '$number $name'.trim();
  }
  return name;
}
