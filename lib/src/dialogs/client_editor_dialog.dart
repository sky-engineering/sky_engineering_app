import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/models/client.dart';
import '../data/repositories/client_repository.dart';
import '../utils/phone_utils.dart';

Future<void> showClientEditorDialog(
  BuildContext context, {
  ClientRecord? client,
}) async {
  final codeCtl = TextEditingController(text: client?.code ?? '');
  final nameCtl = TextEditingController(text: client?.name ?? '');
  final contactNameCtl = TextEditingController(text: client?.contactName ?? '');
  final contactEmailCtl = TextEditingController(
    text: client?.contactEmail ?? '',
  );
  final contactPhoneCtl = TextEditingController(
    text: formatPhoneForDisplay(client?.contactPhone),
  );
  final currentProposalsCtl = TextEditingController(
    text: client?.currentProposals?.join(', ') ?? '',
  );
  final notesCtl = TextEditingController(text: client?.notes ?? '');

  final formKey = GlobalKey<FormState>();
  int priority = client?.priority ?? 3;

  final repo = ClientRepository();
  final auth = FirebaseAuth.instance;

  List<String>? _parseCommaSeparated(String value) {
    final cleaned = value
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    return cleaned.isEmpty ? null : cleaned;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final priorityOptions = List<int>.generate(5, (index) => index + 1);
      final priorityTextStyle = Theme.of(dialogContext).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(dialogContext).colorScheme.onSurface);

      return StatefulBuilder(
        builder: (innerContext, setState) {
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
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
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: priority,
                              decoration: const InputDecoration(
                                labelText: 'Priority',
                                border: OutlineInputBorder(),
                              ),
                              items: priorityOptions
                                  .map(
                                    (value) => DropdownMenuItem<int>(
                                      value: value,
                                      child: Text(
                                        '$value',
                                        style: priorityTextStyle,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              selectedItemBuilder: (context) => priorityOptions
                                  .map(
                                    (value) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '$value',
                                        style: priorityTextStyle,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => priority = value);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 8),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: currentProposalsCtl,
                        decoration: const InputDecoration(
                          labelText: 'Current proposals',
                          hintText: 'Separate entries with commas',
                        ),
                        maxLines: 6,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: notesCtl,
                        decoration: const InputDecoration(
                          labelText: 'Proposal notes',
                          hintText: 'Optional text',
                        ),
                        maxLines: 2,
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
                            onPressed: () =>
                                Navigator.pop(confirmContext, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(confirmContext, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      try {
                        await repo.delete(client.id);
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
                  final currentProposals = _parseCommaSeparated(
                    currentProposalsCtl.text,
                  );
                  final notes = nullIfEmpty(notesCtl.text);

                  try {
                    final user = auth.currentUser;
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
                        priority: priority,
                        currentProposals: currentProposals,
                        notes: notes,
                        contactName: contactName,
                        contactEmail: contactEmail,
                        contactPhone: contactPhone,
                        ownerUid: user.uid,
                      );
                      await repo.add(record, ownerUid: user.uid);
                    } else {
                      final updated = ClientRecord(
                        id: client.id,
                        code: code,
                        name: name,
                        priority: priority,
                        currentProposals: currentProposals,
                        notes: notes,
                        contactName: contactName,
                        contactEmail: contactEmail,
                        contactPhone: contactPhone,
                        ownerUid: client.ownerUid ?? user?.uid,
                      );
                      await repo.update(client.id, updated);
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
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
    },
  );
}
