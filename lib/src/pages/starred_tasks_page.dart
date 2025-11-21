// lib/src/pages/starred_tasks_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/models/project.dart';
import '../data/models/task.dart';
import '../data/models/personal_checklist_item.dart';
import '../data/models/external_task.dart';
import '../services/personal_checklist_service.dart';
import 'personal_checklist_page.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/task_repository.dart';
import '../data/repositories/external_task_repository.dart';
import 'project_detail_page.dart';
import '../dialogs/task_edit_dialog.dart';
import '../dialogs/personal_task_edit_dialog.dart';

class StarredTasksPage extends StatefulWidget {
  const StarredTasksPage({super.key});

  @override
  State<StarredTasksPage> createState() => _StarredTasksPageState();
}

class _StarredTasksPageState extends State<StarredTasksPage> {
  final TaskRepository _repo = TaskRepository();
  final ProjectRepository _projectRepo = ProjectRepository();
  final ExternalTaskRepository _externalRepo = ExternalTaskRepository();

  final Map<String, Project?> _projects = {};
  final Map<String, StreamSubscription<Project?>> _projectSubs = {};

  StreamSubscription<List<TaskItem>>? _sub;
  StreamSubscription<List<Project>>? _externalProjectsSub;
  List<TaskItem> _tasks = const [];
  List<_ExternalStarredTask> _externalTasks = const [];
  bool _loading = true;
  bool _normalizing = false;
  User? _user;

  final PersonalChecklistService _personalService =
      PersonalChecklistService.instance;
  List<PersonalChecklistItem> _personalItems = const [];

  List<_StarredEntry> _entries = const [];
  final Set<String> _subtaskUpdates = <String>{};

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      _sub = _repo.streamStarred().listen(
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
    _externalProjectsSub = _projectRepo.streamAll().listen(
          _onExternalProjects,
          onError: (_) {},
        );
    _personalService.addListener(_onPersonalChanged);
    _personalService.ensureLoaded().then((_) {
      if (!mounted) return;
      _syncPersonal();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _externalProjectsSub?.cancel();
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
    final includePersonal = _personalItems.isNotEmpty;
    final merged = _mergeEntries(
      entries: _entries,
      tasks: sorted,
      personal: includePersonal ? _personalItems : const [],
      external: _externalTasks,
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
    final starred = _personalService.items
        .where((item) => item.isStarred)
        .toList(growable: false);
    final includePersonal = starred.isNotEmpty;
    final merged = _mergeEntries(
      entries: _entries,
      tasks: _tasks,
      personal: includePersonal ? starred : const [],
      external: _externalTasks,
      includePersonal: includePersonal,
    );
    setState(() {
      _personalItems = starred;
      _entries = merged;
    });
  }

  void _onPersonalChanged() {
    _syncPersonal();
  }

  void _onExternalProjects(List<Project> projects) {
    final starred = <_ExternalStarredTask>[];
    for (final project in projects) {
      final tasks = project.externalTasks ?? const <ExternalTask>[];
      for (final task in tasks) {
        if (task.isStarred) {
          starred.add(_ExternalStarredTask(project: project, task: task));
        }
      }
    }
    final sorted = _sortedExternalTasks(starred);
    if (!mounted) return;
    final includePersonal = _personalItems.isNotEmpty;
    final merged = _mergeEntries(
      entries: _entries,
      tasks: _tasks,
      personal: includePersonal ? _personalItems : const [],
      external: sorted,
      includePersonal: includePersonal,
    );
    setState(() {
      _externalTasks = sorted;
      _entries = merged;
    });
  }

  List<_StarredEntry> _mergeEntries({
    required List<_StarredEntry> entries,
    required List<TaskItem> tasks,
    required List<PersonalChecklistItem> personal,
    required List<_ExternalStarredTask> external,
    required bool includePersonal,
  }) {
    final taskMap = {for (final task in tasks) task.id: task};
    final personalMap = {for (final item in personal) item.id: item};
    final externalMap = {
      for (final entry in external) entry.task.id: entry,
    };
    final merged = <_StarredEntry>[];
    final seenTaskIds = <String>{};
    final seenPersonalIds = <String>{};
    final seenExternalIds = <String>{};

    for (final entry in entries) {
      if (entry.isTask) {
        final task = taskMap[entry.task!.id];
        if (task != null) {
          merged.add(_StarredEntry.task(task));
          seenTaskIds.add(task.id);
        }
      } else if (entry.isExternal) {
        final ext = externalMap[entry.external!.id];
        if (ext != null) {
          merged.add(_StarredEntry.external(ext.task, ext.project));
          seenExternalIds.add(ext.task.id);
        }
      } else if (entry.isPersonal && includePersonal) {
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

    for (final ext in external) {
      if (seenExternalIds.add(ext.task.id)) {
        merged.add(_StarredEntry.external(ext.task, ext.project));
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

  List<_ExternalStarredTask> _sortedExternalTasks(
    List<_ExternalStarredTask> input,
  ) {
    final copy = [...input];
    copy.sort((a, b) {
      final ao = a.task.starredOrder ?? 1 << 30;
      final bo = b.task.starredOrder ?? 1 << 30;
      final cmp = ao.compareTo(bo);
      if (cmp != 0) return cmp;
      return _externalTaskComparator(a.task, b.task);
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
    final updatedExternal = <_ExternalStarredTask>[];
    final updatedPersonal = <PersonalChecklistItem>[];
    var order = 0;
    for (final entry in updatedEntries) {
      if (entry.isTask) {
        final updatedTask = entry.task!.copyWith(starredOrder: order++);
        updatedTasks.add(updatedTask);
        normalizedEntries.add(_StarredEntry.task(updatedTask));
      } else if (entry.isExternal) {
        final project = entry.externalProject!;
        final updatedTask = entry.external!.copyWith(starredOrder: order++);
        final externalEntry =
            _ExternalStarredTask(project: project, task: updatedTask);
        updatedExternal.add(externalEntry);
        normalizedEntries.add(_StarredEntry.external(updatedTask, project));
      } else {
        final item = entry.personal!;
        updatedPersonal.add(item);
        normalizedEntries.add(_StarredEntry.personal(item));
      }
    }

    setState(() {
      _entries = normalizedEntries;
      _tasks = updatedTasks;
      _externalTasks = updatedExternal;
      _personalItems = updatedPersonal;
    });

    final futures = <Future<void>>[_repo.reorderStarredTasks(updatedTasks)];
    if (updatedExternal.isNotEmpty) {
      final byProject = <String, Map<String, int?>>{};
      for (final entry in updatedExternal) {
        final projectId = entry.project.id;
        byProject.putIfAbsent(projectId, () => <String, int?>{});
        byProject[projectId]![entry.task.id] = entry.task.starredOrder;
      }
      for (final entry in byProject.entries) {
        futures.add(
          _externalRepo.reorderStarredTasks(entry.key, entry.value),
        );
      }
    }
    if (updatedPersonal.isNotEmpty) {
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
        final includePersonal = _personalItems.isNotEmpty;
        _entries = _mergeEntries(
          entries: _entries,
          tasks: remaining,
          personal: includePersonal ? _personalItems : const [],
          external: _externalTasks,
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
    final ok = await showDialog<bool>(
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

  Future<void> _toggleExternalStar(_ExternalStarredTask entry) async {
    final newValue = !entry.task.isStarred;
    if (!mounted) return;

    if (!newValue) {
      setState(() {
        final remaining = _externalTasks
            .where((item) => item.task.id != entry.task.id)
            .toList(growable: false);
        final normalized = <_ExternalStarredTask>[];
        for (final item in remaining) {
          final updatedTask =
              item.task.copyWith(starredOrder: normalized.length);
          normalized.add(
            _ExternalStarredTask(project: item.project, task: updatedTask),
          );
        }
        _externalTasks = normalized;
        final includePersonal = _personalItems.isNotEmpty;
        _entries = _mergeEntries(
          entries: _entries,
          tasks: _tasks,
          personal: includePersonal ? _personalItems : const [],
          external: normalized,
          includePersonal: includePersonal,
        );
      });
    }

    try {
      await _externalRepo.setStarred(
        entry.project.id,
        entry.task.id,
        newValue,
        starredOrder: newValue ? _externalTasks.length : null,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update star: $e')));
    }
  }

  Future<bool> _toggleExternalTaskDone(_ExternalStarredTask entry) async {
    final nextValue = !entry.task.isDone;
    try {
      await _externalRepo.update(entry.project.id, entry.task.id, {
        'isDone': nextValue,
      });
      return true;
    } catch (e) {
      if (mounted) {
        final action = nextValue ? 'mark complete' : 'reopen';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(content: Text('Could not $action external task: $e')),
        );
      }
      return false;
    }
  }

  Future<bool> _deleteExternalTask(_ExternalStarredTask entry) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Delete external task'),
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
    if (!ok) return false;
    try {
      await _externalRepo.delete(entry.project.id, entry.task.id);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(content: Text('Failed to delete external task: $e')),
        );
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
      _tasks =
          _tasks.map((t) => t.id == updatedTask.id ? updatedTask : t).toList();
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

  Future<void> _togglePersonalStar(PersonalChecklistItem item) async {
    try {
      await _personalService.setStarred(item.id, !item.isStarred);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update star: $e')));
    }
  }

  Future<void> _editPersonalItem(PersonalChecklistItem item) async {
    final result = await showPersonalTaskEditDialog(
      context,
      initialTitle: item.title,
      initialIsDone: item.isDone,
    );

    if (result == null) return;

    try {
      await _personalService.updateItem(
        id: item.id,
        title: result.title,
        isDone: result.isDone,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to update task: $e')));
    }
  }

  Future<bool> _completePersonalItem(PersonalChecklistItem item) async {
    final nextValue = !item.isDone;
    try {
      await _personalService.setCompletion(item.id, nextValue);
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update task: $e')));
      return false;
    }
  }

  Future<bool> _deletePersonalItem(PersonalChecklistItem item) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete personal task'),
          content: Text('Delete "${item.title}"?'),
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

    if (ok != true) {
      return false;
    }

    try {
      await _personalService.removeItem(item.id);
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not delete task: $e')));
      return false;
    }
  }

  void _openPersonalChecklist() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(
      builder: (_) => const PersonalChecklistPage(showAppBar: true),
    ));
  }

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
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final slivers = <Widget>[];

    if (hasEntries) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
          sliver: SliverReorderableList(
            itemCount: _entries.length,
            onReorder: _handleReorder,
            itemBuilder: (context, index) {
              final entry = _entries[index];
              final padding = EdgeInsets.fromLTRB(
                12,
                0,
                12,
                index == _entries.length - 1 ? 0 : 12,
              );
              if (entry.isTask) {
                final task = entry.task!;
                final project = _projects[task.projectId];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(entry.key),
                  index: index,
                  child: Padding(
                    padding: padding,
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
                  ),
                );
              }
              if (entry.isExternal) {
                final task = entry.external!;
                final project = entry.externalProject!;
                final externalEntry =
                    _ExternalStarredTask(project: project, task: task);
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(entry.key),
                  index: index,
                  child: Padding(
                    padding: padding,
                    child: _SwipeableExternalStarredTile(
                      dismissibleKey: ValueKey('dismiss-ext-${task.id}'),
                      task: task,
                      project: project,
                      onOpenProject: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ProjectDetailPage(projectId: project.id),
                          ),
                        );
                      },
                      onToggleStar: () => _toggleExternalStar(externalEntry),
                      onCompleteSwipe: () =>
                          _toggleExternalTaskDone(externalEntry),
                      onDeleteSwipe: () => _deleteExternalTask(externalEntry),
                    ),
                  ),
                );
              }
              final item = entry.personal!;
              return ReorderableDelayedDragStartListener(
                key: ValueKey(entry.key),
                index: index,
                child: Padding(
                  padding: padding,
                  child: _SwipeablePersonalStarredTile(
                    dismissibleKey: ValueKey('personal-${item.id}'),
                    item: item,
                    onToggleStar: () => _togglePersonalStar(item),
                    onTap: () => _editPersonalItem(item),
                    onCompleteSwipe: () => _completePersonalItem(item),
                    onDeleteSwipe: () => _deletePersonalItem(item),
                    onOpenChecklist: _openPersonalChecklist,
                  ),
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
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : const _Empty(),
      );
    }

    return Scaffold(
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

  int _externalTaskComparator(ExternalTask a, ExternalTask b) {
    final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final cmp = ad.compareTo(bd);
    if (cmp != 0) return cmp;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }
}

class _StarredEntry {
  const _StarredEntry.task(this.task)
      : personal = null,
        external = null,
        externalProject = null;
  const _StarredEntry.personal(this.personal)
      : task = null,
        external = null,
        externalProject = null;
  const _StarredEntry.external(this.external, this.externalProject)
      : task = null,
        personal = null;

  final TaskItem? task;
  final PersonalChecklistItem? personal;
  final ExternalTask? external;
  final Project? externalProject;

  bool get isTask => task != null;
  bool get isPersonal => personal != null;
  bool get isExternal => external != null;

  String get key {
    if (isTask) return 'starred-task-${task!.id}';
    if (isExternal) return 'starred-external-${external!.id}';
    return 'starred-personal-${personal!.id}';
  }
}

class _ExternalStarredTask {
  const _ExternalStarredTask({required this.project, required this.task});

  final Project project;
  final ExternalTask task;
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
      margin: EdgeInsets.zero,
      color: cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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

class _SwipeableExternalStarredTile extends StatefulWidget {
  const _SwipeableExternalStarredTile({
    required this.dismissibleKey,
    required this.task,
    required this.project,
    required this.onOpenProject,
    required this.onToggleStar,
    required this.onCompleteSwipe,
    required this.onDeleteSwipe,
  });

  final Key dismissibleKey;
  final ExternalTask task;
  final Project project;
  final VoidCallback onOpenProject;
  final Future<void> Function() onToggleStar;
  final Future<bool> Function() onCompleteSwipe;
  final Future<bool> Function() onDeleteSwipe;

  @override
  State<_SwipeableExternalStarredTile> createState() =>
      _SwipeableExternalStarredTileState();
}

class _SwipeableExternalStarredTileState
    extends State<_SwipeableExternalStarredTile> {
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
      child: _ExternalStarredTile(
        task: widget.task,
        project: widget.project,
        onOpenProject: widget.onOpenProject,
        onToggleStar: widget.onToggleStar,
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

class _ExternalStarredTile extends StatelessWidget {
  const _ExternalStarredTile({
    required this.task,
    required this.project,
    required this.onOpenProject,
    required this.onToggleStar,
  });

  final ExternalTask task;
  final Project project;
  final VoidCallback onOpenProject;
  final Future<void> Function() onToggleStar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const externalColor = Color(0xFFF7B6B6);
    final titleColor =
        task.isDone ? externalColor.withValues(alpha: 0.7) : externalColor;
    final labelColor = externalColor.withValues(alpha: 0.8);
    final small = theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    final secondaryStyle = small.copyWith(
      color: labelColor,
      fontWeight: FontWeight.w600,
    );
    final tertiaryStyle = small.copyWith(color: labelColor);
    final assignee = task.assigneeName.trim();
    final projectLabel = _projectLabel();
    final cardColor =
        task.isDone ? theme.colorScheme.surfaceContainerHighest : null;
    final filledStar = theme.colorScheme.secondary;
    final hollowStar = theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: EdgeInsets.zero,
      color: cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpenProject,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                iconSize: 20,
                splashRadius: 18,
                onPressed: () => onToggleStar(),
                icon: Icon(
                  task.isStarred ? Icons.star : Icons.star_border,
                  color: task.isStarred ? filledStar : hollowStar,
                ),
                tooltip: task.isStarred ? 'Unstar' : 'Star',
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        projectLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: secondaryStyle,
                      ),
                    ),
                    if (assignee.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          assignee,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tertiaryStyle,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open project',
                onPressed: onOpenProject,
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _projectLabel() {
    final number = project.projectNumber?.trim() ?? '';
    final name = project.name.trim();
    if (number.isNotEmpty && name.isNotEmpty) {
      return '$number - $name';
    }
    if (number.isNotEmpty) return number;
    if (name.isNotEmpty) return name;
    return 'Project ${project.id}';
  }
}

class _SwipeablePersonalStarredTile extends StatefulWidget {
  const _SwipeablePersonalStarredTile({
    required this.dismissibleKey,
    required this.item,
    required this.onToggleStar,
    required this.onTap,
    required this.onCompleteSwipe,
    required this.onDeleteSwipe,
    required this.onOpenChecklist,
  });

  final Key dismissibleKey;
  final PersonalChecklistItem item;
  final Future<void> Function() onToggleStar;
  final Future<void> Function() onTap;
  final Future<bool> Function() onCompleteSwipe;
  final Future<bool> Function() onDeleteSwipe;
  final VoidCallback onOpenChecklist;

  @override
  State<_SwipeablePersonalStarredTile> createState() =>
      _SwipeablePersonalStarredTileState();
}

class _SwipeablePersonalStarredTileState
    extends State<_SwipeablePersonalStarredTile> {
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
      child: _PersonalStarredTile(
        item: widget.item,
        onToggleStar: widget.onToggleStar,
        onTap: widget.onTap,
        onOpenChecklist: widget.onOpenChecklist,
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

class _PersonalStarredTile extends StatelessWidget {
  const _PersonalStarredTile({
    required this.item,
    required this.onToggleStar,
    required this.onTap,
    required this.onOpenChecklist,
  });

  final PersonalChecklistItem item;
  final Future<void> Function() onToggleStar;
  final Future<void> Function() onTap;
  final VoidCallback onOpenChecklist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const personalColor = Color(0xFFF3EAA5);
    final filledStar = theme.colorScheme.secondary;
    final hollowStar = theme.colorScheme.onSurfaceVariant;
    final cardColor =
        item.isDone ? theme.colorScheme.surfaceContainerHighest : null;
    final titleColor =
        item.isDone ? personalColor.withValues(alpha: 0.75) : personalColor;
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w600,
      color: titleColor,
    );
    final labelStyle = TextStyle(
      color: personalColor.withValues(alpha: 0.8),
      fontWeight: FontWeight.w600,
    );

    return Card(
      margin: EdgeInsets.zero,
      color: cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onTap(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  iconSize: 20,
                  splashRadius: 18,
                  onPressed: () => onToggleStar(),
                  icon: Icon(
                    item.isStarred ? Icons.star : Icons.star_border,
                    color: item.isStarred ? filledStar : hollowStar,
                  ),
                  tooltip: item.isStarred ? 'Unstar' : 'Star',
                ),
              ),
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
