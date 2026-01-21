import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/models/client.dart';
import '../data/repositories/client_repository.dart';
import '../theme/tokens.dart';
import '../utils/phone_utils.dart';
import '../widgets/form_helpers.dart';

Future<void> showClientEditorDialog(
  BuildContext context, {
  ClientRecord? client,
}) async {
  final codeCtl = TextEditingController(text: client?.code ?? '');
  final nameCtl = TextEditingController(text: client?.name ?? '');
  final contactNameCtl = TextEditingController(text: client?.contactName ?? '');
  final contactEmailCtl =
      TextEditingController(text: client?.contactEmail ?? '');
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

  List<String>? parseCommaSeparated(String value) {
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
      return StatefulBuilder(
        builder: (innerContext, setState) {
          return AppFormDialog(
            title: client == null ? 'Add Client' : 'Edit Client',
            actions: [
              AppDialogActions(
                leading: client != null
                    ? TextButton(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: dialogContext,
                            builder: (confirmContext) => AlertDialog(
                              title: const Text('Delete client?'),
                              content: Text(
                                'Remove ${client.code} ${client.name}?',
                              ),
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
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } catch (e) {
                              if (!dialogContext.mounted) return;
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text('Delete failed: $e')),
                              );
                            }
                          }
                        },
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      )
                    : null,
                secondary: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                primary: FilledButton(
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
                    final currentProposals =
                        parseCommaSeparated(currentProposalsCtl.text);
                    final notes = nullIfEmpty(notesCtl.text);

                    try {
                      final user = auth.currentUser;
                      if (client == null) {
                        if (user == null) {
                          if (!dialogContext.mounted) return;
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
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
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('Save failed: $e')),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: codeCtl,
                          keyboardType: TextInputType.number,
                          maxLength: 3,
                          decoration: const InputDecoration(
                            labelText: 'Client code',
                            hintText: 'e.g., 001',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
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
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: priority,
                          decoration: const InputDecoration(
                            labelText: 'Priority',
                            border: OutlineInputBorder(),
                          ),
                          items: List.generate(
                            5,
                            (index) => DropdownMenuItem<int>(
                              value: index + 1,
                              child: Text('${index + 1}'),
                            ),
                          ),
                          onChanged: (value) {
                            if (value != null) setState(() => priority = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  appTextField('Client name', nameCtl, required: true),
                  const SizedBox(height: AppSpacing.md),
                  appTextField('Contact name', contactNameCtl),
                  const SizedBox(height: AppSpacing.md),
                  appTextField(
                    'Contact email',
                    contactEmailCtl,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  appTextField(
                    'Contact phone',
                    contactPhoneCtl,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  appTextField(
                    'Current proposals',
                    currentProposalsCtl,
                    hint: 'Comma separated list',
                    maxLines: 2,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  appTextField('Notes', notesCtl, maxLines: 3),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
