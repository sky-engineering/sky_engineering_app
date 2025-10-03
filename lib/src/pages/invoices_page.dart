// lib/src/pages/invoices_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/models/invoice.dart';
import '../data/models/project.dart';
import '../data/repositories/invoice_repository.dart';
import '../data/repositories/project_repository.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  static const _accentYellow = Color(0xFFF1C400);

  /// When true, only invoices with balance > 0 are shown.
  bool _unpaidOnly = false;

  /// If empty => all projects. Otherwise, filter by these projectIds.
  final Set<String> _selectedProjectIds = <String>{};

  /// Cache of projectId -> display project number string (from Project.projectNumber).
  final Map<String, String> _projectNumById = <String, String>{};

  /// Current invoice type filter. Only 'Client' or 'Vendor'.
  String _typeFilter = 'Client';

  final _invoiceRepo = InvoiceRepository();
  final _projectRepo = ProjectRepository();

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          // Yellow text toggle: Unpaid Only (Show/Hide Paid Invoices)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: () => setState(() => _unpaidOnly = !_unpaidOnly),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: _accentYellow,
                ),
                child: Text(
                  _unpaidOnly ? 'Show Paid Invoices' : 'Hide Paid Invoices',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _accentYellow,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          // Project filter button (multi-select projects)
          IconButton(
            tooltip: 'Filter by projects',
            onPressed: _openProjectFilter,
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top type switcher: Clients | Vendors
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Client', label: Text('Clients')),
                ButtonSegment(value: 'Vendor', label: Text('Vendors')),
              ],
              selected: {_typeFilter},
              showSelectedIcon: false,
              onSelectionChanged: (set) {
                if (set.isEmpty) return;
                setState(() => _typeFilter = set.first);
              },
            ),
          ),
          const SizedBox(height: 6),

          if (_selectedProjectIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      label: Text(
                        _selectedProjectIds.length == 1
                            ? '1 project selected'
                            : '${_selectedProjectIds.length} projects selected',
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _selectedProjectIds.clear()),
                      child: const Text('Clear project filter'),
                    ),
                  ],
                ),
              ),
            ),

          // Everything below (summary + list) reacts to projects and invoices.
          Expanded(
            child: StreamBuilder<List<Project>>(
              stream: _projectRepo.streamAll(),
              builder: (context, projSnap) {
                final projects = projSnap.data ?? const <Project>[];
                // Refresh project number cache
                _projectNumById
                  ..clear()
                  ..addEntries(
                    projects.map(
                      (p) => MapEntry(p.id, (p.projectNumber ?? '').trim()),
                    ),
                  );

                return StreamBuilder<List<Invoice>>(
                  stream: _invoiceRepo.streamAll(),
                  builder: (context, invSnap) {
                    if (invSnap.connectionState == ConnectionState.waiting ||
                        projSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    var invoices = invSnap.data ?? const <Invoice>[];

                    // Apply invoice type filter (required)
                    invoices = invoices
                        .where((i) => i.invoiceType == _typeFilter)
                        .toList();

                    // Apply unpaid filter
                    if (_unpaidOnly) {
                      invoices = invoices
                          .where((i) => i.balance > 0.0001)
                          .toList();
                    }

                    // Apply project filter
                    if (_selectedProjectIds.isNotEmpty) {
                      invoices = invoices
                          .where(
                            (i) => _selectedProjectIds.contains(i.projectId),
                          )
                          .toList();
                    }

                    // Sort: newest date first (fallback to createdAt/updatedAt/number)
                    invoices.sort((a, b) {
                      final ad = a.invoiceDate ?? a.createdAt ?? a.updatedAt;
                      final bd = b.invoiceDate ?? b.createdAt ?? b.updatedAt;
                      if (ad != null && bd != null) return bd.compareTo(ad);
                      if (ad == null && bd != null) return 1;
                      if (ad != null && bd == null) return -1;
                      return b.invoiceNumber.compareTo(a.invoiceNumber);
                    });

                    // ---- NEW summary of total unpaid for currently listed invoices
                    final totalUnpaid = invoices.fold<double>(
                      0.0,
                      (sum, inv) => sum + (inv.balance > 0 ? inv.balance : 0.0),
                    );
                    final summaryLabel = (_typeFilter == 'Client')
                        ? 'Total Unpaid (Clients)'
                        : 'Total Unpaid (Vendors)';

                    if (invoices.isEmpty) {
                      // Still show the summary line (will be $0.00) for clarity.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                            ),
                            child: Text(
                              '$summaryLabel: ${currency.format(totalUnpaid)}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _selectedProjectIds.isNotEmpty || _unpaidOnly
                                      ? 'No ${_typeFilter.toLowerCase()} invoices match your filters.'
                                      : 'No ${_typeFilter.toLowerCase()} invoices yet.',
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    // When invoices exist, show summary + list
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            '$summaryLabel: ${currency.format(totalUnpaid)}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                            itemCount: invoices.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final inv = invoices[i];
                              final projNum = _projectNumById[inv.projectId];
                              final displayProj =
                                  (projNum != null && projNum.isNotEmpty)
                                  ? projNum
                                  : (inv.projectNumber?.toString() ?? '—');

                              // Title row: [Invoice NNN]  (link icon)      Balance: $X
                              // Subtitle:  Project: 026-01 • Original: $Y
                              return Card(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  dense: true,
                                  visualDensity: const VisualDensity(
                                    vertical: -2,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          inv.invoiceNumber.isNotEmpty
                                              ? 'Invoice ${inv.invoiceNumber}'
                                              : 'Invoice ${inv.id.substring(0, 6)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if ((inv.documentLink ?? '')
                                          .trim()
                                          .isNotEmpty)
                                        IconButton(
                                          tooltip: 'Open document link',
                                          icon: const Icon(Icons.link),
                                          onPressed: () => _openLink(
                                            inv.documentLink!.trim(),
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Balance: ${currency.format(inv.balance)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    'Project: $displayProj • Original: ${currency.format(inv.invoiceAmount)}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _showEditInvoiceDialogInline(
                                    context,
                                    inv,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // -------- actions / helpers --------

  Future<void> _openProjectFilter() async {
    final allProjects = await _projectRepo.streamAll().first;
    final projects = allProjects.where((p) => !p.isArchived).toList()
      ..sort((a, b) {
        final an = a.projectNumber ?? '';
        final bn = b.projectNumber ?? '';
        final cmp = an.compareTo(bn);
        if (cmp != 0) return cmp;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    if (projects.isEmpty) {
      if (mounted && _selectedProjectIds.isNotEmpty) {
        setState(() => _selectedProjectIds.clear());
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Filter by Projects'),
            content: const Text('No active projects available to filter.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
      return;
    }

    final activeIds = projects.map((p) => p.id).toSet();
    final localSel = {..._selectedProjectIds}
      ..removeWhere((id) => !activeIds.contains(id));

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Filter by Projects'),
              content: SizedBox(
                width: 420,
                height: 420,
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('All projects'),
                          selected: localSel.isEmpty,
                          onSelected: (_) =>
                              setStateDialog(() => localSel.clear()),
                        ),
                        if (localSel.isNotEmpty)
                          FilterChip(
                            label: const Text('Clear'),
                            selected: false,
                            onSelected: (_) =>
                                setStateDialog(() => localSel.clear()),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: projects.length,
                        itemBuilder: (context, i) {
                          final p = projects[i];
                          final selected = localSel.contains(p.id);
                          final hasNumber =
                              p.projectNumber != null &&
                              p.projectNumber!.trim().isNotEmpty;
                          final label = hasNumber
                              ? '${p.projectNumber} ${p.name}'
                              : p.name;
                          return CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: selected,
                            onChanged: (v) {
                              setStateDialog(() {
                                if (v == true) {
                                  localSel.add(p.id);
                                } else {
                                  localSel.remove(p.id);
                                }
                              });
                            },
                            title: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _selectedProjectIds
                        ..clear()
                        ..addAll(localSel);
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openLink(String urlStr) async {
    final uri = Uri.tryParse(urlStr);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid document link')));
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  // -------- Inline Edit Dialog (matches your amountPaid flow) --------
  Future<void> _showEditInvoiceDialogInline(
    BuildContext context,
    Invoice inv,
  ) async {
    final invoiceNumberCtl = TextEditingController(text: inv.invoiceNumber);
    // Keep original string (with dashes etc.) if Project.projectNumber is empty; else display Project.projectNumber
    final projectNumberCtl = TextEditingController(
      text: _projectNumById[inv.projectId]?.trim().isNotEmpty == true
          ? _projectNumById[inv.projectId]!
          : (inv.projectNumber?.toString() ?? ''),
    );
    final invoiceAmountCtl = TextEditingController(
      text: inv.invoiceAmount.toStringAsFixed(2),
    );
    final amountPaidCtl = TextEditingController(
      text: inv.amountPaid.toStringAsFixed(2),
    );
    final documentLinkCtl = TextEditingController(text: inv.documentLink ?? '');

    String invoiceType = inv.invoiceType; // keep existing
    DateTime? invoiceDate = inv.invoiceDate;
    DateTime? dueDate = inv.dueDate;
    DateTime? paidDate = inv.paidDate;

    final formKey = GlobalKey<FormState>();
    final repo = _invoiceRepo;

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
                        // Order requested earlier: Project Number first, then Invoice Number, Amount, Amount Paid...
                        TextFormField(
                          controller: projectNumberCtl,
                          decoration: const InputDecoration(
                            labelText: 'Project Number',
                            hintText: 'e.g., 026-01',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: invoiceNumberCtl,
                          decoration: const InputDecoration(
                            labelText: 'Invoice Number',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: invoiceAmountCtl,
                          decoration: const InputDecoration(
                            labelText: 'Invoice Amount',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: amountPaidCtl,
                          decoration: const InputDecoration(
                            labelText: 'Amount Paid',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _appDateField(
                                context: context,
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
                              child: _appDateField(
                                context: context,
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
                        _appDateField(
                          context: context,
                          label: 'Paid Date',
                          value: paidDate,
                          onPick: () async {
                            await pickDate('paid');
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: invoiceType,
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
                              setState(() => invoiceType = v ?? invoiceType),
                          decoration: const InputDecoration(
                            labelText: 'Invoice Type',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: documentLinkCtl,
                          decoration: const InputDecoration(
                            labelText: 'Document Link',
                            hintText: 'https://...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final ok = await _confirmDialog(
                      context,
                      'Delete this invoice?',
                    );
                    if (!ok) return;
                    try {
                      await repo.delete(inv.id);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to delete: $e')),
                      );
                    }
                  },
                  child: const Text('Delete'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;

                    final amt =
                        double.tryParse(invoiceAmountCtl.text.trim()) ??
                        inv.invoiceAmount;
                    final paid = amountPaidCtl.text.trim().isEmpty
                        ? inv.amountPaid
                        : (double.tryParse(amountPaidCtl.text.trim()) ??
                              inv.amountPaid);

                    // We keep the existing projectId; editing the human-readable
                    // "Project Number" string here does not move the invoice.
                    // It’s only stored if your model uses `projectNumber` mirror.
                    int? projNumMirror;
                    final pnText = projectNumberCtl.text.trim();
                    if (pnText.isNotEmpty) {
                      // do NOT strip non-digits; preserve formatting by not parsing if you store as string.
                      // If your Invoice.projectNumber is an int mirror, this remains optional:
                      projNumMirror = int.tryParse(
                        pnText.replaceAll(RegExp(r'[^0-9]'), ''),
                      );
                    }

                    try {
                      await repo.update(inv.id, {
                        'invoiceNumber': invoiceNumberCtl.text.trim(),
                        'projectNumber': projNumMirror, // optional mirror
                        'invoiceAmount': amt,
                        'amountPaid': paid, // canonical
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
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to save: $e')),
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

  // ---- tiny shared UI bits ----

  Future<bool> _confirmDialog(BuildContext context, String msg) async {
    bool ok = false;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () {
                ok = true;
                Navigator.pop(context);
              },
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
    return ok;
  }

  Widget _appDateField({
    required BuildContext context,
    required String label,
    required DateTime? value,
    required Future<void> Function() onPick,
  }) {
    return InkWell(
      onTap: onPick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          value != null ? DateFormat.yMMMd().format(value) : '—',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
