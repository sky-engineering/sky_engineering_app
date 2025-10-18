import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/models/client.dart';
import '../data/models/project.dart';
import '../data/models/task.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/task_repository.dart';
import '../dialogs/client_editor_dialog.dart';

class ProposalsPage extends StatelessWidget {
  ProposalsPage({super.key});

  final ClientRepository _clientRepository = ClientRepository();
  final ProjectRepository _projectRepository = ProjectRepository();
  final TaskRepository _taskRepository = TaskRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proposals'),
        actions: [
          IconButton(
            tooltip: 'View project tasks',
            icon: const Icon(Icons.task),
            onPressed: () => _showProposalTasksDialog(context),
          ),
        ],
      ),
      body: StreamBuilder<List<ClientRecord>>(
        stream: _clientRepository.streamAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Failed to load clients: ${snapshot.error}'),
              ),
            );
          }

          final clients = snapshot.data ?? const <ClientRecord>[];
          if (clients.isEmpty) {
            return const Center(
              child: Text('Add a client to see proposal buckets.'),
            );
          }

          final sortedClients = [...clients]
            ..sort((a, b) {
              final aHasProposals = (a.currentProposals?.isNotEmpty ?? false);
              final bHasProposals = (b.currentProposals?.isNotEmpty ?? false);
              if (aHasProposals != bHasProposals) {
                return aHasProposals ? -1 : 1;
              }
              final priorityCompare = a.priority.compareTo(b.priority);
              if (priorityCompare != 0) {
                return priorityCompare;
              }
              return a.code.compareTo(b.code);
            });

          final withProposals = sortedClients
              .where((client) => client.currentProposals?.isNotEmpty ?? false)
              .toList();
          final withoutProposals = sortedClients
              .where(
                (client) => !(client.currentProposals?.isNotEmpty ?? false),
              )
              .toList();

          return CustomScrollView(
            slivers: [
              if (withProposals.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: _buildGrid(withProposals),
                ),
              if (withProposals.isNotEmpty && withoutProposals.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Divider(thickness: 4, color: Colors.red),
                  ),
                ),
              if (withoutProposals.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: _buildGrid(withoutProposals),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<Project?> _findProposalsProject() async {
    final projects = await _projectRepository.streamAll().first;
    for (final project in projects) {
      final number = project.projectNumber?.trim() ?? '';
      final name = project.name.trim();
      final combined = [
        if (number.isNotEmpty) number,
        if (name.isNotEmpty) name,
      ].join(' ').trim().toLowerCase();
      if (combined == '001 proposals') {
        return project;
      }
      if (number == '001' && name.toLowerCase().contains('proposals')) {
        return project;
      }
      if (name.toLowerCase() == '001 proposals') {
        return project;
      }
    }
    return null;
  }

  Future<void> _showProposalTasksDialog(BuildContext context) async {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return FutureBuilder<Project?>(
          future: _findProposalsProject(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const AlertDialog(
                content: SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            if (snapshot.hasError) {
              return AlertDialog(
                title: const Text('Project Tasks'),
                content: Text('Failed to load project: ${snapshot.error}'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            final project = snapshot.data;
            if (project == null) {
              return AlertDialog(
                title: const Text('Project Tasks'),
                content: const Text(
                  'Could not find the "001 Proposals" project.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            return _ProposalProjectTaskDialog(
              project: project,
              taskRepository: _taskRepository,
              currentUser: _auth.currentUser,
            );
          },
        );
      },
    );
  }

  SliverGrid _buildGrid(List<ClientRecord> clients) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _ProposalClientCard(client: clients[index]),
        childCount: clients.length,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1,
      ),
    );
  }
}

class _ProposalClientCard extends StatelessWidget {
  const _ProposalClientCard({required this.client});

  final ClientRecord client;

  Color _priorityColor(BuildContext context) {
    final clamped = client.priority.clamp(1, 5) as num;
    final fraction = ((clamped - 1) / 4).clamp(0, 1).toDouble();
    const gold = Color(0xFFF1C400);
    const blue = Color(0xFF00426A);
    return Color.lerp(gold, blue, fraction) ?? gold;
  }

  Color _priorityTextColor(Color background) {
    return background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium;
    final proposalStyle = theme.textTheme.bodySmall;
    final notesStyle = proposalStyle?.copyWith(fontStyle: FontStyle.italic);

    final proposals = client.currentProposals ?? const <String>[];
    final notes = (client.notes ?? '').trim();
    final hasProposals = proposals.isNotEmpty;
    final hasNotes = notes.isNotEmpty;

    final cardColor = _priorityColor(context);
    final textColor = _priorityTextColor(cardColor);

    final detailChildren = <Widget>[];
    if (hasProposals) {
      detailChildren.add(
        Flexible(
          child: Text(
            proposals.map((proposal) => 'â€¢ $proposal').join('\n'),
            style: proposalStyle?.copyWith(color: textColor),
            maxLines: hasNotes ? 4 : 6,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    if (hasNotes) {
      if (hasProposals) {
        detailChildren.add(const SizedBox(height: 6));
      }
      detailChildren.add(
        Flexible(
          child: Text(
            notes,
            style: notesStyle?.copyWith(color: textColor),
            maxLines: hasProposals ? 3 : 6,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      color: cardColor,
      child: InkWell(
        onTap: () => showClientEditorDialog(context, client: client),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${client.code} ${client.name}',
                style: titleStyle?.copyWith(color: textColor),
              ),
              if (detailChildren.isNotEmpty) ...[
                const SizedBox(height: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: detailChildren,
                  ),
                ),
              ] else
                const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProposalProjectTaskDialog extends StatefulWidget {
  const _ProposalProjectTaskDialog({
    required this.project,
    required this.taskRepository,
    required this.currentUser,
  });

  final Project project;
  final TaskRepository taskRepository;
  final User? currentUser;

  @override
  State<_ProposalProjectTaskDialog> createState() =>
      _ProposalProjectTaskDialogState();
}

class _ProposalProjectTaskDialogState
    extends State<_ProposalProjectTaskDialog> {
  final TextEditingController _titleController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _handleAddTask() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorMessage = 'Enter a task name.');
      return;
    }

    final owner = widget.currentUser;
    if (owner == null) {
      setState(() => _errorMessage = 'Signed-in user required to add tasks.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final task = TaskItem(
        id: '',
        projectId: widget.project.id,
        ownerUid: owner.uid,
        title: title,
        taskStatus: 'Pending',
        isStarred: false,
        subtasks: const [],
      );
      await widget.taskRepository.add(task);
      setState(() {
        _titleController.clear();
      });
    } catch (error) {
      setState(() => _errorMessage = 'Failed to add task: $error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text('001 Proposals Tasks for ${widget.project.name}'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 280,
              child: StreamBuilder<List<TaskItem>>(
                stream: widget.taskRepository.streamByProject(
                  widget.project.id,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Failed to load tasks: ${snapshot.error}'),
                    );
                  }

                  final tasks = snapshot.data ?? const <TaskItem>[];
                  if (tasks.isEmpty) {
                    return const Center(
                      child: Text('No tasks yet for this project.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return ListTile(
                        dense: true,
                        title: Text(task.title),
                        subtitle: Text(task.taskStatus),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Add task',
                hintText: 'Describe the proposal task',
              ),
              enabled: !_submitting,
              onSubmitted: (_) => _handleAddTask(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _handleAddTask,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add Task'),
        ),
      ],
    );
  }
}
