// lib/src/pages/task_overview_page.dart
import 'package:flutter/material.dart';

import '../data/models/project.dart';
import '../data/models/task.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/task_repository.dart';
import 'project_detail_page.dart';

const _kWatchedStatuses = ['In Progress', 'Pending'];

class TaskOverviewPage extends StatelessWidget {
  TaskOverviewPage({super.key});

  final ProjectRepository _projectRepo = ProjectRepository();
  final TaskRepository _taskRepo = TaskRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Task Overview')),
      body: SafeArea(
        top: false,
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
            final sorted = [...projects]..sort(_compareProjects);
            return ListView.separated(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final project = sorted[index];
                return _ProjectTaskCard(project: project, taskRepo: _taskRepo);
              },
            );
          },
        ),
      ),
    );
  }
}

class _ProjectTaskCard extends StatelessWidget {
  const _ProjectTaskCard({required this.project, required this.taskRepo});

  final Project project;
  final TaskRepository taskRepo;

  @override
  Widget build(BuildContext context) {
    final projectNumber = project.projectNumber?.trim();
    final title = (projectNumber?.isNotEmpty ?? false)
        ? '$projectNumber ${project.name}'
        : project.name;
    final titleColor = _statusTextColor(context, project);

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
                                task.isStarred ? Icons.star : Icons.circle,
                                size: task.isStarred ? 12 : 6,
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
                                style: Theme.of(context).textTheme.bodySmall
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
          ],
        ),
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
