// lib/src/pages/starred_tasks_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/task.dart';
import '../data/repositories/task_repository.dart';
import 'project_detail_page.dart';
import '../dialogs/task_edit_dialog.dart';

class StarredTasksPage extends StatelessWidget {
  StarredTasksPage({super.key});

  final _repo = TaskRepository();

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view starred tasks')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Starred Tasks')),
      body: StreamBuilder<List<TaskItem>>(
        stream: _repo.streamStarredForUser(me.uid),
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
              return _StarredTile(
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
                onTap: () => showTaskEditDialog(context, t, canEdit: true),
                onComplete: () async {
                  try {
                    await _repo.update(t.id, {
                      'taskStatus': 'Completed',
                      'status': 'Done',
                    });
                    return true;
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not mark complete: $e')),
                      );
                    }
                    return false;
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  // ---------- sorting helpers (code asc -> due date -> title) ----------
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

class _StarredTile extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onOpenProject;
  final VoidCallback onToggleStar;
  final VoidCallback onTap;
  final Future<bool> Function() onComplete;

  const _StarredTile({
    required this.task,
    required this.onOpenProject,
    required this.onToggleStar,
    required this.onTap,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final hasDesc = (task.description ?? '').trim().isNotEmpty;
    final small = Theme.of(context).textTheme.bodySmall;
    final filledStar = Theme.of(
      context,
    ).colorScheme.secondary; // accent (yellow)
    final hollowStar = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant; // subtle gray

    return Dismissible(
      key: ValueKey('starred-${task.id}'),
      direction: DismissDirection.endToStart,
      background: _dismissBackground(context),
      confirmDismiss: (_) async {
        final ok = await onComplete();
        return false;
      },
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              crossAxisAlignment: hasDesc
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                // Star toggle
                Padding(
                  padding: EdgeInsets.only(top: hasDesc ? 2 : 0),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
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
                // Texts
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
