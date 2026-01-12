// lib/src/widgets/tasks_by_subphase_section.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/models/project.dart';
import '../data/models/task.dart';
import '../data/models/subphase_template.dart';
import '../data/models/external_task.dart';
import '../data/repositories/task_repository.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/subphase_template_repository.dart';
import '../data/repositories/external_task_repository.dart';
import '../dialogs/select_subphases_dialog.dart';
import 'form_helpers.dart';
import '../dialogs/task_edit_dialog.dart';
import '../ui/loading_overlay.dart';

const _kTaskStatuses = <String>[
  'In Progress',
  'On Hold',
  'Pending',
  'Completed',
];
const _kSubphaseStatuses = <String>['In Progress', 'On Hold', 'Completed'];
const _accentYellow = Color(0xFFF1C400);

class TasksBySubphaseSection extends StatefulWidget {
  final String projectId;
  final bool canEdit;
  final List<SelectedSubphase>? selectedSubphases;
  final String ownerUidForWrites;

  const TasksBySubphaseSection({
    super.key,
    required this.projectId,
    required this.canEdit,
    required this.selectedSubphases,
    required this.ownerUidForWrites,
  });

  @override
  State<TasksBySubphaseSection> createState() => _TasksBySubphaseSectionState();
}

class _TasksBySubphaseSectionState extends State<TasksBySubphaseSection> {
  bool _activeOnly = false; // show only In Progress + Pending

  @override
  Widget build(BuildContext context) {
    final repo = TaskRepository();
    final sel = (widget.selectedSubphases ?? <SelectedSubphase>[])
        .where((s) => _isValidCode(s.code))
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    final statusByCode = {for (final s in sel) s.code: s.status};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<List<TaskItem>>(
          stream: repo.streamByProject(widget.projectId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              );
            }
            final allTasks = (snap.data ?? const <TaskItem>[]);

            // Partition tasks: map<code, list> for selected codes; everything else -> other
            final codeSet = sel.map((e) => e.code).toSet();
            final Map<String, List<TaskItem>> byCode = {
              for (final s in sel) s.code: <TaskItem>[],
            };
            final List<TaskItem> other = [];

            for (final t in allTasks) {
              final code = _sanitizeCode(t.taskCode);
              if (code != null && codeSet.contains(code)) {
                byCode[code]!.add(t);
              } else {
                other.add(t);
              }
            }

            // Sort each list (dueDate asc, then title)
            int compareTasks(TaskItem a, TaskItem b) {
              final ad = a.dueDate, bd = b.dueDate;
              if (ad != null && bd != null) {
                final c = ad.compareTo(bd);
                if (c != 0) return c;
              } else if (ad == null && bd != null) {
                return 1;
              } else if (ad != null && bd == null) {
                return -1;
              }
              return a.title.toLowerCase().compareTo(b.title.toLowerCase());
            }

            for (final list in byCode.values) {
              list.sort(compareTasks);
            }
            other.sort(compareTasks);

            // Header row: Tasks + (Select Subphases icon) ... clickable yellow text
            final header = Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left cluster (title + select subphases)
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Tasks',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (widget.canEdit)
                        IconButton(
                          tooltip: 'Select Subphases',
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final primaryOwner =
                                widget.ownerUidForWrites.trim();
                            final authOwner =
                                (FirebaseAuth.instance.currentUser?.uid ?? '')
                                    .trim();
                            final resolvedOwner = primaryOwner.isNotEmpty
                                ? primaryOwner
                                : authOwner;
                            if (resolvedOwner.isEmpty) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Could not determine an owner for this project.',
                                  ),
                                ),
                              );
                              return;
                            }
                            if (!context.mounted) return;
                            await showSelectSubphasesDialog(
                              context,
                              projectId: widget.projectId,
                              ownerUid: resolvedOwner,
                              fallbackOwnerUid: authOwner,
                            );
                          },
                          icon: const Icon(Icons.tune),
                        ),
                    ],
                  ),
                ),
                // Right: tiny yellow text toggle
                TextButton(
                  onPressed: () => setState(() => _activeOnly = !_activeOnly),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: _accentYellow,
                  ),
                  child: Text(
                    _activeOnly ? 'Show Inactive Tasks' : 'Hide Inactive Tasks',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _accentYellow,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            );

            // Helper to filter a list by activeOnly (In Progress + Pending)
            List<TaskItem> maybeFilter(List<TaskItem> input) {
              if (!_activeOnly) return input;
              return input.where((t) {
                final s = t.taskStatus;
                return s == 'In Progress' || s == 'Pending';
              }).toList();
            }

            final otherTasks = maybeFilter(other);
            final boxes = <Widget>[
              header,
              const SizedBox(height: 4),
              if (sel.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'No subphases selected for this project yet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ...sel.map((s) {
                final rawStatus = statusByCode[s.code]?.trim();
                final status = (rawStatus != null && rawStatus.isNotEmpty)
                    ? rawStatus
                    : 'In Progress';
                final suffix = status == 'In Progress' ? '' : ' - $status';
                final displayLabel = '${s.code}  ${s.name}$suffix';
                return _SubphaseBox(
                  projectId: widget.projectId,
                  label: displayLabel,
                  tasks: maybeFilter(byCode[s.code] ?? const <TaskItem>[]),
                  allSubphases: sel,
                  canEdit: widget.canEdit,
                  ownerUidForWrites: widget.ownerUidForWrites,
                  subphase: s,
                  currentStatus: status,
                  onChangeStatus: (newStatus, newName) async {
                    if (!widget.canEdit) {
                      return _SubphaseBox._viewOnlySnack(context);
                    }
                    await _updateSubphaseStatus(
                      context,
                      projectId: widget.projectId,
                      selected: widget.selectedSubphases ??
                          const <SelectedSubphase>[],
                      code: s.code,
                      newStatus: newStatus,
                      newName: newName,
                    );
                  },
                );
              }),
              if (otherTasks.isNotEmpty)
                _SubphaseBox(
                  projectId: widget.projectId,
                  label: 'Other',
                  tasks: otherTasks,
                  allSubphases: sel,
                  canEdit: widget.canEdit,
                  ownerUidForWrites: widget.ownerUidForWrites,
                  subphase: null,
                  currentStatus: null,
                  onChangeStatus: null,
                ),
              const SizedBox(height: 4),
              if (widget.canEdit)
                Align(
                  alignment: Alignment.centerRight,
                  child: FloatingActionButton(
                    heroTag: null,
                    onPressed: () => _showAddTaskDialog(context,
                        widget.projectId, sel, widget.ownerUidForWrites),
                    backgroundColor: _accentYellow,
                    foregroundColor: Colors.black,
                    child: const Icon(Icons.add),
                  ),
                ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...boxes.expand((w) sync* {
                  yield w;
                  if (w is _SubphaseBox) yield const SizedBox(height: 8);
                }),
              ],
            );
          },
        ),
      ),
    );
  }

  static bool _isValidCode(String? code) =>
      code != null && code.trim().length == 4 && int.tryParse(code) != null;

  static String? _sanitizeCode(String? code) {
    if (!_isValidCode(code)) return null;
    return code!.trim();
  }
}

class _SubphaseBox extends StatelessWidget {
  final String projectId;
  final String label; // "0201  Concept Site Plan" or "Other"
  final List<TaskItem> tasks;
  final List<SelectedSubphase> allSubphases;
  final bool canEdit;
  final String ownerUidForWrites;

  final SelectedSubphase? subphase; // null for Other
  final String? currentStatus; // null for Other
  final Future<void> Function(String status, String name)? onChangeStatus;

  const _SubphaseBox({
    required this.projectId,
    required this.label,
    required this.tasks,
    required this.allSubphases,
    required this.canEdit,
    required this.ownerUidForWrites,
    required this.subphase,
    required this.currentStatus,
    required this.onChangeStatus,
  });

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(
      context,
    ).colorScheme.outlineVariant.withValues(alpha: 0.4);
    final statusLabel =
        (currentStatus != null && currentStatus!.trim().isNotEmpty)
            ? currentStatus!.trim()
            : 'In Progress';
    final hasSubphase = subphase != null;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: hasSubphase
                  ? () async {
                      if (!canEdit) {
                        _viewOnlySnack(context);
                        return;
                      }
                      final dialogStatus =
                          _kSubphaseStatuses.contains(statusLabel)
                              ? statusLabel
                              : 'In Progress';
                      await _showSubphaseStatusDialog(
                        context,
                        code: subphase!.code,
                        current: dialogStatus,
                        initialName: subphase!.name,
                        onPicked: (status, name) async {
                          if (onChangeStatus != null) {
                            await onChangeStatus!(status, name);
                          }
                        },
                      );
                    }
                  : null,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: _accentYellow,
                            ),
                            maxLines: 2,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                          ),
                        ],
                      ),
                    ),
                    if (hasSubphase)
                      IconButton(
                        tooltip: 'Insert default tasks',
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        alignment: Alignment.topCenter,
                        onPressed: canEdit
                            ? () async {
                                final preview = await _loadDefaultsPreview(
                                  context,
                                  ownerUid: ownerUidForWrites,
                                  subphaseCode: subphase!.code,
                                );
                                if (preview == null || !context.mounted) {
                                  return;
                                }
                                final selection =
                                    await _showDefaultsPreviewDialog(
                                  context,
                                  subphase!.name,
                                  preview.template,
                                );
                                if (!context.mounted) return;
                                if (selection == null ||
                                    (selection.internal.isEmpty &&
                                        selection.external.isEmpty)) {
                                  return;
                                }
                                await _insertDefaultsForSubphase(
                                  context,
                                  projectId,
                                  subphase!.code,
                                  ownerUidForWrites,
                                  templateOverride: preview.template,
                                  resolvedOwnerUidOverride: preview.ownerUid,
                                  selectedInternal: selection.internal,
                                  selectedExternal: selection.external,
                                );
                              }
                            : () => _viewOnlySnack(context),
                        icon: const Icon(
                          Icons.playlist_add,
                          color: Colors.black87,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (tasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tasks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 1),
                itemBuilder: (context, i) {
                  final t = tasks[i];
                  return _CompactTaskTile(
                    task: t,
                    canEdit: canEdit,
                    onToggleStar: () async {
                      if (!canEdit) return _viewOnlySnack(context);
                      try {
                        await TaskRepository().setStarred(t, !t.isStarred);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not update star: $e'),
                            ),
                          );
                        }
                      }
                    },
                    onChangeStatus: (newStatus) async {
                      if (!canEdit) return _viewOnlySnack(context);
                      await TaskRepository().update(t.id, {
                        'taskStatus': newStatus,
                        'status': _legacyFromNew(newStatus), // mirror
                      });
                    },
                    onTap: () => showTaskEditDialog(
                      context,
                      t,
                      canEdit: canEdit,
                      subphases: allSubphases,
                    ),
                    onCompleteSwipe: () async {
                      if (!canEdit) {
                        _viewOnlySnack(context);
                        return false;
                      }
                      try {
                        await TaskRepository().update(t.id, {
                          'taskStatus': 'Completed',
                          'status': _legacyFromNew('Completed'),
                        });
                        return true;
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to update task: $e'),
                            ),
                          );
                        }
                        return false;
                      }
                    },
                    onDeleteSwipe: () async {
                      if (!canEdit) {
                        _viewOnlySnack(context);
                        return false;
                      }
                      final ok = await confirmDialog(
                        context,
                        'Delete this task?',
                      );
                      if (!ok) return false;
                      try {
                        await TaskRepository().delete(t.id);
                        return true;
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to delete task: $e'),
                            ),
                          );
                        }
                        return false;
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  static void _viewOnlySnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'View-only: only the project owner or an admin can modify tasks.'),
      ),
    );
  }

  static String _legacyFromNew(String taskStatus) {
    switch (taskStatus) {
      case 'In Progress':
        return 'In Progress';
      case 'On Hold':
        return 'Blocked';
      case 'Completed':
        return 'Done';
      case 'Pending':
      default:
        return 'Open';
    }
  }

  static Future<void> _showSubphaseStatusDialog(
    BuildContext context, {
    required String code,
    required String current,
    required String initialName,
    required Future<void> Function(String status, String name) onPicked,
  }) async {
    var selected = current;
    var editedName = initialName;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Subphase $code'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    initialValue: editedName,
                    onChanged: (value) => editedName = value,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    items: _kSubphaseStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => selected = v ?? selected),
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final trimmed = editedName.trim();
                    final resolvedName =
                        trimmed.isNotEmpty ? trimmed : initialName;
                    await onPicked(selected, resolvedName);
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
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
}

// ===== Compact task tile =====

class _CompactTaskTile extends StatefulWidget {
  final TaskItem task;
  final bool canEdit;
  final VoidCallback onToggleStar;
  final ValueChanged<String> onChangeStatus;
  final VoidCallback onTap;
  final Future<bool> Function() onCompleteSwipe;
  final Future<bool> Function() onDeleteSwipe;

  const _CompactTaskTile({
    required this.task,
    required this.canEdit,
    required this.onToggleStar,
    required this.onChangeStatus,
    required this.onTap,
    required this.onCompleteSwipe,
    required this.onDeleteSwipe,
  });

  @override
  State<_CompactTaskTile> createState() => _CompactTaskTileState();
}

class _CompactTaskTileState extends State<_CompactTaskTile> {
  static const double _completeThreshold = 0.6;
  static const double _deleteThreshold = 0.85;

  late List<SubtaskItem> _subtasks;
  bool _expanded = false;
  bool _subtaskUpdateInProgress = false;

  double _dragProgress = 0.0;
  DismissDirection? _currentDirection;

  bool get _completeArmed =>
      _currentDirection == DismissDirection.startToEnd &&
      _dragProgress >= _completeThreshold;

  bool get _deleteArmed =>
      _currentDirection == DismissDirection.endToStart &&
      _dragProgress >= _deleteThreshold;

  bool get _hasSubtasks => _subtasks.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _subtasks = List<SubtaskItem>.from(widget.task.subtasks);
  }

  @override
  void didUpdateWidget(covariant _CompactTaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_subtaskListsEqual(widget.task.subtasks, oldWidget.task.subtasks)) {
      _subtasks = List<SubtaskItem>.from(widget.task.subtasks);
      if (_subtasks.isEmpty) {
        _expanded = false;
      }
    }
  }

  void _resetDrag() {
    if (_dragProgress != 0.0 || _currentDirection != null) {
      setState(() {
        _dragProgress = 0.0;
        _currentDirection = null;
      });
    }
  }

  void _toggleExpansion() {
    if (!_hasSubtasks) return;
    setState(() {
      _expanded = !_expanded;
    });
  }

  Future<void> _handleSubtaskTap(int index) async {
    if (!widget.canEdit) {
      _showSnack(
          'View-only: only the project owner or an admin can modify tasks.');
      return;
    }
    if (_subtaskUpdateInProgress || index < 0 || index >= _subtasks.length) {
      return;
    }

    final previous = List<SubtaskItem>.from(_subtasks);
    final current = previous[index];
    final toggled = current.copyWith(isDone: !current.isDone);
    final updated = List<SubtaskItem>.from(previous)..[index] = toggled;

    setState(() {
      _subtaskUpdateInProgress = true;
      _subtasks = updated;
    });

    try {
      await TaskRepository().update(widget.task.id, {'subtasks': updated});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subtasks = previous;
      });
      _showSnack('Failed to update subtask: $e');
    } finally {
      if (mounted) {
        setState(() {
          _subtaskUpdateInProgress = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static bool _subtaskListsEqual(List<SubtaskItem> a, List<SubtaskItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.title != right.title ||
          left.isDone != right.isDone) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(fontSize: 12);
    final task = widget.task;
    final canEdit = widget.canEdit;
    final hasDesc = (task.description ?? '').trim().isNotEmpty;
    final hasSubtasks = _hasSubtasks;

    final filledStarColor = theme.colorScheme.secondary;
    final hollowStarColor = theme.colorScheme.onSurfaceVariant;

    final baseSubtaskColor =
        theme.textTheme.bodySmall?.color ?? theme.colorScheme.onSurfaceVariant;
    final TextStyle baseSubtaskStyle = (small ?? const TextStyle()).copyWith(
      fontSize: 11,
    );

    return Dismissible(
      key: ValueKey('proj-task-${task.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: _completeThreshold,
        DismissDirection.endToStart: _deleteThreshold,
      },
      background: _buildSwipeBackground(context, isStartToEnd: true),
      secondaryBackground: _buildSwipeBackground(context, isStartToEnd: false),
      onUpdate: (details) {
        final progress = details.progress.abs().clamp(0.0, 1.0);
        final direction = details.direction == DismissDirection.startToEnd ||
                details.direction == DismissDirection.endToStart
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
        final progress = _dragProgress;
        _resetDrag();
        if (direction == DismissDirection.startToEnd &&
            progress >= _completeThreshold) {
          await widget.onCompleteSwipe();
        } else if (direction == DismissDirection.endToStart &&
            progress >= _deleteThreshold) {
          await widget.onDeleteSwipe();
        }
        return false;
      },
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
          child: Row(
            crossAxisAlignment: hasDesc || (hasSubtasks && _expanded)
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: hasDesc ? 1 : 0),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  iconSize: 18,
                  splashRadius: 16,
                  onPressed: widget.onToggleStar,
                  icon: Icon(
                    task.isStarred ? Icons.star : Icons.star_border,
                    color: task.isStarred ? filledStarColor : hollowStarColor,
                  ),
                  tooltip: task.isStarred ? 'Unstar' : 'Star',
                ),
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (hasSubtasks)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              iconSize: 18,
                              splashRadius: 18,
                              onPressed: _toggleExpansion,
                              icon: Icon(_expanded ? Icons.remove : Icons.add),
                              tooltip:
                                  _expanded ? 'Hide subtasks' : 'Show subtasks',
                            ),
                          ),
                        const SizedBox(width: 6),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _kTaskStatuses.contains(task.taskStatus)
                                ? task.taskStatus
                                : 'In Progress',
                            items: _kTaskStatuses
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                            onChanged: canEdit
                                ? (v) {
                                    if (v != null) {
                                      widget.onChangeStatus(v);
                                    }
                                  }
                                : null,
                            isDense: true,
                            icon: const SizedBox.shrink(),
                            style: small,
                          ),
                        ),
                      ],
                    ),
                    if (hasDesc)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          task.description!.trim(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                      ),
                    if (hasSubtasks && _expanded)
                      Padding(
                        padding: EdgeInsets.only(top: hasDesc ? 6 : 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(_subtasks.length, (index) {
                            final subtask = _subtasks[index];
                            final color =
                                baseSubtaskStyle.color ?? baseSubtaskColor;
                            final displayColor = subtask.isDone
                                ? color.withValues(alpha: 0.6)
                                : color;
                            final style = baseSubtaskStyle.copyWith(
                              color: displayColor,
                              decoration: subtask.isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                            );
                            return Padding(
                              padding: EdgeInsets.only(top: index == 0 ? 0 : 4),
                              child: InkWell(
                                onTap: () => _handleSubtaskTap(index),
                                child: Text('- ${subtask.title}', style: style),
                              ),
                            );
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ],
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

Future<void> _showAddTaskDialog(
  BuildContext context,
  String projectId,
  List<SelectedSubphase> subphases,
  String ownerUid,
) async {
  final titleCtl = TextEditingController();
  final notesCtl = TextEditingController();
  String? selectedCode;
  String taskStatus = 'In Progress'; // default to In Progress

  final me = FirebaseAuth.instance.currentUser;
  final repo = TaskRepository();
  final formKey = GlobalKey<FormState>();
  final resolvedOwnerUid = ownerUid.isNotEmpty ? ownerUid : me?.uid ?? '';

  if (resolvedOwnerUid.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('You must be signed in.')));
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('New Task'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      appTextField(
                        'Title',
                        titleCtl,
                        required: true,
                        hint: 'e.g., Site visit',
                      ),
                      const SizedBox(height: 10),
                      appTextField('Notes', notesCtl),
                      const SizedBox(height: 10),

                      // Task Code (dropdown of selected subphases)
                      DropdownButtonFormField<String?>(
                        initialValue: selectedCode,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('No Task Code'),
                          ),
                          ...subphases.map(
                            (s) => DropdownMenuItem<String?>(
                              value: s.code,
                              child: Text(
                                '${s.code}  ${s.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => selectedCode = v),
                        decoration: const InputDecoration(
                          labelText: 'Task Code (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Task Status
                      DropdownButtonFormField<String>(
                        initialValue: taskStatus,
                        isExpanded: true,
                        items: _kTaskStatuses
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => taskStatus = v ?? taskStatus),
                        decoration: const InputDecoration(
                          labelText: 'Task Status',
                          border: OutlineInputBorder(),
                        ),
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
                  final navigator = Navigator.of(context);
                  if (!(formKey.currentState?.validate() ?? false)) return;

                  final t = TaskItem(
                    id: '_',
                    projectId: projectId,
                    ownerUid: resolvedOwnerUid,
                    title: titleCtl.text.trim(),
                    description: notesCtl.text.trim().isEmpty
                        ? null
                        : notesCtl.text.trim(),
                    taskStatus: taskStatus,
                    isStarred: false,
                    taskCode: selectedCode,
                    dueDate: null,
                    assigneeName: null,
                    createdAt: null,
                    updatedAt: null,
                  );
                  await repo.add(t);
                  if (navigator.mounted) {
                    navigator.pop();
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

class _DefaultsPreviewData {
  const _DefaultsPreviewData({
    required this.ownerUid,
    required this.template,
  });

  final String ownerUid;
  final SubphaseTemplate template;
}

class _DefaultsSelection {
  const _DefaultsSelection({
    required this.internal,
    required this.external,
  });

  final List<String> internal;
  final List<String> external;
}

List<String> _cleanDefaults(List<String> values) {
  return values.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
}

Future<_DefaultsPreviewData?> _loadDefaultsPreview(
  BuildContext context, {
  required String ownerUid,
  required String subphaseCode,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final me = FirebaseAuth.instance.currentUser;
  final trimmedOwner = ownerUid.trim();
  final authOwner = (me?.uid ?? '').trim();
  final resolvedOwnerUid = trimmedOwner.isNotEmpty ? trimmedOwner : authOwner;
  if (resolvedOwnerUid.isEmpty) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('You must be signed in.')),
    );
    return null;
  }

  List<String> buildOwnerFallbackOrder() {
    final seen = <String>{};
    final order = <String>[];

    void addCandidate(String value, {bool allowEmpty = false}) {
      final trimmed = value.trim();
      if (trimmed.isEmpty && !allowEmpty) return;
      if (!seen.add(trimmed)) return;
      order.add(trimmed);
    }

    addCandidate(trimmedOwner);
    addCandidate(authOwner);
    addCandidate('', allowEmpty: true);
    return order;
  }

  try {
    final templatesRepo = SubphaseTemplateRepository();
    SubphaseTemplate? tpl;
    String? matchedOwner;
    for (final candidate in buildOwnerFallbackOrder()) {
      tpl = await templatesRepo.getByOwnerAndCode(candidate, subphaseCode);
      if (tpl != null) {
        matchedOwner = candidate;
        break;
      }
    }

    if (tpl == null) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('No default tasks defined for this subphase.'),
        ),
      );
      return null;
    }

    final hasAny = _cleanDefaults(tpl.defaultTasks).isNotEmpty ||
        _cleanDefaults(tpl.defaultExternalTasks).isNotEmpty;
    if (!hasAny) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('No default tasks defined for this subphase.'),
        ),
      );
      return null;
    }

    return _DefaultsPreviewData(
      ownerUid: matchedOwner ?? resolvedOwnerUid,
      template: tpl,
    );
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Failed to load defaults: $e')),
    );
    return null;
  }
}

Future<_DefaultsSelection?> _showDefaultsPreviewDialog(
  BuildContext context,
  String subphaseName,
  SubphaseTemplate template,
) async {
  final internal = _cleanDefaults(template.defaultTasks);
  final external = _cleanDefaults(template.defaultExternalTasks);
  final selectedInternal = internal.toSet();
  final selectedExternal = external.toSet();
  var expandInternal = true;
  var expandExternal = true;

  return showDialog<_DefaultsSelection>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          Widget buildSection(
            String heading,
            List<String> items,
            Set<String> selected,
            bool expanded,
            VoidCallback onToggle,
          ) {
            if (items.isEmpty) return const SizedBox.shrink();
            final allSelected =
                selected.length == items.length && items.isNotEmpty;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onToggle,
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(
                                expanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                heading,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (allSelected) {
                            selected.clear();
                          } else {
                            selected
                              ..clear()
                              ..addAll(items);
                          }
                        });
                      },
                      child: Text(allSelected ? 'Deselect All' : 'Select All'),
                    ),
                  ],
                ),
                if (expanded)
                  ...items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 2, left: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Transform.scale(
                              scale: 0.85,
                              child: Checkbox(
                                value: selected.contains(item),
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked ?? false) {
                                      selected.add(item);
                                    } else {
                                      selected.remove(item);
                                    }
                                  });
                                },
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(height: 1.2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          }

          return AlertDialog(
            title: const Text('Default Tasks'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildSection(
                      'Tasks',
                      internal,
                      selectedInternal,
                      expandInternal,
                      () => setState(() => expandInternal = !expandInternal),
                    ),
                    if (internal.isNotEmpty && external.isNotEmpty)
                      const SizedBox(height: 10),
                    buildSection(
                      'External tasks',
                      external,
                      selectedExternal,
                      expandExternal,
                      () => setState(() => expandExternal = !expandExternal),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                    _DefaultsSelection(
                      internal: internal
                          .where((item) => selectedInternal.contains(item))
                          .toList(),
                      external: external
                          .where((item) => selectedExternal.contains(item))
                          .toList(),
                    ),
                  );
                },
                child: const Text('Add Tasks'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Insert default tasks for a given subphase code into the current project.
/// De-duplicates by title (case-insensitive) among tasks that already
/// exist for the same `projectId` + `taskCode`.
Future<void> _insertDefaultsForSubphase(
  BuildContext context,
  String projectId,
  String subphaseCode,
  String ownerUid, {
  SubphaseTemplate? templateOverride,
  String? resolvedOwnerUidOverride,
  List<String>? selectedInternal,
  List<String>? selectedExternal,
}) async {
  final me = FirebaseAuth.instance.currentUser;
  final overrideUid = (resolvedOwnerUidOverride ?? '').trim();
  final fallbackOwnerUid = ownerUid.trim();
  final authUid = (me?.uid ?? '').trim();
  final resolvedOwnerUid = overrideUid.isNotEmpty
      ? overrideUid
      : (fallbackOwnerUid.isNotEmpty ? fallbackOwnerUid : authUid);
  if (resolvedOwnerUid.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('You must be signed in.')));
    return;
  }

  final templatesRepo = SubphaseTemplateRepository();
  final messenger = ScaffoldMessenger.maybeOf(context);

  try {
    LoadingOverlay.show(context, message: 'Adding tasks...');
    final tpl = templateOverride ??
        await templatesRepo.getByOwnerAndCode(resolvedOwnerUid, subphaseCode);
    if (tpl == null) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('No default tasks defined for this subphase.'),
        ),
      );
      return;
    }

    final cleanedDefaults = List<String>.from(
      selectedInternal ?? _cleanDefaults(tpl.defaultTasks),
    );
    final cleanedExternalDefaults = List<String>.from(
      selectedExternal ?? _cleanDefaults(tpl.defaultExternalTasks),
    );

    if (cleanedDefaults.isEmpty && cleanedExternalDefaults.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('No default tasks defined for this subphase.'),
        ),
      );
      return;
    }

    var insertedInternal = 0;
    var insertedExternal = 0;

    if (cleanedDefaults.isNotEmpty) {
      final existingQs = await FirebaseFirestore.instance
          .collection('tasks')
          .where('projectId', isEqualTo: projectId)
          .where('taskCode', isEqualTo: subphaseCode)
          .get();

      final existingTitleSet = existingQs.docs
          .map((d) =>
              ((d.data()['title'] as String?) ?? '').trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet();

      final toInsert = cleanedDefaults
          .where((t) => !existingTitleSet.contains(t.toLowerCase()))
          .toList();

      if (toInsert.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        final tasksCol = FirebaseFirestore.instance.collection('tasks');

        for (final title in toInsert) {
          final ref = tasksCol.doc();
          final task = TaskItem(
            id: ref.id,
            projectId: projectId,
            ownerUid: resolvedOwnerUid,
            title: title,
            description: null,
            taskStatus: 'In Progress',
            isStarred: false,
            taskCode: subphaseCode,
            dueDate: null,
            assigneeName: null,
            createdAt: null,
            updatedAt: null,
          ).toMap();

          batch.set(ref, {
            ...task,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();
        insertedInternal = toInsert.length;
      }
    }

    if (cleanedExternalDefaults.isNotEmpty) {
      final projectSnap = await FirebaseFirestore.instance
          .collection('projects')
          .doc(projectId)
          .get();
      final existingExternalTitles = <String>{};
      final rawList = projectSnap.data()?['externalTasks'];
      if (rawList is List) {
        for (final entry in rawList) {
          if (entry is Map<String, dynamic>) {
            final title =
                (entry['title'] as String? ?? '').trim().toLowerCase();
            if (title.isNotEmpty) {
              existingExternalTitles.add(title);
            }
          }
        }
      }

      final externalToInsert = cleanedExternalDefaults
          .where((t) => !existingExternalTitles.contains(t.toLowerCase()))
          .toList();

      if (externalToInsert.isNotEmpty) {
        final externalRepo = ExternalTaskRepository();
        for (final title in externalToInsert) {
          final task = ExternalTask(
            id: '',
            projectId: projectId,
            title: title,
            assigneeKey: '',
            assigneeName: '',
            isDone: false,
            isStarred: false,
            starredOrder: null,
            createdAt: null,
            updatedAt: null,
          );
          await externalRepo.add(projectId, task);
        }
        insertedExternal = externalToInsert.length;
      }
    }

    if (insertedInternal == 0 && insertedExternal == 0) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('All default tasks are already present.')),
      );
      return;
    }

    final parts = <String>[];
    if (insertedInternal > 0) {
      parts.add('$insertedInternal task(s)');
    }
    if (insertedExternal > 0) {
      parts.add('$insertedExternal external task(s)');
    }
    messenger?.showSnackBar(
      SnackBar(content: Text('Inserted ${parts.join(' and ')}.')),
    );
  } catch (e) {
    messenger?.showSnackBar(
      SnackBar(content: Text('Failed to insert defaults: $e')),
    );
  } finally {
    LoadingOverlay.hide();
  }
}

Future<void> _updateSubphaseStatus(
  BuildContext context, {
  required String projectId,
  required List<SelectedSubphase> selected,
  required String code,
  required String newStatus,
  String? newName,
}) async {
  final repo = ProjectRepository();
  final updated = selected.map((s) {
    if (s.code != code) return s.toMap();
    final trimmedName = newName?.trim();
    final resolvedName =
        (trimmedName != null && trimmedName.isNotEmpty) ? trimmedName : s.name;
    return s.copyWith(status: newStatus, name: resolvedName).toMap();
  }).toList();
  await repo.update(projectId, {'selectedSubphases': updated});
}
