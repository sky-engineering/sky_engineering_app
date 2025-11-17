import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/models/checklist.dart';
import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';
import '../dialogs/checklist_edit_dialog.dart';

class TemplateChecklistsPage extends StatefulWidget {
  const TemplateChecklistsPage({super.key});

  @override
  State<TemplateChecklistsPage> createState() => _TemplateChecklistsPageState();
}

class _TemplateChecklistsPageState extends State<TemplateChecklistsPage> {
  final Set<String> _templateExpanded = <String>{};
  final Set<String> _projectExpanded = <String>{};
  final CollectionReference<Map<String, dynamic>> _collection =
      FirebaseFirestore.instance.collection('checklistTemplates');
  final CollectionReference<Map<String, dynamic>> _projectCollection =
      FirebaseFirestore.instance.collection('checklistProjects');
  final ProjectRepository _projectRepository = ProjectRepository();

  bool _fabExpanded = false;
  List<Checklist> _templatesCache = const <Checklist>[];

  Stream<List<Checklist>> _templateStream() {
    return _collection.orderBy('title').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final normalizedItems = <Map<String, Object?>>[];
        final rawItems = data['items'];
        if (rawItems is List) {
          for (final entry in rawItems) {
            if (entry is Map<String, dynamic>) {
              normalizedItems.add(Map<String, Object?>.from(entry));
            } else if (entry is Map) {
              final typed = <String, Object?>{};
              entry.forEach((key, value) {
                typed[key.toString()] = value;
              });
              normalizedItems.add(typed);
            }
          }
        }
        return Checklist.fromMap({
          'id': doc.id,
          'title': data['title'] ?? '',
          'items': normalizedItems,
        });
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    final listContent = StreamBuilder<List<Checklist>>(
      stream: _templateStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to load templates: ${snapshot.error}'),
            ),
          );
        }
        final templates = snapshot.data ?? const <Checklist>[];
        _templatesCache = templates;

        return StreamBuilder<List<ProjectChecklistDoc>>(
          stream: _projectChecklistStream(),
          builder: (context, projectSnapshot) {
            final projectChecklists =
                projectSnapshot.data ?? const <ProjectChecklistDoc>[];

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Project Checklists', style: titleStyle),
                const SizedBox(height: 8),
                if (projectSnapshot.connectionState ==
                        ConnectionState.waiting &&
                    projectChecklists.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else if (projectChecklists.isEmpty)
                  const _EmptyProjectState()
                else
                  ...projectChecklists.map((doc) {
                    final isExpanded = _projectExpanded.contains(doc.id);
                    return _ProjectChecklistCard(
                      key: ValueKey('project-checklist-${doc.id}'),
                      checklist: doc,
                      expanded: isExpanded,
                      onToggleExpanded: () {
                        setState(() {
                          if (isExpanded) {
                            _projectExpanded.remove(doc.id);
                          } else {
                            _projectExpanded.add(doc.id);
                          }
                        });
                      },
                      onEdit: () => _editProjectChecklist(doc),
                      onToggleItem: (item) =>
                          _toggleProjectChecklistItem(doc, item),
                    );
                  }),
                const SizedBox(height: 24),
                Text('Template Checklists', style: titleStyle),
                const SizedBox(height: 8),
                if (templates.isEmpty)
                  const _EmptyTemplatesState()
                else
                  ...templates.asMap().entries.map((entry) {
                    final index = entry.key;
                    final template = entry.value;
                    final title = template.title.isEmpty
                        ? 'Template ${index + 1}'
                        : template.title.trim();
                    final isExpanded = _templateExpanded.contains(template.id);
                    return _TemplateCard(
                      key: ValueKey('template-${template.id}'),
                      title: title,
                      template: template,
                      titleStyle: titleStyle,
                      expanded: isExpanded,
                      onToggleExpanded: () {
                        setState(() {
                          if (isExpanded) {
                            _templateExpanded.remove(template.id);
                          } else {
                            _templateExpanded.add(template.id);
                          }
                        });
                      },
                      onEdit: () => _editTemplate(template),
                    );
                  }),
                const SizedBox(height: 96),
              ],
            );
          },
        );
      },
    );

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Checklists'),
      ),
      body: listContent,
    );

    return Stack(
      children: [
        scaffold,
        Positioned(
          right: 24,
          bottom: 32,
          child: SizedBox(
            width: 220,
            height: 220,
            child: Stack(
              alignment: Alignment.bottomRight,
              clipBehavior: Clip.none,
              children: [
                _RadialFabOption(
                  label: 'Project Checklist',
                  icon: Icons.assignment_add,
                  offset: const Offset(88, 54),
                  visible: _fabExpanded,
                  onTap: () {
                    setState(() => _fabExpanded = false);
                    _createProjectChecklist();
                  },
                ),
                _RadialFabOption(
                  label: 'Template Checklist',
                  icon: Icons.playlist_add,
                  offset: const Offset(30, 118),
                  visible: _fabExpanded,
                  onTap: () {
                    setState(() => _fabExpanded = false);
                    _createTemplate();
                  },
                ),
                FloatingActionButton(
                  backgroundColor: const Color(0xFFF1C400),
                  foregroundColor: Colors.black,
                  tooltip: 'Add checklist',
                  onPressed: () => setState(() => _fabExpanded = !_fabExpanded),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editTemplate(Checklist template) async {
    final result = await showChecklistEditDialog(
      context,
      initial: template,
      onDelete: () => _deleteTemplate(template),
    );
    if (result == null) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _collection.doc(template.id).update({
        'title': result.title.trim(),
        'items': result.items.map((item) => item.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Checklist updated')),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to update checklist: $error')),
        );
      }
    }
  }

  Future<void> _deleteTemplate(Checklist template) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _collection.doc(template.id).delete();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Checklist deleted')),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to delete checklist: $error')),
        );
      }
    }
  }

  Future<void> _createTemplate() async {
    final result = await showChecklistEditDialog(context);
    if (result == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to create templates.')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _collection.add({
        'ownerUid': user.uid,
        'title': result.title.trim(),
        'items': result.items.map((item) => item.toMap()).toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Checklist created')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to create checklist: $error')),
      );
    }
  }

  Stream<List<ProjectChecklistDoc>> _projectChecklistStream() {
    return _projectCollection
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final normalizedItems = <Map<String, Object?>>[];
        final rawItems = data['items'];
        if (rawItems is List) {
          for (final entry in rawItems) {
            if (entry is Map<String, dynamic>) {
              normalizedItems.add(Map<String, Object?>.from(entry));
            } else if (entry is Map) {
              final typed = <String, Object?>{};
              entry.forEach((key, value) {
                typed[key.toString()] = value;
              });
              normalizedItems.add(typed);
            }
          }
        }
        return ProjectChecklistDoc(
          id: doc.id,
          title: data['title'] as String? ?? '',
          projectId: data['projectId'] as String? ?? '',
          projectLabel: data['projectLabel'] as String? ?? '',
          templateId: data['templateId'] as String?,
          items: normalizedItems.map(ChecklistItem.fromMap).toList(),
        );
      }).toList();
    });
  }

  Future<void> _createProjectChecklist() async {
    if (_templatesCache.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a template first.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to create checklists.')),
      );
      return;
    }

    final projects = await _projectRepository.streamAll().first;
    if (!mounted) return;
    if (projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No projects available.')),
      );
      return;
    }

    final sortedProjects = [...projects]..sort(_compareProjectsByNumber);

    final result = await showProjectChecklistDialog(
      context,
      projects: sortedProjects,
      templates: _templatesCache,
    );

    if (result == null) return;

    final template = _templatesCache.firstWhere(
      (template) => template.id == result.templateId,
      orElse: () => Checklist(id: '', title: '', items: const []),
    );
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _projectCollection.add({
        'ownerUid': user.uid,
        'title': result.title,
        'projectId': result.projectId,
        'projectLabel': result.projectLabel,
        'templateId': result.templateId,
        'items': template.items.map((item) => item.toMap()).toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Project checklist created')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to create project checklist: $error')),
      );
    }
  }

  Future<void> _editProjectChecklist(ProjectChecklistDoc checklist) async {
    final result = await showChecklistEditDialog(
      context,
      initial: Checklist(
        id: checklist.id,
        title: checklist.title,
        items: checklist.items,
      ),
      onDelete: () => _deleteProjectChecklist(checklist),
    );

    if (result == null) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await _projectCollection.doc(checklist.id).update({
        'title': result.title.trim(),
        'items': result.items.map((item) => item.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Project checklist updated')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update checklist: $error')),
      );
    }
  }

  Future<void> _deleteProjectChecklist(ProjectChecklistDoc checklist) async {
    try {
      await _projectCollection.doc(checklist.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Project checklist deleted')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete checklist: $error')),
        );
      }
    }
  }

  Future<void> _toggleProjectChecklistItem(
    ProjectChecklistDoc checklist,
    ChecklistItem item,
  ) async {
    final updatedItems = checklist.items
        .map((entry) =>
            entry.id == item.id ? entry.copyWith(isDone: !item.isDone) : entry)
        .toList();
    try {
      await _projectCollection.doc(checklist.id).update({
        'items': updatedItems.map((entry) => entry.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to toggle item: $error')),
      );
    }
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    super.key,
    required this.title,
    required this.template,
    required this.titleStyle,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onEdit,
  });

  final String title;
  final Checklist template;
  final TextStyle? titleStyle;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final styledTitle = (titleStyle ?? const TextStyle(fontSize: 16))
        .copyWith(fontWeight: FontWeight.w400);
    final toggleLabel = expanded ? '-' : '+';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: onToggleExpanded,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    toggleLabel,
                    style: styledTitle.copyWith(fontSize: 20),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(title, style: styledTitle),
                  ),
                ),
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 4),
            if (template.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text('No checklist items'),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: template.items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.check_box_outline_blank,
                            size: 12,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.title,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(height: 1.05),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProjectChecklistCard extends StatelessWidget {
  const _ProjectChecklistCard({
    super.key,
    required this.checklist,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onEdit,
    required this.onToggleItem,
  });

  final ProjectChecklistDoc checklist;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onEdit;
  final Future<void> Function(ChecklistItem item) onToggleItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: onToggleExpanded,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      expanded ? '-' : '+',
                      style: titleStyle?.copyWith(fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InkWell(
                        onTap: onEdit,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(checklist.title, style: titleStyle),
                        ),
                      ),
                      Text(
                        checklist.projectLabel,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 6),
              if (checklist.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('No checklist items'),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: checklist.items.map((item) {
                    final completed = item.isDone;
                    return InkWell(
                      onTap: () => onToggleItem(item),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                completed
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                size: 14,
                                color: completed
                                    ? theme.colorScheme.primary
                                    : theme.iconTheme.color,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.title,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.05,
                                  decoration: completed
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                  color: completed
                                      ? theme.textTheme.bodySmall?.color
                                          ?.withValues(alpha: 0.6)
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyTemplatesState extends StatelessWidget {
  const _EmptyTemplatesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.fact_check_outlined, size: 64),
            SizedBox(height: 12),
            Text('No template checklists found.'),
          ],
        ),
      ),
    );
  }
}

class _EmptyProjectState extends StatelessWidget {
  const _EmptyProjectState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.assignment_outlined, size: 48),
            SizedBox(height: 8),
            Text('No project checklists yet.'),
          ],
        ),
      ),
    );
  }
}

class ProjectChecklistDoc {
  ProjectChecklistDoc({
    required this.id,
    required this.title,
    required this.projectId,
    required this.projectLabel,
    required this.templateId,
    required this.items,
  });

  final String id;
  final String title;
  final String projectId;
  final String projectLabel;
  final String? templateId;
  final List<ChecklistItem> items;
}

class _RadialFabOption extends StatelessWidget {
  const _RadialFabOption({
    required this.label,
    required this.icon,
    required this.offset,
    required this.visible,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Offset offset;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      right: visible ? offset.dx : 0,
      bottom: visible ? offset.dy : 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: visible ? 1 : 0,
          curve: Curves.easeOutCubic,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: 52,
                bottom: 26,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      label,
                      maxLines: 2,
                      softWrap: true,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.white, height: 1.1),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                height: 60,
                child: FloatingActionButton(
                  heroTag: label,
                  backgroundColor: const Color(0xFFF1C400),
                  foregroundColor: Colors.black,
                  shape: const CircleBorder(),
                  onPressed: onTap,
                  child: Icon(icon, size: 24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectChecklistCreationResult {
  const _ProjectChecklistCreationResult({
    required this.title,
    required this.projectId,
    required this.projectLabel,
    required this.templateId,
  });

  final String title;
  final String projectId;
  final String projectLabel;
  final String templateId;
}

Future<_ProjectChecklistCreationResult?> showProjectChecklistDialog(
  BuildContext context, {
  required List<Project> projects,
  required List<Checklist> templates,
}) {
  return showDialog<_ProjectChecklistCreationResult>(
    context: context,
    builder: (dialogContext) {
      return _ProjectChecklistDialog(
        projects: projects,
        templates: templates,
      );
    },
  );
}

class _ProjectChecklistDialog extends StatefulWidget {
  const _ProjectChecklistDialog({
    required this.projects,
    required this.templates,
  });

  final List<Project> projects;
  final List<Checklist> templates;

  @override
  State<_ProjectChecklistDialog> createState() =>
      _ProjectChecklistDialogState();
}

class _ProjectChecklistDialogState extends State<_ProjectChecklistDialog> {
  late final TextEditingController _titleController;
  Project? _selectedProject;
  Checklist? _selectedTemplate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _selectedProject = null;
    _selectedTemplate = null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  bool get _canSave {
    return _selectedProject != null &&
        _selectedTemplate != null &&
        _titleController.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Project Checklist'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Checklist title',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Project?>(
              value: _selectedProject,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Project',
              ),
              hint: const Text('Select...'),
              items: widget.projects
                  .map(
                    (project) => DropdownMenuItem<Project?>(
                      value: project,
                      child: Text(_projectLabel(project)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedProject = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Checklist?>(
              value: _selectedTemplate,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Template Checklist',
              ),
              hint: const Text('Select...'),
              items: widget.templates.asMap().entries.map((entry) {
                final index = entry.key;
                final template = entry.value;
                final title = template.title.isEmpty
                    ? 'Template ${index + 1}'
                    : template.title;
                return DropdownMenuItem<Checklist?>(
                  value: template,
                  child: Text(title),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedTemplate = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSave
              ? () {
                  final project = _selectedProject!;
                  final template = _selectedTemplate!;
                  Navigator.of(context).pop(_ProjectChecklistCreationResult(
                    title: _titleController.text.trim(),
                    projectId: project.id,
                    projectLabel: _projectLabel(project),
                    templateId: template.id,
                  ));
                }
              : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

String _projectLabel(Project project) {
  final number = project.projectNumber?.trim() ?? '';
  final name = project.name.trim();
  if (number.isNotEmpty && name.isNotEmpty) {
    return '$number - $name';
  }
  if (number.isNotEmpty) return number;
  if (name.isNotEmpty) return name;
  return 'Project ${project.id}';
}

int _compareProjectsByNumber(Project a, Project b) {
  final numberA = a.projectNumber?.trim();
  final numberB = b.projectNumber?.trim();

  if (numberA != null &&
      numberA.isNotEmpty &&
      numberB != null &&
      numberB.isNotEmpty) {
    final cmp = _naturalCompare(numberA, numberB);
    if (cmp != 0) return cmp;
  } else if (numberA != null && numberA.isNotEmpty) {
    return -1;
  } else if (numberB != null && numberB.isNotEmpty) {
    return 1;
  }

  final createdA = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final createdB = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return createdA.compareTo(createdB);
}

int _naturalCompare(String a, String b) {
  final tokensA = _tokenizeNatural(a);
  final tokensB = _tokenizeNatural(b);
  final len = tokensA.length < tokensB.length ? tokensA.length : tokensB.length;
  for (var i = 0; i < len; i++) {
    final ta = tokensA[i];
    final tb = tokensB[i];
    if (ta == tb) continue;
    if (ta is int && tb is int) {
      final cmp = ta.compareTo(tb);
      if (cmp != 0) return cmp;
    } else {
      final cmp = ta.toString().compareTo(tb.toString());
      if (cmp != 0) return cmp;
    }
  }
  return tokensA.length.compareTo(tokensB.length);
}

List<Object> _tokenizeNatural(String input) {
  final tokens = <Object>[];
  final buffer = StringBuffer();
  var inNumber = false;

  void flush() {
    if (buffer.isEmpty) return;
    final chunk = buffer.toString();
    if (inNumber) {
      tokens.add(int.tryParse(chunk) ?? chunk);
    } else {
      tokens.add(chunk.toLowerCase());
    }
    buffer.clear();
  }

  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final isDigit = rune >= 0x30 && rune <= 0x39;
    if (isDigit) {
      if (!inNumber) {
        flush();
        inNumber = true;
      }
      buffer.write(ch);
    } else {
      if (inNumber) {
        flush();
        inNumber = false;
      }
      buffer.write(ch);
    }
  }
  flush();
  return tokens;
}
