// lib/src/pages/task_overview_page.dart
import 'package:flutter/material.dart';
import '../data/models/external_task.dart';
import '../data/models/project.dart';
import '../data/models/task.dart';
import '../data/repositories/external_task_repository.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/task_repository.dart';
import 'project_detail_page.dart';

const _kWatchedStatuses = ['In Progress', 'Pending'];

class TaskOverviewPage extends StatefulWidget {
  const TaskOverviewPage({super.key});
  @override
  State<TaskOverviewPage> createState() => _TaskOverviewPageState();
}

class _TaskOverviewPageState extends State<TaskOverviewPage> {
  final ProjectRepository _projectRepo = ProjectRepository();
  final TaskRepository _taskRepo = TaskRepository();
  final ExternalTaskRepository _externalRepo = ExternalTaskRepository();
  static const List<MapEntry<String, String>> _statusOptions =
      <MapEntry<String, String>>[
    MapEntry('In Progress', 'IP'),
    MapEntry('Under Construction', 'UC'),
    MapEntry('On Hold', 'OH'),
    MapEntry('Close When Paid', 'CWP'),
    MapEntry('Archive', 'Arch'),
  ];
  static const Set<String> _defaultStatusFilters = <String>{
    'In Progress',
    'Under Construction',
    'On Hold',
    'Close When Paid',
  };
  Set<String> _statusFilters = {..._defaultStatusFilters};
  @override
  Widget build(BuildContext context) {
    final filterLabelStyle = Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontSize: 9.5, height: 1.0) ??
        const TextStyle(fontSize: 9.5, height: 1.0);
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Project>>(
          stream: _projectRepo.streamAll(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final projects = snapshot.data ?? const <Project>[];
            if (projects.isEmpty) {
              return const _EmptyState();
            }
            final visibleProjects =
                projects.where(_includeProject).toList(growable: false);
            visibleProjects.sort(_compareProjects);
            final children = <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
                child: SegmentedButton<String>(
                  segments: _statusOptions
                      .map(
                        (entry) => ButtonSegment<String>(
                          value: entry.key,
                          label: SizedBox(
                            width: 132,
                            child: Text(
                              entry.key,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.visible,
                              softWrap: true,
                              style: filterLabelStyle,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  selected: _statusFilters,
                  multiSelectionEnabled: true,
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    ),
                    minimumSize: WidgetStatePropertyAll(Size(0, 32)),
                  ),
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _statusFilters = Set<String>.from(newSelection);
                    });
                  },
                ),
              ),
              const SizedBox(height: 8),
            ];
            if (visibleProjects.isEmpty) {
              children.add(
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.inbox_outlined, size: 48),
                      SizedBox(height: 8),
                      Text('No projects match the selected statuses.'),
                    ],
                  ),
                ),
              );
            } else {
              for (var i = 0; i < visibleProjects.length; i++) {
                children.add(
                  _ProjectTaskCard(
                    project: visibleProjects[i],
                    taskRepo: _taskRepo,
                    externalRepo: _externalRepo,
                  ),
                );
                if (i != visibleProjects.length - 1) {
                  children.add(const SizedBox(height: 12));
                }
              }
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: children,
            );
          },
        ),
      ),
    );
  }

  bool _includeProject(Project project) {
    if (_statusFilters.isEmpty) {
      return false;
    }
    final status = project.status.trim();
    if (_statusFilters.contains(status)) {
      return true;
    }
    if (_statusFilters.contains('Archive') &&
        (project.isArchived || status == 'Archive')) {
      return true;
    }
    return false;
  }
}

class _ProjectTaskCard extends StatelessWidget {
  const _ProjectTaskCard({
    required this.project,
    required this.taskRepo,
    required this.externalRepo,
  });
  final Project project;
  final TaskRepository taskRepo;
  final ExternalTaskRepository externalRepo;
  @override
  Widget build(BuildContext context) {
    final projectNumber = project.projectNumber?.trim();
    final title = (projectNumber?.isNotEmpty ?? false)
        ? '$projectNumber ${project.name}'
        : project.name;
    final titleColor = _statusTextColor(context, project);
    final externalSection = _buildExternalTasksSection(context, titleColor);
    Future<void> toggleStar(TaskItem task) async {
      try {
        await taskRepo.setStarred(task, !task.isStarred);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update task: $e')));
      }
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProjectDetailPage(projectId: project.id),
                  ),
                );
              },
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<TaskItem>>(
              stream: taskRepo.streamByProject(project.id),
              builder: (context, snapshot) {
                final tasks = (snapshot.data ?? const <TaskItem>[])
                    .where((t) => _kWatchedStatuses.contains(t.taskStatus))
                    .toList();
                if (tasks.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: tasks.take(6).map((task) {
                    return InkWell(
                      onTap: () => toggleStar(task),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Icon(
                                task.isStarred ? Icons.star : Icons.star_border,
                                size: 12,
                                color: task.isStarred
                                    ? const Color(0xFFF1C400)
                                    : titleColor.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                task.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: titleColor.withValues(alpha: 0.85),
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            if (externalSection != null) externalSection,
          ],
        ),
      ),
    );
  }

  Widget? _buildExternalTasksSection(
    BuildContext context,
    Color titleColor,
  ) {
    final tasks = (project.externalTasks ?? const <ExternalTask>[])
        .where((task) => !task.isDone)
        .toList();
    if (tasks.isEmpty) return null;
    tasks.sort((a, b) {
      if (a.isStarred != b.isStarred) {
        return a.isStarred ? -1 : 1;
      }
      final ao = a.starredOrder ?? 1 << 20;
      final bo = b.starredOrder ?? 1 << 20;
      final cmpOrder = ao.compareTo(bo);
      if (cmpOrder != 0) return cmpOrder;
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ad.compareTo(bd);
    });
    final theme = Theme.of(context);
    final mutedColor = titleColor.withValues(alpha: 0.7);
    final visible = tasks.take(3).toList();
    final remaining = tasks.length - visible.length;
    Widget buildRow(ExternalTask task) {
      final assignee = task.assigneeName.trim();
      final parts = <String>['External', task.title.trim()];
      if (assignee.isNotEmpty) {
        parts.add(assignee);
      }
      final line = parts.join(' - ');
      return InkWell(
        onTap: () => _toggleExternalStar(context, task),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  task.isStarred ? Icons.star : Icons.star_border,
                  size: 12,
                  color: task.isStarred
                      ? const Color(0xFFF1C400)
                      : titleColor.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  line,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: titleColor.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        ...visible.map(buildRow),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+$remaining more external tasks',
              style: theme.textTheme.bodySmall?.copyWith(
                color: titleColor.withValues(alpha: 0.8),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _toggleExternalStar(
      BuildContext context, ExternalTask task) async {
    final messenger = ScaffoldMessenger.of(context);
    final nextValue = !task.isStarred;
    try {
      await externalRepo.setStarred(
        project.id,
        task.id,
        nextValue,
        starredOrder: nextValue ? _nextExternalStarOrder(task) : null,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update external task: $e')),
      );
    }
  }

  int _nextExternalStarOrder(ExternalTask toggled) {
    final tasks = project.externalTasks ?? const <ExternalTask>[];
    var maxOrder = -1;
    var starredCount = 0;
    for (final task in tasks) {
      if (task.id == toggled.id) continue;
      if (task.isStarred) {
        starredCount++;
        if (task.starredOrder != null && task.starredOrder! > maxOrder) {
          maxOrder = task.starredOrder!;
        }
      }
    }
    if (maxOrder >= 0) {
      return maxOrder + 1;
    }
    return starredCount;
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
            Icon(Icons.assignment_outlined, size: 72),
            SizedBox(height: 12),
            Text('No projects yet.'),
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

Color _statusTextColor(BuildContext context, Project project) {
  switch (project.status) {
    case 'On Hold':
      return const Color(0xFF546E7A);
    case 'Under Construction':
      return const Color(0xFF2E7D32);
    case 'Close When Paid':
      return const Color(0xFFE65100);
    case 'Archive':
      return const Color(0xFFC62828);
    case 'In Progress':
    default:
      return Theme.of(context).colorScheme.onSurface;
  }
}
