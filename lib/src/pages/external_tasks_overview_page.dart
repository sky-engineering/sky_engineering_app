// lib/src/pages/external_tasks_overview_page.dart
import 'package:flutter/material.dart';

import '../data/models/external_task.dart';
import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/external_task_repository.dart';
import 'project_detail_page.dart';

class ExternalTasksOverviewPage extends StatefulWidget {
  const ExternalTasksOverviewPage({super.key});

  @override
  State<ExternalTasksOverviewPage> createState() =>
      _ExternalTasksOverviewPageState();
}

class _ExternalTasksOverviewPageState extends State<ExternalTasksOverviewPage> {
  final ProjectRepository _projectRepo = ProjectRepository();
  final ExternalTaskRepository _externalRepo = ExternalTaskRepository();
  final TextEditingController _searchCtl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchCtl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search external tasks...',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() => _query = value.trim().toLowerCase());
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
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
                          (project.externalTasks ?? const <ExternalTask>[])
                              .isEmpty,
                    )
                    ..sort(_compareProjects);

                  final entries = <_ExternalTaskEntry>[];
                  for (final project in sortedProjects) {
                    final tasks = [
                      ...(project.externalTasks ?? const <ExternalTask>[]),
                    ]..sort(_compareTasks);
                    for (final task in tasks) {
                      entries.add(
                        _ExternalTaskEntry(project: project, task: task),
                      );
                    }
                  }

                  final filtered = _filterEntries(entries, _query);

                  if (filtered.isEmpty) {
                    if (entries.isEmpty) {
                      return const _EmptyState();
                    }
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _query.isEmpty
                              ? 'No external tasks found.'
                              : 'No tasks match your search.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
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
          ],
        ),
      ),
    );
  }

  List<_ExternalTaskEntry> _filterEntries(
    List<_ExternalTaskEntry> entries,
    String query,
  ) {
    if (query.isEmpty) return entries;
    final tokens = _tokenizeQuery(query);
    if (tokens.isEmpty) return entries;

    bool entryMatches(_ExternalTaskEntry entry) {
      bool matchesField(String term) {
        bool contains(String? value) {
          if (value == null) return false;
          final trimmed = value.trim();
          if (trimmed.isEmpty) return false;
          return trimmed.toLowerCase().contains(term);
        }

        final project = entry.project;
        final task = entry.task;

        if (contains(task.title)) return true;
        if (contains(project.projectNumber)) return true;
        if (contains(project.name)) return true;

        final assigneeKey = task.assigneeKey.toLowerCase();
        final memberLabel = _teamLabelForKey(assigneeKey);
        final memberName = _teamValueForKey(project, assigneeKey);

        if (contains(memberLabel)) return true;
        if (contains(memberName)) return true;
        if (contains(task.assigneeName)) return true;

        return false;
      }

      bool evaluateTokens() {
        var index = 0;
        bool result = matchesField(tokens[index].term);
        index++;

        while (index < tokens.length) {
          final op = tokens[index];
          if (index + 1 >= tokens.length) break;
          final nextTerm = tokens[index + 1];
          final nextMatches = matchesField(nextTerm.term);
          if (op.isAnd) {
            result = result && nextMatches;
          } else {
            result = result || nextMatches;
          }
          index += 2;
        }

        return result;
      }

      return evaluateTokens();
    }

    return entries.where(entryMatches).toList();
  }

  List<_QueryToken> _tokenizeQuery(String raw) {
    final lowered = raw.toLowerCase();
    final parts = lowered.split(RegExp(r'\s+'));
    final tokens = <_QueryToken>[];
    _QueryToken? last;

    for (final part in parts) {
      if (part.isEmpty) continue;
      if (part == 'and') {
        if (last != null && last.isTerm) {
          tokens.add(_QueryToken.and());
          last = _QueryToken.and();
        }
      } else if (part == 'or') {
        if (last != null && last.isTerm) {
          tokens.add(_QueryToken.or());
          last = _QueryToken.or();
        }
      } else {
        final token = _QueryToken.term(part);
        tokens.add(token);
        last = token;
      }
    }

    if (tokens.isNotEmpty && !tokens.last.isTerm) {
      tokens.removeLast();
    }

    while (tokens.isNotEmpty && !tokens.first.isTerm) {
      tokens.removeAt(0);
    }

    return tokens;
  }

  String? _teamLabelForKey(String key) {
    switch (key) {
      case 'owner':
      case 'teamowner':
        return 'Owner';
      case 'teamarchitect':
        return 'Architect';
      case 'teamsurveyor':
        return 'Surveyor';
      case 'teamgeotechnical':
        return 'Geotechnical';
      case 'teammechanical':
        return 'Mechanical';
      case 'teamelectrical':
        return 'Electrical';
      case 'teamplumbing':
        return 'Plumbing';
      case 'teamlandscape':
        return 'Landscape';
      case 'teamcontractor':
        return 'Contractor';
      case 'teamenvironmental':
        return 'Environmental';
      case 'teamother':
        return 'Other';
      default:
        return null;
    }
  }

  String? _teamValueForKey(Project project, String key) {
    switch (key) {
      case 'owner':
      case 'teamowner':
        return project.teamOwner;
      case 'teamarchitect':
        return project.teamArchitect;
      case 'teamsurveyor':
        return project.teamSurveyor;
      case 'teamgeotechnical':
        return project.teamGeotechnical;
      case 'teammechanical':
        return project.teamMechanical;
      case 'teamelectrical':
        return project.teamElectrical;
      case 'teamplumbing':
        return project.teamPlumbing;
      case 'teamlandscape':
        return project.teamLandscape;
      case 'teamcontractor':
        return project.teamContractor;
      case 'teamenvironmental':
        return project.teamEnvironmental;
      case 'teamother':
        return project.teamOther;
      default:
        return null;
    }
  }
}

class _ExternalTaskEntry {
  const _ExternalTaskEntry({required this.project, required this.task});

  final Project project;
  final ExternalTask task;
}

class _QueryToken {
  const _QueryToken._(this.term, this.operator);

  final String term;
  final _QueryOperator operator;

  bool get isTerm => operator == _QueryOperator.term;
  bool get isAnd => operator == _QueryOperator.and;
  bool get isOr => operator == _QueryOperator.or;

  factory _QueryToken.term(String value) =>
      _QueryToken._(value, _QueryOperator.term);
  factory _QueryToken.and() => _QueryToken._('', _QueryOperator.and);
  factory _QueryToken.or() => _QueryToken._('', _QueryOperator.or);
}

enum _QueryOperator { term, and, or }

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
          ? theme.textTheme.bodyLarge?.color?.withValues(alpha: 0.6)
          : null,
    );
    final subStyle = theme.textTheme.bodySmall?.copyWith(
      color: _isDone
          ? theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6)
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
              ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
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
      if (!context.mounted) return;
      setState(() => _isDone = value);
      final message = value
          ? 'External task marked complete'
          : 'External task reopened';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!context.mounted) return;
      final action = value ? 'mark complete' : 'reopen';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to $action: $e')));
    } finally {
      if (context.mounted) {
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
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('External task deleted')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    } finally {
      if (context.mounted) {
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
        ? theme.colorScheme.primary.withValues(
            alpha: isActive && isArmed ? 0.25 : 0.12,
          )
        : theme.colorScheme.error.withValues(
            alpha: isActive && isArmed ? 0.25 : 0.12,
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
      child: Icon(
        icon,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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

int _compareTasks(ExternalTask a, ExternalTask b) {
  if (a.isDone != b.isDone) {
    return (a.isDone ? 1 : 0) - (b.isDone ? 1 : 0);
  }
  final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return ad.compareTo(bd);
}
