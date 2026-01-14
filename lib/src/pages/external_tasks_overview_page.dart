// lib/src/pages/external_tasks_overview_page.dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models/external_task.dart';
import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/external_task_repository.dart';
import 'project_detail_page.dart';

enum _ExternalTaskSort { teamType, memberName, projectNumber }

class ExternalTasksOverviewPage extends StatefulWidget {
  const ExternalTasksOverviewPage({super.key});

  @override
  State<ExternalTasksOverviewPage> createState() =>
      _ExternalTasksOverviewPageState();
}

class _ExternalTasksOverviewPageState extends State<ExternalTasksOverviewPage> {
  final ProjectRepository _projectRepo = ProjectRepository();
  final ExternalTaskRepository _externalRepo = ExternalTaskRepository();
  final TextEditingController _searchCtl = TextEditingController();
  String _query = '';
  _ExternalTaskSort _sort = _ExternalTaskSort.teamType;
  List<Project> _projectsCache = const [];
  late final Future<void> _seedExternalTaskFlags =
      _projectRepo.ensureExternalTaskFlagsSeeded();

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchCtl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search external tasks...',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() => _query = value.trim().toLowerCase());
                },
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Sort by:',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<_ExternalTaskSort>(
                    value: _sort,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _sort = value);
                    },
                    items: const [
                      DropdownMenuItem(
                        value: _ExternalTaskSort.teamType,
                        child: Text('Team Role'),
                      ),
                      DropdownMenuItem(
                        value: _ExternalTaskSort.memberName,
                        child: Text('Team Member Name'),
                      ),
                      DropdownMenuItem(
                        value: _ExternalTaskSort.projectNumber,
                        child: Text('Project Number'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: FutureBuilder<void>(
                future: _seedExternalTaskFlags,
                builder: (context, seedSnapshot) {
                  if (seedSnapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return StreamBuilder<List<Project>>(
                    stream: _projectRepo.streamWithExternalTasks(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final projects = snapshot.data ?? const <Project>[];
                      final sortedProjects = [...projects]
                        ..removeWhere(
                          (project) =>
                              (project.externalTasks ?? const <ExternalTask>[])
                                  .isEmpty,
                        )
                        ..sort(_compareProjects);
                      _projectsCache = sortedProjects;

                      final entries = <_ExternalTaskEntry>[];
                      for (final project in sortedProjects) {
                        final tasks = [
                          ...(project.externalTasks ?? const <ExternalTask>[]),
                        ]..sort(_compareTasks);
                        for (final task in tasks) {
                          entries.add(
                            _ExternalTaskEntry(project: project, task: task),
                          );
                        }
                      }

                      final filtered = _filterEntries(entries, _query);
                      final sortedEntries = [...filtered]
                        ..sort(_entryComparator);

                      if (sortedEntries.isEmpty) {
                        if (entries.isEmpty) {
                          return const _EmptyState();
                        }
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _query.isEmpty
                                  ? 'No external tasks found.'
                                  : 'No tasks match your search.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
                        itemCount: sortedEntries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final entry = sortedEntries[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: _OverviewExternalTaskTile(
                              project: entry.project,
                              task: entry.task,
                              repo: _externalRepo,
                              onEdit: () => _openEditExternalTask(
                                  entry.project, entry.task),
                              onOpenProject: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ProjectDetailPage(
                                        projectId: entry.project.id),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add external task',
        backgroundColor: const Color(0xFFF1C400),
        foregroundColor: Colors.black,
        onPressed: _openAddTaskDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _openAddTaskDialog() async {
    if (_projectsCache.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No projects available for external tasks')),
      );
      return;
    }

    final result = await showDialog<_NewExternalTaskResult>(
      context: context,
      builder: (context) => _AddExternalTaskDialog(
        projects: _projectsCache,
        projectLabelBuilder: _projectLabel,
        assigneeBuilder: _assigneeOptionsForProject,
      ),
    );

    if (result == null) return;

    try {
      await _externalRepo.add(
        result.project.id,
        ExternalTask(
          id: '',
          projectId: result.project.id,
          title: result.description.trim(),
          assigneeKey: result.assigneeKey,
          assigneeName: result.assigneeName,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add external task: $e')),
      );
    }
  }

  Future<void> _openEditExternalTask(
    Project project,
    ExternalTask task,
  ) async {
    final options = _assigneeOptionsForProject(project);
    final result = await showDialog<_EditExternalTaskResult>(
      context: context,
      builder: (context) => _EditExternalTaskDialog(
        projectLabel: _projectLabel(project),
        assigneeOptions: options,
        initialDescription: task.title,
        initialAssigneeKey: task.assigneeKey,
      ),
    );

    if (result == null) return;

    try {
      await _externalRepo.update(project.id, task.id, {
        'title': result.description.trim(),
        'assigneeKey': result.assigneeKey,
        'assigneeName': result.assigneeName,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('External task updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update task: $e')),
      );
    }
  }

  int _entryComparator(_ExternalTaskEntry a, _ExternalTaskEntry b) {
    switch (_sort) {
      case _ExternalTaskSort.teamType:
        final la = (_teamLabelForKey(a.task.assigneeKey.toLowerCase()) ?? '')
            .toLowerCase();
        final lb = (_teamLabelForKey(b.task.assigneeKey.toLowerCase()) ?? '')
            .toLowerCase();
        final cmpType = la.compareTo(lb);
        if (cmpType != 0) return cmpType;
        break;
      case _ExternalTaskSort.memberName:
        String normalizeName(_ExternalTaskEntry entry) {
          final task = entry.task;
          final project = entry.project;
          final fromTask = task.assigneeName.trim();
          if (fromTask.isNotEmpty) {
            return fromTask.toLowerCase();
          }
          final projectValue =
              _teamValueForKey(project, task.assigneeKey.toLowerCase())?.trim();
          if (projectValue != null && projectValue.isNotEmpty) {
            return projectValue.toLowerCase();
          }
          return '';
        }

        final cmpName = normalizeName(a).compareTo(normalizeName(b));
        if (cmpName != 0) return cmpName;
        break;
      case _ExternalTaskSort.projectNumber:
        final projectA = a.project.projectNumber?.trim().toLowerCase() ?? '';
        final projectB = b.project.projectNumber?.trim().toLowerCase() ?? '';
        final cmpProject = projectA.compareTo(projectB);
        if (cmpProject != 0) return cmpProject;
        break;
    }

    final cmpProject = _compareProjects(a.project, b.project);
    if (cmpProject != 0) return cmpProject;
    return _compareTasks(a.task, b.task);
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

  List<_AssigneeOption> _assigneeOptionsForProject(Project project) {
    const keys = [
      'teamowner',
      'teamarchitect',
      'teamsurveyor',
      'teamgeotechnical',
      'teammechanical',
      'teamelectrical',
      'teamplumbing',
      'teamlandscape',
      'teamcontractor',
      'teamenvironmental',
      'teamother',
    ];
    final options = <_AssigneeOption>[];
    for (final key in keys) {
      final label = _teamLabelForKey(key);
      if (label == null) continue;
      final value = _teamValueForKey(project, key)?.trim();
      if (value == null || value.isEmpty) continue;
      options.add(_AssigneeOption(
        key: key,
        label: label,
        displayName: value,
      ));
    }
    return options;
  }

  List<_ExternalTaskEntry> _filterEntries(
    List<_ExternalTaskEntry> entries,
    String query,
  ) {
    if (query.isEmpty) return entries;
    final tokens = _tokenizeQuery(query);
    if (tokens.isEmpty) return entries;

    bool entryMatches(_ExternalTaskEntry entry) {
      bool matchesField(String term) {
        bool contains(String? value) {
          if (value == null) return false;
          final trimmed = value.trim();
          if (trimmed.isEmpty) return false;
          return trimmed.toLowerCase().contains(term);
        }

        final project = entry.project;
        final task = entry.task;

        if (contains(task.title)) return true;
        if (contains(project.projectNumber)) return true;
        if (contains(project.name)) return true;

        final assigneeKey = task.assigneeKey.toLowerCase();
        final memberLabel = _teamLabelForKey(assigneeKey);
        final memberName = _teamValueForKey(project, assigneeKey);

        if (contains(memberLabel)) return true;
        if (contains(memberName)) return true;
        if (contains(task.assigneeName)) return true;

        return false;
      }

      bool evaluateTokens() {
        var index = 0;
        bool result = matchesField(tokens[index].term);
        index++;

        while (index < tokens.length) {
          final op = tokens[index];
          if (index + 1 >= tokens.length) break;
          final nextTerm = tokens[index + 1];
          final nextMatches = matchesField(nextTerm.term);
          if (op.isAnd) {
            result = result && nextMatches;
          } else {
            result = result || nextMatches;
          }
          index += 2;
        }

        return result;
      }

      return evaluateTokens();
    }

    return entries.where(entryMatches).toList();
  }

  List<_QueryToken> _tokenizeQuery(String raw) {
    final lowered = raw.toLowerCase();
    final parts = lowered.split(RegExp(r'\s+'));
    final tokens = <_QueryToken>[];
    _QueryToken? last;

    for (final part in parts) {
      if (part.isEmpty) continue;
      if (part == 'and') {
        if (last != null && last.isTerm) {
          tokens.add(_QueryToken.and());
          last = _QueryToken.and();
        }
      } else if (part == 'or') {
        if (last != null && last.isTerm) {
          tokens.add(_QueryToken.or());
          last = _QueryToken.or();
        }
      } else {
        final token = _QueryToken.term(part);
        tokens.add(token);
        last = token;
      }
    }

    if (tokens.isNotEmpty && !tokens.last.isTerm) {
      tokens.removeLast();
    }

    while (tokens.isNotEmpty && !tokens.first.isTerm) {
      tokens.removeAt(0);
    }

    return tokens;
  }

  String? _teamLabelForKey(String key) {
    switch (key) {
      case 'owner':
      case 'teamowner':
        return 'Owner';
      case 'teamarchitect':
        return 'Architect';
      case 'teamsurveyor':
        return 'Surveyor';
      case 'teamgeotechnical':
        return 'Geotechnical';
      case 'teammechanical':
        return 'Mechanical';
      case 'teamstructural':
        return 'Structural';
      case 'teamelectrical':
        return 'Electrical';
      case 'teamplumbing':
        return 'Plumbing';
      case 'teamlandscape':
        return 'Landscape';
      case 'teamcontractor':
        return 'Contractor';
      case 'teamenvironmental':
        return 'Environmental';
      case 'teamother':
        return 'Other';
      default:
        return null;
    }
  }

  String? _teamValueForKey(Project project, String key) {
    switch (key) {
      case 'owner':
      case 'teamowner':
        return project.teamOwner;
      case 'teamarchitect':
        return project.teamArchitect;
      case 'teamsurveyor':
        return project.teamSurveyor;
      case 'teamgeotechnical':
        return project.teamGeotechnical;
      case 'teammechanical':
        return project.teamMechanical;
      case 'teamstructural':
        return project.teamStructural;
      case 'teamelectrical':
        return project.teamElectrical;
      case 'teamplumbing':
        return project.teamPlumbing;
      case 'teamlandscape':
        return project.teamLandscape;
      case 'teamcontractor':
        return project.teamContractor;
      case 'teamenvironmental':
        return project.teamEnvironmental;
      case 'teamother':
        return project.teamOther;
      default:
        return null;
    }
  }
}

class _NewExternalTaskResult {
  const _NewExternalTaskResult({
    required this.project,
    required this.description,
    required this.assigneeKey,
    required this.assigneeName,
  });

  final Project project;
  final String description;
  final String assigneeKey;
  final String assigneeName;
}

class _EditExternalTaskResult {
  const _EditExternalTaskResult({
    required this.description,
    required this.assigneeKey,
    required this.assigneeName,
  });

  final String description;
  final String assigneeKey;
  final String assigneeName;
}

class _AssigneeOption {
  const _AssigneeOption({
    required this.key,
    required this.label,
    required this.displayName,
  });

  final String key;
  final String label;
  final String displayName;
}

class _AddExternalTaskDialog extends StatefulWidget {
  const _AddExternalTaskDialog({
    required this.projects,
    required this.projectLabelBuilder,
    required this.assigneeBuilder,
  });

  final List<Project> projects;
  final String Function(Project) projectLabelBuilder;
  final List<_AssigneeOption> Function(Project) assigneeBuilder;

  @override
  State<_AddExternalTaskDialog> createState() => _AddExternalTaskDialogState();
}

class _EditExternalTaskDialog extends StatefulWidget {
  const _EditExternalTaskDialog({
    required this.projectLabel,
    required this.assigneeOptions,
    required this.initialDescription,
    required this.initialAssigneeKey,
  });

  final String projectLabel;
  final List<_AssigneeOption> assigneeOptions;
  final String initialDescription;
  final String initialAssigneeKey;

  @override
  State<_EditExternalTaskDialog> createState() =>
      _EditExternalTaskDialogState();
}

class _EditExternalTaskDialogState extends State<_EditExternalTaskDialog> {
  late TextEditingController _descriptionCtl;
  _AssigneeOption? _selectedAssignee;

  @override
  void initState() {
    super.initState();
    _descriptionCtl = TextEditingController(text: widget.initialDescription);
    final options = widget.assigneeOptions;
    final matchIndex =
        options.indexWhere((option) => option.key == widget.initialAssigneeKey);
    if (matchIndex != -1) {
      _selectedAssignee = options[matchIndex];
    } else if (options.isNotEmpty) {
      _selectedAssignee = options.first;
    } else {
      _selectedAssignee = null;
    }
  }

  @override
  void dispose() {
    _descriptionCtl.dispose();
    super.dispose();
  }

  bool get _canSave {
    return _descriptionCtl.text.trim().isNotEmpty && _selectedAssignee != null;
  }

  void _handleSave() {
    if (!_canSave) return;
    final assignee = _selectedAssignee!;
    Navigator.of(context).pop(
      _EditExternalTaskResult(
        description: _descriptionCtl.text.trim(),
        assigneeKey: assignee.key,
        assigneeName: assignee.displayName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assigneeOptions = widget.assigneeOptions;
    return AlertDialog(
      title: const Text('Edit External Task'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _descriptionCtl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Task description'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Project'),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(widget.projectLabel),
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Assign to'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_AssigneeOption>(
                  value: _selectedAssignee,
                  isExpanded: true,
                  items: assigneeOptions
                      .map((option) => DropdownMenuItem<_AssigneeOption>(
                            value: option,
                            child:
                                Text('${option.label}: ${option.displayName}'),
                          ))
                      .toList(),
                  onChanged: assigneeOptions.isEmpty
                      ? null
                      : (value) => setState(() => _selectedAssignee = value),
                  hint: const Text('No team members for project'),
                ),
              ),
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
          onPressed: _canSave ? _handleSave : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _AddExternalTaskDialogState extends State<_AddExternalTaskDialog> {
  late TextEditingController _descriptionCtl;
  Project? _selectedProject;
  List<_AssigneeOption> _assigneeOptions = const <_AssigneeOption>[];
  _AssigneeOption? _selectedAssignee;

  @override
  void initState() {
    super.initState();
    _descriptionCtl = TextEditingController();
    _assigneeOptions = const <_AssigneeOption>[];
  }

  @override
  void dispose() {
    _descriptionCtl.dispose();
    super.dispose();
  }

  void _handleProjectChanged(Project? project) {
    setState(() {
      _selectedProject = project;
      _assigneeOptions = project == null
          ? const <_AssigneeOption>[]
          : widget.assigneeBuilder(project);
      _selectedAssignee =
          _assigneeOptions.isNotEmpty ? _assigneeOptions.first : null;
    });
  }

  bool get _assigneeDropdownEnabled =>
      _selectedProject != null && _assigneeOptions.isNotEmpty;

  String get _assigneeHintText {
    if (_selectedProject == null) {
      return 'Select a project first';
    }
    if (_assigneeOptions.isEmpty) {
      return 'No team members for project';
    }
    return 'Select team member...';
  }

  bool get _canSave {
    return _descriptionCtl.text.trim().isNotEmpty &&
        _selectedProject != null &&
        _selectedAssignee != null;
  }

  void _handleSave() {
    if (!_canSave) return;
    final project = _selectedProject!;
    final assignee = _selectedAssignee!;
    Navigator.of(context).pop(
      _NewExternalTaskResult(
        project: project,
        description: _descriptionCtl.text.trim(),
        assigneeKey: assignee.key,
        assigneeName: assignee.displayName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = widget.projects;
    return AlertDialog(
      title: const Text('Add External Task'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _descriptionCtl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Task description',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Project'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Project>(
                  value: _selectedProject,
                  isExpanded: true,
                  hint: const Text('Select Project...'),
                  items: projects
                      .map((project) => DropdownMenuItem<Project>(
                            value: project,
                            child: Text(widget.projectLabelBuilder(project)),
                          ))
                      .toList(),
                  onChanged: projects.isEmpty ? null : _handleProjectChanged,
                ),
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Assign to'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_AssigneeOption>(
                  value: _assigneeDropdownEnabled ? _selectedAssignee : null,
                  isExpanded: true,
                  items: _assigneeOptions
                      .map((option) => DropdownMenuItem<_AssigneeOption>(
                            value: option,
                            child:
                                Text('${option.label}: ${option.displayName}'),
                          ))
                      .toList(),
                  onChanged: _assigneeDropdownEnabled
                      ? (value) => setState(() => _selectedAssignee = value)
                      : null,
                  hint: Text(_assigneeHintText),
                ),
              ),
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
          onPressed: _canSave ? _handleSave : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _ExternalTaskEntry {
  const _ExternalTaskEntry({required this.project, required this.task});

  final Project project;
  final ExternalTask task;
}

class _QueryToken {
  const _QueryToken._(this.term, this.operator);

  final String term;
  final _QueryOperator operator;

  bool get isTerm => operator == _QueryOperator.term;
  bool get isAnd => operator == _QueryOperator.and;
  bool get isOr => operator == _QueryOperator.or;

  factory _QueryToken.term(String value) =>
      _QueryToken._(value, _QueryOperator.term);
  factory _QueryToken.and() => _QueryToken._('', _QueryOperator.and);
  factory _QueryToken.or() => _QueryToken._('', _QueryOperator.or);
}

enum _QueryOperator { term, and, or }

class _OverviewExternalTaskTile extends StatefulWidget {
  const _OverviewExternalTaskTile({
    required this.project,
    required this.task,
    required this.repo,
    required this.onOpenProject,
    this.onEdit,
  });

  final Project project;
  final ExternalTask task;
  final ExternalTaskRepository repo;
  final VoidCallback onOpenProject;
  final Future<void> Function()? onEdit;

  @override
  State<_OverviewExternalTaskTile> createState() =>
      _OverviewExternalTaskTileState();
}

class _OverviewExternalTaskTileState extends State<_OverviewExternalTaskTile> {
  static const double _completeThreshold = 0.6;
  static const double _deleteThreshold = 0.85;

  double _dragProgress = 0.0;
  DismissDirection? _currentDirection;
  bool _processing = false;
  late bool _isDone;
  late bool _isStarred;
  bool _starProcessing = false;

  @override
  void initState() {
    super.initState();
    _isDone = widget.task.isDone;
    _isStarred = widget.task.isStarred;
  }

  @override
  void didUpdateWidget(covariant _OverviewExternalTaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.task.isDone != widget.task.isDone) {
      _isDone = widget.task.isDone;
    }
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.task.isStarred != widget.task.isStarred) {
      _isStarred = widget.task.isStarred;
    }
  }

  bool get _completeArmed =>
      _currentDirection == DismissDirection.startToEnd &&
      _dragProgress >= _completeThreshold;

  bool get _deleteArmed =>
      _currentDirection == DismissDirection.endToStart &&
      _dragProgress >= _deleteThreshold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasAssignee = widget.task.hasAssignedTeamMember;
    final assigneeLabel = widget.task.displayAssigneeLabel;
    final projectNumber = widget.project.projectNumber?.trim() ?? '';
    final projectName = widget.project.name.trim();
    final projectLabel = projectNumber.isNotEmpty && projectName.isNotEmpty
        ? '$projectNumber - $projectName'
        : (projectNumber.isNotEmpty
            ? projectNumber
            : projectName.isNotEmpty
                ? projectName
                : 'Project ${widget.project.id}');
    final defaultTitle = DefaultTextStyle.of(context).style;
    final titleStyle = defaultTitle.copyWith(
      fontWeight: FontWeight.w600,
      color: _isDone
          ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75)
          : defaultTitle.color,
    );
    final baseSubStyle = theme.textTheme.bodySmall?.copyWith(
      color: _isDone
          ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65)
          : theme.textTheme.bodySmall?.color,
    );
    final subStyle = baseSubStyle;
    final assigneeStyle = hasAssignee
        ? baseSubStyle
        : baseSubStyle?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          );
    final cardColor = _isDone
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surface;

    return Dismissible(
      key: ValueKey('overview-external-${widget.task.id}'),
      direction:
          _processing ? DismissDirection.none : DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: _completeThreshold,
        DismissDirection.endToStart: _deleteThreshold,
      },
      background: _buildSwipeBackground(context, isStartToEnd: true),
      secondaryBackground: _buildSwipeBackground(context, isStartToEnd: false),
      onUpdate: (details) {
        final progress = details.progress.abs().clamp(0.0, 1.0);
        final direction = (details.direction == DismissDirection.startToEnd ||
                details.direction == DismissDirection.endToStart)
            ? details.direction
            : null;
        if (_dragProgress != progress || _currentDirection != direction) {
          setState(() {
            _dragProgress = progress;
            _currentDirection = direction;
          });
        }
      },
      confirmDismiss: (direction) async {
        if (_processing) return false;
        final progress = _dragProgress;
        _resetDrag();
        if (direction == DismissDirection.startToEnd &&
            progress >= _completeThreshold) {
          await _setDone(context, !_isDone);
        } else if (direction == DismissDirection.endToStart &&
            progress >= _deleteThreshold) {
          await _deleteTask(context);
        }
        return false;
      },
      child: Card(
        margin: EdgeInsets.zero,
        color: cardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (widget.onEdit == null || _starProcessing || _processing) {
              return;
            }
            await widget.onEdit!();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minHeight: 36, minWidth: 36),
                  iconSize: 20,
                  splashRadius: 20,
                  tooltip: _isStarred ? 'Unstar task' : 'Star task',
                  onPressed: () => _toggleStar(context),
                  icon: Icon(
                    _isStarred ? Icons.star : Icons.star_border,
                    color: _isStarred
                        ? theme.colorScheme.secondary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(assigneeLabel, style: assigneeStyle),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(projectLabel, style: subStyle),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Open project',
                  onPressed: widget.onOpenProject,
                  icon: const Icon(Icons.open_in_new),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _resetDrag() {
    if (_dragProgress != 0.0 || _currentDirection != null) {
      setState(() {
        _dragProgress = 0.0;
        _currentDirection = null;
      });
    }
  }

  Future<void> _setDone(BuildContext context, bool value) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await widget.repo.update(widget.project.id, widget.task.id, {
        'isDone': value,
      });
      if (!context.mounted) return;
      setState(() => _isDone = value);
      final message =
          value ? 'External task marked complete' : 'External task reopened';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!context.mounted) return;
      final action = value ? 'mark complete' : 'reopen';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to $action: $e')));
    } finally {
      if (context.mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _deleteTask(BuildContext context) async {
    if (_processing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete task?'),
          content: const Text(
            'Are you sure you want to delete this external task?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _processing = true);
    try {
      await widget.repo.delete(widget.project.id, widget.task.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('External task deleted')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    } finally {
      if (context.mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _toggleStar(BuildContext context) async {
    if (_starProcessing || _processing) return;
    final nextValue = !_isStarred;
    setState(() => _starProcessing = true);
    try {
      await widget.repo.setStarred(
        widget.project.id,
        widget.task.id,
        nextValue,
        starredOrder: nextValue ? _nextStarredOrder() : null,
      );
      if (!context.mounted) return;
      setState(() => _isStarred = nextValue);
    } catch (e) {
      if (!context.mounted) return;
      final action = nextValue ? 'star' : 'unstar';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to $action task: $e')));
    } finally {
      if (context.mounted) {
        setState(() => _starProcessing = false);
      }
    }
  }

  int _nextStarredOrder() {
    final tasks = widget.project.externalTasks ?? const <ExternalTask>[];
    final ordered = tasks.where((task) =>
        task.id != widget.task.id &&
        task.isStarred &&
        task.starredOrder != null);
    if (ordered.isEmpty) {
      final count = tasks
          .where((task) => task.id != widget.task.id && task.isStarred)
          .length;
      return count;
    }
    var maxOrder = ordered.first.starredOrder!;
    for (final task in ordered) {
      final order = task.starredOrder!;
      if (order > maxOrder) {
        maxOrder = order;
      }
    }
    return maxOrder + 1;
  }

  Widget _buildSwipeBackground(
    BuildContext context, {
    required bool isStartToEnd,
  }) {
    final theme = Theme.of(context);
    final isActive = _currentDirection ==
        (isStartToEnd
            ? DismissDirection.startToEnd
            : DismissDirection.endToStart);
    final isArmed = isStartToEnd ? _completeArmed : _deleteArmed;
    final color = isStartToEnd
        ? theme.colorScheme.primary.withValues(
            alpha: isActive && isArmed ? 0.25 : 0.12,
          )
        : Colors.transparent;

    final icon = isStartToEnd ? Icons.check : Icons.delete;
    final alignment =
        isStartToEnd ? Alignment.centerLeft : Alignment.centerRight;

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.only(
        left: isStartToEnd ? 6 : 0,
        right: isStartToEnd ? 0 : 6,
      ),
      alignment: alignment,
      child: Icon(
        icon,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.groups_outlined, size: 72),
            SizedBox(height: 12),
            Text('No external tasks outstanding.'),
          ],
        ),
      ),
    );
  }
}

int _compareProjects(Project a, Project b) {
  final pa = a.projectNumber?.trim();
  final pb = b.projectNumber?.trim();
  if (pa != null && pa.isNotEmpty && pb != null && pb.isNotEmpty) {
    final cmp = _naturalCompare(pa, pb);
    if (cmp != 0) return cmp;
  } else if (pa != null && pa.isNotEmpty && (pb == null || pb.isEmpty)) {
    return -1;
  } else if ((pa == null || pa.isEmpty) && pb != null && pb.isNotEmpty) {
    return 1;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

int _naturalCompare(String a, String b) {
  final ta = _tokenizeNatural(a);
  final tb = _tokenizeNatural(b);
  final len = ta.length < tb.length ? ta.length : tb.length;
  for (var i = 0; i < len; i++) {
    final va = ta[i];
    final vb = tb[i];
    if (va == vb) continue;
    if (va is int && vb is int) {
      final c = va.compareTo(vb);
      if (c != 0) return c;
    } else {
      final c = va.toString().compareTo(vb.toString());
      if (c != 0) return c;
    }
  }
  return ta.length.compareTo(tb.length);
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

int _compareTasks(ExternalTask a, ExternalTask b) {
  final ao = a.sortOrder;
  final bo = b.sortOrder;
  if (ao != null || bo != null) {
    if (ao == null) return 1;
    if (bo == null) return -1;
    final cmpOrder = ao.compareTo(bo);
    if (cmpOrder != 0) return cmpOrder;
  }
  if (a.isDone != b.isDone) {
    return (a.isDone ? 1 : 0) - (b.isDone ? 1 : 0);
  }
  final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return ad.compareTo(bd);
}
