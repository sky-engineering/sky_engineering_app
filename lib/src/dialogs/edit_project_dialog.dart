// lib/src/dialogs/edit_project_dialog.dart
import 'package:flutter/material.dart';
import '../data/models/project.dart';
import '../data/repositories/project_repository.dart';
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
  final contactPhoneCtl = TextEditingController(text: p.contactPhone ?? '');
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
    builder: (context) {
      return AlertDialog(
        title: const Text('Edit Project'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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

                  // Contact block (NEW)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Client Contact',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
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
                  ),
                  const SizedBox(height: 10),
                  appTextField(
                    'Contact Email',
                    contactEmailCtl,
                    hint: 'e.g., jane@example.com',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              // Basic required checks (since appTextField doesn't validate itself)
              if (nameCtl.text.trim().isEmpty ||
                  clientCtl.text.trim().isEmpty) {
                final msg = nameCtl.text.trim().isEmpty
                    ? 'Project Name is required.'
                    : 'Client is required.';
                ScaffoldMessenger.of(
                  context,
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
                'contactPhone': nullIfEmpty(contactPhoneCtl.text),
                'contactEmail': nullIfEmpty(contactEmailCtl.text),
              });

              // ignore: use_build_context_synchronously
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}
