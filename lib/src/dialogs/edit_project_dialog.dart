// lib/src/dialogs/edit_project_dialog.dart
import 'package:flutter/material.dart';
import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';
import '../utils/phone_utils.dart';
import '../widgets/form_helpers.dart';

Future<void> showEditProjectDialog(BuildContext context, Project p) async {
  final nameCtl = TextEditingController(text: p.name);
  final clientCtl = TextEditingController(text: p.clientName);
  final projectNumCtl = TextEditingController(text: p.projectNumber ?? '');
  final folderCtl = TextEditingController(text: p.folderName ?? '');
  final contractCtl = TextEditingController(
    text: p.contractAmount != null ? p.contractAmount!.toStringAsFixed(2) : '',
  );

  // NEW contact fields
  final contactNameCtl = TextEditingController(text: p.contactName ?? '');
  final contactPhoneCtl = TextEditingController(
    text: formatPhoneForDisplay(p.contactPhone),
  );
  final contactEmailCtl = TextEditingController(text: p.contactEmail ?? '');

  final formKey = GlobalKey<FormState>();
  final repo = ProjectRepository();

  double? _parseMoney(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final mediaQuery = MediaQuery.of(dialogContext);
      final bottomInset = mediaQuery.viewInsets.bottom;
      final maxHeight = mediaQuery.size.height * 0.85;

      return AlertDialog(
        title: const Text('Edit Project'),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  appTextField(
                    'Project Name',
                    nameCtl,
                    required: true,
                    hint: 'e.g., Main St Improvements',
                  ),
                  const SizedBox(height: 10),
                  appTextField(
                    'Client',
                    clientCtl,
                    required: true,
                    hint: 'e.g., City of Anywhere',
                  ),
                  const SizedBox(height: 10),
                  appTextField(
                    'Project Number',
                    projectNumCtl,
                    hint: 'e.g., 026-01',
                  ),
                  const SizedBox(height: 10),
                  appTextField(
                    'Dropbox Folder',
                    folderCtl,
                    hint: 'e.g., /2024/Project123',
                  ),
                  const SizedBox(height: 10),
                  appTextField(
                    'Contract Amount',
                    contractCtl,
                    hint: 'e.g., 150000.00',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Client Contact',
                    style: Theme.of(dialogContext).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  appTextField(
                    'Contact Name',
                    contactNameCtl,
                    hint: 'e.g., Jane Smith',
                  ),
                  const SizedBox(height: 10),
                  appTextField(
                    'Contact Phone',
                    contactPhoneCtl,
                    hint: 'e.g., (555) 123-4567',
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [UsPhoneInputFormatter()],
                  ),
                  const SizedBox(height: 10),
                  appTextField(
                    'Contact Email',
                    contactEmailCtl,
                    hint: 'e.g., jane@example.com',
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: () async {
                          if (nameCtl.text.trim().isEmpty ||
                              clientCtl.text.trim().isEmpty) {
                            final msg = nameCtl.text.trim().isEmpty
                                ? 'Project Name is required.'
                                : 'Client is required.';
                            ScaffoldMessenger.of(
                              dialogContext,
                            ).showSnackBar(SnackBar(content: Text(msg)));
                            return;
                          }

                          final amt = _parseMoney(contractCtl.text);
                          String? nullIfEmpty(String s) =>
                              s.trim().isEmpty ? null : s.trim();

                          await repo.update(p.id, {
                            'name': nameCtl.text.trim(),
                            'clientName': clientCtl.text.trim(),
                            'contractAmount': amt,
                            'projectNumber': nullIfEmpty(projectNumCtl.text),
                            'folderName': nullIfEmpty(folderCtl.text),
                            'contactName': nullIfEmpty(contactNameCtl.text),
                            'contactPhone': normalizePhone(
                              contactPhoneCtl.text,
                            ),
                            'contactEmail': nullIfEmpty(contactEmailCtl.text),
                          });

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
