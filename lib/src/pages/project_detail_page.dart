// lib/src/pages/project_detail_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../data/models/project.dart';
import '../data/models/invoice.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/invoice_repository.dart';

import '../widgets/form_helpers.dart';
import '../widgets/tasks_by_subphase_section.dart';
import '../widgets/invoices_section.dart' as inv;
import '../dialogs/edit_project_dialog.dart';

class ProjectDetailPage extends StatefulWidget {
  final String projectId;
  const ProjectDetailPage({super.key, required this.projectId});

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  bool _unpaidOnly = false; // toggle for invoice filtering
  final ScrollController _scrollCtrl = ScrollController();
  static const _accentYellow = Color(0xFFF1C400);

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _setUnpaidOnly(bool v) {
    final offset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    setState(() => _unpaidOnly = v);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(offset);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ProjectRepository();
    final me = FirebaseAuth.instance.currentUser;

    return StreamBuilder<Project?>(
      stream: repo.streamById(widget.projectId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final p = snap.data;
        if (p == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Project')),
            body: const Center(child: Text('Project not found')),
          );
        }
        final isOwner = (p.ownerUid != null && p.ownerUid == me?.uid);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              (p.projectNumber != null && p.projectNumber!.trim().isNotEmpty)
                  ? '${p.projectNumber} ${p.name}'
                  : p.name,
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.visible,
            ),
            actions: [
              if (isOwner)
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => showEditProjectDialog(context, p),
                  icon: const Icon(Icons.edit),
                ),
            ],
          ),
          body: ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              _kv('Client', p.clientName),

              if ((p.contactName ?? '').isNotEmpty ||
                  (p.contactEmail ?? '').isNotEmpty ||
                  (p.contactPhone ?? '').isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Contact', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        if ((p.contactName ?? '').isNotEmpty) Text(p.contactName!),
                        if ((p.contactEmail ?? '').isNotEmpty) Text(p.contactEmail!),
                        if ((p.contactPhone ?? '').isNotEmpty) Text(p.contactPhone!),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              TasksBySubphaseSection(
                projectId: p.id,
                isOwner: isOwner,
                selectedSubphases: p.selectedSubphases,
              ),

              const SizedBox(height: 12),

              _FinancialSummaryCard(
                projectId: p.id,
                contractAmount: p.contractAmount,
              ),

              const SizedBox(height: 12),

              // Combined Invoices card with tiny yellow text toggle
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Invoices',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _setUnpaidOnly(!_unpaidOnly),
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
                        ],
                      ),

                      const SizedBox(height: 10),

                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child: Text('Client Invoices',
                            style: Theme.of(context).textTheme.labelLarge),
                      ),
                      inv.InvoicesSection(
                        projectId: p.id,
                        isOwner: isOwner,
                        projectNumberString: p.projectNumber,
                        title: '',
                        invoiceTypeFilter: 'Client',
                        wrapInCard: false,
                        showNewButton: false,
                        unpaidOnly: _unpaidOnly,
                      ),

                      const SizedBox(height: 10),

                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child: Text('Vendor Invoices',
                            style: Theme.of(context).textTheme.labelLarge),
                      ),
                      inv.InvoicesSection(
                        projectId: p.id,
                        isOwner: isOwner,
                        projectNumberString: p.projectNumber,
                        title: '',
                        invoiceTypeFilter: 'Vendor',
                        wrapInCard: false,
                        showNewButton: false,
                        unpaidOnly: _unpaidOnly,
                      ),

                      const SizedBox(height: 12),

                      if (isOwner)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: () => inv.showAddInvoiceDialog(
                              context,
                              p.id,
                              defaultProjectNumber: p.projectNumber,
                              initialInvoiceType: 'Client',
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('New Invoice'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Archive / Unarchive toggle button (full width)
              if (isOwner)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.isArchived
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      await repo.update(p.id, {'isArchived': !p.isArchived});
                    },
                    child: Text(p.isArchived ? 'Unarchive Project' : 'Archive Project'),
                  ),
                ),

              const SizedBox(height: 16),

              // Bottom row (meta + delete)
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Owner UID: ${p.ownerUid ?? '(none)'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  if (isOwner)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                      label: const Text('Delete Project',
                          style: TextStyle(color: Colors.redAccent)),
                      onPressed: () async {
                        final ok = await confirmDialog(context, 'Delete this project?');
                        if (ok) {
                          await repo.delete(p.id);
                          // ignore: use_build_context_synchronously
                          Navigator.pop(context);
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Card(
      child: ListTile(
        title: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(v),
      ),
    );
  }
}

class _FinancialSummaryCard extends StatelessWidget {
  final String projectId;
  final double? contractAmount;

  const _FinancialSummaryCard({
    required this.projectId,
    required this.contractAmount,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency();
    final currency0 = NumberFormat.simpleCurrency(decimalDigits: 0); // no cents for contract

    return StreamBuilder<List<Invoice>>(
      stream: InvoiceRepository().streamByProject(projectId),
      builder: (context, snap) {
        final invoices = snap.data ?? const <Invoice>[];

        double clientInvoiced = 0;
        double clientUnpaid = 0;
        double vendorInvoiced = 0;
        double vendorUnpaid = 0;

        for (final inv in invoices) {
          if (inv.invoiceType == 'Client') {
            clientInvoiced += inv.invoiceAmount;
            clientUnpaid += inv.balance; // amount - amountPaid
          } else if (inv.invoiceType == 'Vendor') {
            vendorInvoiced += inv.invoiceAmount;
            vendorUnpaid += inv.balance;
          }
        }

        final contract = contractAmount ?? 0.0;
        final pctInvoiced = (contract > 0) ? (clientInvoiced / contract) * 100 : 0.0;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contract Amount: ${contractAmount != null ? currency0.format(contractAmount) : '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _metricBox(
                        context,
                        label: 'Client Invoiced',
                        value: currency.format(clientInvoiced),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricBox(
                        context,
                        label: 'Balance',
                        value: currency.format(clientUnpaid),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  (contract > 0)
                      ? 'Contract Progress: ${pctInvoiced.toStringAsFixed(0)}%'
                      : 'Contract Progress: —',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _metricBox(
                        context,
                        label: 'Vendor Invoiced',
                        value: currency.format(vendorInvoiced),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _metricBox(
                        context,
                        label: 'Balance',
                        value: currency.format(vendorUnpaid),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricBox(BuildContext context, {required String label, required String value}) {
    final outline = Theme.of(context).colorScheme.outlineVariant.withOpacity(0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
