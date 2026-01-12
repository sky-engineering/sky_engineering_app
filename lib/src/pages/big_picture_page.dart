import 'package:flutter/material.dart';

import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';

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
        return 'Big Work';
      case _BigPictureLane.finishingTouches:
        return 'Small Work';
      case _BigPictureLane.strongProposals:
        return 'Strong Proposals';
      case _BigPictureLane.inactive:
        return 'No Work';
    }
  }
}

class BigPicturePage extends StatefulWidget {
  const BigPicturePage({super.key});

  @override
  State<BigPicturePage> createState() => _BigPicturePageState();
}

class _BigPicturePageState extends State<BigPicturePage> {
  final ProjectRepository _projectRepository = ProjectRepository();
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
            final partitions = _partitionProjects(visibleProjects);
            final sections = _laneSections(colors);

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < sections.length; i++) ...[
                    _LaneColumn(
                      title: sections[i].title,
                      color: sections[i].color,
                      projects:
                          partitions[sections[i].lane] ?? const <Project>[],
                      onProjectDropped: (project) =>
                          _handleDrop(project, sections[i].lane),
                    ),
                    if (i != sections.length - 1) const SizedBox(height: 12),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
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
  });

  final String title;
  final Color color;
  final List<Project> projects;
  final ValueChanged<Project> onProjectDropped;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.labelSmall?.copyWith(
      fontSize: 11,
      letterSpacing: 0.3,
      fontWeight: FontWeight.w600,
    );

    return DragTarget<Project>(
      onWillAccept: (_) => true,
      onAccept: onProjectDropped,
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
              ),
            ],
          ),
        );
      },
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
  });

  final List<Project> projects;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          'Drop projects here',
          style: labelStyle?.copyWith(
            color: labelStyle?.color?.withOpacity(0.7) ?? Colors.white70,
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
          ),
      ],
    );
  }
}

class _DraggableProjectToken extends StatelessWidget {
  const _DraggableProjectToken({
    required this.project,
    required this.textStyle,
  });

  final Project project;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final textColor =
        textStyle?.color ?? Theme.of(context).colorScheme.onSurface;
    final background = Colors.black.withOpacity(0.05);

    Widget buildLabel({double opacity = 1}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background.withOpacity(opacity),
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
      child: buildLabel(),
    );
  }
}
