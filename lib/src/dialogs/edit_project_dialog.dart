// lib/src/dialogs/edit_project_dialog.dart
import 'package:flutter/material.dart';

import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';
import '../theme/tokens.dart';
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
  final contactNameCtl = TextEditingController(text: p.contactName ?? '');
  final contactPhoneCtl = TextEditingController(
    text: formatPhoneForDisplay(p.contactPhone),
  );
  final contactEmailCtl = TextEditingController(text: p.contactEmail ?? '');
  final schedulingNotesCtl =
      TextEditingController(text: p.schedulingNotes ?? '');
  final formKey = GlobalKey<FormState>();
  final repo = ProjectRepository();
  String projectStatus =
      kProjectStatuses.contains(p.status) ? p.status : 'In Progress';

  double? parseMoney(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (innerContext, setState) {
          return AppFormDialog(
            title: 'Edit Project',
            width: 520,
            actions: [
              AppDialogActions(
                secondary: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                primary: FilledButton(
                  onPressed: () async {
                    if (nameCtl.text.trim().isEmpty ||
                        clientCtl.text.trim().isEmpty) {
                      final msg = nameCtl.text.trim().isEmpty
                          ? 'Project Name is required.'
                          : 'Client is required.';
                      ScaffoldMessenger.of(
                        innerContext,
                      ).showSnackBar(SnackBar(content: Text(msg)));
                      return;
                    }

                    final amt = parseMoney(contractCtl.text);
                    String? nullIfEmpty(String s) =>
                        s.trim().isEmpty ? null : s.trim();

                    await repo.update(p.id, {
                      'name': nameCtl.text.trim(),
                      'clientName': clientCtl.text.trim(),
                      'contractAmount': amt,
                      'projectNumber': nullIfEmpty(
                        projectNumCtl.text,
                      ),
                      'folderName': nullIfEmpty(folderCtl.text),
                      'contactName': nullIfEmpty(contactNameCtl.text),
                      'contactPhone': normalizePhone(
                        contactPhoneCtl.text,
                      ),
                      'contactEmail': nullIfEmpty(
                        contactEmailCtl.text,
                      ),
                      'schedulingNotes': nullIfEmpty(
                        schedulingNotesCtl.text,
                      ),
                      'status': projectStatus,
                      'isArchived': projectStatus == 'Archive',
                    });

                    if (!innerContext.mounted) return;
                    Navigator.pop(innerContext);
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
                  appTextField(
                    'Project Name',
                    nameCtl,
                    required: true,
                    hint: 'e.g., Main St Improvements',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  appTextField(
                    'Client',
                    clientCtl,
                    required: true,
                    hint: 'e.g., City of Anywhere',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  appTextField(
                    'Project Number',
                    projectNumCtl,
                    hint: 'e.g., 026-01',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  appTextField(
                    'Dropbox Folder',
                    folderCtl,
                    hint: 'e.g., /2024/Project123',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: projectStatus,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: kProjectStatuses
                        .map(
                          (status) => DropdownMenuItem<String>(
                            value: status,
                            child: Text(status),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => projectStatus = value);
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  appTextField(
                    'Contract Amount',
                    contractCtl,
                    hint: 'e.g., 150000.00',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  appTextField(
                    'Scheduling Notes',
                    schedulingNotesCtl,
                    hint: 'Optional scheduling info',
                    maxLines: 3,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Client Contact',
                    style: Theme.of(innerContext).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  appTextField(
                    'Contact Name',
                    contactNameCtl,
                    hint: 'e.g., Jane Smith',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  appTextField(
                    'Contact Phone',
                    contactPhoneCtl,
                    hint: 'e.g., (555) 123-4567',
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [UsPhoneInputFormatter()],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  appTextField(
                    'Contact Email',
                    contactEmailCtl,
                    hint: 'e.g., jane@example.com',
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
