// lib/src/widgets/invoices_section.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../data/models/invoice.dart';
import '../data/models/project.dart';
import '../data/repositories/invoice_repository.dart';
import 'form_helpers.dart';

class InvoicesSection extends StatelessWidget {
  /// Project whose invoices are shown.
  final String projectId;

  /// Whether current user owns the project (enables editing).
  final bool canEdit;

  /// Used to prefill in the Add dialog (we’ll show this exact string first).
  final String? projectNumberString;

  /// Optional section title. If null/empty and wrapInCard=true we suppress a header.
  final String? title;

  /// Optional filter for invoice type: 'Client' or 'Vendor'.
  /// If null, shows all invoices.
  final String? invoiceTypeFilter;

  /// When false, renders content without an outer Card. Default: true.
  final bool wrapInCard;

  /// When false, hides the internal "New Invoice" button. Default: true.
  final bool showNewButton;

  /// When true, shows only invoices with a positive balance.
  final bool unpaidOnly;

  /// Owner UID used when admins create invoices on others' behalf.
  final String? ownerUidForWrites;

  const InvoicesSection({
    super.key,
    required this.projectId,
    required this.canEdit,
    this.projectNumberString,
    this.title,
    this.invoiceTypeFilter,
    this.wrapInCard = true,
    this.showNewButton = true,
    this.unpaidOnly = false,
    this.ownerUidForWrites,
  });

  @override
  Widget build(BuildContext context) {
    final repo = InvoiceRepository();
    final currency = NumberFormat.simpleCurrency();

    Widget content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title!.trim().isNotEmpty)
            Text(title!, style: Theme.of(context).textTheme.titleLarge),
          if (title != null && title!.trim().isNotEmpty)
            const SizedBox(height: 8),
          StreamBuilder<List<Invoice>>(
            stream: repo.streamForProject(
              projectId: projectId,
              projectNumber: projectNumberString,
            ),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                );
              }

              var invoices = snap.data ?? const <Invoice>[];

              // filter by type
              if (invoiceTypeFilter != null) {
                invoices = invoices
                    .where((inv) => inv.invoiceType == invoiceTypeFilter)
                    .toList();
              }

              // filter by unpaid
              if (unpaidOnly) {
                invoices =
                    invoices.where((inv) => (inv.balance) > 0.0001).toList();
              }

              if (invoices.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        invoiceTypeFilter == 'Vendor'
                            ? 'No vendor invoices yet'
                            : invoiceTypeFilter == 'Client'
                                ? 'No client invoices yet'
                                : 'No invoices yet',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (canEdit && showNewButton)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () => showAddInvoiceDialog(
                            context,
                            projectId,
                            defaultProjectNumber: projectNumberString,
                            initialInvoiceType: invoiceTypeFilter ?? 'Client',
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('New Invoice'),
                        ),
                      ),
                  ],
                );
              }

              return Column(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: invoices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final inv = invoices[i];
                      return InkWell(
                        onTap: () => _showEditInvoiceDialog(
                          context,
                          inv,
                          canEdit: canEdit,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                inv.invoiceNumber.isNotEmpty
                                                    ? 'Invoice ${inv.invoiceNumber}'
                                                    : 'Invoice ${inv.id.substring(0, 6)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Original: ${currency.format(inv.invoiceAmount)}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    currency.format(inv.balance),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  if (canEdit && showNewButton)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => showAddInvoiceDialog(
                          context,
                          projectId,
                          defaultProjectNumber: projectNumberString,
                          initialInvoiceType: invoiceTypeFilter ?? 'Client',
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('New Invoice'),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );

    if (wrapInCard) {
      return Card(child: content);
    }
    return content;
  }
}

/// Public helper so other widgets can open the "New Invoice" dialog.
Future<void> showAddInvoiceDialog(
  BuildContext context,
  String? projectId, {
  String? defaultProjectNumber,
  String initialInvoiceType = 'Client',
  List<Project>? projectChoices,
  String? ownerUid,
}) {
  return _showAddInvoiceDialog(
    context,
    projectId,
    defaultProjectNumber: defaultProjectNumber,
    initialInvoiceType: initialInvoiceType,
    projectChoices: projectChoices,
    ownerUid: ownerUid,
  );
}

// ---------- Helpers ----------
String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// Returns true if a project exists with an exact projectNumber match to [text]
/// OR whose digits-only value equals digits-only of [text].
Future<bool> _projectNumberExists(String text) async {
  final projects = FirebaseFirestore.instance.collection('projects');

  // 1) Try exact match first (fast, indexed).
  final exact =
      await projects.where('projectNumber', isEqualTo: text).limit(1).get();
  if (exact.docs.isNotEmpty) return true;

  // 2) Fallback: scan a reasonable number and compare digits-only client-side.
  final digits = _digitsOnly(text);
  if (digits.isEmpty) return false;

  final scan = await projects.limit(500).get(); // adjust for your dataset scale
  for (final d in scan.docs) {
    final v = (d.data()['projectNumber'] as String?) ?? '';
    if (_digitsOnly(v) == digits) return true;
  }
  return false;
}

Future<void> _showAddInvoiceDialog(
  BuildContext context,
  String? projectId, {
  String? defaultProjectNumber,
  String initialInvoiceType = 'Client',
  List<Project>? projectChoices,
  String? ownerUid,
}) async {
  // Reordered fields per request:
  // 1) Project Number (defaults to current project's projectNumber string)
  // 2) Invoice Number
  // 3) Invoice Amount
  // 4) Amount Paid (default 0)
  // then dates (Invoice Date defaults today, Due Date = today+30), type, link.

  final projectMap = <String, Project>{
    for (final project in projectChoices ?? const <Project>[])
      project.id: project,
  };

  String projectLabel(Project project) {
    final number = (project.projectNumber ?? '').trim();
    return number.isNotEmpty ? '$number ${project.name}' : project.name;
  }

  String? selectedProjectId = projectId;
  if (projectMap.isNotEmpty) {
    if (selectedProjectId == null ||
        !projectMap.containsKey(selectedProjectId)) {
      selectedProjectId = projectMap.keys.first;
    }
  }
  Project? selectedProject =
      selectedProjectId != null ? projectMap[selectedProjectId] : null;

  final now = DateTime.now();
  DateTime? invoiceDate = DateTime(now.year, now.month, now.day);
  DateTime? dueDate = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(const Duration(days: 30));
  DateTime? paidDate;

  final projectNumberCtl = TextEditingController(
    text: defaultProjectNumber ?? selectedProject?.projectNumber ?? '',
  );
  final invoiceNumberCtl = TextEditingController();
  final invoiceAmountCtl = TextEditingController();
  final amountPaidCtl = TextEditingController(text: '0');
  final documentLinkCtl = TextEditingController();

  String invoiceType = (initialInvoiceType == 'Vendor') ? 'Vendor' : 'Client';

  final formKey = GlobalKey<FormState>();
  final repo = InvoiceRepository();
  final me = FirebaseAuth.instance.currentUser;

  if (me == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('You must be signed in.')));
    return;
  }

  Future<void> pickDate(String which) async {
    final seed = (which == 'invoice')
        ? (invoiceDate ?? DateTime.now())
        : (which == 'due')
            ? (dueDate ?? DateTime.now())
            : (paidDate ?? DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: seed,
      firstDate: DateTime(seed.year - 5),
      lastDate: DateTime(seed.year + 5),
    );
    if (d != null) {
      switch (which) {
        case 'invoice':
          invoiceDate = d;
          break;
        case 'due':
          dueDate = d;
          break;
        case 'paid':
          paidDate = d;
          break;
      }
    }
  }

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('New Invoice'),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (projectMap.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          initialValue: selectedProjectId,
                          decoration: const InputDecoration(
                            labelText: 'Project',
                            border: OutlineInputBorder(),
                          ),
                          isExpanded: true,
                          items: projectMap.entries
                              .map(
                                (entry) => DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(projectLabel(entry.value)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              selectedProjectId = value;
                              selectedProject = projectMap[value];
                              final suggestion =
                                  (selectedProject?.projectNumber ?? '').trim();
                              if (suggestion.isNotEmpty) {
                                projectNumberCtl.text = suggestion;
                                projectNumberCtl.selection =
                                    TextSelection.fromPosition(
                                  TextPosition(
                                    offset: projectNumberCtl.text.length,
                                  ),
                                );
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      appTextField(
                        'Project Number',
                        projectNumberCtl,
                        required: true,
                        hint: 'e.g., 026-01',
                      ),
                      const SizedBox(height: 10),
                      appTextField(
                        'Invoice Number',
                        invoiceNumberCtl,
                        required: true,
                        hint: 'e.g., 1220',
                      ),
                      const SizedBox(height: 10),
                      appTextField(
                        'Invoice Amount',
                        invoiceAmountCtl,
                        required: true,
                        hint: 'e.g., 17150.91',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      appTextField(
                        'Amount Paid',
                        amountPaidCtl,
                        hint: '0',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: appDateField(
                              label: 'Invoice Date',
                              value: invoiceDate,
                              onPick: () async {
                                await pickDate('invoice');
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: appDateField(
                              label: 'Due Date',
                              value: dueDate,
                              onPick: () async {
                                await pickDate('due');
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      appDateField(
                        label: 'Paid Date',
                        value: paidDate,
                        onPick: () async {
                          await pickDate('paid');
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: invoiceType,
                        items: const [
                          DropdownMenuItem(
                            value: 'Client',
                            child: Text('Client'),
                          ),
                          DropdownMenuItem(
                            value: 'Vendor',
                            child: Text('Vendor'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => invoiceType = v ?? 'Client'),
                        decoration: const InputDecoration(
                          labelText: 'Invoice Type',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      appTextField(
                        'Document Link',
                        documentLinkCtl,
                        hint: 'https://...',
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
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  if (!(formKey.currentState?.validate() ?? false)) return;

                  // Validate that the project number exists before saving.
                  final pnText = projectNumberCtl.text.trim();
                  if (pnText.isEmpty || !(await _projectNumberExists(pnText))) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Project Number not found.'),
                      ),
                    );
                    return;
                  }

                  final amt =
                      double.tryParse(invoiceAmountCtl.text.trim()) ?? 0.0;
                  final paid = amountPaidCtl.text.trim().isEmpty
                      ? 0.0
                      : (double.tryParse(amountPaidCtl.text.trim()) ?? 0.0);

                  // Store the project number exactly as entered so formatting is preserved.
                  final projectNumberValue = pnText.isNotEmpty ? pnText : null;

                  final targetProjectId = selectedProjectId ?? projectId;
                  if (targetProjectId == null || targetProjectId.isEmpty) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Select a project.')),
                    );
                    return;
                  }

                  final me = FirebaseAuth.instance.currentUser;
                  final providedOwner = ownerUid;
                  final projectOwner = selectedProject?.ownerUid;
                  final ownerForInvoice =
                      (providedOwner != null && providedOwner.isNotEmpty)
                          ? providedOwner
                          : ((projectOwner != null && projectOwner.isNotEmpty)
                              ? projectOwner
                              : (me?.uid ?? ''));
                  final resolvedOwner = ownerForInvoice.isNotEmpty
                      ? ownerForInvoice
                      : (me?.uid ?? '');
                  final inv = Invoice(
                    id: '_',
                    projectId: targetProjectId,
                    ownerUid:
                        resolvedOwner.isNotEmpty ? resolvedOwner : me?.uid,
                    invoiceNumber: invoiceNumberCtl.text.trim(),
                    projectNumber: projectNumberValue,
                    invoiceAmount: amt,
                    amountPaid: paid,
                    invoiceDate: invoiceDate,
                    dueDate: dueDate,
                    paidDate: paidDate,
                    documentLink: documentLinkCtl.text.trim().isNotEmpty
                        ? documentLinkCtl.text.trim()
                        : null,
                    invoiceType: invoiceType,
                  );

                  try {
                    await repo.add(inv);
                    if (navigator.mounted) {
                      navigator.pop();
                    }
                  } catch (e) {
                    if (!navigator.mounted) return;
                    if (messenger.mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Failed to create invoice: $e')),
                      );
                    }
                  }
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showEditInvoiceDialog(
  BuildContext context,
  Invoice inv, {
  required bool canEdit,
}) async {
  // Prefill the formatted project number string from the actual project doc.
  String initialProjectNumberText = inv.projectNumber ?? '';
  try {
    final projSnap = await FirebaseFirestore.instance
        .collection('projects')
        .doc(inv.projectId)
        .get();
    final pn = (projSnap.data()?['projectNumber'] as String?) ?? '';
    if (pn.isNotEmpty) initialProjectNumberText = pn;
  } catch (_) {
    // fall back to digits
  }

  if (!context.mounted) return;

  final projectNumberCtl = TextEditingController(
    text: initialProjectNumberText,
  );
  final invoiceNumberCtl = TextEditingController(text: inv.invoiceNumber);
  final invoiceAmountCtl = TextEditingController(
    text: inv.invoiceAmount.toStringAsFixed(2),
  );
  final amountPaidCtl = TextEditingController(
    text: inv.amountPaid.toStringAsFixed(2),
  );
  final documentLinkCtl = TextEditingController(text: inv.documentLink ?? '');

  String invoiceType = inv.invoiceType;
  DateTime? invoiceDate = inv.invoiceDate;
  DateTime? dueDate = inv.dueDate;
  DateTime? paidDate = inv.paidDate;

  final formKey = GlobalKey<FormState>();
  final repo = InvoiceRepository();

  Future<void> pickDate(String which) async {
    final seed = (which == 'invoice')
        ? (invoiceDate ?? DateTime.now())
        : (which == 'due')
            ? (dueDate ?? DateTime.now())
            : (paidDate ?? DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: seed,
      firstDate: DateTime(seed.year - 5),
      lastDate: DateTime(seed.year + 5),
    );
    if (d != null) {
      switch (which) {
        case 'invoice':
          invoiceDate = d;
          break;
        case 'due':
          dueDate = d;
          break;
        case 'paid':
          paidDate = d;
          break;
      }
    }
  }

  void viewOnlyTap() {
    if (!canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'View-only: only the project owner or an admin can modify invoices.',
          ),
        ),
      );
    }
  }

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              'Invoice ${inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : inv.id.substring(0, 6)}',
            ),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      appTextField(
                        'Project Number',
                        projectNumberCtl,
                        required: true,
                        hint: 'e.g., 026-01',
                      ),
                      const SizedBox(height: 10),
                      appTextField(
                        'Invoice Number',
                        invoiceNumberCtl,
                        required: true,
                      ),
                      const SizedBox(height: 10),
                      appTextField(
                        'Invoice Amount',
                        invoiceAmountCtl,
                        required: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      appTextField(
                        'Amount Paid',
                        amountPaidCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: appDateField(
                              label: 'Invoice Date',
                              value: invoiceDate,
                              onPick: () async {
                                if (!canEdit) return viewOnlyTap();
                                await pickDate('invoice');
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: appDateField(
                              label: 'Due Date',
                              value: dueDate,
                              onPick: () async {
                                if (!canEdit) return viewOnlyTap();
                                await pickDate('due');
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      appDateField(
                        label: 'Paid Date',
                        value: paidDate,
                        onPick: () async {
                          if (!canEdit) return viewOnlyTap();
                          await pickDate('paid');
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: invoiceType,
                        items: const [
                          DropdownMenuItem(
                            value: 'Client',
                            child: Text('Client'),
                          ),
                          DropdownMenuItem(
                            value: 'Vendor',
                            child: Text('Vendor'),
                          ),
                        ],
                        onChanged: canEdit
                            ? (v) =>
                                setState(() => invoiceType = v ?? invoiceType)
                            : (v) => viewOnlyTap(),
                        decoration: const InputDecoration(
                          labelText: 'Invoice Type',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      appTextField('Document Link', documentLinkCtl),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              if (canEdit)
                TextButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await confirmDialog(
                      context,
                      'Delete this invoice?',
                    );
                    if (!ok) return;
                    try {
                      await repo.delete(inv.id);
                      if (navigator.mounted) {
                        navigator.pop();
                      }
                    } catch (e) {
                      if (!navigator.mounted) return;
                      if (messenger.mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Failed to delete: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Delete'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(canEdit ? 'Cancel' : 'Close'),
              ),
              if (canEdit)
                FilledButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    if (!(formKey.currentState?.validate() ?? false)) return;

                    // Validate that the project number exists before saving.
                    final pnText = projectNumberCtl.text.trim();
                    if (pnText.isEmpty ||
                        !(await _projectNumberExists(pnText))) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Project Number not found.'),
                        ),
                      );
                      return;
                    }

                    final amt = double.tryParse(invoiceAmountCtl.text.trim()) ??
                        inv.invoiceAmount;
                    final paid = amountPaidCtl.text.trim().isEmpty
                        ? inv.amountPaid
                        : (double.tryParse(amountPaidCtl.text.trim()) ??
                            inv.amountPaid);

                    // Store the project number exactly as entered so formatting is preserved.
                    final projectNumberValue =
                        pnText.isNotEmpty ? pnText : null;

                    try {
                      await repo.update(inv.id, {
                        'invoiceNumber': invoiceNumberCtl.text.trim(),
                        'projectNumber': projectNumberValue,
                        'invoiceAmount': amt,
                        'amountPaid': paid,
                        'invoiceDate': invoiceDate != null
                            ? Timestamp.fromDate(invoiceDate!)
                            : null,
                        'dueDate': dueDate != null
                            ? Timestamp.fromDate(dueDate!)
                            : null,
                        'paidDate': paidDate != null
                            ? Timestamp.fromDate(paidDate!)
                            : null,
                        'documentLink': documentLinkCtl.text.trim().isNotEmpty
                            ? documentLinkCtl.text.trim()
                            : null,
                        'invoiceType': invoiceType,
                      });
                      if (navigator.mounted) {
                        navigator.pop();
                      }
                    } catch (e) {
                      if (!navigator.mounted) return;
                      if (messenger.mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('Failed to save: $e')),
                        );
                      }
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
