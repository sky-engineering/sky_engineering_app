// lib/src/widgets/external_tasks_section.dart
import 'package:flutter/material.dart';

import '../data/models/external_task.dart';
import '../data/repositories/external_task_repository.dart';

class ExternalAssigneeOption {
  const ExternalAssigneeOption({
    required this.key,
    required this.label,
    required this.value,
  });

  final String key;
  final String label;
  final String value;
}

class ExternalTasksSection extends StatelessWidget {
  const ExternalTasksSection({
    super.key,
    required this.projectId,
    required this.canEdit,
    required this.assigneeOptions,
    required this.tasks,
  });

  final String projectId;
  final bool canEdit;
  final List<ExternalAssigneeOption> assigneeOptions;
  final List<ExternalTask> tasks;
  static const _fabColor = Color(0xFFF1C400);

  static final ExternalTaskRepository _repo = ExternalTaskRepository();

  static int _compareTasks(ExternalTask a, ExternalTask b) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enableEditing = canEdit && assigneeOptions.isNotEmpty;
    final items = [...tasks];
    items.sort(_compareTasks);

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
                  enableEditing
                      ? 'No external tasks yet.'
                      : 'No external tasks to display.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              _ExternalTaskList(
                tasks: items,
                canEdit: enableEditing,
                onSetDone: (task, value) => _setDone(context, task, value),
                onDelete: (task) => _delete(context, task),
                onToggleStar: (task) => _toggleStar(context, task),
                onEdit: (task) => _showEditExternalTaskDialog(context, task),
                onReorder: enableEditing
                    ? (ordered) => _reorderTasks(context, ordered)
                    : null,
              ),
            if (enableEditing) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FloatingActionButton(
                  heroTag: null,
                  onPressed: () => _showAddExternalTaskDialog(context),
                  backgroundColor: _fabColor,
                  foregroundColor: Colors.black,
                  child: const Icon(Icons.add),
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
    final confirmed = await showDialog<bool>(
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

  Future<void> _reorderTasks(
    BuildContext context,
    List<ExternalTask> ordered,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.reorderTasks(
        projectId,
        ordered.map((task) => task.id).toList(),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to reorder tasks: $e')),
      );
      rethrow;
    }
  }

  Future<void> _toggleStar(BuildContext context, ExternalTask task) async {
    final messenger = ScaffoldMessenger.of(context);
    final next = !task.isStarred;
    try {
      await _repo.setStarred(
        projectId,
        task.id,
        next,
        starredOrder: next ? DateTime.now().millisecondsSinceEpoch : null,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update task: $e')),
      );
    }
  }

  Future<void> _showAddExternalTaskDialog(BuildContext context) async {
    final titleController = TextEditingController();
    var selectedKey =
        assigneeOptions.isNotEmpty ? assigneeOptions.first.key : null;

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
                        labelText: 'Assignee',
                      ),
                      items: assigneeOptions
                          .map(
                            (option) => DropdownMenuItem<String>(
                              value: option.key,
                              child: Text(option.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => selectedKey = value);
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                            content: Text('Enter title & assignee.')),
                      );
                      return;
                    }
                    Navigator.of(dialogContext)
                        .pop({'title': title, 'assigneeKey': selectedKey!});
                  },
                  child: const Text('Save'),
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
          title: result['title']!,
          assigneeKey: option.key,
          assigneeName: option.value,
          isDone: false,
          isStarred: false,
          starredOrder: null,
          createdAt: null,
          updatedAt: null,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to add task: $e')),
      );
    }
  }

  Future<void> _showEditExternalTaskDialog(
    BuildContext context,
    ExternalTask task,
  ) async {
    final titleController = TextEditingController(text: task.title);
    var selectedKey = task.assigneeKey;

    final messenger = ScaffoldMessenger.of(context);
    final option = assigneeOptions.firstWhere(
      (item) => item.key == selectedKey,
      orElse: () => assigneeOptions.isNotEmpty
          ? assigneeOptions.first
          : const ExternalAssigneeOption(
              key: '',
              label: 'Unassigned',
              value: 'Unassigned',
            ),
    );
    if (!assigneeOptions.contains(option)) {
      selectedKey = option.key;
    }

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('Edit External Task'),
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
                      key: ValueKey(selectedKey),
                      initialValue: selectedKey,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Assignee',
                      ),
                      items: assigneeOptions
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item.key,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => selectedKey = value);
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    if (title.isEmpty) {
                      messenger.showSnackBar(
                        const SnackBar(
                            content: Text('Enter title & assignee.')),
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop({
                      'title': title,
                      'assigneeKey': selectedKey,
                    });
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    final selectedOption = assigneeOptions.firstWhere(
      (item) => item.key == result['assigneeKey'],
      orElse: () => option,
    );

    try {
      await _repo.update(projectId, task.id, {
        'title': result['title'],
        'assigneeKey': selectedOption.key,
        'assigneeName': selectedOption.value,
      });
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update task: $e')),
      );
    }
  }
}

class _ExternalTaskList extends StatefulWidget {
  const _ExternalTaskList({
    required this.tasks,
    required this.canEdit,
    required this.onSetDone,
    required this.onDelete,
    required this.onToggleStar,
    required this.onEdit,
    this.onReorder,
  });

  final List<ExternalTask> tasks;
  final bool canEdit;
  final Future<bool> Function(ExternalTask task, bool value) onSetDone;
  final Future<bool> Function(ExternalTask task) onDelete;
  final Future<void> Function(ExternalTask task) onToggleStar;
  final Future<void> Function(ExternalTask task) onEdit;
  final Future<void> Function(List<ExternalTask> ordered)? onReorder;

  @override
  State<_ExternalTaskList> createState() => _ExternalTaskListState();
}

class _ExternalTaskListState extends State<_ExternalTaskList> {
  late List<ExternalTask> _tasks;
  bool _pendingReorder = false;

  bool get _reorderEnabled => widget.canEdit && widget.onReorder != null;

  @override
  void initState() {
    super.initState();
    _tasks = List<ExternalTask>.from(widget.tasks);
  }

  @override
  void didUpdateWidget(covariant _ExternalTaskList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWithIncoming(widget.tasks);
  }

  @override
  Widget build(BuildContext context) {
    if (_tasks.isEmpty) return const SizedBox.shrink();
    if (!_reorderEnabled) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.tasks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final task = widget.tasks[index];
          return _buildTile(context, task);
        },
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _tasks.length,
      buildDefaultDragHandles: true,
      proxyDecorator: (child, index, animation) {
        return Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          child: child,
        );
      },
      onReorder: _handleReorder,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        return Column(
          key: ValueKey('external-${task.id}'),
          children: [
            _buildTile(context, task),
            if (index != _tasks.length - 1) const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  Widget _buildTile(BuildContext context, ExternalTask task) {
    return _ExternalTaskTile(
      key: ValueKey('external-tile-${task.id}'),
      dismissibleKey: ValueKey('external-${task.id}'),
      task: task,
      canEdit: widget.canEdit,
      onSetDone: (value) => widget.onSetDone(task, value),
      onDelete: () => widget.onDelete(task),
      onToggleStar: () => widget.onToggleStar(task),
      onEdit: () => widget.onEdit(task),
    );
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    if (!_reorderEnabled) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final previous = List<ExternalTask>.from(_tasks);
    final task = _tasks.removeAt(oldIndex);
    _tasks.insert(newIndex, task);
    setState(() {
      _pendingReorder = true;
    });
    try {
      await widget.onReorder!(List<ExternalTask>.unmodifiable(_tasks));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tasks = previous;
        _pendingReorder = false;
      });
    }
  }

  void _syncWithIncoming(List<ExternalTask> next) {
    final incomingIds = _ids(next);
    final localIds = _ids(_tasks);

    final sameSet = _sameIdSet(incomingIds, localIds);
    if (!sameSet) {
      setState(() {
        _tasks = List<ExternalTask>.from(next);
        _pendingReorder = false;
      });
      return;
    }

    final sameOrder = _listsEqual(incomingIds, localIds);
    if (_pendingReorder) {
      if (sameOrder) {
        setState(() {
          _tasks = List<ExternalTask>.from(next);
          _pendingReorder = false;
        });
      }
      return;
    }

    if (!sameOrder || _hasDifferentInstances(next, _tasks)) {
      setState(() {
        _tasks = List<ExternalTask>.from(next);
      });
    }
  }

  static List<String> _ids(List<ExternalTask> tasks) =>
      tasks.map((task) => task.id).toList(growable: false);

  static bool _sameIdSet(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final seen = <String, int>{};
    for (final id in a) {
      seen[id] = (seen[id] ?? 0) + 1;
    }
    for (final id in b) {
      final count = seen[id];
      if (count == null) return false;
      if (count == 1) {
        seen.remove(id);
      } else {
        seen[id] = count - 1;
      }
    }
    return seen.isEmpty;
  }

  static bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _hasDifferentInstances(
    List<ExternalTask> next,
    List<ExternalTask> current,
  ) {
    if (next.length != current.length) return true;
    for (var i = 0; i < next.length; i++) {
      if (!identical(next[i], current[i])) {
        return true;
      }
    }
    return false;
  }
}

class _ExternalTaskTile extends StatefulWidget {
  const _ExternalTaskTile({
    super.key,
    required this.dismissibleKey,
    required this.task,
    required this.canEdit,
    required this.onSetDone,
    required this.onDelete,
    required this.onToggleStar,
    required this.onEdit,
  });

  final Key dismissibleKey;
  final ExternalTask task;
  final bool canEdit;
  final Future<bool> Function(bool) onSetDone;
  final Future<bool> Function() onDelete;
  final VoidCallback onToggleStar;
  final VoidCallback onEdit;

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
    final hasAssignee = task.hasAssignedTeamMember;
    final assigneeLabel = task.displayAssigneeLabel;
    final baseAssigneeStyle = small ?? const TextStyle(fontSize: 12);
    final fallbackColor =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75) ??
            Colors.black54;
    final assigneeStyle = hasAssignee
        ? baseAssigneeStyle
        : baseAssigneeStyle.copyWith(
            fontStyle: FontStyle.italic,
            color: fallbackColor,
          );
    final baseColor = theme.textTheme.bodyMedium?.color;
    final doneColor = baseColor?.withValues(alpha: 0.6);
    const baseTitleStyle = TextStyle(fontWeight: FontWeight.w600, fontSize: 13);
    final titleStyle = task.isDone
        ? baseTitleStyle.copyWith(
            decoration: TextDecoration.lineThrough,
            color: doneColor,
          )
        : baseTitleStyle;
    final filledStarColor = theme.colorScheme.secondary;
    final hollowStarColor = theme.colorScheme.onSurfaceVariant;

    return Dismissible(
      key: widget.dismissibleKey,
      direction:
          widget.canEdit ? DismissDirection.horizontal : DismissDirection.none,
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
        if (!widget.canEdit) return false;
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
          onTap: widget.canEdit ? widget.onEdit : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    iconSize: 20,
                    splashRadius: 18,
                    tooltip: task.isStarred ? 'Unstar task' : 'Star task',
                    onPressed: widget.canEdit ? widget.onToggleStar : null,
                    icon: Icon(
                      task.isStarred ? Icons.star : Icons.star_border,
                      color: task.isStarred ? filledStarColor : hollowStarColor,
                    ),
                  ),
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
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          assigneeLabel,
                          style: assigneeStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
    final isActive = _currentDirection ==
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

    final alignment =
        isStartToEnd ? Alignment.centerLeft : Alignment.centerRight;
    final rowAlignment =
        isStartToEnd ? MainAxisAlignment.start : MainAxisAlignment.end;

    final icon = isStartToEnd ? Icons.check_circle : Icons.delete_forever;
    final iconColor =
        isStartToEnd ? theme.colorScheme.primary : theme.colorScheme.error;

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
