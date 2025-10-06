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
    setState(() {
      _tasks = sorted;
      _loading = false;
      for (final id in removedProjectIds) {
        _projects.remove(id);
      }
    });
  }

  void _syncPersonal() {
    if (!mounted) return;
    setState(() {
      _personalItems = List<PersonalChecklistItem>.from(_personalService.items);
      _showPersonal = _personalService.showInStarred;
    });
  }

  void _onPersonalChanged() {
    _syncPersonal();
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
    setState(() {
      final updated = [..._tasks];
      final item = updated.removeAt(oldIndex);
      updated.insert(newIndex, item);
      final reindexed = <TaskItem>[];
      for (var i = 0; i < updated.length; i++) {
        reindexed.add(updated[i].copyWith(starredOrder: i));
      }
      _tasks = reindexed;
    });

    try {
      await _repo.reorderStarredTasks(_tasks);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to reorder tasks: $e')));
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

  Future<bool> _completeTask(TaskItem task) async {
    try {
      await _repo.update(task.id, {
        'taskStatus': 'Completed',
        'status': 'Done',
      });
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not mark complete: $e')));
      }
      return false;
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

    final includePersonal = _shouldShowPersonal;
    final hasStarredTasks = _tasks.isNotEmpty;

    if (_loading && !hasStarredTasks && !includePersonal) {
      return Scaffold(
        appBar: AppBar(title: const Text('Starred Tasks')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final slivers = <Widget>[];

    if (hasStarredTasks) {
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, includePersonal ? 12 : 24),
          sliver: SliverReorderableList(
            itemCount: _tasks.length,
            onReorder: _handleReorder,
            itemBuilder: (context, index) {
              final task = _tasks[index];
              final project = _projects[task.projectId];
              return ReorderableDelayedDragStartListener(
                key: ValueKey('starred-${task.id}'),
                index: index,
                child: Dismissible(
                  key: ValueKey('dismiss-${task.id}'),
                  direction: DismissDirection.endToStart,
                  background: _dismissBackground(context),
                  confirmDismiss: (_) async {
                    await _completeTask(task);
                    return false;
                  },
                  child: _StarredTile(
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
                    onTap: () =>
                        showTaskEditDialog(context, task, canEdit: true),
                    onComplete: () => _completeTask(task),
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

    if (includePersonal) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, hasStarredTasks ? 8 : 24, 16, 8),
            child: Text(
              'Personal Checklist',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = _personalItems[index];
              return _PersonalStarredTile(
                item: item,
                onToggle: (value) => _togglePersonalItem(item, value),
                onOpenChecklist: _openPersonalChecklist,
              );
            }, childCount: _personalItems.length),
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

class _StarredTile extends StatelessWidget {
  final TaskItem task;
  final Project? project;
  final VoidCallback onOpenProject;
  final Future<void> Function() onToggleStar;
  final VoidCallback onTap;
  final Future<bool> Function() onComplete;

  const _StarredTile({
    required this.task,
    this.project,
    required this.onOpenProject,
    required this.onToggleStar,
    required this.onTap,
    required this.onComplete,
  });

  String? _projectSummary() {
    final number = project?.projectNumber?.trim() ?? '';
    final name = project?.name.trim() ?? '';
    final parts = <String>[];
    if (number.isNotEmpty) parts.add(number);
    if (name.isNotEmpty) parts.add(name);
    if (parts.isNotEmpty) return parts.join(' - ');
    if (task.projectId.isNotEmpty) return 'Project ${task.projectId}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasDesc = (task.description ?? '').trim().isNotEmpty;
    final projectLabel = _projectSummary();
    final small = Theme.of(context).textTheme.bodySmall;
    final Color? baseProjectColor = small?.color;
    final projectStyle = small?.copyWith(
      color: baseProjectColor?.withOpacity(0.8),
    );
    final filledStar = Theme.of(context).colorScheme.secondary;
    final hollowStar = Theme.of(context).colorScheme.onSurfaceVariant;
    final hasMultiLine = hasDesc || projectLabel != null;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: hasMultiLine
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: hasMultiLine ? 2 : 0),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  iconSize: 20,
                  splashRadius: 18,
                  onPressed: () {
                    onToggleStar();
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
                  ],
                ),
              ),
              const SizedBox(width: 4),
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
    final small = textTheme.bodySmall;
    final titleStyle = item.isDone
        ? const TextStyle(
            decoration: TextDecoration.lineThrough,
            fontWeight: FontWeight.w600,
          )
        : const TextStyle(fontWeight: FontWeight.w600);

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
                  Text(
                    'Personal',
                    style: small?.copyWith(
                      color: small?.color?.withOpacity(0.8),
                    ),
                  ),
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

Widget _dismissBackground(BuildContext context) {
  final color = Theme.of(context).colorScheme.primary;
  return Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    color: color.withAlpha((0.2 * 255).round()),
    child: Icon(Icons.check_circle, color: color),
  );
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
