// lib/src/pages/project_detail_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/external_task.dart';
import '../data/repositories/external_task_repository.dart';
import 'package:intl/intl.dart';

import '../data/models/project.dart';
import '../data/models/invoice.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/invoice_repository.dart';

import '../widgets/form_helpers.dart';
import '../widgets/tasks_by_subphase_section.dart';
import '../widgets/invoices_section.dart' as inv;
import '../dialogs/edit_project_dialog.dart';
import '../utils/phone_utils.dart';

class _TeamFieldConfig {
  const _TeamFieldConfig({required this.key, required this.label});

  final String key;
  final String label;
}

const List<_TeamFieldConfig> _teamFieldConfigs = [
  _TeamFieldConfig(key: 'teamOwner', label: 'Owner'),
  _TeamFieldConfig(key: 'teamArchitect', label: 'Architect'),
  _TeamFieldConfig(key: 'teamSurveyor', label: 'Surveyor'),
  _TeamFieldConfig(key: 'teamGeotechnical', label: 'Geotechnical'),
  _TeamFieldConfig(key: 'teamMechanical', label: 'Mechanical'),
  _TeamFieldConfig(key: 'teamElectrical', label: 'Electrical'),
  _TeamFieldConfig(key: 'teamPlumbing', label: 'Plumbing'),
  _TeamFieldConfig(key: 'teamLandscape', label: 'Landscape'),
  _TeamFieldConfig(key: 'teamContractor', label: 'Contractor'),
  _TeamFieldConfig(key: 'teamEnvironmental', label: 'Environmental'),
  _TeamFieldConfig(key: 'teamOther', label: 'Other'),
];

class _AssigneeOption {
  const _AssigneeOption({
    required this.key,
    required this.label,
    required this.value,
  });

  final String key;
  final String label;
  final String value;
}

Map<String, String?> _teamValueMap(Project project) => {
  'teamOwner': project.teamOwner,
  'teamArchitect': project.teamArchitect,
  'teamSurveyor': project.teamSurveyor,
  'teamGeotechnical': project.teamGeotechnical,
  'teamMechanical': project.teamMechanical,
  'teamElectrical': project.teamElectrical,
  'teamPlumbing': project.teamPlumbing,
  'teamLandscape': project.teamLandscape,
  'teamContractor': project.teamContractor,
  'teamEnvironmental': project.teamEnvironmental,
  'teamOther': project.teamOther,
};

List<_AssigneeOption> _buildExternalAssigneeOptions(
  Project project,
  User? owner,
) {
  final options = <_AssigneeOption>[];

  if (owner != null) {
    final email = owner.email?.trim();
    final label = (email != null && email.isNotEmpty)
        ? 'Owner ($email)'
        : 'Owner';
    options.add(_AssigneeOption(key: 'owner', label: label, value: label));
  }

  final values = _teamValueMap(project);
  for (final field in _teamFieldConfigs) {
    final value = values[field.key];
    if (value != null) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        final label = '${field.label} - $trimmed';
        options.add(
          _AssigneeOption(key: field.key, label: label, value: label),
        );
      }
    }
  }

  return options;
}

class ProjectDetailPage extends StatefulWidget {
  final String projectId;
  const ProjectDetailPage({super.key, required this.projectId});

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  bool _unpaidOnly = true; // toggle for invoice filtering (default hide paid)
  final ScrollController _scrollCtrl = ScrollController();
  static const _accentYellow = Color(0xFFF1C400);

  late final ProjectRepository _projectRepo;
  StreamSubscription<Project?>? _projectSub;
  Project? _project;
  bool _isLoading = true;
  bool _notFound = false;

  @override
  void dispose() {
    _projectSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _projectRepo = ProjectRepository();
    _subscribeToProject(widget.projectId);
  }

  @override
  void didUpdateWidget(covariant ProjectDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _projectSub?.cancel();
      _project = null;
      _isLoading = true;
      _notFound = false;
      _subscribeToProject(widget.projectId);
    }
  }

  void _subscribeToProject(String projectId) {
    _projectSub?.cancel();
    _project = null;
    _isLoading = true;
    _notFound = false;
    _projectSub = _projectRepo
        .streamById(projectId)
        .listen(
          (proj) {
            if (!mounted) return;
            setState(() {
              _project = proj;
              _isLoading = false;
              _notFound = proj == null;
            });
          },
          onError: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _notFound = true;
            });
          },
        );
  }

  void _setUnpaidOnly(bool v) {
    final offset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    setState(() => _unpaidOnly = v);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      var target = offset;
      final maxScroll = _scrollCtrl.position.maxScrollExtent;
      if (target > maxScroll) {
        target = maxScroll;
      } else if (target < 0) {
        target = 0;
      }
      if ((_scrollCtrl.offset - target).abs() > 0.5) {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final project = _project;
    if (_notFound || project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Project')),
        body: const Center(child: Text('Project not found')),
      );
    }

    final isOwner = project.ownerUid != null && project.ownerUid == me?.uid;
    final ownerUser = isOwner ? me : null;
    final assigneeOptions = _buildExternalAssigneeOptions(project, ownerUser);
    final phoneDisplay = formatPhoneForDisplay(project.contactPhone);
    final hasTeamEntries = _teamValueMap(project).values.any((value) {
      if (value == null) return false;
      return value.trim().isNotEmpty;
    });
    final showTeamCard = isOwner || hasTeamEntries;
    final externalTasks = project.externalTasks ?? const <ExternalTask>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          (project.projectNumber != null &&
                  project.projectNumber!.trim().isNotEmpty)
              ? '${project.projectNumber} ${project.name}'
              : project.name,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.visible,
        ),
        actions: [
          if (isOwner)
            IconButton(
              tooltip: 'Edit',
              onPressed: () => showEditProjectDialog(context, project),
              icon: const Icon(Icons.edit),
            ),
        ],
      ),
      body: ListView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(16),
        children: [
          _kv(context, 'Client', project.clientName),
          if ((project.contactName ?? '').isNotEmpty ||
              (project.contactEmail ?? '').isNotEmpty ||
              phoneDisplay.isNotEmpty)
            Card(
              color: _subtleSurfaceTint(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contact',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if ((project.contactName ?? '').isNotEmpty)
                      Text(project.contactName!),
                    if ((project.contactEmail ?? '').isNotEmpty)
                      Text(project.contactEmail!),
                    if (phoneDisplay.isNotEmpty) Text(phoneDisplay),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (showTeamCard) ...[
            _projectTeamCard(context, project, isOwner: isOwner),
            const SizedBox(height: 16),
          ],
          TasksBySubphaseSection(
            projectId: project.id,
            isOwner: isOwner,
            selectedSubphases: project.selectedSubphases,
          ),
          const SizedBox(height: 12),
          _ExternalTasksSection(
            projectId: project.id,
            isOwner: isOwner,
            assigneeOptions: assigneeOptions,
            tasks: externalTasks,
          ),
          const SizedBox(height: 12),
          _FinancialSummaryCard(
            projectId: project.id,
            projectNumber: project.projectNumber,
            contractAmount: project.contractAmount,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Invoices',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _setUnpaidOnly(!_unpaidOnly),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: _accentYellow,
                        ),
                        child: Text(
                          _unpaidOnly
                              ? 'Show Paid Invoices'
                              : 'Hide Paid Invoices',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _accentYellow,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      'Client Invoices',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _accentYellow,
                      ),
                    ),
                  ),
                  inv.InvoicesSection(
                    projectId: project.id,
                    isOwner: isOwner,
                    projectNumberString: project.projectNumber,
                    title: '',
                    invoiceTypeFilter: 'Client',
                    wrapInCard: false,
                    showNewButton: false,
                    unpaidOnly: _unpaidOnly,
                  ),
                  const SizedBox(height: 10),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      'Vendor Invoices',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _accentYellow,
                      ),
                    ),
                  ),
                  inv.InvoicesSection(
                    projectId: project.id,
                    isOwner: isOwner,
                    projectNumberString: project.projectNumber,
                    title: '',
                    invoiceTypeFilter: 'Vendor',
                    wrapInCard: false,
                    showNewButton: false,
                    unpaidOnly: _unpaidOnly,
                  ),
                  const SizedBox(height: 12),
                  if (isOwner)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => inv.showAddInvoiceDialog(
                          context,
                          project.id,
                          defaultProjectNumber: project.projectNumber,
                          initialInvoiceType: 'Client',
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('New Invoice'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Owner UID: ${project.ownerUid ?? '(none)'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              if (isOwner)
                TextButton.icon(
                  icon: const Icon(
                    Icons.delete_forever,
                    color: Colors.redAccent,
                  ),
                  label: const Text(
                    'Delete Project',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      'Delete this project?',
                    );
                    if (ok) {
                      await _projectRepo.delete(project.id);
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _projectTeamCard(
    BuildContext context,
    Project project, {
    required bool isOwner,
  }) {
    final theme = Theme.of(context);
    final values = _teamValueMap(project);
    final entries = <MapEntry<String, String>>[];

    for (final field in _teamFieldConfigs) {
      final value = values[field.key];
      if (value == null) continue;
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      entries.add(MapEntry(field.label, trimmed));
    }

    final hasEntries = entries.isNotEmpty;
    final headerStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    final prompt = isOwner
        ? 'Tap to add project partners'
        : 'No project partners listed';

    return Card(
      color: _subtleSurfaceTint(context),
      child: InkWell(
        onTap: isOwner ? () => _editProjectTeam(project) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Project Team', style: headerStyle)),
                  if (isOwner)
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (hasEntries)
                ...entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${entry.key}: ', style: labelStyle),
                          TextSpan(
                            text: entry.value,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Text(
                  prompt,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editProjectTeam(Project project) async {
    final initialValues = _teamValueMap(project);
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (dialogContext) {
        return _EditProjectTeamDialog(initialValues: initialValues);
      },
    );

    if (result == null) return;

    final updates = <String, dynamic>{};
    var hasChanges = false;
    for (final field in _teamFieldConfigs) {
      final key = field.key;
      final initial = (initialValues[key] ?? '').trim();
      final normalizedInitial = initial.isEmpty ? null : initial;
      final updated = result[key]?.trim();
      final normalizedUpdated = (updated == null || updated.isEmpty)
          ? null
          : updated;
      if (normalizedInitial != normalizedUpdated) {
        updates[key] = normalizedUpdated;
        hasChanges = true;
      }
    }

    if (!hasChanges) return;

    try {
      await _projectRepo.update(project.id, updates);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Project team updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  Color _subtleSurfaceTint(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Color.alphaBlend(const Color(0x14FFFFFF), surface);
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Card(
      color: _subtleSurfaceTint(context),
      child: ListTile(
        title: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(v),
      ),
    );
  }
}

class _EditProjectTeamDialog extends StatefulWidget {
  const _EditProjectTeamDialog({required this.initialValues});

  final Map<String, String?> initialValues;

  @override
  State<_EditProjectTeamDialog> createState() => _EditProjectTeamDialogState();
}

class _EditProjectTeamDialogState extends State<_EditProjectTeamDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in _teamFieldConfigs)
        field.key: TextEditingController(
          text: widget.initialValues[field.key] ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String?> _collectUpdates() {
    final updates = <String, String?>{};
    for (final field in _teamFieldConfigs) {
      final text = _controllers[field.key]!.text.trim();
      updates[field.key] = text.isEmpty ? null : text;
    }
    return updates;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Project Team'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _teamFieldConfigs.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == _teamFieldConfigs.length - 1 ? 0 : 8,
                ),
                child: appTextField(
                  _teamFieldConfigs[i].label,
                  _controllers[_teamFieldConfigs[i].key]!,
                  dense: true,
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
          onPressed: () {
            Navigator.of(context).pop(_collectUpdates());
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ExternalTasksSection extends StatelessWidget {
  const _ExternalTasksSection({
    required this.projectId,
    required this.isOwner,
    required this.assigneeOptions,
    required this.tasks,
  });

  final String projectId;
  final bool isOwner;
  final List<_AssigneeOption> assigneeOptions;
  final List<ExternalTask> tasks;

  static final ExternalTaskRepository _repo = ExternalTaskRepository();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = isOwner && assigneeOptions.isNotEmpty;
    final items = [...tasks];
    items.sort((a, b) {
      if (a.isDone != b.isDone) {
        return (a.isDone ? 1 : 0) - (b.isDone ? 1 : 0);
      }
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ad.compareTo(bd);
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('External Tasks', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  canEdit
                      ? 'No external tasks yet.'
                      : 'No external tasks to display.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final task = items[index];
                  return _ExternalTaskTile(
                    key: ValueKey('external-${task.id}'),
                    dismissibleKey: ValueKey('external-${task.id}'),
                    task: task,
                    isOwner: isOwner,
                    onSetDone: (value) => _setDone(context, task, value),
                    onDelete: () => _delete(context, task),
                  );
                },
              ),
            if (canEdit) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _showAddExternalTaskDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New Task'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<bool> _setDone(
    BuildContext context,
    ExternalTask task,
    bool value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.update(projectId, task.id, {'isDone': value});
      return true;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update task: $e')),
      );
      return false;
    }
  }

  Future<bool> _delete(BuildContext context, ExternalTask task) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Delete task'),
              content: const Text('Delete this external task?'),
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
        ) ??
        false;
    if (!confirmed) return false;

    try {
      await _repo.delete(projectId, task.id);
      return true;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete task: $e')),
      );
      return false;
    }
  }

  Future<void> _showAddExternalTaskDialog(BuildContext context) async {
    final titleController = TextEditingController();
    var selectedKey = assigneeOptions.isNotEmpty
        ? assigneeOptions.first.key
        : null;

    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('Add External Task'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: titleController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Task description',
                      ),
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: DropdownButtonFormField<String>(
                      initialValue: selectedKey,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Assigned to',
                        border: OutlineInputBorder(),
                      ),
                      items: assigneeOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option.key,
                              child: Text(option.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => selectedKey = value),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty || selectedKey == null) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Provide a title and assignee.'),
                        ),
                      );
                      return;
                    }
                    Navigator.of(
                      dialogContext,
                    ).pop({'title': title, 'assigneeKey': selectedKey!});
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    final option = assigneeOptions.firstWhere(
      (item) => item.key == result['assigneeKey'],
      orElse: () => assigneeOptions.first,
    );

    try {
      await _repo.add(
        projectId,
        ExternalTask(
          id: '',
          projectId: projectId,
          title: result['title'] ?? '',
          assigneeKey: option.key,
          assigneeName: option.value,
          isDone: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to add task: $e')));
    }
  }
}

class _ExternalTaskTile extends StatefulWidget {
  const _ExternalTaskTile({
    super.key,
    required this.dismissibleKey,
    required this.task,
    required this.isOwner,
    required this.onSetDone,
    required this.onDelete,
  });

  final Key dismissibleKey;
  final ExternalTask task;
  final bool isOwner;
  final Future<bool> Function(bool) onSetDone;
  final Future<bool> Function() onDelete;

  @override
  State<_ExternalTaskTile> createState() => _ExternalTaskTileState();
}

class _ExternalTaskTileState extends State<_ExternalTaskTile> {
  static const double _completeThreshold = 0.6;
  static const double _deleteThreshold = 0.85;

  double _dragProgress = 0.0;
  DismissDirection? _currentDirection;

  bool get _completeArmed =>
      _currentDirection == DismissDirection.startToEnd &&
      _dragProgress >= _completeThreshold;

  bool get _deleteArmed =>
      _currentDirection == DismissDirection.endToStart &&
      _dragProgress >= _deleteThreshold;

  void _resetDrag() {
    if (_dragProgress != 0.0 || _currentDirection != null) {
      setState(() {
        _dragProgress = 0.0;
        _currentDirection = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final small = theme.textTheme.bodySmall?.copyWith(fontSize: 12);
    final assignee = task.assigneeName.trim();
    final baseColor = theme.textTheme.bodyMedium?.color;
    final doneColor = baseColor?.withValues(alpha: 0.6);
    const baseTitleStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 13);
    final titleStyle = task.isDone
        ? baseTitleStyle.copyWith(
            decoration: TextDecoration.lineThrough,
            color: doneColor,
          )
        : baseTitleStyle;

    return Dismissible(
      key: widget.dismissibleKey,
      direction: widget.isOwner
          ? DismissDirection.horizontal
          : DismissDirection.none,
      dismissThresholds: const {
        DismissDirection.startToEnd: _completeThreshold,
        DismissDirection.endToStart: _deleteThreshold,
      },
      background: _buildSwipeBackground(context, isStartToEnd: true),
      secondaryBackground: _buildSwipeBackground(context, isStartToEnd: false),
      onUpdate: (details) {
        final progress = details.progress.abs().clamp(0.0, 1.0);
        final direction =
            (details.direction == DismissDirection.startToEnd ||
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
        if (!widget.isOwner) return false;
        final progress = _dragProgress;
        _resetDrag();
        if (direction == DismissDirection.startToEnd &&
            progress >= _completeThreshold) {
          await widget.onSetDone(!task.isDone);
          return false;
        }
        if (direction == DismissDirection.endToStart &&
            progress >= _deleteThreshold) {
          return await widget.onDelete();
        }
        return false;
      },
      child: Material(
        color: task.isDone
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.isOwner
              ? () {
                  final next = !task.isDone;
                  widget.onSetDone(next);
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: task.isDone,
                  onChanged: widget.isOwner
                      ? (value) {
                          final newValue = value ?? false;
                          if (newValue != task.isDone) {
                            widget.onSetDone(newValue);
                          }
                        }
                      : null,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      if (assignee.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(assignee, style: small),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeBackground(
    BuildContext context, {
    required bool isStartToEnd,
  }) {
    final theme = Theme.of(context);
    final isActive =
        _currentDirection ==
        (isStartToEnd
            ? DismissDirection.startToEnd
            : DismissDirection.endToStart);
    final progress = isActive ? _dragProgress : 0.0;

    final baseColor = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.2,
    );
    final accentColor = isStartToEnd
        ? theme.colorScheme.primary.withValues(alpha: 0.25)
        : theme.colorScheme.error.withValues(alpha: 0.25);

    final isArmed = isStartToEnd ? _completeArmed : _deleteArmed;
    final bgColor = isActive && isArmed ? accentColor : baseColor;

    final iconOpacity = isStartToEnd
        ? (progress / _completeThreshold).clamp(0.0, 1.0)
        : progress <= _completeThreshold
        ? 0.0
        : ((progress - _completeThreshold) /
                  (_deleteThreshold - _completeThreshold))
              .clamp(0.0, 1.0);

    final alignment = isStartToEnd
        ? Alignment.centerLeft
        : Alignment.centerRight;
    final rowAlignment = isStartToEnd
        ? MainAxisAlignment.start
        : MainAxisAlignment.end;

    final icon = isStartToEnd ? Icons.check_circle : Icons.delete_forever;
    final iconColor = isStartToEnd
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: bgColor,
      child: Row(
        mainAxisAlignment: rowAlignment,
        children: [
          Opacity(
            opacity: iconOpacity,
            child: Icon(icon, color: iconColor),
          ),
        ],
      ),
    );
  }
}

class _FinancialSummaryCard extends StatelessWidget {
  final String projectId;
  final String? projectNumber;
  final double? contractAmount;

  const _FinancialSummaryCard({
    required this.projectId,
    required this.projectNumber,
    required this.contractAmount,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency();
    final currency0 = NumberFormat.simpleCurrency(
      decimalDigits: 0,
    ); // no cents for contract

    return StreamBuilder<List<Invoice>>(
      stream: InvoiceRepository().streamForProject(
        projectId: projectId,
        projectNumber: projectNumber,
      ),
      builder: (context, snap) {
        final invoices = snap.data ?? const <Invoice>[];

        double clientInvoiced = 0;
        double clientUnpaid = 0;
        double vendorInvoiced = 0;
        double vendorUnpaid = 0;

        for (final inv in invoices) {
          if (inv.invoiceType == 'Client') {
            clientInvoiced += inv.invoiceAmount;
            clientUnpaid += inv.balance; // amount - amountPaid
          } else if (inv.invoiceType == 'Vendor') {
            vendorInvoiced += inv.invoiceAmount;
            vendorUnpaid += inv.balance;
          }
        }

        final contract = contractAmount ?? 0.0;
        final pctInvoiced = (contract > 0)
            ? (clientInvoiced / contract) * 100
            : 0.0;
        final theme = Theme.of(context);
        final surface = theme.colorScheme.surface;
        final cardColor = Color.alphaBlend(const Color(0x14FFFFFF), surface);

        return Card(
          color: cardColor,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contract Amount: ${contractAmount != null ? currency0.format(contractAmount) : '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  (contract > 0)
                      ? 'Contract Progress: ${pctInvoiced.toStringAsFixed(0)}%'
                      : 'Contract Progress: —',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _metricBox(
                        context,
                        label: 'Client Invoiced',
                        value: currency.format(clientInvoiced),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricBox(
                        context,
                        label: 'Balance',
                        value: currency.format(clientUnpaid),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _metricBox(
                        context,
                        label: 'Vendor Invoiced',
                        value: currency.format(vendorInvoiced),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricBox(
                        context,
                        label: 'Balance',
                        value: currency.format(vendorUnpaid),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricBox(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final outline = Theme.of(
      context,
    ).colorScheme.outlineVariant.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
