// lib/src/widgets/invoices_section.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../data/models/invoice.dart';
import '../data/models/project.dart';
import '../data/repositories/invoice_repository.dart';
import '../data/repositories/project_repository.dart';
import '../theme/tokens.dart';
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
                      return InvoiceQuickPayDismissible(
                        invoice: inv,
                        canEdit: canEdit,
                        child: InkWell(
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                            ),
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

/// Public helper so other pages can open the shared "Edit Invoice" dialog.
Future<void> showEditInvoiceDialog(
  BuildContext context,
  Invoice invoice, {
  required bool canEdit,
}) {
  return _showEditInvoiceDialog(
    context,
    invoice,
    canEdit: canEdit,
  );
}

Future<void> showQuickPayInvoiceDialog(
  BuildContext context,
  Invoice invoice, {
  required bool canEdit,
}) async {
  final payment = await _showQuickPayInvoiceDialog(
    context,
    invoice,
    canEdit: canEdit,
  );
  if (payment == null || !context.mounted) return;
  await _applyQuickPayInvoice(context, invoice, payment);
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

class InvoiceQuickPayDismissible extends StatefulWidget {
  const InvoiceQuickPayDismissible({
    super.key,
    required this.invoice,
    required this.canEdit,
    required this.child,
  });

  final Invoice invoice;
  final bool canEdit;
  final Widget child;

  @override
  State<InvoiceQuickPayDismissible> createState() =>
      _InvoiceQuickPayDismissibleState();
}

class _InvoiceQuickPayDismissibleState
    extends State<InvoiceQuickPayDismissible> {
  static const double _triggerDistance = 96;
  static const double _maxOffset = 72;

  double _dragExtent = 0;
  bool _openingDialog = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.canEdit || widget.invoice.balance <= 0.0001) {
      return widget.child;
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _resetDrag(),
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: _resetDrag,
      child: Stack(
        children: [
          Positioned.fill(child: _buildQuickPaySwipeBackground(context)),
          Transform.translate(
            offset: Offset(_dragExtent.clamp(0, _maxOffset), 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_openingDialog) return;
    final next = (_dragExtent + details.delta.dx).clamp(0.0, _triggerDistance);
    if (next == _dragExtent) return;
    setState(() => _dragExtent = next);
  }

  Future<void> _handleDragEnd(DragEndDetails details) async {
    if (_openingDialog) return;

    final shouldOpen = _dragExtent >= _triggerDistance ||
        (details.primaryVelocity != null && details.primaryVelocity! > 700);
    _resetDrag();
    if (!shouldOpen || !mounted) return;

    setState(() => _openingDialog = true);
    try {
      await showQuickPayInvoiceDialog(
        context,
        widget.invoice,
        canEdit: widget.canEdit,
      );
    } finally {
      if (mounted) {
        setState(() => _openingDialog = false);
      }
    }
  }

  void _resetDrag() {
    if (_dragExtent == 0) return;
    setState(() => _dragExtent = 0);
  }
}

Widget _buildQuickPaySwipeBackground(BuildContext context) {
  final theme = Theme.of(context);
  return Container(
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    color: theme.colorScheme.primary.withValues(alpha: 0.18),
    child: Icon(
      Icons.payments,
      color: theme.colorScheme.primary,
    ),
  );
}

class _QuickPayInvoicePayment {
  const _QuickPayInvoicePayment({
    required this.amountPaid,
    required this.paidDate,
  });

  final double amountPaid;
  final DateTime paidDate;
}

Future<_QuickPayInvoicePayment?> _showQuickPayInvoiceDialog(
  BuildContext context,
  Invoice inv, {
  required bool canEdit,
}) async {
  if (!canEdit) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'View-only: only the project owner or an admin can modify invoices.',
        ),
      ),
    );
    return null;
  }

  final today = DateTime.now();
  DateTime paidDate = DateTime(today.year, today.month, today.day);
  final amountCtl = TextEditingController(
    text: inv.invoiceAmount.toStringAsFixed(2),
  );
  final formKey = GlobalKey<FormState>();

  try {
    return await showDialog<_QuickPayInvoicePayment>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setState) {
            Future<void> pickPaidDate() async {
              final d = await showDatePicker(
                context: dialogContext,
                initialDate: paidDate,
                firstDate: DateTime(paidDate.year - 5),
                lastDate: DateTime(paidDate.year + 5),
              );
              if (d != null) {
                setState(() => paidDate = d);
              }
            }

            return AppFormDialog(
              title:
                  'Pay ${inv.invoiceNumber.isNotEmpty ? 'Invoice ${inv.invoiceNumber}' : 'Invoice'}',
              width: 420,
              actions: [
                AppDialogActions(
                  secondary: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  primary: FilledButton(
                    onPressed: () async {
                      if (!(formKey.currentState?.validate() ?? false)) {
                        return;
                      }

                      final paid = double.parse(amountCtl.text.trim());
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(
                          _QuickPayInvoicePayment(
                            amountPaid: paid,
                            paidDate: paidDate,
                          ),
                        );
                      }
                    },
                    child: const Text('Pay'),
                  ),
                ),
              ],
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    appTextField(
                      'Amount',
                      amountCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      required: true,
                      validator: (value) {
                        final raw = value?.trim() ?? '';
                        final amount = double.tryParse(raw);
                        if (amount == null) return 'Enter a valid amount';
                        if (amount < 0) return 'Amount cannot be negative';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    InkWell(
                      onTap: pickPaidDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(DateFormat.yMd().format(paidDate)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  } finally {
    amountCtl.dispose();
  }
}

Future<void> _applyQuickPayInvoice(
  BuildContext context,
  Invoice inv,
  _QuickPayInvoicePayment payment,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await InvoiceRepository().update(inv.id, {
      'amountPaid': payment.amountPaid,
      'paidDate': Timestamp.fromDate(payment.paidDate),
    });
  } catch (e) {
    if (messenger?.mounted ?? false) {
      messenger!.showSnackBar(
        SnackBar(
          content: Text('Failed to pay invoice: $e'),
        ),
      );
    }
  }
}

class _DirectExpenseDialogResult {
  const _DirectExpenseDialogResult.save(this.expense) : delete = false;
  const _DirectExpenseDialogResult.delete()
      : expense = null,
        delete = true;

  final InvoiceDirectExpense? expense;
  final bool delete;
}

Future<_DirectExpenseDialogResult?> _showDirectExpenseDialog(
  BuildContext context, {
  InvoiceDirectExpense? expense,
  bool allowDelete = false,
}) async {
  final descriptionCtl = TextEditingController(
    text: expense?.description ?? '',
  );
  final amountCtl = TextEditingController(
    text: expense == null ? '' : expense.amount.toStringAsFixed(2),
  );
  final formKey = GlobalKey<FormState>();

  try {
    return await showDialog<_DirectExpenseDialogResult>(
      context: context,
      builder: (dialogContext) => AppFormDialog(
        title: expense == null ? 'Add Direct Expense' : 'Edit Direct Expense',
        width: 420,
        actions: [
          AppDialogActions(
            leading: allowDelete
                ? TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(
                      const _DirectExpenseDialogResult.delete(),
                    ),
                    child: const Text('Delete'),
                  )
                : null,
            secondary: TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            primary: FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.of(dialogContext).pop(
                  _DirectExpenseDialogResult.save(
                    InvoiceDirectExpense(
                      description: descriptionCtl.text.trim(),
                      amount: double.parse(amountCtl.text.trim()),
                    ),
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ),
        ],
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              appTextField(
                'Description',
                descriptionCtl,
                required: true,
              ),
              const SizedBox(height: AppSpacing.md),
              appTextField(
                'Amount',
                amountCtl,
                required: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  final raw = value?.trim() ?? '';
                  final amount = double.tryParse(raw);
                  if (amount == null) return 'Enter a valid amount';
                  if (amount < 0) return 'Amount cannot be negative';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    descriptionCtl.dispose();
    amountCtl.dispose();
  }
}

class _DirectExpensesSection extends StatelessWidget {
  const _DirectExpensesSection({
    required this.expenses,
    required this.canEdit,
    required this.onAdd,
    required this.onEdit,
  });

  final List<InvoiceDirectExpense> expenses;
  final bool canEdit;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency();
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < expenses.length; i++)
          InkWell(
            onTap: canEdit ? () => onEdit(i) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      expenses[i].description,
                      style: textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    currency.format(expenses[i].amount),
                    style: textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: canEdit ? onAdd : null,
            icon: const Icon(Icons.add),
            label: const Text('Direct Expense'),
          ),
        ),
      ],
    );
  }
}

Future<void> _showAddInvoiceDialog(
  BuildContext context,
  String? projectId, {
  String? defaultProjectNumber,
  String initialInvoiceType = 'Client',
  List<Project>? projectChoices,
  String? ownerUid,
}) async {
  // Invoice amount is computed from subphase percent-complete billing rows.

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
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('You must be signed in.')));
    return;
  }
  if (selectedProject == null &&
      selectedProjectId != null &&
      selectedProjectId.isNotEmpty) {
    selectedProject = await ProjectRepository().getById(selectedProjectId);
  }
  if (selectedProject != null) {
    selectedProject = await _projectWithInvoicedAmountsFromInvoices(
      selectedProject,
    );
  }

  final now = DateTime.now();
  DateTime? invoiceDate = DateTime(now.year, now.month, now.day);

  final projectNumberCtl = TextEditingController(
    text: defaultProjectNumber ?? selectedProject?.projectNumber ?? '',
  );
  final invoiceNumberCtl = TextEditingController();
  final termsCtl = TextEditingController(text: '30');
  var billingRows = _buildBillingRows(selectedProject);
  final directExpenses = <InvoiceDirectExpense>[];

  final invoiceType = (initialInvoiceType == 'Vendor') ? 'Vendor' : 'Client';

  final formKey = GlobalKey<FormState>();
  final repo = InvoiceRepository();

  Future<void> pickInvoiceDate(BuildContext pickerContext) async {
    final seed = invoiceDate ?? DateTime.now();
    final d = await showDatePicker(
      context: pickerContext,
      initialDate: seed,
      firstDate: DateTime(seed.year - 5),
      lastDate: DateTime(seed.year + 5),
    );
    if (d != null) {
      invoiceDate = d;
    }
  }

  if (!context.mounted) return;

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setState) {
            return AppFormDialog(
              title: 'New Invoice',
              width: 540,
              actions: [
                AppDialogActions(
                  secondary: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  primary: FilledButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(dialogContext);
                      if (!(formKey.currentState?.validate() ?? false)) return;

                      final pnText = projectNumberCtl.text.trim();
                      if (pnText.isEmpty ||
                          !(await _projectNumberExists(pnText))) {
                        if (messenger.mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Project Number not found.'),
                            ),
                          );
                        }
                        return;
                      }

                      final amt = _invoiceAmountTotal(
                        billingRows,
                        directExpenses,
                      );
                      final termsDays =
                          int.tryParse(termsCtl.text.trim()) ?? 30;
                      final dueDate = invoiceDate?.add(
                        Duration(days: termsDays < 0 ? 0 : termsDays),
                      );

                      final projectNumberValue =
                          pnText.isNotEmpty ? pnText : null;

                      final targetProjectId = selectedProjectId ?? projectId;
                      if (targetProjectId == null || targetProjectId.isEmpty) {
                        if (messenger.mounted) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Select a project.')),
                          );
                        }
                        return;
                      }

                      final providedOwner = ownerUid;
                      final projectOwner = selectedProject?.ownerUid;
                      final String ownerForInvoice = (providedOwner != null &&
                              providedOwner.isNotEmpty)
                          ? providedOwner
                          : ((projectOwner != null && projectOwner.isNotEmpty)
                              ? projectOwner
                              : me.uid);
                      final resolvedOwner =
                          ownerForInvoice.isNotEmpty ? ownerForInvoice : me.uid;
                      final subphaseBillings = _buildInvoiceSubphaseBillings(
                        billingRows,
                      );
                      final inv = Invoice(
                        id: '_',
                        projectId: targetProjectId,
                        ownerUid:
                            resolvedOwner.isNotEmpty ? resolvedOwner : me.uid,
                        invoiceNumber: invoiceNumberCtl.text.trim(),
                        projectNumber: projectNumberValue,
                        invoiceAmount: amt,
                        amountPaid: 0,
                        invoiceDate: invoiceDate,
                        dueDate: dueDate,
                        invoiceType: invoiceType,
                        subphaseBillings: subphaseBillings,
                        directExpenses: List<InvoiceDirectExpense>.from(
                          directExpenses,
                        ),
                      );

                      try {
                        await repo.add(inv);
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext, rootNavigator: true).pop();
                        await _applyInvoiceSubphaseBillings(
                          targetProjectId,
                          subphaseBillings,
                        );
                      } catch (e) {
                        if (!dialogContext.mounted) return;
                        if (messenger.mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                                content: Text('Failed to create invoice: $e')),
                          );
                        }
                      }
                    },
                    child: const Text('Create'),
                  ),
                ),
              ],
              child: Form(
                key: formKey,
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
                        onChanged: (value) async {
                          if (value == null) return;
                          var nextProject = projectMap[value];
                          if (nextProject != null) {
                            nextProject =
                                await _projectWithInvoicedAmountsFromInvoices(
                              nextProject,
                            );
                          }
                          if (!dialogContext.mounted) return;
                          setState(() {
                            selectedProjectId = value;
                            _disposeBillingRows(billingRows);
                            selectedProject = nextProject;
                            billingRows = _buildBillingRows(selectedProject);
                            final suggestion =
                                (selectedProject?.projectNumber ?? '').trim();
                            if (suggestion.isNotEmpty) {
                              projectNumberCtl.text = suggestion;
                              projectNumberCtl.selection =
                                  TextSelection.fromPosition(
                                TextPosition(
                                    offset: projectNumberCtl.text.length),
                              );
                            }
                          });
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    appTextField(
                      'Project Number',
                      projectNumberCtl,
                      required: true,
                      hint: 'e.g., 026-01',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    appTextField(
                      'Invoice Number',
                      invoiceNumberCtl,
                      required: true,
                      hint: 'e.g., 1220',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _InvoiceDateField(
                            value: invoiceDate,
                            onPick: () async {
                              await pickInvoiceDate(dialogContext);
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: appTextField(
                            'Terms',
                            termsCtl,
                            dense: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SubphaseBillingTable(
                      rows: billingRows,
                      onPercentChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _DirectExpensesSection(
                      expenses: directExpenses,
                      canEdit: true,
                      onAdd: () async {
                        final result = await _showDirectExpenseDialog(
                          dialogContext,
                        );
                        final expense = result?.expense;
                        if (expense == null || !dialogContext.mounted) return;
                        setState(() => directExpenses.add(expense));
                      },
                      onEdit: (index) async {
                        final result = await _showDirectExpenseDialog(
                          dialogContext,
                          expense: directExpenses[index],
                          allowDelete: true,
                        );
                        if (result == null || !dialogContext.mounted) return;
                        setState(() {
                          if (result.delete) {
                            directExpenses.removeAt(index);
                          } else if (result.expense != null) {
                            directExpenses[index] = result.expense!;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Invoice Amount: ${NumberFormat.simpleCurrency().format(_invoiceAmountTotal(billingRows, directExpenses))}',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  } finally {
    _disposeBillingRows(billingRows);
  }
}

class _InvoiceSubphaseBillingRow {
  _InvoiceSubphaseBillingRow({
    required this.subphase,
    required this.percentCtl,
    required this.percentFocus,
    this.totalFeeOverride,
    this.previousBillingOverride,
  });

  final SelectedSubphase subphase;
  final TextEditingController percentCtl;
  final FocusNode percentFocus;
  final double? totalFeeOverride;
  final double? previousBillingOverride;

  double get totalFee => totalFeeOverride ?? subphase.contractAmount ?? 0.0;
  double get percentComplete {
    final raw = percentCtl.text.trim();
    if (raw.isEmpty) return 0.0;
    final parsed = double.tryParse(raw.replaceAll('%', ''));
    if (parsed == null || parsed.isNaN) return 0.0;
    return parsed.clamp(0.0, 100.0).toDouble();
  }

  double get totalEarned => previousBilling + currentBilling;
  double get previousBilling =>
      previousBillingOverride ?? subphase.invoicedAmount ?? 0.0;
  double get previousBillingPercent {
    if (totalFee <= 0) return 0.0;
    return (previousBilling / totalFee) * 100.0;
  }

  double get currentBilling => totalFee * (percentComplete / 100.0);
  double get cumulativeBillingPercent {
    if (totalFee <= 0) return 0.0;
    return (totalEarned / totalFee) * 100.0;
  }

  void normalizePercent() {
    final raw = percentCtl.text.trim();
    if (raw.isEmpty) return;
    final parsed = double.tryParse(raw.replaceAll('%', ''));
    if (parsed == null || parsed.isNaN) return;
    final clamped = parsed.clamp(0.0, 100.0).toDouble();
    final normalized = clamped == clamped.roundToDouble()
        ? clamped.toStringAsFixed(0)
        : clamped.toStringAsFixed(2);
    if (percentCtl.text != normalized) {
      percentCtl.text = normalized;
      percentCtl.selection = TextSelection.collapsed(
        offset: percentCtl.text.length,
      );
    }
  }

  void dispose() {
    percentFocus.dispose();
    percentCtl.dispose();
  }
}

List<_InvoiceSubphaseBillingRow> _buildBillingRows(Project? project) {
  final subphases = project?.selectedSubphases ?? const <SelectedSubphase>[];
  final rows = <_InvoiceSubphaseBillingRow>[];
  for (final subphase in subphases) {
    if ((subphase.contractAmount ?? 0) <= 0) continue;
    rows.add(
      _InvoiceSubphaseBillingRow(
        subphase: subphase,
        percentCtl: TextEditingController(
          text: '0',
        ),
        percentFocus: FocusNode(),
      ),
    );
  }
  rows.sort((a, b) => a.subphase.code.compareTo(b.subphase.code));
  return rows;
}

List<_InvoiceSubphaseBillingRow> _buildEditBillingRows(
  Project? project,
  Invoice invoice,
) {
  final subphases = project?.selectedSubphases ?? const <SelectedSubphase>[];
  final oldByCode = {
    for (final billing in invoice.subphaseBillings)
      billing.subphaseCode: billing,
  };
  final rows = <_InvoiceSubphaseBillingRow>[];

  for (final subphase in subphases) {
    final totalFee =
        subphase.contractAmount ?? oldByCode[subphase.code]?.totalFee;
    if ((totalFee ?? 0) <= 0) continue;
    final oldBilling = oldByCode.remove(subphase.code);
    final previousBilling =
        ((subphase.invoicedAmount ?? 0.0) - (oldBilling?.currentBilling ?? 0.0))
            .clamp(0.0, double.infinity)
            .toDouble();
    rows.add(
      _InvoiceSubphaseBillingRow(
        subphase: subphase,
        percentCtl: TextEditingController(
          text: _percentText(
            _percentForBilling(
              oldBilling?.currentBilling ?? 0.0,
              totalFee ?? 0.0,
            ),
          ),
        ),
        percentFocus: FocusNode(),
        totalFeeOverride: totalFee,
        previousBillingOverride: previousBilling,
      ),
    );
  }

  for (final oldBilling in oldByCode.values) {
    if (oldBilling.totalFee <= 0) continue;
    rows.add(
      _InvoiceSubphaseBillingRow(
        subphase: SelectedSubphase(
          code: oldBilling.subphaseCode,
          name: oldBilling.subphaseName,
          isDeliverable: false,
          contractAmount: oldBilling.totalFee,
        ),
        percentCtl: TextEditingController(
          text: _percentText(
            _percentForBilling(
              oldBilling.currentBilling,
              oldBilling.totalFee,
            ),
          ),
        ),
        percentFocus: FocusNode(),
        totalFeeOverride: oldBilling.totalFee,
        previousBillingOverride: oldBilling.previousBilling,
      ),
    );
  }

  rows.sort((a, b) => a.subphase.code.compareTo(b.subphase.code));
  return rows;
}

double _percentForBilling(double billing, double totalFee) {
  if (totalFee <= 0) return 0.0;
  return ((billing / totalFee) * 100).clamp(0.0, 100.0).toDouble();
}

String _percentText(double percent) {
  final clamped = percent.clamp(0.0, 100.0).toDouble();
  return clamped == clamped.roundToDouble()
      ? clamped.toStringAsFixed(0)
      : clamped.toStringAsFixed(2);
}

void _disposeBillingRows(List<_InvoiceSubphaseBillingRow> rows) {
  for (final row in rows) {
    row.dispose();
  }
}

double _sumCurrentBilling(List<_InvoiceSubphaseBillingRow> rows) {
  var total = 0.0;
  for (final row in rows) {
    total += row.currentBilling;
  }
  return total;
}

double _sumDirectExpenses(List<InvoiceDirectExpense> expenses) {
  var total = 0.0;
  for (final expense in expenses) {
    total += expense.amount;
  }
  return total;
}

double _invoiceAmountTotal(
  List<_InvoiceSubphaseBillingRow> rows,
  List<InvoiceDirectExpense> expenses,
) {
  return _sumCurrentBilling(rows) + _sumDirectExpenses(expenses);
}

List<InvoiceSubphaseBilling> _buildInvoiceSubphaseBillings(
  List<_InvoiceSubphaseBillingRow> rows,
) {
  final billings = <InvoiceSubphaseBilling>[];
  for (final row in rows) {
    if (row.currentBilling.abs() < 0.0001) continue;
    billings.add(
      InvoiceSubphaseBilling(
        subphaseCode: row.subphase.code,
        subphaseName: row.subphase.name,
        totalFee: row.totalFee,
        percentComplete: row.percentComplete,
        totalEarned: row.totalEarned,
        previousBilling: row.previousBilling,
        currentBilling: row.currentBilling,
      ),
    );
  }
  return billings;
}

Future<void> _applyInvoiceSubphaseBillings(
  String projectId,
  List<InvoiceSubphaseBilling> billings, {
  bool reverse = false,
}) async {
  if (billings.isEmpty) return;

  final repo = ProjectRepository();
  final project = await repo.getById(projectId);
  final selected = project?.selectedSubphases;
  if (selected == null || selected.isEmpty) return;

  final deltaByCode = <String, double>{};
  for (final billing in billings) {
    final delta = reverse ? -billing.currentBilling : billing.currentBilling;
    deltaByCode.update(
      billing.subphaseCode,
      (value) => value + delta,
      ifAbsent: () => delta,
    );
  }

  final updated = selected.map((subphase) {
    final delta = deltaByCode[subphase.code];
    if (delta == null) return subphase.toMap();
    final next = ((subphase.invoicedAmount ?? 0.0) + delta)
        .clamp(0.0, double.infinity)
        .toDouble();
    return subphase.copyWith(invoicedAmount: next).toMap();
  }).toList();

  await repo.update(projectId, {
    'selectedSubphases': updated,
    'contractAmount': _sumSubphaseContractAmount(updated),
  });
}

Future<void> _replaceInvoiceSubphaseBillings(
  String projectId, {
  required List<InvoiceSubphaseBilling> oldBillings,
  required List<InvoiceSubphaseBilling> newBillings,
}) async {
  final deltaByCode = <String, double>{};
  for (final billing in oldBillings) {
    deltaByCode.update(
      billing.subphaseCode,
      (value) => value - billing.currentBilling,
      ifAbsent: () => -billing.currentBilling,
    );
  }
  for (final billing in newBillings) {
    deltaByCode.update(
      billing.subphaseCode,
      (value) => value + billing.currentBilling,
      ifAbsent: () => billing.currentBilling,
    );
  }
  if (deltaByCode.values.every((delta) => delta.abs() < 0.0001)) return;

  final repo = ProjectRepository();
  final project = await repo.getById(projectId);
  final selected = project?.selectedSubphases;
  if (selected == null || selected.isEmpty) return;

  final updated = selected.map((subphase) {
    final delta = deltaByCode[subphase.code];
    if (delta == null) return subphase.toMap();
    final next = ((subphase.invoicedAmount ?? 0.0) + delta)
        .clamp(0.0, double.infinity)
        .toDouble();
    return subphase.copyWith(invoicedAmount: next).toMap();
  }).toList();

  await repo.update(projectId, {
    'selectedSubphases': updated,
    'contractAmount': _sumSubphaseContractAmount(updated),
  });
}

Future<Project> _projectWithInvoicedAmountsFromInvoices(Project project) async {
  final selected = project.selectedSubphases;
  if (selected == null || selected.isEmpty) return project;

  List<Invoice> invoices;
  try {
    invoices = await InvoiceRepository()
        .streamForProject(
          projectId: project.id,
          projectNumber: project.projectNumber,
        )
        .first;
  } catch (_) {
    return project;
  }
  final billedByCode = <String, double>{};
  for (final invoice in invoices) {
    for (final billing in invoice.subphaseBillings) {
      billedByCode.update(
        billing.subphaseCode,
        (value) => value + billing.currentBilling,
        ifAbsent: () => billing.currentBilling,
      );
    }
  }

  final updatedSubphases = selected
      .map(
        (subphase) => subphase.copyWith(
          invoicedAmount: billedByCode[subphase.code] ?? 0.0,
        ),
      )
      .toList();

  return project.copyWith(selectedSubphases: updatedSubphases);
}

double _sumSubphaseContractAmount(List<Map<String, dynamic>> subphases) {
  var total = 0.0;
  for (final subphase in subphases) {
    final amount = subphase['contractAmount'];
    if (amount is num) {
      total += amount.toDouble();
    }
  }
  return total;
}

class _InvoiceDateField extends StatelessWidget {
  const _InvoiceDateField({
    required this.value,
    required this.onPick,
    this.label = 'Invoice Date',
  });

  final DateTime? value;
  final VoidCallback onPick;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = value == null ? '--' : DateFormat.yMd().format(value!);
    return InkWell(
      onTap: onPick,
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ).copyWith(labelText: label),
        child: Text(text),
      ),
    );
  }
}

class _SubphaseBillingTable extends StatelessWidget {
  const _SubphaseBillingTable({
    required this.rows,
    required this.onPercentChanged,
  });

  final List<_InvoiceSubphaseBillingRow> rows;
  final VoidCallback onPercentChanged;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('No subphase contract amounts are set for this project.'),
      );
    }

    final currency = NumberFormat.simpleCurrency(decimalDigits: 0);
    final titleStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700);
    final detailStyle = Theme.of(context).textTheme.labelSmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 18),
          _SubphaseBillingRowView(
            row: rows[i],
            currency: currency,
            titleStyle: titleStyle,
            detailStyle: detailStyle,
            onPercentChanged: onPercentChanged,
          ),
        ],
      ],
    );
  }
}

class _SubphaseBillingRowView extends StatefulWidget {
  const _SubphaseBillingRowView({
    required this.row,
    required this.currency,
    required this.titleStyle,
    required this.detailStyle,
    required this.onPercentChanged,
  });

  final _InvoiceSubphaseBillingRow row;
  final NumberFormat currency;
  final TextStyle? titleStyle;
  final TextStyle? detailStyle;
  final VoidCallback onPercentChanged;

  @override
  State<_SubphaseBillingRowView> createState() =>
      _SubphaseBillingRowViewState();
}

class _SubphaseBillingRowViewState extends State<_SubphaseBillingRowView> {
  @override
  void initState() {
    super.initState();
    widget.row.percentFocus.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _SubphaseBillingRowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row != widget.row) {
      oldWidget.row.percentFocus.removeListener(_handleFocusChange);
      widget.row.percentFocus.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    widget.row.percentFocus.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (widget.row.percentFocus.hasFocus) return;
    widget.row.normalizePercent();
    widget.onPercentChanged();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final currency = widget.currency;
    final detailStyle = widget.detailStyle;
    final previouslyInvoicedLabel =
        '${currency.format(row.previousBilling)} (${row.previousBillingPercent.toStringAsFixed(0)}%)';
    final totalInvoicedLabel =
        '${currency.format(row.totalEarned)} (${row.cumulativeBillingPercent.toStringAsFixed(0)}%)';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${row.subphase.code} ${row.subphase.name}',
            softWrap: true,
            style: widget.titleStyle,
          ),
          const SizedBox(height: 2),
          Text(
            'Total Fee: ${currency.format(row.totalFee)}',
            style: detailStyle,
          ),
          Text(
            'Previously Invoiced: $previouslyInvoicedLabel',
            style: detailStyle,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text('Current % Complete:', style: detailStyle),
              ),
              SizedBox(
                width: 68,
                child: TextFormField(
                  controller: row.percentCtl,
                  focusNode: row.percentFocus,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.end,
                  style: detailStyle,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: '%',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) => widget.onPercentChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Current Invoice: ${currency.format(row.currentBilling)}',
            style: detailStyle,
          ),
          Text(
            'Total Invoiced: $totalInvoicedLabel',
            style: detailStyle,
          ),
        ],
      ),
    );
  }
}

String _termsFromDates(Invoice invoice) {
  final invoiceDate = invoice.invoiceDate;
  final dueDate = invoice.dueDate;
  if (invoiceDate == null || dueDate == null) return '30';
  final days = dueDate.difference(invoiceDate).inDays;
  if (days < 0) return '0';
  return days.toString();
}

Future<void> _showEditInvoiceDialog(
  BuildContext context,
  Invoice inv, {
  required bool canEdit,
}) async {
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
  final amountPaidCtl = TextEditingController(
    text: inv.amountPaid.toStringAsFixed(2),
  );
  final termsCtl = TextEditingController(text: _termsFromDates(inv));

  DateTime? invoiceDate = inv.invoiceDate;
  DateTime? paidDate = inv.paidDate;
  Project? selectedProject = await ProjectRepository().getById(inv.projectId);
  if (selectedProject != null) {
    selectedProject = await _projectWithInvoicedAmountsFromInvoices(
      selectedProject,
    );
  }
  final billingRows = _buildEditBillingRows(selectedProject, inv);
  final directExpenses = List<InvoiceDirectExpense>.from(inv.directExpenses);
  if (!context.mounted) {
    projectNumberCtl.dispose();
    invoiceNumberCtl.dispose();
    amountPaidCtl.dispose();
    termsCtl.dispose();
    _disposeBillingRows(billingRows);
    return;
  }

  final formKey = GlobalKey<FormState>();
  final repo = InvoiceRepository();

  Future<void> pickInvoiceDate(BuildContext pickerContext) async {
    final seed = invoiceDate ?? DateTime.now();
    final d = await showDatePicker(
      context: pickerContext,
      initialDate: seed,
      firstDate: DateTime(seed.year - 5),
      lastDate: DateTime(seed.year + 5),
    );
    if (d != null) {
      invoiceDate = d;
    }
  }

  Future<void> pickPaidDate(BuildContext pickerContext) async {
    final seed = paidDate ?? DateTime.now();
    final d = await showDatePicker(
      context: pickerContext,
      initialDate: seed,
      firstDate: DateTime(seed.year - 5),
      lastDate: DateTime(seed.year + 5),
    );
    if (d != null) {
      paidDate = d;
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

  try {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setState) {
            return AppFormDialog(
              title:
                  'Invoice ${inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : inv.id.substring(0, 6)}',
              width: 540,
              actions: [
                if (canEdit)
                  AppDialogActions(
                    leading: TextButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(dialogContext);
                        final ok = await confirmDialog(
                          dialogContext,
                          'Delete this invoice?',
                        );
                        if (!ok || !dialogContext.mounted) return;
                        try {
                          await repo.delete(inv.id);
                          if (!dialogContext.mounted) return;
                          Navigator.of(
                            dialogContext,
                            rootNavigator: true,
                          ).pop();
                          await _applyInvoiceSubphaseBillings(
                            inv.projectId,
                            inv.subphaseBillings,
                            reverse: true,
                          );
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          if (messenger.mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Failed to delete: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Delete'),
                    ),
                    secondary: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    primary: FilledButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(dialogContext);
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }

                        final pnText = projectNumberCtl.text.trim();
                        if (pnText.isEmpty ||
                            !(await _projectNumberExists(pnText))) {
                          if (messenger.mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Project Number not found.'),
                              ),
                            );
                          }
                          return;
                        }

                        final amt = _invoiceAmountTotal(
                          billingRows,
                          directExpenses,
                        );
                        final paid = amountPaidCtl.text.trim().isEmpty
                            ? inv.amountPaid
                            : (double.tryParse(amountPaidCtl.text.trim()) ??
                                inv.amountPaid);
                        final termsDays =
                            int.tryParse(termsCtl.text.trim()) ?? 30;
                        final dueDate = invoiceDate?.add(
                          Duration(days: termsDays < 0 ? 0 : termsDays),
                        );
                        final projectNumberValue =
                            pnText.isNotEmpty ? pnText : null;
                        final subphaseBillings =
                            _buildInvoiceSubphaseBillings(billingRows);

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
                                ? Timestamp.fromDate(dueDate)
                                : null,
                            'paidDate': paidDate != null
                                ? Timestamp.fromDate(paidDate!)
                                : null,
                            'invoiceType': inv.invoiceType,
                            'subphaseBillings':
                                subphaseBillings.map((b) => b.toMap()).toList(),
                            'directExpenses':
                                directExpenses.map((e) => e.toMap()).toList(),
                          });
                          if (!dialogContext.mounted) return;
                          Navigator.of(
                            dialogContext,
                            rootNavigator: true,
                          ).pop();
                          await _replaceInvoiceSubphaseBillings(
                            inv.projectId,
                            oldBillings: inv.subphaseBillings,
                            newBillings: subphaseBillings,
                          );
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          if (messenger.mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Failed to save: $e')),
                            );
                          }
                        }
                      },
                      child: const Text('Save'),
                    ),
                  )
                else
                  AppDialogActions(
                    primary: TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close'),
                    ),
                  ),
              ],
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    appTextField(
                      'Project Number',
                      projectNumberCtl,
                      required: true,
                      hint: 'e.g., 026-01',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    appTextField(
                      'Invoice Number',
                      invoiceNumberCtl,
                      required: true,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _InvoiceDateField(
                            value: invoiceDate,
                            onPick: () async {
                              if (!canEdit) return viewOnlyTap();
                              await pickInvoiceDate(dialogContext);
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: appTextField(
                            'Terms',
                            termsCtl,
                            dense: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SubphaseBillingTable(
                      rows: billingRows,
                      onPercentChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _DirectExpensesSection(
                      expenses: directExpenses,
                      canEdit: canEdit,
                      onAdd: () async {
                        final result = await _showDirectExpenseDialog(
                          dialogContext,
                        );
                        final expense = result?.expense;
                        if (expense == null || !dialogContext.mounted) return;
                        setState(() => directExpenses.add(expense));
                      },
                      onEdit: (index) async {
                        final result = await _showDirectExpenseDialog(
                          dialogContext,
                          expense: directExpenses[index],
                          allowDelete: true,
                        );
                        if (result == null || !dialogContext.mounted) return;
                        setState(() {
                          if (result.delete) {
                            directExpenses.removeAt(index);
                          } else if (result.expense != null) {
                            directExpenses[index] = result.expense!;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Invoice Amount: ${NumberFormat.simpleCurrency().format(_invoiceAmountTotal(billingRows, directExpenses))}',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    appTextField(
                      'Amount Paid',
                      amountPaidCtl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _InvoiceDateField(
                      label: 'Paid Date',
                      value: paidDate,
                      onPick: () async {
                        if (!canEdit) return viewOnlyTap();
                        await pickPaidDate(dialogContext);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  } finally {
    termsCtl.dispose();
    projectNumberCtl.dispose();
    invoiceNumberCtl.dispose();
    amountPaidCtl.dispose();
    _disposeBillingRows(billingRows);
  }
}
