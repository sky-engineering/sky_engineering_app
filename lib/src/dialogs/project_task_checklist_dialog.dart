// lib/src/dialogs/project_task_checklist_dialog.dart
import 'package:flutter/material.dart';

import '../data/models/checklist.dart';
import '../data/models/project.dart';
import '../data/models/project_task_checklist.dart';

Future<ProjectTaskChecklistDialogResult?> showProjectTaskChecklistDialog(
  BuildContext context, {
  required List<Checklist> templates,
  required List<Project> projects,
  ProjectTaskChecklist? initial,
}) {
  return showDialog<ProjectTaskChecklistDialogResult?>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _ProjectTaskChecklistDialog(
        templates: templates,
        projects: projects,
        initial: initial,
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
    this.initial,
  });

  final List<Checklist> templates;
  final List<Project> projects;
  final ProjectTaskChecklist? initial;

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

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    if (_isEdit) {
      _selectedChecklistId = widget.initial!.templateId;
    } else if (widget.templates.isNotEmpty) {
      _selectedChecklistId = widget.templates.first.id;
    }

    final sorted = _sortedProjects();
    if (_isEdit) {
      _selectedProjectId = widget.initial!.projectId;
      if (_selectedProjectId == null && sorted.isNotEmpty) {
        _selectedProjectId = sorted.first.id;
      }
    } else if (sorted.isNotEmpty) {
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
    if (_isEdit) {
      nextChecklistId ??= widget.initial?.templateId;
    } else if (widget.templates.isEmpty) {
      nextChecklistId = null;
    } else if (nextChecklistId == null ||
        !widget.templates.any((template) => template.id == nextChecklistId)) {
      nextChecklistId = widget.templates.first.id;
    }

    final sortedProjects = _sortedProjects();
    String? nextProjectId = _selectedProjectId;
    if (_isEdit) {
      nextProjectId ??= widget.initial?.projectId;
    } else if (sortedProjects.isEmpty) {
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
    final hasChecklist =
        _selectedChecklistId != null || widget.initial?.templateId != null;
    return (_formKey.currentState?.validate() ?? false) &&
        hasChecklist &&
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

    final projectItems = sortedProjects
        .map(
          (project) => DropdownMenuItem<String>(
            value: project.id,
            child: Text(_projectLabel(project)),
          ),
        )
        .toList(growable: true);

    if (widget.initial != null && widget.initial!.projectId.isNotEmpty) {
      final hasExistingProject = projectItems.any(
        (item) => item.value == widget.initial!.projectId,
      );
      if (!hasExistingProject) {
        projectItems.add(
          DropdownMenuItem<String>(
            value: widget.initial!.projectId,
            child: Text(_projectLabelForChecklist(widget.initial!)),
          ),
        );
      }
    }

    final checklistId =
        _selectedChecklistId ?? widget.initial?.templateId ?? '';

    return AlertDialog(
      title: Text(
        _isEdit
            ? 'Edit Project Task Checklist'
            : 'Create Project Task Checklist',
      ),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              if (_isEdit) ...[
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Source checklist',
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(widget.initial!.templateTitle),
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                DropdownButtonFormField<String>(
                  key: ValueKey<int>(
                    Object.hash(
                      _selectedChecklistId,
                      templates.length,
                      templates.hashCode,
                    ),
                  ),
                  initialValue: templates.isEmpty ? null : _selectedChecklistId,
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
              ],
              DropdownButtonFormField<String>(
                key: ValueKey<int>(
                  Object.hash(
                    _selectedProjectId,
                    sortedProjects.length,
                    sortedProjects.hashCode,
                  ),
                ),
                initialValue: projectItems.isEmpty ? null : _selectedProjectId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Project'),
                items: projectItems,
                onChanged: projectItems.isEmpty
                    ? null
                    : (value) => setState(() {
                        _selectedProjectId = value;
                      }),
              ),
              if (projectItems.isEmpty)
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
            if (!_canSubmit || checklistId.isEmpty) {
              _formKey.currentState?.validate();
              return;
            }
            Navigator.of(context).pop(
              ProjectTaskChecklistDialogResult(
                name: _nameController.text.trim(),
                checklistId: checklistId,
                projectId: _selectedProjectId!,
              ),
            );
          },
          child: Text(_isEdit ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  String _projectLabel(Project project) {
    final number = project.projectNumber?.trim();
    if (number != null && number.isNotEmpty) {
      return '$number - ${project.name}'.trim();
    }
    return project.name;
  }

  String _projectLabelForChecklist(ProjectTaskChecklist checklist) {
    final number = checklist.projectNumber?.trim();
    if (number != null && number.isNotEmpty) {
      return '$number - ${checklist.projectName}'.trim();
    }
    return checklist.projectName;
  }
}
