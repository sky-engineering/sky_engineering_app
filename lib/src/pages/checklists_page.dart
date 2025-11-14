// lib/src/pages/checklists_page.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models/checklist.dart';
import '../data/models/project.dart';
import '../data/models/project_task_checklist.dart';
import '../data/repositories/project_repository.dart';
import '../dialogs/checklist_edit_dialog.dart';
import '../dialogs/project_task_checklist_dialog.dart';
import '../services/checklists_service.dart';
import '../services/project_task_checklist_service.dart';
import '../widgets/form_helpers.dart';
import '../app/shell.dart';

class ChecklistsPage extends StatefulWidget {
  const ChecklistsPage({super.key});

  @override
  State<ChecklistsPage> createState() => _ChecklistsPageState();
}

class _ChecklistsPageState extends State<ChecklistsPage> {
  final ChecklistsService _templateService = ChecklistsService.instance;
  final ProjectTaskChecklistService _projectTaskService =
      ProjectTaskChecklistService.instance;
  final ProjectRepository _projectRepository = ProjectRepository();

  final Set<String> _templateExpanded = <String>{};
  final Set<String> _projectExpanded = <String>{};

  bool _templatesLoading = true;
  bool _projectTasksLoading = true;
  bool _projectsLoading = true;

  StreamSubscription<List<Project>>? _projectSub;
  List<Project> _projects = const <Project>[];

  @override
  void initState() {
    super.initState();
    _templateService.addListener(_handleTemplateChanged);
    _templateService.ensureLoaded().then((_) {
      if (mounted) {
        setState(() => _templatesLoading = false);
      }
    });

    _projectTaskService.addListener(_handleProjectTaskChanged);
    _projectTaskService.ensureLoaded().then((_) {
      if (mounted) {
        setState(() => _projectTasksLoading = false);
      }
    });

    _projectSub = _projectRepository.streamAll().listen((projects) {
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _projectsLoading = false;
      });
    });
  }

  @override
  void dispose() {
    _templateService.removeListener(_handleTemplateChanged);
    _projectTaskService.removeListener(_handleProjectTaskChanged);
    _projectSub?.cancel();
    super.dispose();
  }

  void _handleTemplateChanged() {
    if (!mounted) return;
    final ids = _templateService.checklists.map((c) => c.id).toSet();
    _templateExpanded.removeWhere((id) => !ids.contains(id));
    setState(() {});
  }

  void _handleProjectTaskChanged() {
    if (!mounted) return;
    final ids = _projectTaskService.checklists.map((c) => c.id).toSet();
    _projectExpanded.removeWhere((id) => !ids.contains(id));
    setState(() {});
  }

  Future<void> _handleAddChecklist() async {
    final result = await showChecklistEditDialog(context);
    if (result == null) return;
    try {
      final created = await _templateService.createChecklist(
        title: result.title,
        items: result.items,
      );
      setState(() {
        _templateExpanded.add(created.id);
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _handleEditChecklist(Checklist checklist) async {
    final result = await showChecklistEditDialog(context, initial: checklist);
    if (result == null) return;
    try {
      final updated = checklist.copyWith(
        title: result.title,
        items: result.items,
      );
      await _templateService.updateChecklist(updated);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _handleDeleteChecklist(Checklist checklist) async {
    final confirmed = await confirmDialog(
      context,
      'Delete "${checklist.title}" checklist?',
    );
    if (!confirmed) return;
    await _templateService.deleteChecklist(checklist.id);
  }

  Future<void> _handleCreateProjectTaskChecklist() async {
    final templates = _templateService.checklists.toList(growable: false);
    final projects = _projects;

    if (templates.isEmpty) {
      _showInfo('Create a checklist before creating a project task checklist.');
      return;
    }
    if (projects.isEmpty) {
      _showInfo('No projects available to attach the checklist to.');
      return;
    }

    final result = await showProjectTaskChecklistDialog(
      context,
      templates: templates,
      projects: projects,
    );
    if (result == null) return;

    try {
      final template = templates.firstWhere(
        (item) => item.id == result.checklistId,
        orElse: () => throw StateError('Checklist not found'),
      );
      final project = projects.firstWhere(
        (item) => item.id == result.projectId,
        orElse: () => throw StateError('Project not found'),
      );
      final created = await _projectTaskService.createFromTemplate(
        name: result.name,
        template: template,
        project: project,
      );
      setState(() {
        _projectExpanded.add(created.id);
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteProjectTaskChecklist(
    ProjectTaskChecklist checklist,
  ) async {
    final confirmed = await confirmDialog(
      context,
      'Delete "${checklist.name}" project task checklist?',
    );
    if (!confirmed) return;
    await _projectTaskService.delete(checklist.id);
  }

  Future<void> _toggleProjectTaskItem(
    ProjectTaskChecklist checklist,
    ChecklistItem item,
  ) async {
    await _projectTaskService.toggleItem(
      checklistId: checklist.id,
      itemId: item.id,
    );
  }

  Future<void> _handleEditProjectTaskChecklist(
    ProjectTaskChecklist checklist,
  ) async {
    final templates = _templateService.checklists.toList(growable: false);
    final result = await showProjectTaskChecklistDialog(
      context,
      templates: templates,
      projects: _projects,
      initial: checklist,
    );
    if (result == null) return;

    Project? selectedProject;
    for (final project in _projects) {
      if (project.id == result.projectId) {
        selectedProject = project;
        break;
      }
    }

    if (selectedProject == null && result.projectId != checklist.projectId) {
      _showInfo('Selected project is no longer available.');
      return;
    }

    try {
      await _projectTaskService.updateMetadata(
        id: checklist.id,
        name: result.name,
        projectId: selectedProject?.id ?? checklist.projectId,
        projectName: selectedProject?.name ?? checklist.projectName,
        projectNumber:
            selectedProject?.projectNumber ?? checklist.projectNumber,
      );
    } catch (error) {
      _showError(error);
    }
  }

  void _toggleTemplateExpanded(String id) {
    setState(() {
      if (_templateExpanded.contains(id)) {
        _templateExpanded.remove(id);
      } else {
        _templateExpanded.add(id);
      }
    });
  }

  void _toggleProjectExpanded(String id) {
    setState(() {
      if (_projectExpanded.contains(id)) {
        _projectExpanded.remove(id);
      } else {
        _projectExpanded.add(id);
      }
    });
  }

  void _showError(Object error) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Something went wrong: $error')),
    );
  }

  void _showInfo(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final templates = _templateService.checklists.toList(growable: false);
    final projectTasks = _projectTaskService.checklists.toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final isLoading =
        _templatesLoading || _projectTasksLoading || _projectsLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Checklists')),
      bottomNavigationBar: const ShellBottomNav(popCurrentRoute: true),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: templates.isEmpty || _projects.isEmpty
                        ? null
                        : _handleCreateProjectTaskChecklist,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Create Project Task Checklist'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Project Task Checklists',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _ProjectTaskSection(
                  checklists: projectTasks,
                  expanded: _projectExpanded,
                  onToggleExpanded: _toggleProjectExpanded,
                  onToggleItem: _toggleProjectTaskItem,
                  onEdit: _handleEditProjectTaskChecklist,
                  onDelete: _deleteProjectTaskChecklist,
                ),
                const SizedBox(height: 24),
                Text(
                  'Reusable Checklists',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (templates.isEmpty)
                  const _EmptyState()
                else
                  _TemplateChecklistSection(
                    checklists: templates,
                    expanded: _templateExpanded,
                    onToggleExpanded: _toggleTemplateExpanded,
                    onEdit: _handleEditChecklist,
                    onDelete: _handleDeleteChecklist,
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _handleAddChecklist,
        tooltip: 'Create checklist',
        child: const Icon(Icons.playlist_add_check),
      ),
    );
  }
}

class _TemplateChecklistSection extends StatelessWidget {
  const _TemplateChecklistSection({
    required this.checklists,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Checklist> checklists;
  final Set<String> expanded;
  final void Function(String id) onToggleExpanded;
  final void Function(Checklist checklist) onEdit;
  final void Function(Checklist checklist) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < checklists.length; i++) ...[
          _ChecklistCard(
            checklist: checklists[i],
            expanded: expanded.contains(checklists[i].id),
            onToggleExpanded: () => onToggleExpanded(checklists[i].id),
            onEdit: () => onEdit(checklists[i]),
            onDelete: () => onDelete(checklists[i]),
          ),
          if (i < checklists.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ProjectTaskSection extends StatelessWidget {
  const _ProjectTaskSection({
    required this.checklists,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onToggleItem,
    required this.onEdit,
    required this.onDelete,
  });

  final List<ProjectTaskChecklist> checklists;
  final Set<String> expanded;
  final void Function(String id) onToggleExpanded;
  final void Function(ProjectTaskChecklist checklist, ChecklistItem item)
      onToggleItem;
  final void Function(ProjectTaskChecklist checklist) onEdit;
  final void Function(ProjectTaskChecklist checklist) onDelete;

  @override
  Widget build(BuildContext context) {
    if (checklists.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Text(
            'No project task checklists yet. Create one to track tasks for a project.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < checklists.length; i++) ...[
          _ProjectTaskChecklistCard(
            checklist: checklists[i],
            expanded: expanded.contains(checklists[i].id),
            onToggleExpanded: () => onToggleExpanded(checklists[i].id),
            onToggleItem: (item) => onToggleItem(checklists[i], item),
            onEdit: () => onEdit(checklists[i]),
            onDelete: () => onDelete(checklists[i]),
          ),
          if (i < checklists.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ProjectTaskChecklistCard extends StatelessWidget {
  const _ProjectTaskChecklistCard({
    required this.checklist,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onToggleItem,
    required this.onEdit,
    required this.onDelete,
  });

  final ProjectTaskChecklist checklist;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final ValueChanged<ChecklistItem> onToggleItem;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium;
    final projectLabel = checklist.projectNumber != null &&
            checklist.projectNumber!.trim().isNotEmpty
        ? '${checklist.projectNumber} - ${checklist.projectName}'
        : checklist.projectName;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onEdit,
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(checklist.name, style: titleStyle),
                          const SizedBox(height: 4),
                          Text(projectLabel, style: theme.textTheme.bodySmall),
                          Text(
                            'Template: ${checklist.templateTitle}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: expanded
                      ? 'Collapse project task checklist'
                      : 'Expand project task checklist',
                  onPressed: onToggleExpanded,
                  icon: Icon(expanded ? Icons.remove : Icons.add),
                ),
                IconButton(
                  tooltip: 'Delete project task checklist',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: _ProjectTaskItems(
                checklist: checklist,
                onToggleItem: onToggleItem,
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectTaskItems extends StatelessWidget {
  const _ProjectTaskItems({
    required this.checklist,
    required this.onToggleItem,
  });

  final ProjectTaskChecklist checklist;
  final ValueChanged<ChecklistItem> onToggleItem;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Column(
        children: checklist.items
            .map(
              (item) => ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                onTap: () => onToggleItem(item),
                leading: Icon(
                  item.isDone
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: item.isDone
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  item.title,
                  style: item.isDone
                      ? const TextStyle(decoration: TextDecoration.lineThrough)
                      : null,
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({
    required this.checklist,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onEdit,
    required this.onDelete,
  });

  final Checklist checklist;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: onToggleExpanded,
                  icon: Icon(expanded ? Icons.remove : Icons.add),
                ),
                Expanded(child: Text(checklist.title, style: titleStyle)),
                IconButton(
                  tooltip: 'Edit checklist',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Delete checklist',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: _ChecklistItems(checklist: checklist),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistItems extends StatelessWidget {
  const _ChecklistItems({required this.checklist});

  final Checklist checklist;

  @override
  Widget build(BuildContext context) {
    if (checklist.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Text(
          'No items yet. Edit the checklist to add steps.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    final bulletColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Column(
        children: checklist.items
            .map(
              (item) => ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(Icons.circle, size: 10, color: bulletColor),
                title: Text(item.title),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fact_check_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No checklists yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Create a checklist to track repeatable workflows like utility or grading plans.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
