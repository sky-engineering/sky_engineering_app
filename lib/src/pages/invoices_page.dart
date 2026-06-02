// lib/src/pages/invoices_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models/invoice.dart';
import '../data/models/project.dart';
import '../data/repositories/invoice_repository.dart';
import '../data/repositories/project_repository.dart';
import '../dialogs/quick_actions.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_scaffold.dart';
import '../widgets/invoices_section.dart' as invoice_dialogs;

enum _InvoiceSort {
  projectNumberAsc,
  invoiceNumberAsc,
  dateDesc,
}

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  /// When true, only invoices with balance > 0 are shown.
  bool _unpaidOnly = true;

  /// Cache of projectId -> display project number string (from Project.projectNumber).
  final Map<String, String> _projectNumById = <String, String>{};

  /// Cache of projectId -> client display name.
  final Map<String, String> _clientNameById = <String, String>{};

  /// Current invoice type filter. Only 'Client' or 'Vendor'.
  String _typeFilter = 'Client';

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  _InvoiceSort _sortMode = _InvoiceSort.projectNumberAsc;

  final _invoiceRepo = InvoiceRepository();
  final _projectRepo = ProjectRepository();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency();
    final dateFormat = DateFormat('MM/dd/yy');

    final filterCard = SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
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
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: () => setState(() => _unpaidOnly = !_unpaidOnly),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.accentYellow,
                ),
                child: Text(
                  _unpaidOnly ? 'Show Paid Invoices' : 'Hide Paid Invoices',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.accentYellow,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search invoices...',
              border: const OutlineInputBorder(),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: const Icon(Icons.clear),
                    )
                  : null,
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                'Sort by:',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(width: AppSpacing.sm),
              DropdownButton<_InvoiceSort>(
                value: _sortMode,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _sortMode = value);
                },
                items: const [
                  DropdownMenuItem(
                    value: _InvoiceSort.projectNumberAsc,
                    child: Text('Project Number'),
                  ),
                  DropdownMenuItem(
                    value: _InvoiceSort.invoiceNumberAsc,
                    child: Text('Invoice Number'),
                  ),
                  DropdownMenuItem(
                    value: _InvoiceSort.dateDesc,
                    child: Text('Date (newest first)'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return AppPageScaffold(
      useSafeArea: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      fabLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton(
        heroTag: 'dashboard-quick',
        onPressed: () => showQuickAddInvoiceDialog(context),
        backgroundColor: AppColors.accentYellow,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          filterCard,
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: _buildInvoiceList(context, currency, dateFormat),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceList(
    BuildContext context,
    NumberFormat currency,
    DateFormat dateFormat,
  ) {
    return StreamBuilder<List<Project>>(
      stream: _projectRepo.streamAll(),
      builder: (context, projSnap) {
        final projects = projSnap.data ?? const <Project>[];
        _projectNumById
          ..clear()
          ..addEntries(
            projects.map(
              (p) => MapEntry(p.id, (p.projectNumber ?? '').trim()),
            ),
          );
        _clientNameById
          ..clear()
          ..addEntries(
            projects.map((p) => MapEntry(p.id, p.clientName.trim())),
          );

        return StreamBuilder<List<Invoice>>(
          stream: _invoiceRepo.streamAll(),
          builder: (context, invSnap) {
            if (invSnap.connectionState == ConnectionState.waiting ||
                projSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            var invoices = invSnap.data ?? const <Invoice>[];
            invoices =
                invoices.where((i) => i.invoiceType == _typeFilter).toList();

            if (_unpaidOnly) {
              invoices = invoices.where((i) => i.balance > 0.0001).toList();
            }

            if (_searchQuery.trim().isNotEmpty) {
              invoices = invoices.where(_matchesSearch).toList();
            }

            invoices.sort(_compareInvoices);

            final totalUnpaid = invoices.fold<double>(
              0.0,
              (total, inv) => total + (inv.balance > 0 ? inv.balance : 0.0),
            );
            final summaryLabel = (_typeFilter == 'Client')
                ? 'Total Unpaid (Clients)'
                : 'Total Unpaid (Vendors)';
            final hasFilters = _unpaidOnly || _searchQuery.trim().isNotEmpty;

            if (invoices.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Text(
                      '$summaryLabel: ${currency.format(totalUnpaid)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          hasFilters
                              ? 'No ${_typeFilter.toLowerCase()} invoices match your filters.'
                              : 'No ${_typeFilter.toLowerCase()} invoices yet.',
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Text(
                    '$summaryLabel: ${currency.format(totalUnpaid)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      AppSpacing.sm,
                      AppSpacing.sm,
                      AppSpacing.xl * 2,
                    ),
                    itemCount: invoices.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final inv = invoices[i];
                      final projNum = _projectNumById[inv.projectId];
                      final displayProj =
                          (projNum != null && projNum.isNotEmpty)
                              ? projNum
                              : (inv.projectNumber?.toString() ?? '--');
                      final invoiceDateLabel = inv.invoiceDate != null
                          ? dateFormat.format(inv.invoiceDate!)
                          : '--/--/--';

                      return invoice_dialogs.InvoiceQuickPayDismissible(
                        invoice: inv,
                        canEdit: true,
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            dense: true,
                            visualDensity: const VisualDensity(vertical: -2),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
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
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  currency.format(inv.balance),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              'Project: $displayProj  -  Original: ${currency.format(inv.invoiceAmount)}  -  $invoiceDateLabel',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => invoice_dialogs.showEditInvoiceDialog(
                              context,
                              inv,
                              canEdit: true,
                            ),
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
    );
  }

  // -------- actions / helpers --------

  bool _matchesSearch(Invoice invoice) {
    final rawQuery = _searchQuery.trim();
    if (rawQuery.isEmpty) {
      return true;
    }

    final tokens = rawQuery
        .split(',')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList();

    if (tokens.isEmpty) {
      tokens.add(rawQuery);
    }

    for (final token in tokens) {
      if (_matchesSingleQuery(invoice, token.toLowerCase())) {
        return true;
      }
    }

    return false;
  }

  bool _matchesSingleQuery(Invoice invoice, String query) {
    if (query.isEmpty) {
      return true;
    }

    final fields = <String>[
      invoice.invoiceNumber,
      invoice.projectNumber ?? '',
      _projectNumById[invoice.projectId] ?? '',
      _clientNameById[invoice.projectId] ?? '',
    ];

    for (final field in fields) {
      if (field.toLowerCase().contains(query)) {
        return true;
      }
    }

    final numericQuery = query.replaceAll(RegExp(r'[^0-9.]'), '');
    if (numericQuery.isEmpty) {
      return false;
    }

    final numberFields = <String>[
      invoice.invoiceAmount.toStringAsFixed(2),
      invoice.invoiceAmount.toStringAsFixed(0),
      invoice.balance.toStringAsFixed(2),
      invoice.balance.toStringAsFixed(0),
      invoice.amountPaid.toStringAsFixed(2),
      invoice.amountPaid.toStringAsFixed(0),
    ];

    for (final value in numberFields) {
      if (value.contains(numericQuery)) {
        return true;
      }
    }

    return false;
  }

  int _compareInvoices(Invoice a, Invoice b) {
    return switch (_sortMode) {
      _InvoiceSort.projectNumberAsc => _compareByProjectAsc(a, b),
      _InvoiceSort.invoiceNumberAsc => _compareByNumberAsc(a, b),
      _InvoiceSort.dateDesc => _compareByDateDesc(a, b),
    };
  }

  String _projectNumberFor(Invoice invoice) {
    return (_projectNumById[invoice.projectId]?.trim() ?? '').toLowerCase();
  }

  int _compareByProjectAsc(Invoice a, Invoice b) {
    final aNumber = _projectNumberFor(a);
    final bNumber = _projectNumberFor(b);
    final aEmpty = aNumber.isEmpty;
    final bEmpty = bNumber.isEmpty;
    if (aEmpty && !bEmpty) return 1;
    if (!aEmpty && bEmpty) return -1;
    if (!aEmpty && !bEmpty) {
      final cmp = aNumber.toLowerCase().compareTo(bNumber.toLowerCase());
      if (cmp != 0) return cmp;
    }
    return _compareByNumberAsc(a, b);
  }

  int _compareByNumberAsc(Invoice a, Invoice b) {
    final aDigits = _invoiceNumberDigits(a.invoiceNumber);
    final bDigits = _invoiceNumberDigits(b.invoiceNumber);

    if (aDigits != null && bDigits != null && aDigits != bDigits) {
      return aDigits.compareTo(bDigits);
    }

    if (aDigits == null && bDigits != null) {
      return 1;
    }

    if (aDigits != null && bDigits == null) {
      return -1;
    }

    final textCmp = a.invoiceNumber.toLowerCase().compareTo(
          b.invoiceNumber.toLowerCase(),
        );
    if (textCmp != 0) {
      return textCmp;
    }

    return _compareByDateDesc(a, b);
  }

  int _compareByDateDesc(Invoice a, Invoice b) {
    final ad = a.invoiceDate ?? a.createdAt ?? a.updatedAt;
    final bd = b.invoiceDate ?? b.createdAt ?? b.updatedAt;
    if (ad != null && bd != null) {
      return bd.compareTo(ad);
    }
    if (ad == null && bd != null) {
      return 1;
    }
    if (ad != null && bd == null) {
      return -1;
    }
    return b.id.compareTo(a.id);
  }

  int? _invoiceNumberDigits(String value) {
    final digits = RegExp(
      r'[0-9]+',
    ).allMatches(value).map((match) => match.group(0)!).join();
    if (digits.isEmpty) {
      return null;
    }
    return int.tryParse(digits);
  }
}
