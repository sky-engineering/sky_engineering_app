// lib/src/pages/external_tasks_overview_page.dart
import 'package:flutter/material.dart';

import '../data/models/external_task.dart';
import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/external_task_repository.dart';
import 'project_detail_page.dart';

class ExternalTasksOverviewPage extends StatelessWidget {
  ExternalTasksOverviewPage({super.key});

  final ProjectRepository _projectRepo = ProjectRepository();
  final ExternalTaskRepository _externalRepo = ExternalTaskRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('External Tasks Overview')),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<Project>>(
          stream: _projectRepo.streamAll(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final projects = snapshot.data ?? const <Project>[];
            final sortedProjects = [...projects]
              ..removeWhere(
                (project) =>
                    (project.externalTasks ?? const <ExternalTask>[]).isEmpty,
              )
              ..sort(_compareProjects);

            final entries = <_ExternalTaskEntry>[];
            for (final project in sortedProjects) {
              final tasks = [
                ...(project.externalTasks ?? const <ExternalTask>[]),
              ]..sort(_compareTasks);
              for (final task in tasks) {
                entries.add(_ExternalTaskEntry(project: project, task: task));
              }
            }

            if (entries.isEmpty) {
              return const _EmptyState();
            }

            return ListView.separated(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _OverviewExternalTaskTile(
                  project: entry.project,
                  task: entry.task,
                  repo: _externalRepo,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ExternalTaskEntry {
  const _ExternalTaskEntry({required this.project, required this.task});

  final Project project;
  final ExternalTask task;
}

class _OverviewExternalTaskTile extends StatefulWidget {
  const _OverviewExternalTaskTile({
    required this.project,
    required this.task,
    required this.repo,
  });

  final Project project;
  final ExternalTask task;
  final ExternalTaskRepository repo;

  @override
  State<_OverviewExternalTaskTile> createState() =>
      _OverviewExternalTaskTileState();
}

class _OverviewExternalTaskTileState extends State<_OverviewExternalTaskTile> {
  static const double _completeThreshold = 0.6;
  static const double _deleteThreshold = 0.85;

  double _dragProgress = 0.0;
  DismissDirection? _currentDirection;
  bool _processing = false;
  late bool _isDone;

  @override
  void initState() {
    super.initState();
    _isDone = widget.task.isDone;
  }

  @override
  void didUpdateWidget(covariant _OverviewExternalTaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id ||
        oldWidget.task.isDone != widget.task.isDone) {
      _isDone = widget.task.isDone;
    }
  }

  bool get _completeArmed =>
      _currentDirection == DismissDirection.startToEnd &&
      _dragProgress >= _completeThreshold;

  bool get _deleteArmed =>
      _currentDirection == DismissDirection.endToStart &&
      _dragProgress >= _deleteThreshold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assignee = widget.task.assigneeName.trim();
    final projectLabel =
        (widget.project.projectNumber?.trim().isNotEmpty ?? false)
        ? '${widget.project.projectNumber} ${widget.project.name}'
        : widget.project.name;
    final titleStyle = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
      decoration: _isDone ? TextDecoration.lineThrough : null,
      color: _isDone
          ? theme.textTheme.bodyLarge?.color?.withOpacity(0.6)
          : null,
    );
    final subStyle = theme.textTheme.bodySmall?.copyWith(
      color: _isDone
          ? theme.textTheme.bodySmall?.color?.withOpacity(0.6)
          : null,
    );

    return Dismissible(
      key: ValueKey('overview-external-${widget.task.id}'),
      direction: _processing
          ? DismissDirection.none
          : DismissDirection.horizontal,
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
        if (_processing) return false;
        final progress = _dragProgress;
        _resetDrag();
        if (direction == DismissDirection.startToEnd &&
            progress >= _completeThreshold) {
          await _setDone(context, !_isDone);
        } else if (direction == DismissDirection.endToStart &&
            progress >= _deleteThreshold) {
          await _deleteTask(context);
        }
        return false;
      },
      child: SizedBox(
        width: double.infinity,
        child: Material(
          color: _isDone
              ? theme.colorScheme.surfaceVariant.withOpacity(0.6)
              : theme.colorScheme.surface,
          elevation: 2,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ProjectDetailPage(projectId: widget.project.id),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (assignee.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(assignee, style: subStyle),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(projectLabel, style: subStyle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _resetDrag() {
    if (_dragProgress != 0.0 || _currentDirection != null) {
      setState(() {
        _dragProgress = 0.0;
        _currentDirection = null;
      });
    }
  }

  Future<void> _setDone(BuildContext context, bool value) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await widget.repo.update(widget.project.id, widget.task.id, {
        'isDone': value,
      });
      if (!mounted) return;
      setState(() => _isDone = value);
      final message = value
          ? 'External task marked complete'
          : 'External task reopened';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      final action = value ? 'mark complete' : 'reopen';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to $action: $e')));
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _deleteTask(BuildContext context) async {
    if (_processing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete task?'),
          content: const Text(
            'Are you sure you want to delete this external task?',
          ),
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

    if (confirmed != true) return;

    setState(() => _processing = true);
    try {
      await widget.repo.delete(widget.project.id, widget.task.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('External task deleted')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
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
    final isArmed = isStartToEnd ? _completeArmed : _deleteArmed;
    final color = isStartToEnd
        ? theme.colorScheme.primary.withOpacity(
            isActive && isArmed ? 0.25 : 0.12,
          )
        : theme.colorScheme.error.withOpacity(
            isActive && isArmed ? 0.25 : 0.12,
          );

    final icon = isStartToEnd ? Icons.check : Icons.delete;
    final alignment = isStartToEnd
        ? Alignment.centerLeft
        : Alignment.centerRight;

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: alignment,
      child: Icon(icon, color: theme.colorScheme.onSurface.withOpacity(0.7)),
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
            Icon(Icons.groups_outlined, size: 72),
            SizedBox(height: 12),
            Text('No external tasks outstanding.'),
          ],
        ),
      ),
    );
  }
}

int _compareProjects(Project a, Project b) {
  final pa = a.projectNumber?.trim();
  final pb = b.projectNumber?.trim();
  final hasA = pa != null && pa.isNotEmpty;
  final hasB = pb != null && pb.isNotEmpty;
  if (hasA && hasB) {
    final cmp = _naturalCompare(pa!, pb!);
    if (cmp != 0) return cmp;
  } else if (hasA && !hasB) {
    return -1;
  } else if (!hasA && hasB) {
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

int _compareTasks(ExternalTask a, ExternalTask b) {
  if (a.isDone != b.isDone) {
    return (a.isDone ? 1 : 0) - (b.isDone ? 1 : 0);
  }
  final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return ad.compareTo(bd);
}
