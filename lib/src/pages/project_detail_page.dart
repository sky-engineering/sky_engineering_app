// lib/src/pages/project_detail_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/external_task.dart';
import 'package:intl/intl.dart';

import '../data/models/project.dart';
import '../data/models/invoice.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/invoice_repository.dart';

import '../widgets/form_helpers.dart';
import '../widgets/tasks_by_subphase_section.dart';
import '../widgets/external_tasks_section.dart';
import '../widgets/invoices_section.dart' as inv;
import '../dialogs/edit_project_dialog.dart';
import '../utils/phone_utils.dart';
import '../app/shell.dart';

import '../app/user_access_scope.dart';

class _TeamFieldConfig {
  const _TeamFieldConfig({required this.key, required this.label});

  final String key;
  final String label;
}

const List<_TeamFieldConfig> _teamFieldConfigs = [
  _TeamFieldConfig(key: 'teamOwner', label: 'Owner'),
  _TeamFieldConfig(key: 'teamArchitect', label: 'Architect'),
  _TeamFieldConfig(key: 'teamSurveyor', label: 'Surveyor'),
  _TeamFieldConfig(key: 'teamGeotechnical', label: 'Geotechnical'),
  _TeamFieldConfig(key: 'teamMechanical', label: 'Mechanical'),
  _TeamFieldConfig(key: 'teamStructural', label: 'Structural'),
  _TeamFieldConfig(key: 'teamElectrical', label: 'Electrical'),
  _TeamFieldConfig(key: 'teamPlumbing', label: 'Plumbing'),
  _TeamFieldConfig(key: 'teamLandscape', label: 'Landscape'),
  _TeamFieldConfig(key: 'teamContractor', label: 'Contractor'),
  _TeamFieldConfig(key: 'teamEnvironmental', label: 'Environmental'),
  _TeamFieldConfig(key: 'teamOther', label: 'Other'),
];

Map<String, String?> _teamValueMap(Project project) => {
      'teamOwner': project.teamOwner,
      'teamArchitect': project.teamArchitect,
      'teamSurveyor': project.teamSurveyor,
      'teamGeotechnical': project.teamGeotechnical,
      'teamMechanical': project.teamMechanical,
      'teamStructural': project.teamStructural,
      'teamElectrical': project.teamElectrical,
      'teamPlumbing': project.teamPlumbing,
      'teamLandscape': project.teamLandscape,
      'teamContractor': project.teamContractor,
      'teamEnvironmental': project.teamEnvironmental,
      'teamOther': project.teamOther,
    };

List<ExternalAssigneeOption> _buildExternalAssigneeOptions(
  Project project,
  User? owner,
) {
  final options = <ExternalAssigneeOption>[];

  if (owner != null) {
    final email = owner.email?.trim();
    final label =
        (email != null && email.isNotEmpty) ? 'Owner ($email)' : 'Owner';
    options
        .add(ExternalAssigneeOption(key: 'owner', label: label, value: label));
  }

  final values = _teamValueMap(project);
  for (final field in _teamFieldConfigs) {
    final value = values[field.key];
    if (value != null) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        final label = '${field.label} - $trimmed';
        options.add(
          ExternalAssigneeOption(key: field.key, label: label, value: label),
        );
      }
    }
  }

  return options;
}

class ProjectDetailPage extends StatefulWidget {
  final String projectId;
  const ProjectDetailPage({super.key, required this.projectId});

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  bool _unpaidOnly = true; // toggle for invoice filtering (default hide paid)
  final ScrollController _scrollCtrl = ScrollController();
  static const _accentYellow = Color(0xFFF1C400);

  late final ProjectRepository _projectRepo;
  StreamSubscription<Project?>? _projectSub;
  Project? _project;
  bool _isLoading = true;
  bool _notFound = false;

  @override
  void dispose() {
    _projectSub?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _projectRepo = ProjectRepository();
    _subscribeToProject(widget.projectId);
  }

  @override
  void didUpdateWidget(covariant ProjectDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _projectSub?.cancel();
      _project = null;
      _isLoading = true;
      _notFound = false;
      _subscribeToProject(widget.projectId);
    }
  }

  void _subscribeToProject(String projectId) {
    _projectSub?.cancel();
    _project = null;
    _isLoading = true;
    _notFound = false;
    _projectSub = _projectRepo.streamById(projectId).listen(
      (proj) {
        if (!mounted) return;
        final offset = _scrollCtrl.hasClients ? _scrollCtrl.offset : null;
        setState(() {
          _project = proj;
          _isLoading = false;
          _notFound = proj == null;
        });
        _restoreScrollOffset(offset);
      },
      onError: (_) {
        if (!mounted) return;
        final offset = _scrollCtrl.hasClients ? _scrollCtrl.offset : null;
        setState(() {
          _isLoading = false;
          _notFound = true;
        });
        _restoreScrollOffset(offset);
      },
    );
  }

  void _setUnpaidOnly(bool v) {
    final offset = _scrollCtrl.hasClients ? _scrollCtrl.offset : null;
    setState(() => _unpaidOnly = v);
    _restoreScrollOffset(offset);
  }

  void _restoreScrollOffset(double? offset) {
    if (offset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final maxScroll = _scrollCtrl.position.maxScrollExtent;
      final clamped = offset.clamp(0.0, maxScroll) as num;
      final target = clamped.toDouble();
      if ((_scrollCtrl.offset - target).abs() > 0.5) {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final project = _project;
    if (_notFound || project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Project')),
        body: const Center(child: Text('Project not found')),
      );
    }

    final isOwner = project.ownerUid != null && project.ownerUid == me?.uid;
    final scopedAccess = UserAccessScope.maybeOf(context);
    final access = scopedAccess ?? UserAccessController.instance.current;
    final isAdmin = access?.isAdmin ?? false;
    final canManageProject = isOwner || isAdmin;
    debugPrint(
        "Project ${project.id} owner=${project.ownerUid ?? '(none)'} isOwner=$isOwner isAdmin=$isAdmin (user=${me?.uid ?? '(none)'} type=${access?.profile?.userType ?? '(null)'})");
    final ownerUser = isOwner ? me : null;
    final assigneeOptions = _buildExternalAssigneeOptions(project, ownerUser);
    final editorOwnerUid =
        (project.ownerUid != null && project.ownerUid!.isNotEmpty)
            ? project.ownerUid!
            : (me?.uid ?? '');
    final phoneDisplay = formatPhoneForDisplay(project.contactPhone);
    final schedulingNotes = project.schedulingNotes?.trim() ?? '';
    final hasTeamEntries = _teamValueMap(project).values.any((value) {
      if (value == null) return false;
      return value.trim().isNotEmpty;
    });
    final showSchedulingCard = canManageProject || schedulingNotes.isNotEmpty;
    final showTeamCard = canManageProject || hasTeamEntries;
    final externalTasks = project.externalTasks ?? const <ExternalTask>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          (project.projectNumber != null &&
                  project.projectNumber!.trim().isNotEmpty)
              ? '${project.projectNumber} ${project.name}'
              : project.name,
          maxLines: 2,
          softWrap: true,
          overflow: TextOverflow.visible,
        ),
        actions: [
          if (canManageProject)
            IconButton(
              tooltip: 'Edit',
              onPressed: () => showEditProjectDialog(context, project),
              icon: const Icon(Icons.edit),
            ),
        ],
      ),
      bottomNavigationBar: const ShellBottomNav(popCurrentRoute: true),
      body: ListView(
        controller: _scrollCtrl,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _kv(context, 'Client', project.clientName),
          if ((project.contactName ?? '').isNotEmpty ||
              (project.contactEmail ?? '').isNotEmpty ||
              phoneDisplay.isNotEmpty)
            Card(
              color: _subtleSurfaceTint(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contact',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    if ((project.contactName ?? '').isNotEmpty)
                      Text(project.contactName!),
                    if ((project.contactEmail ?? '').isNotEmpty)
                      Text(project.contactEmail!),
                    if (phoneDisplay.isNotEmpty) Text(phoneDisplay),
                  ],
                ),
              ),
            ),
          if (showSchedulingCard)
            Card(
              color: _subtleSurfaceTint(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Scheduling Notes',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (canManageProject)
                          IconButton(
                            tooltip: 'Edit scheduling notes',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            onPressed: () => _showSchedulingNotesDialog(
                              context,
                              project,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (schedulingNotes.isNotEmpty)
                      Text(
                        schedulingNotes,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      Text(
                        canManageProject
                            ? 'No scheduling notes yet.'
                            : 'No scheduling notes to display.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (showTeamCard) ...[
            _projectTeamCard(context, project, canEdit: canManageProject),
            const SizedBox(height: 16),
          ],
          TasksBySubphaseSection(
            projectId: project.id,
            canEdit: canManageProject,
            selectedSubphases: project.selectedSubphases,
            ownerUidForWrites: editorOwnerUid,
          ),
          const SizedBox(height: 12),
          ExternalTasksSection(
            projectId: project.id,
            canEdit: canManageProject,
            assigneeOptions: assigneeOptions,
            tasks: externalTasks,
          ),
          const SizedBox(height: 12),
          _FinancialSummaryCard(
            projectId: project.id,
            projectNumber: project.projectNumber,
            contractAmount: project.contractAmount,
          ),
          const SizedBox(height: 12),
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
                        style: Theme.of(context).textTheme.titleLarge,
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
                          _unpaidOnly
                              ? 'Show Paid Invoices'
                              : 'Hide Paid Invoices',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
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
                    child: Text(
                      'Client Invoices',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  inv.InvoicesSection(
                    projectId: project.id,
                    canEdit: canManageProject,
                    projectNumberString: project.projectNumber,
                    title: '',
                    invoiceTypeFilter: 'Client',
                    wrapInCard: false,
                    showNewButton: false,
                    unpaidOnly: _unpaidOnly,
                    ownerUidForWrites: editorOwnerUid,
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      'Vendor Invoices',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  inv.InvoicesSection(
                    projectId: project.id,
                    canEdit: canManageProject,
                    projectNumberString: project.projectNumber,
                    title: '',
                    invoiceTypeFilter: 'Vendor',
                    wrapInCard: false,
                    showNewButton: false,
                    unpaidOnly: _unpaidOnly,
                    ownerUidForWrites: editorOwnerUid,
                  ),
                  const SizedBox(height: 12),
                  if (canManageProject)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FloatingActionButton(
                        heroTag: null,
                        backgroundColor: _accentYellow,
                        foregroundColor: Colors.black,
                        onPressed: () => inv.showAddInvoiceDialog(
                          context,
                          project.id,
                          defaultProjectNumber: project.projectNumber,
                          initialInvoiceType: 'Client',
                          ownerUid: editorOwnerUid,
                        ),
                        child: const Icon(Icons.add),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Owner UID: ${project.ownerUid ?? '(none)'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              if (canManageProject)
                TextButton.icon(
                  icon: const Icon(
                    Icons.delete_forever,
                    color: Colors.redAccent,
                  ),
                  label: const Text(
                    'Delete Project',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      'Delete this project?',
                    );
                    if (ok) {
                      await _projectRepo.delete(project.id);
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _projectTeamCard(
    BuildContext context,
    Project project, {
    required bool canEdit,
  }) {
    final theme = Theme.of(context);
    final values = _teamValueMap(project);
    final entries = <MapEntry<String, String>>[];

    for (final field in _teamFieldConfigs) {
      final value = values[field.key];
      if (value == null) continue;
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      entries.add(MapEntry(field.label, trimmed));
    }

    final hasEntries = entries.isNotEmpty;
    final headerStyle = theme.textTheme.titleLarge;
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    final prompt =
        canEdit ? 'Tap to add project partners' : 'No project partners listed';

    return Card(
      color: _subtleSurfaceTint(context),
      child: InkWell(
        onTap: canEdit ? () => _editProjectTeam(project) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Project Team', style: headerStyle)),
                  if (canEdit)
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (hasEntries)
                ...entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${entry.key}: ', style: labelStyle),
                          TextSpan(
                            text: entry.value,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Text(
                  prompt,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editProjectTeam(Project project) async {
    final initialValues = _teamValueMap(project);
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (dialogContext) {
        return _EditProjectTeamDialog(initialValues: initialValues);
      },
    );

    if (result == null) return;

    final updates = <String, dynamic>{};
    var hasChanges = false;
    for (final field in _teamFieldConfigs) {
      final key = field.key;
      final initial = (initialValues[key] ?? '').trim();
      final normalizedInitial = initial.isEmpty ? null : initial;
      final updated = result[key]?.trim();
      final normalizedUpdated =
          (updated == null || updated.isEmpty) ? null : updated;
      if (normalizedInitial != normalizedUpdated) {
        updates[key] = normalizedUpdated;
        hasChanges = true;
      }
    }

    if (!hasChanges) return;

    try {
      await _projectRepo.update(project.id, updates);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Project team updated')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  Color _subtleSurfaceTint(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Color.alphaBlend(const Color(0x14FFFFFF), surface);
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Card(
      color: _subtleSurfaceTint(context),
      child: ListTile(
        title: Text(k, style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text(v),
      ),
    );
  }
}

class _EditProjectTeamDialog extends StatefulWidget {
  const _EditProjectTeamDialog({required this.initialValues});

  final Map<String, String?> initialValues;

  @override
  State<_EditProjectTeamDialog> createState() => _EditProjectTeamDialogState();
}

class _EditProjectTeamDialogState extends State<_EditProjectTeamDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in _teamFieldConfigs)
        field.key: TextEditingController(
          text: widget.initialValues[field.key] ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String?> _collectUpdates() {
    final updates = <String, String?>{};
    for (final field in _teamFieldConfigs) {
      final text = _controllers[field.key]!.text.trim();
      updates[field.key] = text.isEmpty ? null : text;
    }
    return updates;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Project Team'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < _teamFieldConfigs.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == _teamFieldConfigs.length - 1 ? 0 : 8,
                ),
                child: appTextField(
                  _teamFieldConfigs[i].label,
                  _controllers[_teamFieldConfigs[i].key]!,
                  dense: true,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(_collectUpdates());
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _FinancialSummaryCard extends StatelessWidget {
  final String projectId;
  final String? projectNumber;
  final double? contractAmount;

  const _FinancialSummaryCard({
    required this.projectId,
    required this.projectNumber,
    required this.contractAmount,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency();
    final currency0 = NumberFormat.simpleCurrency(
      decimalDigits: 0,
    ); // no cents for contract

    return StreamBuilder<List<Invoice>>(
      stream: InvoiceRepository().streamForProject(
        projectId: projectId,
        projectNumber: projectNumber,
      ),
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
        final pctInvoiced =
            (contract > 0) ? (clientInvoiced / contract) * 100 : 0.0;
        final theme = Theme.of(context);
        final surface = theme.colorScheme.surface;
        final cardColor = Color.alphaBlend(const Color(0x14FFFFFF), surface);

        return Card(
          color: cardColor,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contract Amount: ${contractAmount != null ? currency0.format(contractAmount) : '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  (contract > 0)
                      ? 'Contract Progress: ${pctInvoiced.toStringAsFixed(0)}%'
                      : 'Contract Progress: —',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
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

  Widget _metricBox(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final outline = Theme.of(
      context,
    ).colorScheme.outlineVariant.withValues(alpha: 0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

Future<void> _showSchedulingNotesDialog(
  BuildContext context,
  Project project,
) async {
  var notesText = project.schedulingNotes ?? '';
  final repo = ProjectRepository();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Scheduling Notes'),
        content: TextFormField(
          initialValue: notesText,
          maxLines: 5,
          onChanged: (value) => notesText = value,
          decoration: const InputDecoration(
            hintText: 'Enter scheduling notes',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final text = notesText.trim();
              await repo.update(project.id, {
                'schedulingNotes': text.isEmpty ? null : text,
              });
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}
