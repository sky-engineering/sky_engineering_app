import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models/project.dart';
import '../data/models/invoice.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/invoice_repository.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_scaffold.dart';

enum _SnapshotSort { project, remaining, contract }

class ContractSnapshotPage extends StatefulWidget {
  const ContractSnapshotPage({super.key});

  @override
  State<ContractSnapshotPage> createState() => _ContractSnapshotPageState();
}

class _ContractSnapshotPageState extends State<ContractSnapshotPage> {
  final ProjectRepository _projectRepo = ProjectRepository();
  final InvoiceRepository _invoiceRepo = InvoiceRepository();
  _SnapshotSort _sortColumn = _SnapshotSort.project;
  bool _ascending = true;

  void _toggleSort(_SnapshotSort column) {
    setState(() {
      if (_sortColumn == column) {
        _ascending = !_ascending;
      } else {
        _sortColumn = column;
        _ascending = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency();

    return AppPageScaffold(
      title: 'Contract Snapshot',
      useSafeArea: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      body: StreamBuilder<List<Project>>(
        stream: _projectRepo.streamAll(),
        builder: (context, projectSnap) {
          if (projectSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (projectSnap.hasError) {
            return Center(
              child: Text('Failed to load projects: ${projectSnap.error}'),
            );
          }
          final projects = projectSnap.data ?? const <Project>[];
          if (projects.isEmpty) {
            return const Center(child: Text('No projects found.'));
          }

          return StreamBuilder<List<Invoice>>(
            stream: _invoiceRepo.streamAll(),
            builder: (context, invoiceSnap) {
              if (invoiceSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (invoiceSnap.hasError) {
                return Center(
                  child: Text('Failed to load invoices: ${invoiceSnap.error}'),
                );
              }

              final invoices = invoiceSnap.data ?? const <Invoice>[];
              final totalsByProject = <String, double>{};
              final invoicesByProject = <String, List<Invoice>>{};
              for (final invoice in invoices) {
                if (invoice.invoiceType != 'Client') continue;
                final projNumber = (invoice.projectNumber ?? '').trim();
                if (projNumber.isEmpty) continue;
                totalsByProject.update(
                  projNumber,
                  (value) => value + invoice.invoiceAmount,
                  ifAbsent: () => invoice.invoiceAmount,
                );
                (invoicesByProject[projNumber] ??= <Invoice>[]).add(invoice);
              }

              final theme = Theme.of(context);
              final rowTextStyle =
                  theme.textTheme.bodySmall?.copyWith(height: 1.2);
              final projectStyle = rowTextStyle?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              );
              final remainingStyle = rowTextStyle?.copyWith(
                color: AppColors.accentYellow,
                fontWeight: FontWeight.w600,
              );

              final rows = projects.map((project) {
                final projectNumber = (project.projectNumber ?? '').trim();
                final totalInvoiced = projectNumber.isNotEmpty
                    ? (totalsByProject[projectNumber] ?? 0.0)
                    : 0.0;
                final contractAmount = project.contractAmount ?? 0.0;
                final double? remaining =
                    contractAmount > 0 ? contractAmount - totalInvoiced : null;
                final projectLabel = projectNumber.isNotEmpty
                    ? '$projectNumber • ${project.name}'
                    : project.name;
                final projectInvoices = List<Invoice>.from(
                  projectNumber.isNotEmpty
                      ? (invoicesByProject[projectNumber] ?? const [])
                      : const [],
                );
                return _SnapshotRow(
                  label: projectLabel,
                  remaining: remaining,
                  contractAmount: contractAmount,
                  totalInvoiced: totalInvoiced,
                  invoices: projectInvoices,
                );
              }).toList();

              rows.sort((a, b) {
                int cmp;
                switch (_sortColumn) {
                  case _SnapshotSort.project:
                    cmp =
                        a.label.toLowerCase().compareTo(b.label.toLowerCase());
                    break;
                  case _SnapshotSort.remaining:
                    final aVal = a.remaining ?? 0.0;
                    final bVal = b.remaining ?? 0.0;
                    cmp = aVal.compareTo(bVal);
                    break;
                  case _SnapshotSort.contract:
                    cmp = a.contractAmount.compareTo(b.contractAmount);
                    break;
                }
                return _ascending ? cmp : -cmp;
              });

              Widget buildHeader() {
                final headerStyle = rowTextStyle?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                );

                Widget headerCell(String label, _SnapshotSort column) {
                  final isActive = _sortColumn == column;
                  final arrow = isActive ? (_ascending ? ' ↑' : ' ↓') : '';
                  return TextButton(
                    onPressed: () => _toggleSort(column),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('$label$arrow', style: headerStyle),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: headerCell('Project', _SnapshotSort.project),
                      ),
                      Expanded(
                        flex: 1,
                        child: headerCell('Remaining', _SnapshotSort.remaining),
                      ),
                      Expanded(
                        flex: 1,
                        child: headerCell('Contract', _SnapshotSort.contract),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                itemCount: rows.length + 1,
                separatorBuilder: (_, index) => index == 0
                    ? const SizedBox.shrink()
                    : const Divider(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return buildHeader();
                  }

                  final row = rows[index - 1];

                  return InkWell(
                    onTap: () => _showProjectBreakdown(
                      context,
                      row,
                      currency,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Padding(
                            padding:
                                const EdgeInsets.only(right: AppSpacing.sm),
                            child: Text(
                              row.label,
                              style: projectStyle,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            row.remaining != null
                                ? currency.format(row.remaining!)
                                : '--',
                            style: remainingStyle,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            row.contractAmount > 0
                                ? currency.format(row.contractAmount)
                                : '--',
                            style: rowTextStyle,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showProjectBreakdown(
    BuildContext context,
    _SnapshotRow row,
    NumberFormat currency,
  ) {
    final invoices = row.invoices.toList()
      ..sort((a, b) {
        final aDate = a.invoiceDate ??
            a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.invoiceDate ??
            b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(row.label),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Contract: ${currency.format(row.contractAmount)}'),
                Text('Invoiced: ${currency.format(row.totalInvoiced)}'),
                const SizedBox(height: AppSpacing.sm),
                const Divider(),
                if (invoices.isEmpty)
                  const Text('No invoices yet.')
                else
                  ...invoices.map(
                    (invoice) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        invoice.invoiceNumber.isNotEmpty
                            ? invoice.invoiceNumber
                            : 'Invoice',
                      ),
                      trailing: Text(currency.format(invoice.invoiceAmount)),
                    ),
                  ),
                const Divider(),
                Text(
                  'Remaining: ${row.remaining != null ? currency.format(row.remaining!) : '--'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _SnapshotRow {
  _SnapshotRow({
    required this.label,
    required this.remaining,
    required this.contractAmount,
    required this.totalInvoiced,
    required this.invoices,
  });

  final String label;
  final double? remaining;
  final double contractAmount;
  final double totalInvoiced;
  final List<Invoice> invoices;
}
