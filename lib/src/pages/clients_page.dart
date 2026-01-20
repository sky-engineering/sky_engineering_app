import 'package:flutter/material.dart';

import '../data/models/client.dart';
import '../data/repositories/client_repository.dart';
import '../dialogs/client_editor_dialog.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_scaffold.dart';

class ClientsPage extends StatelessWidget {
  ClientsPage({super.key});

  final ClientRepository _repo = ClientRepository();

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Clients',
      includeShellBottomNav: true,
      popShellRoute: true,
      padding: EdgeInsets.zero,
      floatingActionButton: FloatingActionButton(
        onPressed: () => showClientEditorDialog(context),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<ClientRecord>>(
        stream: _repo.streamAll(),
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
            return const Center(child: Text('No clients yet.'));
          }
          return ListView.separated(
            itemCount: clients.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final client = clients[index];
              return ListTile(
                title: Text('${client.code} ${client.name}'),
                onTap: () => showClientEditorDialog(context, client: client),
              );
            },
          );
        },
      ),
    );
  }
}
