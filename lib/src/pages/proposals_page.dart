import 'package:flutter/material.dart';

import '../data/models/client.dart';
import '../data/models/project.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/project_repository.dart';
import '../dialogs/client_editor_dialog.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_scaffold.dart';
import 'project_detail_page.dart';

class ProposalsPage extends StatelessWidget {
  ProposalsPage({super.key});

  final ClientRepository _clientRepository = ClientRepository();
  final ProjectRepository _projectRepository = ProjectRepository();

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Proposals',
      includeShellBottomNav: true,
      popShellRoute: true,
      padding: EdgeInsets.zero,
      actions: [
        IconButton(
          tooltip: 'Open 001 Proposals project',
          icon: const Icon(Icons.open_in_new),
          onPressed: () => _openProposalsProject(context),
        ),
      ],
      body: StreamBuilder<List<ClientRecord>>(
        stream: _clientRepository.streamAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
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

          final sortedClients = [...clients]..sort((a, b) {
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
                  padding: const EdgeInsets.all(AppSpacing.md),
                  sliver: _buildGrid(withProposals),
                ),
              if (withProposals.isNotEmpty && withoutProposals.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Divider(
                      thickness: 3,
                      color: AppColors.warning,
                    ),
                  ),
                ),
              if (withoutProposals.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  sliver: _buildGrid(withoutProposals),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openProposalsProject(BuildContext context) async {
    final project = await _findProposalsProject();
    if (!context.mounted) return;
    if (project == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not find the "001 Proposals" project.'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectDetailPage(projectId: project.id),
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

  SliverGrid _buildGrid(List<ClientRecord> clients) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _ProposalClientCard(client: clients[index]),
        childCount: clients.length,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.xs,
        crossAxisSpacing: AppSpacing.xs,
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
    const gold = AppColors.accentYellow;
    const blue = AppColors.brandPrimary;
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
            proposals.map((proposal) => '\u2022 $proposal').join('\n'),
            style: proposalStyle?.copyWith(color: textColor),
            maxLines: hasNotes ? 4 : 6,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    if (hasNotes) {
      if (hasProposals) {
        detailChildren.add(const SizedBox(height: AppSpacing.sm));
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
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${client.code} ${client.name}',
                style: titleStyle?.copyWith(color: textColor),
              ),
              if (detailChildren.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
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
