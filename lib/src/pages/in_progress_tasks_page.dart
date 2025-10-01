// lib/src/pages/in_progress_tasks_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/models/task.dart';
import '../data/repositories/task_repository.dart';
import 'project_detail_page.dart';

class InProgressTasksPage extends StatelessWidget {
  InProgressTasksPage({super.key});

  final _repo = TaskRepository();
  static const _statuses = <String>['In Progress', 'Pending'];

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view tasks')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('In Progress Tasks')),
      body: StreamBuilder<List<TaskItem>>(
        stream: _repo.streamByStatuses(me.uid, _statuses),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final list = (snap.data ?? const <TaskItem>[])..sort(_taskComparator);
          if (list.isEmpty) {
            return const _Empty();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final t = list[i];
              return _TaskTile(
                task: t,
                onOpenProject: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProjectDetailPage(projectId: t.projectId),
                    ),
                  );
                },
                onToggleStar: () async {
                  await _repo.update(t.id, {'isStarred': !t.isStarred});
                },
              );
            },
          );
        },
      ),
    );
  }

  static int? _codeToInt(String? code) {
    if (code == null) return null;
    final s = code.trim();
    if (s.length != 4) return null;
    return int.tryParse(s);
  }

  static int? _extractTitleCode(String title) {
    final m = RegExp(r'^\s*(\d{4})\b').firstMatch(title);
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

class _TaskTile extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onOpenProject;
  final VoidCallback onToggleStar;

  const _TaskTile({
    required this.task,
    required this.onOpenProject,
    required this.onToggleStar,
  });

  @override
  Widget build(BuildContext context) {
    final hasDesc = (task.description ?? '').trim().isNotEmpty;
    final small = Theme.of(context).textTheme.bodySmall;
    final filledStar = Theme.of(context).colorScheme.secondary;
    final hollowStar = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      child: InkWell(
        onTap: onOpenProject,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment:
                hasDesc ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: hasDesc ? 2 : 0),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  iconSize: 20,
                  splashRadius: 18,
                  onPressed: onToggleStar,
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
                    if (hasDesc)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
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
            Icon(Icons.pending_actions, size: 80),
            SizedBox(height: 12),
            Text('No in-progress or pending tasks'),
          ],
        ),
      ),
    );
  }
}
