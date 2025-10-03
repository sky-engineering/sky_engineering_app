import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/models/client.dart';
import '../data/repositories/client_repository.dart';
import '../utils/phone_utils.dart';

class ClientsPage extends StatelessWidget {
  ClientsPage({super.key});

  final ClientRepository _repo = ClientRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clients')),
      body: StreamBuilder<List<ClientRecord>>(
        stream: _repo.streamAll(),
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
            return const Center(child: Text('No clients yet.'));
          }
          return ListView.separated(
            itemCount: clients.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final client = clients[index];
              return ListTile(
                title: Text('${client.code} ${client.name}'),
                onTap: () => _showClientDialog(context, client: client),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showClientDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Client'),
      ),
    );
  }

  Future<void> _showClientDialog(
    BuildContext context, {
    ClientRecord? client,
  }) async {
    final codeCtl = TextEditingController(text: client?.code ?? '');
    final nameCtl = TextEditingController(text: client?.name ?? '');
    final contactNameCtl = TextEditingController(
      text: client?.contactName ?? '',
    );
    final contactEmailCtl = TextEditingController(
      text: client?.contactEmail ?? '',
    );
    final contactPhoneCtl = TextEditingController(
      text: formatPhoneForDisplay(client?.contactPhone),
    );
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(client == null ? 'Add Client' : 'Edit Client'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: codeCtl,
                      decoration: const InputDecoration(
                        labelText: 'Client code',
                        hintText: 'e.g., 001',
                      ),
                      maxLength: 3,
                      buildCounter:
                          (
                            _, {
                            required int currentLength,
                            required bool isFocused,
                            int? maxLength,
                          }) => null,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Required';
                        if (v.length != 3 || int.tryParse(v) == null) {
                          return 'Use a 3-digit code';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: nameCtl,
                      decoration: const InputDecoration(
                        labelText: 'Client name',
                        hintText: 'e.g., City of Anywhere',
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Required'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Client Contact',
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: contactNameCtl,
                      decoration: const InputDecoration(
                        labelText: 'Contact name',
                        hintText: 'e.g., Jane Smith',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: contactPhoneCtl,
                      decoration: const InputDecoration(
                        labelText: 'Contact phone',
                        hintText: 'e.g., (555) 123-4567',
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: const [UsPhoneInputFormatter()],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: contactEmailCtl,
                      decoration: const InputDecoration(
                        labelText: 'Contact email',
                        hintText: 'e.g., jane@example.com',
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            if (client != null)
              TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: dialogContext,
                    builder: (confirmContext) => AlertDialog(
                      title: const Text('Delete client?'),
                      content: Text('Remove ${client.code} ${client.name}?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmContext, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(confirmContext, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    try {
                      await _repo.delete(client.id);
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                    } catch (e) {
                      if (!dialogContext.mounted) return;
                      final messenger = ScaffoldMessenger.maybeOf(
                        dialogContext,
                      );
                      messenger?.showSnackBar(
                        SnackBar(content: Text('Delete failed: $e')),
                      );
                    }
                  }
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;

                final code = codeCtl.text.trim();
                final name = nameCtl.text.trim();
                String? nullIfEmpty(String value) {
                  final trimmed = value.trim();
                  return trimmed.isEmpty ? null : trimmed;
                }

                final contactName = nullIfEmpty(contactNameCtl.text);
                final contactEmail = nullIfEmpty(contactEmailCtl.text);
                final contactPhone = normalizePhone(contactPhoneCtl.text);

                try {
                  final user = _auth.currentUser;
                  if (client == null) {
                    if (user == null) {
                      if (!dialogContext.mounted) return;
                      final messenger = ScaffoldMessenger.maybeOf(
                        dialogContext,
                      );
                      messenger?.showSnackBar(
                        const SnackBar(
                          content: Text('Sign in required to add clients.'),
                        ),
                      );
                      return;
                    }
                    final record = ClientRecord(
                      id: '',
                      code: code,
                      name: name,
                      contactName: contactName,
                      contactEmail: contactEmail,
                      contactPhone: contactPhone,
                      ownerUid: user.uid,
                    );
                    await _repo.add(record, ownerUid: user.uid);
                  } else {
                    final updated = ClientRecord(
                      id: client.id,
                      code: code,
                      name: name,
                      contactName: contactName,
                      contactEmail: contactEmail,
                      contactPhone: contactPhone,
                      ownerUid: client.ownerUid ?? user?.uid,
                    );
                    await _repo.update(client.id, updated);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  final messenger = ScaffoldMessenger.maybeOf(dialogContext);
                  messenger?.showSnackBar(
                    SnackBar(content: Text('Save failed: $e')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}
