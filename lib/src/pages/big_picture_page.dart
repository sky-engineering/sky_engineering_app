import 'package:flutter/material.dart';

import '../data/models/project.dart';
import '../data/models/task.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/task_repository.dart';
import 'project_detail_page.dart';

enum _BigPictureLane {
  revenue,
  finishingTouches,
  strongProposals,
  inactive,
}

extension _BigPictureLaneMeta on _BigPictureLane {
  String get title {
    switch (this) {
      case _BigPictureLane.revenue:
        return 'Heavy Projects';
      case _BigPictureLane.finishingTouches:
        return 'Light Projects';
      case _BigPictureLane.strongProposals:
        return 'Proposals';
      case _BigPictureLane.inactive:
        return 'On Hold or Pause';
    }
  }
}

class BigPicturePage extends StatefulWidget {
  const BigPicturePage({super.key});

  @override
  State<BigPicturePage> createState() => _BigPicturePageState();
}

class _BigPicturePageState extends State<BigPicturePage> {
  static const _kStrongProposalsProjectName = '001 Proposals';
  static const _kStrongProposalsProjectNumber = '001';

  final ProjectRepository _projectRepository = ProjectRepository();
  final TaskRepository _taskRepository = TaskRepository();
  final Map<String, _BigPictureLane> _pendingLaneByProjectId = {};

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).colorScheme.primary;
    final colors = _buildSections(baseColor);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Big Picture'),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Project>>(
          stream: _projectRepository.streamAll(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Could not load projects',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              );
            }

            final projects = snapshot.data ?? const <Project>[];
            final visibleProjects = projects
                .where((project) =>
                    !(project.isArchived || project.status == 'Archive'))
                .toList();
            final strongProposalsProject =
                _findProposalsProject(visibleProjects);
            final partitions = _partitionProjects(visibleProjects);
            final sections = _laneSections(colors);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    if (sections[i].lane == _BigPictureLane.strongProposals)
                      _StrongProposalsLane(
                        title: sections[i].title,
                        color: sections[i].color,
                        project: strongProposalsProject,
                        expectedProjectName: _kStrongProposalsProjectName,
                        taskRepository: _taskRepository,
                        onProposalTap: strongProposalsProject == null
                            ? null
                            : () => _openProjectDetail(strongProposalsProject),
                      )
                    else
                      _LaneColumn(
                        title: sections[i].title,
                        color: sections[i].color,
                        projects:
                            partitions[sections[i].lane] ?? const <Project>[],
                        onProjectDropped: (project) =>
                            _handleDrop(project, sections[i].lane),
                        onProjectTap: _openProjectDetail,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openProjectDetail(Project project) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectDetailPage(projectId: project.id),
      ),
    );
  }

  Project? _findProposalsProject(List<Project> projects) {
    for (final project in projects) {
      if (_matchesStrongProposalProject(project)) {
        return project;
      }
    }
    return null;
  }

  bool _matchesStrongProposalProject(Project project) {
    final number = project.projectNumber?.trim() ?? '';
    final name = project.name.trim();
    final combined = [
      if (number.isNotEmpty) number,
      if (name.isNotEmpty) name,
    ].join(' ').trim().toLowerCase();

    final expectedLower = _kStrongProposalsProjectName.toLowerCase();

    if (combined == expectedLower) {
      return true;
    }
    if (number == _kStrongProposalsProjectNumber &&
        name.toLowerCase().contains('proposal')) {
      return true;
    }
    if (name.toLowerCase() == expectedLower) {
      return true;
    }
    return false;
  }

  void _handleDrop(Project project, _BigPictureLane lane) {
    final previousLane = _pendingLaneByProjectId[project.id] ??
        _laneFromStoredValue(project.bigPictureLane);

    setState(() {
      _pendingLaneByProjectId[project.id] = lane;
    });

    _projectRepository
        .update(project.id, {'bigPictureLane': lane.name}).catchError((error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not move project. Please try again.')),
      );
      setState(() {
        if (previousLane == null) {
          _pendingLaneByProjectId.remove(project.id);
        } else {
          _pendingLaneByProjectId[project.id] = previousLane;
        }
      });
    });
  }

  Map<_BigPictureLane, List<Project>> _partitionProjects(
    List<Project> projects,
  ) {
    final map = {
      for (final lane in _BigPictureLane.values) lane: <Project>[],
    };
    final knownIds = projects.map((p) => p.id).toSet();
    _pendingLaneByProjectId
        .removeWhere((key, value) => !knownIds.contains(key));

    final pendingMatches = <String>[];

    for (final project in projects) {
      final stored = _laneFromStoredValue(project.bigPictureLane);
      final pending = _pendingLaneByProjectId[project.id];
      if (pending != null && stored == pending) {
        pendingMatches.add(project.id);
      }
      final lane = pending ?? stored ?? _BigPictureLane.revenue;
      map[lane]!.add(project);
    }

    for (final id in pendingMatches) {
      _pendingLaneByProjectId.remove(id);
    }

    return map;
  }

  _BigPictureLane? _laneFromStoredValue(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    for (final lane in _BigPictureLane.values) {
      if (lane.name == raw) {
        return lane;
      }
    }
    return null;
  }

  List<Color> _buildSections(Color base) {
    return List<Color>.generate(4, (index) {
      final t = index / 3;
      return Color.lerp(base, Colors.white, t * 0.6)!;
    });
  }

  List<_LaneSection> _laneSections(List<Color> colors) {
    return List<_LaneSection>.generate(colors.length, (index) {
      final lane = _BigPictureLane.values[index];
      return _LaneSection(
        lane: lane,
        title: lane.title,
        color: colors[index],
      );
    });
  }
}

class _LaneSection {
  const _LaneSection({
    required this.lane,
    required this.title,
    required this.color,
  });

  final _BigPictureLane lane;
  final String title;
  final Color color;
}

class _LaneColumn extends StatelessWidget {
  const _LaneColumn({
    required this.title,
    required this.color,
    required this.projects,
    required this.onProjectDropped,
    required this.onProjectTap,
  });

  final String title;
  final Color color;
  final List<Project> projects;
  final ValueChanged<Project> onProjectDropped;
  final ValueChanged<Project> onProjectTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.labelSmall?.copyWith(
      fontSize: 11,
      letterSpacing: 0.3,
      fontWeight: FontWeight.w600,
    );

    return DragTarget<Project>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onProjectDropped(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHighlighted = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(
              color: isHighlighted ? Colors.white : Colors.transparent,
              width: isHighlighted ? 3 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: const BoxConstraints(minHeight: 60),
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  color: _textColor(color),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _ProjectWrap(
                projects: projects,
                labelStyle: labelStyle,
                onProjectTap: onProjectTap,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StrongProposalsLane extends StatelessWidget {
  const _StrongProposalsLane({
    required this.title,
    required this.color,
    required this.project,
    required this.expectedProjectName,
    required this.taskRepository,
    required this.onProposalTap,
  });

  final String title;
  final Color color;
  final Project? project;
  final String expectedProjectName;
  final TaskRepository taskRepository;
  final VoidCallback? onProposalTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final titleColor = _textColor(color);
    final labelStyle = textTheme.bodySmall?.copyWith(
      fontSize: 12,
      color: titleColor,
    );

    Widget buildLaneBody(Widget child) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.transparent, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: const BoxConstraints(minHeight: 60),
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                color: titleColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
    }

    if (project == null) {
      return buildLaneBody(
        Text(
          'Project "$expectedProjectName" not found.',
          style: labelStyle,
        ),
      );
    }

    final projectId = project!.id;
    return StreamBuilder<List<TaskItem>>(
      stream: taskRepository.streamByProject(projectId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return buildLaneBody(
            Text(
              'Could not load proposal tasks.',
              style: labelStyle,
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return buildLaneBody(
            const SizedBox(
              height: 32,
              child: Align(
                alignment: Alignment.centerLeft,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final tasks = snapshot.data ?? const <TaskItem>[];
        return buildLaneBody(
          _ProposalsTaskWrap(
            tasks: tasks,
            labelStyle: labelStyle,
            projectName: expectedProjectName,
            onProposalTap: onProposalTap,
          ),
        );
      },
    );
  }
}

class _ProposalsTaskWrap extends StatelessWidget {
  const _ProposalsTaskWrap({
    required this.tasks,
    required this.labelStyle,
    required this.projectName,
    required this.onProposalTap,
  });

  final List<TaskItem> tasks;
  final TextStyle? labelStyle;
  final String projectName;
  final VoidCallback? onProposalTap;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Text(
        'No tasks in $projectName.',
        style: labelStyle?.copyWith(
          color: labelStyle?.color?.withValues(alpha: 0.8) ?? Colors.white70,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final task in tasks)
          _ProposalTaskChip(
            task: task,
            textStyle: labelStyle,
            onTap: onProposalTap,
          ),
      ],
    );
  }
}

class _ProposalTaskChip extends StatelessWidget {
  const _ProposalTaskChip({
    required this.task,
    required this.textStyle,
    required this.onTap,
  });

  final TaskItem task;
  final TextStyle? textStyle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final baseStyle = (textStyle ?? const TextStyle(fontSize: 11)).copyWith(
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Text(task.title, style: baseStyle),
      ),
    );
  }
}

Color _textColor(Color background) {
  return background.computeLuminance() > 0.5
      ? Colors.blueGrey.shade900
      : Colors.white;
}

class _ProjectWrap extends StatelessWidget {
  const _ProjectWrap({
    required this.projects,
    required this.labelStyle,
    required this.onProjectTap,
  });

  final List<Project> projects;
  final TextStyle? labelStyle;
  final ValueChanged<Project> onProjectTap;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          'Drop projects here',
          style: labelStyle?.copyWith(
            color: labelStyle?.color?.withValues(alpha: 0.7) ?? Colors.white70,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final project in projects)
          _DraggableProjectToken(
            project: project,
            textStyle: labelStyle,
            onTap: () => onProjectTap(project),
          ),
      ],
    );
  }
}

class _DraggableProjectToken extends StatelessWidget {
  const _DraggableProjectToken({
    required this.project,
    required this.textStyle,
    required this.onTap,
  });

  final Project project;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor =
        textStyle?.color ?? Theme.of(context).colorScheme.onSurface;
    final background = Colors.black.withValues(alpha: 0.05);

    Widget buildLabel({double opacity = 1}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.black12),
        ),
        child: Text(
          project.name,
          style: (textStyle ?? const TextStyle(fontSize: 11)).copyWith(
            color: textColor,
          ),
        ),
      );
    }

    return LongPressDraggable<Project>(
      data: project,
      feedback: Material(
        color: Colors.transparent,
        child: buildLabel(opacity: 1),
      ),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: buildLabel(opacity: 0.6),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: buildLabel(),
      ),
    );
  }
}
