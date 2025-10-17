// lib/src/pages/starred_tasks_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/models/project.dart';
import '../data/models/task.dart';
import '../data/models/personal_checklist_item.dart';
import '../services/personal_checklist_service.dart';
import 'personal_checklist_page.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/task_repository.dart';
import 'project_detail_page.dart';
import '../dialogs/task_edit_dialog.dart';

class StarredTasksPage extends StatefulWidget {
  const StarredTasksPage({super.key});

  @override
  State<StarredTasksPage> createState() => _StarredTasksPageState();
}

class _StarredTasksPageState extends State<StarredTasksPage> {
  final TaskRepository _repo = TaskRepository();
  final ProjectRepository _projectRepo = ProjectRepository();

  final Map<String, Project?> _projects = {};
  final Map<String, StreamSubscription<Project?>> _projectSubs = {};

  StreamSubscription<List<TaskItem>>? _sub;
  List<TaskItem> _tasks = const [];
  bool _loading = true;
  bool _normalizing = false;
  User? _user;

  final PersonalChecklistService _personalService =
      PersonalChecklistService.instance;
  List<PersonalChecklistItem> _personalItems = const [];
  bool _showPersonal = false;

  List<_StarredEntry> _entries = const [];
  final Set<String> _subtaskUpdates = <String>{};

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      _sub = _repo
          .streamStarredForUser(_user!.uid)
          .listen(
            _onTasks,
            onError: (_) {
              if (mounted) {
                setState(() => _loading = false);
              }
            },
          );
    } else {
      _loading = false;
    }
    _personalService.addListener(_onPersonalChanged);
    _personalService.ensureLoaded().then((_) {
      if (!mounted) return;
      _syncPersonal();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final sub in _projectSubs.values) {
      sub.cancel();
    }
    _personalService.removeListener(_onPersonalChanged);
    super.dispose();
  }

  void _onTasks(List<TaskItem> snapshot) {
    final sorted = _sortedTasks(snapshot);
    if (!_normalizing && _requiresResequence(sorted)) {
      _normalizing = true;
      _repo.reorderStarredTasks(sorted).whenComplete(() {
        if (mounted) {
          setState(() => _normalizing = false);
        } else {
          _normalizing = false;
        }
      });
    }
    final removedProjectIds = _syncProjectSubscriptions(sorted);
    if (!mounted) return;
    final includePersonal = _shouldShowPersonal;
    final merged = _mergeEntries(
      entries: _entries,
      tasks: sorted,
      personal: includePersonal ? _personalItems : const [],
      includePersonal: includePersonal,
    );
    setState(() {
      _tasks = sorted;
      _loading = false;
      for (final id in removedProjectIds) {
        _projects.remove(id);
      }
      _entries = merged;
    });
  }

  void _syncPersonal() {
    if (!mounted) return;
    final items = List<PersonalChecklistItem>.from(_personalService.items);
    final show = _personalService.showInStarred;
    final includePersonal = show && items.isNotEmpty;
    final merged = _mergeEntries(
      entries: _entries,
      tasks: _tasks,
      personal: includePersonal ? items : const [],
      includePersonal: includePersonal,
    );
    setState(() {
      _personalItems = items;
      _showPersonal = show;
      _entries = merged;
    });
  }

  void _onPersonalChanged() {
    _syncPersonal();
  }

  List<_StarredEntry> _mergeEntries({
    required List<_StarredEntry> entries,
    required List<TaskItem> tasks,
    required List<PersonalChecklistItem> personal,
    required bool includePersonal,
  }) {
    final taskMap = {for (final task in tasks) task.id: task};
    final personalMap = {for (final item in personal) item.id: item};
    final merged = <_StarredEntry>[];
    final seenTaskIds = <String>{};
    final seenPersonalIds = <String>{};

    for (final entry in entries) {
      if (entry.isTask) {
        final task = taskMap[entry.task!.id];
        if (task != null) {
          merged.add(_StarredEntry.task(task));
          seenTaskIds.add(task.id);
        }
      } else if (includePersonal) {
        final item = personalMap[entry.personal!.id];
        if (item != null) {
          merged.add(_StarredEntry.personal(item));
          seenPersonalIds.add(item.id);
        }
      }
    }

    for (final task in tasks) {
      if (seenTaskIds.add(task.id)) {
        merged.add(_StarredEntry.task(task));
      }
    }

    if (includePersonal) {
      for (final item in personal) {
        if (seenPersonalIds.add(item.id)) {
          merged.add(_StarredEntry.personal(item));
        }
      }
    }

    return merged;
  }

  List<TaskItem> _sortedTasks(List<TaskItem> input) {
    final copy = [...input];
    copy.sort((a, b) {
      final ao = a.starredOrder ?? 1 << 30;
      final bo = b.starredOrder ?? 1 << 30;
      final cmp = ao.compareTo(bo);
      if (cmp != 0) return cmp;
      return _taskComparator(a, b);
    });
    return copy;
  }

  bool _requiresResequence(List<TaskItem> tasks) {
    var expected = 0;
    for (final task in tasks) {
      final order = task.starredOrder;
      if (order == null || order != expected) {
        return true;
      }
      expected++;
    }
    return false;
  }

  List<String> _syncProjectSubscriptions(List<TaskItem> tasks) {
    final requiredIds = <String>{};
    for (final task in tasks) {
      final id = task.projectId;
      if (id.isNotEmpty) {
        requiredIds.add(id);
      }
    }

    for (final id in requiredIds) {
      if (_projectSubs.containsKey(id)) continue;
      _projectSubs[id] = _projectRepo.streamById(id).listen((project) {
        if (!mounted) return;
        setState(() {
          if (project != null) {
            _projects[id] = project;
          } else {
            _projects.remove(id);
          }
        });
      });
    }

    final removed = _projectSubs.keys
        .where((id) => !requiredIds.contains(id))
        .toList(growable: false);
    for (final id in removed) {
      _projectSubs.remove(id)?.cancel();
    }
    return removed;
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final updatedEntries = [..._entries];
    final moved = updatedEntries.removeAt(oldIndex);
    updatedEntries.insert(newIndex, moved);

    final normalizedEntries = <_StarredEntry>[];
    final updatedTasks = <TaskItem>[];
    final updatedPersonal = <PersonalChecklistItem>[];
    var order = 0;
    for (final entry in updatedEntries) {
      if (entry.isTask) {
        final updatedTask = entry.task!.copyWith(starredOrder: order++);
        updatedTasks.add(updatedTask);
        normalizedEntries.add(_StarredEntry.task(updatedTask));
      } else {
        final item = entry.personal!;
        updatedPersonal.add(item);
        normalizedEntries.add(_StarredEntry.personal(item));
      }
    }

    setState(() {
      _entries = normalizedEntries;
      _tasks = updatedTasks;
      if (_showPersonal) {
        _personalItems = updatedPersonal;
      }
    });

    final futures = <Future<void>>[_repo.reorderStarredTasks(updatedTasks)];
    if (_showPersonal && updatedPersonal.isNotEmpty) {
      futures.add(
        _personalService.reorderItems(
          updatedPersonal.map((item) => item.id).toList(growable: false),
        ),
      );
    }

    try {
      await Future.wait(futures);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to reorder items: $e')));
    }
  }

  Future<void> _toggleStar(TaskItem task) async {
    final newValue = !task.isStarred;
    if (!mounted) return;

    if (!newValue) {
      setState(() {
        final remaining = _tasks.where((t) => t.id != task.id).toList();
        for (var i = 0; i < remaining.length; i++) {
          remaining[i] = remaining[i].copyWith(starredOrder: i);
        }
        _tasks = remaining;
        final includePersonal = _shouldShowPersonal;
        _entries = _mergeEntries(
          entries: _entries,
          tasks: remaining,
          personal: includePersonal ? _personalItems : const [],
          includePersonal: includePersonal,
        );
      });
    }

    try {
      await _repo.setStarred(
        task,
        newValue,
        order: newValue ? _tasks.length : null,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update star: $e')));
    }
  }

  Future<bool> _toggleTaskDone(TaskItem task) async {
    final nextDone = !(task.taskStatus == 'Completed');
    final nextStatus = nextDone ? 'Completed' : 'Pending';
    final nextLabel = nextDone ? 'Done' : 'Todo';
    try {
      await _repo.update(task.id, {
        'taskStatus': nextStatus,
        'status': nextLabel,
      });
      return true;
    } catch (e) {
      if (mounted) {
        final action = nextStatus == 'Completed' ? 'mark complete' : 'reopen';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not $action: $e')));
      }
      return false;
    }
  }

  Future<bool> _deleteTask(TaskItem task) async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Delete task'),
              content: const Text('Delete this task?'),
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
    if (!ok) return false;
    try {
      await _repo.delete(task.id);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete task: $e')));
      }
      return false;
    }
  }

  Future<void> _toggleSubtask(TaskItem task, int index) async {
    if (_subtaskUpdates.contains(task.id)) return;
    final entryIndex = _entries.indexWhere(
      (entry) => entry.task?.id == task.id,
    );
    if (entryIndex == -1) return;

    final currentEntry = _entries[entryIndex];
    final currentTask = currentEntry.task!;
    if (index < 0 || index >= currentTask.subtasks.length) return;

    final updatedSubtasks = List<SubtaskItem>.from(currentTask.subtasks);
    final toggled = updatedSubtasks[index].copyWith(
      isDone: !updatedSubtasks[index].isDone,
    );
    updatedSubtasks[index] = toggled;
    final updatedTask = currentTask.copyWith(subtasks: updatedSubtasks);

    setState(() {
      _subtaskUpdates.add(task.id);
      _entries = List<_StarredEntry>.from(_entries)
        ..[entryIndex] = _StarredEntry.task(updatedTask);
      _tasks = _tasks
          .map((t) => t.id == updatedTask.id ? updatedTask : t)
          .toList();
    });

    try {
      await _repo.update(task.id, {'subtasks': updatedSubtasks});
    } catch (e) {
      if (!mounted) {
        _subtaskUpdates.remove(task.id);
        return;
      }
      setState(() {
        _entries = List<_StarredEntry>.from(_entries)
          ..[entryIndex] = _StarredEntry.task(currentTask);
        _tasks = _tasks
            .map((t) => t.id == currentTask.id ? currentTask : t)
            .toList();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update subtask: $e')));
    } finally {
      if (!mounted) {
        _subtaskUpdates.remove(task.id);
      } else {
        setState(() {
          _subtaskUpdates.remove(task.id);
        });
      }
    }
  }

  Future<void> _togglePersonalItem(PersonalChecklistItem item, bool value) {
    return _personalService.setCompletion(item.id, value);
  }

  void _openPersonalChecklist() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PersonalChecklistPage()));
  }

  bool get _shouldShowPersonal => _showPersonal && _personalItems.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view starred tasks')),
      );
    }

    final hasEntries = _entries.isNotEmpty;

    if (_loading && !hasEntries) {
      return Scaffold(
        appBar: AppBar(title: const Text('Starred Tasks')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final slivers = <Widget>[];

    if (hasEntries) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          sliver: SliverReorderableList(
            itemCount: _entries.length,
            onReorder: _handleReorder,
            itemBuilder: (context, index) {
              final entry = _entries[index];
              if (entry.isTask) {
                final task = entry.task!;
                final project = _projects[task.projectId];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(entry.key),
                  index: index,
                  child: _SwipeableStarredTile(
                    dismissibleKey: ValueKey('dismiss-${task.id}'),
                    task: task,
                    project: project,
                    onOpenProject: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProjectDetailPage(projectId: task.projectId),
                        ),
                      );
                    },
                    onToggleStar: () => _toggleStar(task),
                    onTap: () => showTaskEditDialog(
                      context,
                      task,
                      canEdit: true,
                      subphases: project?.selectedSubphases ?? const [],
                    ),
                    onCompleteSwipe: () => _toggleTaskDone(task),
                    onDeleteSwipe: () => _deleteTask(task),
                    onToggleSubtask: (index) => _toggleSubtask(task, index),
                    isSubtaskUpdating: _subtaskUpdates.contains(task.id),
                  ),
                );
              }

              final item = entry.personal!;
              return ReorderableDelayedDragStartListener(
                key: ValueKey(entry.key),
                index: index,
                child: _PersonalStarredTile(
                  item: item,
                  onToggle: (value) => _togglePersonalItem(item, value),
                  onOpenChecklist: _openPersonalChecklist,
                ),
              );
            },
          ),
        ),
      );
    } else if (!_loading) {
      slivers.add(
        SliverToBoxAdapter(
          child: const Padding(
            padding: EdgeInsets.fromLTRB(12, 24, 12, 12),
            child: _Empty(),
          ),
        ),
      );
    }

    if (slivers.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Starred Tasks')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : const _Empty(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Starred Tasks')),
      body: CustomScrollView(slivers: slivers),
    );
  }

  // ---------- fallback comparator (code asc -> due date -> title) ----------

  static int? _codeToInt(String? code) {
    if (code == null) return null;
    final s = code.trim();
    if (s.length != 4) return null;
    return int.tryParse(s);
  }

  static int? _extractTitleCode(String title) {
    final m = RegExp(r'^\s*(\d{4})').firstMatch(title);
    return (m == null) ? null : int.tryParse(m.group(1)!);
  }

  static int _taskComparator(TaskItem a, TaskItem b) {
    final ac = _codeToInt(a.taskCode) ?? _extractTitleCode(a.title);
    final bc = _codeToInt(b.taskCode) ?? _extractTitleCode(b.title);
    if (ac != null && bc != null) return ac.compareTo(bc);
    if (ac != null && bc == null) return -1;
    if (ac == null && bc != null) return 1;

    final ad = a.dueDate, bd = b.dueDate;
    if (ad != null && bd != null) {
      final cmp = ad.compareTo(bd);
      if (cmp != 0) return cmp;
    } else if (ad == null && bd != null) {
      return 1; // nulls last
    } else if (ad != null && bd == null) {
      return -1;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }
}

class _StarredEntry {
  const _StarredEntry.task(this.task) : personal = null;
  const _StarredEntry.personal(this.personal) : task = null;

  final TaskItem? task;
  final PersonalChecklistItem? personal;

  bool get isTask => task != null;
  bool get isPersonal => personal != null;
  String get key =>
      isTask ? 'starred-task-${task!.id}' : 'starred-personal-${personal!.id}';
}

class _SwipeableStarredTile extends StatefulWidget {
  final Key dismissibleKey;
  final TaskItem task;
  final Project? project;
  final VoidCallback onOpenProject;
  final Future<void> Function() onToggleStar;
  final VoidCallback onTap;
  final Future<bool> Function() onCompleteSwipe;
  final Future<bool> Function() onDeleteSwipe;
  final Future<void> Function(int index) onToggleSubtask;
  final bool isSubtaskUpdating;

  const _SwipeableStarredTile({
    required this.dismissibleKey,
    required this.task,
    required this.project,
    required this.onOpenProject,
    required this.onToggleStar,
    required this.onTap,
    required this.onCompleteSwipe,
    required this.onDeleteSwipe,
    required this.onToggleSubtask,
    required this.isSubtaskUpdating,
  });

  @override
  State<_SwipeableStarredTile> createState() => _SwipeableStarredTileState();
}

class _SwipeableStarredTileState extends State<_SwipeableStarredTile> {
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
    return Dismissible(
      key: widget.dismissibleKey,
      direction: DismissDirection.horizontal,
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
      child: _StarredTile(
        task: widget.task,
        project: widget.project,
        onOpenProject: widget.onOpenProject,
        onToggleStar: widget.onToggleStar,
        onTap: widget.onTap,
        onToggleSubtask: widget.onToggleSubtask,
        isSubtaskUpdating: widget.isSubtaskUpdating,
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

class _StarredTile extends StatefulWidget {
  final TaskItem task;
  final Project? project;
  final VoidCallback onOpenProject;
  final Future<void> Function() onToggleStar;
  final VoidCallback onTap;
  final Future<void> Function(int index) onToggleSubtask;
  final bool isSubtaskUpdating;

  const _StarredTile({
    required this.task,
    this.project,
    required this.onOpenProject,
    required this.onToggleStar,
    required this.onTap,
    required this.onToggleSubtask,
    required this.isSubtaskUpdating,
  });

  @override
  State<_StarredTile> createState() => _StarredTileState();
}

class _StarredTileState extends State<_StarredTile> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _StarredTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.subtasks.isEmpty && _expanded) {
      _expanded = false;
    }
  }

  String? _projectSummary() {
    final number = widget.project?.projectNumber?.trim() ?? '';
    final name = widget.project?.name.trim() ?? '';
    final parts = <String>[];
    if (number.isNotEmpty) parts.add(number);
    if (name.isNotEmpty) parts.add(name);
    if (parts.isNotEmpty) return parts.join(' - ');
    if (widget.task.projectId.isNotEmpty) {
      return 'Project ${widget.task.projectId}';
    }
    return null;
  }

  void _toggleExpansion() {
    if (widget.task.subtasks.isEmpty) return;
    setState(() {
      _expanded = !_expanded;
    });
  }

  Future<void> _handleSubtaskTap(int index) async {
    if (widget.isSubtaskUpdating) return;
    await widget.onToggleSubtask(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final hasDesc = (task.description ?? '').trim().isNotEmpty;
    final projectLabel = _projectSummary();
    final small = theme.textTheme.bodySmall;
    final Color? baseProjectColor = small?.color;
    final projectStyle = small?.copyWith(
      color: baseProjectColor?.withValues(alpha: 0.8),
    );
    final filledStar = theme.colorScheme.secondary;
    final hollowStar = theme.colorScheme.onSurfaceVariant;

    final hasSubtasks = task.subtasks.isNotEmpty;
    final showMultiLine = hasDesc || projectLabel != null;
    final showExpanded = hasSubtasks && _expanded;
    final crossAxis = (showMultiLine || showExpanded)
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center;

    final cardColor = task.taskStatus.trim().toLowerCase() == 'completed'
        ? theme.colorScheme.surfaceContainerHighest
        : null;

    final baseSubtaskColor = small?.color ?? theme.colorScheme.onSurfaceVariant;
    final TextStyle baseSubtaskStyle = (small ?? const TextStyle()).copyWith(
      fontSize: 11,
    );

    return Card(
      color: cardColor,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: crossAxis,
            children: [
              Padding(
                padding: EdgeInsets.only(top: showMultiLine ? 2 : 0),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  iconSize: 20,
                  splashRadius: 18,
                  onPressed: () {
                    widget.onToggleStar();
                  },
                  icon: Icon(
                    task.isStarred ? Icons.star : Icons.star_border,
                    color: task.isStarred ? filledStar : hollowStar,
                  ),
                  tooltip: task.isStarred ? 'Unstar' : 'Star',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (projectLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          projectLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: projectStyle ?? small,
                        ),
                      ),
                    if (hasDesc)
                      Padding(
                        padding: EdgeInsets.only(
                          top: projectLabel != null ? 3 : 2,
                        ),
                        child: Text(
                          task.description!.trim(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: small,
                        ),
                      ),
                    if (hasSubtasks && _expanded)
                      Padding(
                        padding: EdgeInsets.only(
                          top: (hasDesc || projectLabel != null) ? 6 : 4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(task.subtasks.length, (
                            index,
                          ) {
                            final subtask = task.subtasks[index];
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
              if (hasSubtasks)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    iconSize: 20,
                    splashRadius: 20,
                    onPressed: _toggleExpansion,
                    icon: Icon(_expanded ? Icons.remove : Icons.add),
                    tooltip: _expanded ? 'Hide subtasks' : 'Show subtasks',
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
    );
  }
}

class _PersonalStarredTile extends StatelessWidget {
  const _PersonalStarredTile({
    required this.item,
    required this.onToggle,
    required this.onOpenChecklist,
  });

  final PersonalChecklistItem item;
  final Future<void> Function(bool) onToggle;
  final VoidCallback onOpenChecklist;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const personalColor = Color(0xFFF3EAA5);
    final baseTitleStyle = TextStyle(
      fontWeight: FontWeight.w600,
      color: personalColor,
    );
    final titleStyle = item.isDone
        ? baseTitleStyle.copyWith(decoration: TextDecoration.lineThrough)
        : baseTitleStyle;
    final labelTemplate = textTheme.bodySmall ?? const TextStyle();
    final labelStyle = labelTemplate.copyWith(
      color: personalColor.withValues(alpha: 0.8),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: item.isDone,
              onChanged: (value) => onToggle(value ?? false),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  const SizedBox(height: 2),
                  Text('Personal', style: labelStyle),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Open checklist',
              onPressed: onOpenChecklist,
              icon: const Icon(Icons.open_in_new),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.star_border, size: 80),
            SizedBox(height: 12),
            Text('No starred tasks yet'),
          ],
        ),
      ),
    );
  }
}
