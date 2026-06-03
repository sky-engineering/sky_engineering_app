// lib/src/pages/project_detail_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/models/external_task.dart';
import 'package:intl/intl.dart';
import '../utils/external_task_utils.dart';

import '../data/models/project.dart';
import '../data/models/invoice.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/invoice_repository.dart';
import '../integrations/dropbox/dropbox_api.dart';
import '../integrations/dropbox/dropbox_auth.dart';

import '../widgets/form_helpers.dart';
import '../widgets/tasks_by_subphase_section.dart';
import '../widgets/external_tasks_section.dart';
import '../widgets/invoices_section.dart' as inv;
import '../dialogs/edit_project_dialog.dart';
import '../utils/phone_utils.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_scaffold.dart';

import '../app/user_access_scope.dart';

class ProjectDetailPage extends StatefulWidget {
  final String projectId;
  const ProjectDetailPage({super.key, required this.projectId});

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  bool _unpaidOnly = true; // toggle for invoice filtering (default hide paid)
  final ScrollController _scrollCtrl = ScrollController();

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
      return const AppPageScaffold(
        title: 'Project',
        includeShellBottomNav: true,
        popShellRoute: true,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final project = _project;
    if (_notFound || project == null) {
      return const AppPageScaffold(
        title: 'Project',
        includeShellBottomNav: true,
        popShellRoute: true,
        body: Center(child: Text('Project not found')),
      );
    }

    final isOwner = project.ownerUid != null && project.ownerUid == me?.uid;
    final scopedAccess = UserAccessScope.maybeOf(context);
    final access = scopedAccess ?? UserAccessController.instance.current;
    final isAdmin = access?.isAdmin ?? false;
    final canManageProject = isOwner || isAdmin;
    debugPrint(
        "Project ${project.id} owner=${project.ownerUid ?? '(none)'} isOwner=$isOwner isAdmin=$isAdmin (user=${me?.uid ?? '(none)'} type=${access?.profile?.userType ?? '(null)'})");
    final ownerEmail = isOwner ? me?.email : null;
    final assigneeOptions = buildExternalAssigneeOptions(
      project,
      ownerEmail: ownerEmail,
    );
    final editorOwnerUid =
        (project.ownerUid != null && project.ownerUid!.isNotEmpty)
            ? project.ownerUid!
            : (me?.uid ?? '');
    final hasTeamEntries = projectTeamValueMap(project).values.any((value) {
      if (value == null) return false;
      return value.trim().isNotEmpty;
    });
    final showTeamCard = canManageProject || hasTeamEntries;
    final externalTasks = project.externalTasks ?? const <ExternalTask>[];

    return AppPageScaffold(
      includeShellBottomNav: true,
      popShellRoute: true,
      padding: EdgeInsets.zero,
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
      body: ListView(
        controller: _scrollCtrl,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            color: _subtleSurfaceTint(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Client: ${project.clientName}',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Client contact',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      visualDensity: VisualDensity.compact,
                      iconSize: 17,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      icon: const Icon(Icons.contact_page_outlined),
                      onPressed: () => _showClientContactDialog(project),
                    ),
                  ],
                ),
                if (showTeamCard) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.sm),
                  _projectTeamInfo(context, project, canEdit: canManageProject),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
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
          SectionCard(
            header: SectionHeader(
              title: 'Invoices',
              action: TextButton(
                onPressed: () => _setUnpaidOnly(!_unpaidOnly),
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
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
                const SizedBox(height: AppSpacing.md),
                if (canManageProject)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FloatingActionButton(
                      heroTag: null,
                      backgroundColor: AppColors.accentYellow,
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
          const SizedBox(height: 12),
          _FinancialSummaryCard(
            projectId: project.id,
            projectNumber: project.projectNumber,
            contractAmount: project.contractAmount,
            folderName: project.folderName,
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

  Future<void> _showClientContactDialog(Project project) async {
    final theme = Theme.of(context);
    final phoneDisplay = formatPhoneForDisplay(project.contactPhone);
    final contactName = project.contactName?.trim() ?? '';
    final contactEmail = project.contactEmail?.trim() ?? '';
    final hasContact = contactName.isNotEmpty ||
        phoneDisplay.isNotEmpty ||
        contactEmail.isNotEmpty;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Client Contact'),
          content: hasContact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (contactName.isNotEmpty)
                      Text(contactName, style: theme.textTheme.bodyMedium),
                    if (phoneDisplay.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(phoneDisplay, style: theme.textTheme.bodyMedium),
                    ],
                    if (contactEmail.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(contactEmail, style: theme.textTheme.bodyMedium),
                    ],
                  ],
                )
              : Text(
                  'No client contact details listed.',
                  style: theme.textTheme.bodyMedium,
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

  Widget _projectTeamInfo(
    BuildContext context,
    Project project, {
    required bool canEdit,
  }) {
    final theme = Theme.of(context);
    final values = projectTeamValueMap(project);
    final entries = <MapEntry<String, String>>[];

    for (final field in kProjectTeamFields) {
      final value = values[field.key];
      if (value == null) continue;
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      entries.add(MapEntry(field.label, trimmed));
    }

    final hasEntries = entries.isNotEmpty;
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    final prompt =
        canEdit ? 'Tap to add project partners' : 'No project partners listed';

    final content = hasEntries
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries
                .map(
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
                .toList(),
          )
        : Text(
            prompt,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );

    if (!canEdit) return content;

    return InkWell(
      onTap: () => _editProjectTeam(project),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: content),
            Icon(
              Icons.edit_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editProjectTeam(Project project) async {
    final initialValues = projectTeamValueMap(project);
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (dialogContext) {
        return _EditProjectTeamDialog(initialValues: initialValues);
      },
    );

    if (result == null) return;

    final updates = <String, dynamic>{};
    var hasChanges = false;
    for (final field in kProjectTeamFields) {
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
      for (final field in kProjectTeamFields)
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
    for (final field in kProjectTeamFields) {
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
            for (var i = 0; i < kProjectTeamFields.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == kProjectTeamFields.length - 1 ? 0 : 8,
                ),
                child: appTextField(
                  kProjectTeamFields[i].label,
                  _controllers[kProjectTeamFields[i].key]!,
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

class _FinancialSummaryCard extends StatefulWidget {
  final String projectId;
  final String? projectNumber;
  final double? contractAmount;
  final String? folderName;

  const _FinancialSummaryCard({
    required this.projectId,
    required this.projectNumber,
    required this.contractAmount,
    required this.folderName,
  });

  @override
  State<_FinancialSummaryCard> createState() => _FinancialSummaryCardState();
}

class _FinancialSummaryCardState extends State<_FinancialSummaryCard> {
  final DropboxAuth _dropboxAuth = DropboxAuth();
  late final DropboxApi _dropboxApi = DropboxApi(_dropboxAuth);
  List<DbxEntry> _internalContractFiles = const <DbxEntry>[];
  List<DbxEntry> _externalContractFiles = const <DbxEntry>[];

  @override
  void initState() {
    super.initState();
    _loadContractFiles();
  }

  @override
  void didUpdateWidget(covariant _FinancialSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folderName != widget.folderName) {
      _internalContractFiles = const <DbxEntry>[];
      _externalContractFiles = const <DbxEntry>[];
      _loadContractFiles();
    }
  }

  Future<void> _loadContractFiles() async {
    final projectRoot = _resolveProjectDropboxPath(widget.folderName);
    if (projectRoot == null) return;

    try {
      final signedIn = await _dropboxAuth.isSignedIn();
      if (!signedIn) return;

      final internalFiles = await _listDropboxFiles(
        '$projectRoot/00 PRMG/01 CTRA/01 Internal',
      );
      final externalFiles = await _listDropboxFiles(
        '$projectRoot/00 PRMG/01 CTRA/02 External',
      );

      if (!mounted) return;
      setState(() {
        _internalContractFiles = internalFiles;
        _externalContractFiles = externalFiles;
      });
    } catch (_) {
      // Broken/missing Dropbox folders intentionally render no contract files.
    }
  }

  Future<List<DbxEntry>> _listDropboxFiles(String path) async {
    try {
      final entries = await _dropboxApi.listFolder(path: path);
      final files = entries.where((entry) => !entry.isFolder).toList()
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      return files;
    } catch (_) {
      return const <DbxEntry>[];
    }
  }

  String? _resolveProjectDropboxPath(String? raw) {
    if (raw == null) return null;
    var sanitized = raw.replaceAll('\\', '/').trim();
    if (sanitized.isEmpty) return null;
    sanitized = sanitized.replaceAll(RegExp(r'/+'), '/');
    if (sanitized.startsWith('/')) {
      sanitized = sanitized.substring(1);
    }
    if (!sanitized.toUpperCase().startsWith('SKY/')) {
      sanitized = 'SKY/01 PRJT/$sanitized';
    }
    sanitized = sanitized.replaceAll(RegExp(r'/+'), '/');
    sanitized = sanitized.replaceAll(RegExp(r'/+$'), '');
    return '/$sanitized';
  }

  Future<void> _openDropboxFile(BuildContext context, DbxEntry file) async {
    final path = file.pathDisplay.trim().isNotEmpty
        ? file.pathDisplay.trim()
        : file.pathLower.trim();
    if (path.isEmpty) return;

    try {
      final uri = await _dropboxApi.getOrCreateSharedLink(path);
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Dropbox file.')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Dropbox file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency();

    return StreamBuilder<List<Invoice>>(
      stream: InvoiceRepository().streamForProject(
        projectId: widget.projectId,
        projectNumber: widget.projectNumber,
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
            clientUnpaid += inv.balance;
          } else if (inv.invoiceType == 'Vendor') {
            vendorInvoiced += inv.invoiceAmount;
            vendorUnpaid += inv.balance;
          }
        }

        final contract = widget.contractAmount ?? 0.0;
        final pctInvoiced =
            (contract > 0) ? (clientInvoiced / contract) * 100 : 0.0;
        final contractLabel =
            widget.contractAmount != null ? currency.format(contract) : '--';
        final progressLabel =
            contract > 0 ? '${pctInvoiced.toStringAsFixed(0)}%' : '--';
        final vendorContractLabel = currency.format(0);
        final theme = Theme.of(context);
        final surface = theme.colorScheme.surface;
        final cardColor = Color.alphaBlend(const Color(0x14FFFFFF), surface);

        return SectionCard(
          color: cardColor,
          header: const SectionHeader(title: 'Financial Summary'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Client Contract: $contractLabel',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              _contractFileLinks(context, _internalContractFiles),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _metricBox(
                      context,
                      label: 'Client Invoiced',
                      value:
                          '${currency.format(clientInvoiced)} ($progressLabel)',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _metricBox(
                      context,
                      label: 'Balance',
                      value: currency.format(clientUnpaid),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Vendor Contract: $vendorContractLabel',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              _contractFileLinks(context, _externalContractFiles),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _metricBox(
                      context,
                      label: 'Vendor Invoiced',
                      value: currency.format(vendorInvoiced),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
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
        );
      },
    );
  }

  Widget _contractFileLinks(BuildContext context, List<DbxEntry> files) {
    if (files.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: 0,
      children: [
        for (final file in files)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: TextButton.icon(
              onPressed: () => _openDropboxFile(context, file),
              icon: const Icon(Icons.description_outlined, size: 16),
              label: Text(
                file.name,
                overflow: TextOverflow.ellipsis,
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: theme.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
  }

  Widget _metricBox(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final outline =
        Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6);
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
