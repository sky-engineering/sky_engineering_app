import 'package:flutter/material.dart';

import '../data/models/client.dart';
import '../data/repositories/client_repository.dart';
import '../dialogs/client_editor_dialog.dart';

class ProposalsPage extends StatelessWidget {
  ProposalsPage({super.key});

  final ClientRepository _clientRepository = ClientRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Proposals')),
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
            proposals.map((proposal) => '• ' + proposal).join('\n'),
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
