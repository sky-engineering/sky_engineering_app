// lib/src/dialogs/select_subphases_dialog.dart
import 'package:flutter/material.dart';
import '../data/models/project.dart';
import '../data/models/subphase_template.dart';
import '../data/repositories/project_repository.dart';
import '../data/repositories/subphase_template_repository.dart';
import '../theme/tokens.dart';
import '../widgets/form_helpers.dart';

/// Shows all subphases grouped by phase (01..04).
/// - Pre-checks currently selected project subphases.
/// - On save, stores selected subphases with a per-project `status`.
///   New selections default to 'In Progress'. Existing ones preserve status.
Future<void> showSelectSubphasesDialog(
  BuildContext context, {
  required String projectId,
  required String ownerUid,
  String? fallbackOwnerUid,
}) async {
  final projRepo = ProjectRepository();
  final tmplRepo = SubphaseTemplateRepository();

  final templates = await _loadSubphaseTemplates(
    tmplRepo,
    ownerUid: ownerUid,
    fallbackOwnerUid: fallbackOwnerUid,
  );
  final project = await projRepo.getById(projectId);

  if (!context.mounted) return;

  if (templates.isEmpty) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text(
          'No subphases configured yet. Add them under "Project Subphases".',
        ),
      ),
    );
    return;
  }

  // Lookups
  final templateByCode = {for (final t in templates) t.subphaseCode: t};
  final existing = project?.selectedSubphases ?? const <SelectedSubphase>[];
  final existingByCode = {for (final s in existing) s.code: s};

  // Group templates by phase
  final grouped = <String, List<SubphaseTemplate>>{
    '01': [],
    '02': [],
    '03': [],
    '04': [],
    '??': [],
  };
  for (final t in templates) {
    final phase =
        (t.subphaseCode.length >= 2) ? t.subphaseCode.substring(0, 2) : '??';
    (grouped[phase] ??= []).add(t);
  }
  for (final k in grouped.keys) {
    grouped[k]!.sort((a, b) => a.subphaseCode.compareTo(b.subphaseCode));
  }

  String phaseLabel(String code) {
    switch (code) {
      case '01':
        return '01 - Land Use';
      case '02':
        return '02 - Preliminary Design';
      case '03':
        return '03 - Construction Design';
      case '04':
        return '04 - Construction Management';
      default:
        return 'Other / Unknown';
    }
  }

  final orderedPhaseKeys = ['01', '02', '03', '04', '??'];

  // Pre-check existing selections
  final selected = <String>{...existing.map((s) => s.code)};

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (innerContext, setState) {
          return AppFormDialog(
            title: 'Select Subphases',
            width: 600,
            scrollable: false,
            actions: [
              AppDialogActions(
                secondary: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                primary: FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(dialogContext);
                    final messenger = ScaffoldMessenger.of(dialogContext);

                    final picked = <Map<String, dynamic>>[];

                    for (final code in selected) {
                      final template = templateByCode[code];
                      final prev = existingByCode[code];
                      if (template != null) {
                        final overriddenName = prev?.name.trim();
                        final resolvedName = (overriddenName != null &&
                                overriddenName.isNotEmpty)
                            ? overriddenName
                            : template.subphaseName;
                        picked.add(
                          SelectedSubphase(
                            code: template.subphaseCode,
                            name: resolvedName,
                            responsibility: template.responsibility,
                            isDeliverable: template.isDeliverable,
                            status: prev?.status ?? 'In Progress',
                          ).toMap(),
                        );
                      } else if (prev != null) {
                        picked.add(prev.toMap());
                      }
                    }

                    try {
                      await projRepo.update(projectId, {
                        'selectedSubphases': picked,
                      });
                      if (navigator.mounted) {
                        navigator.pop();
                      }
                      if (messenger.mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Saved ${picked.length} subphase(s).',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (!navigator.mounted) return;
                      if (messenger.mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Failed to save subphases: $e'),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
              ),
            ],
            child: SizedBox(
              width: 560,
              height: 520,
              child: ListView.builder(
                itemCount: orderedPhaseKeys.length,
                itemBuilder: (context, idx) {
                  final phaseKey = orderedPhaseKeys[idx];
                  final items = grouped[phaseKey] ?? const <SubphaseTemplate>[];
                  if (items.isEmpty) {
                    if (phaseKey == '??') return const SizedBox.shrink();
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            phaseLabel(phaseKey),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'No subphases configured for this phase.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                          horizontal: AppSpacing.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              phaseLabel(phaseKey),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            ...items.map((t) {
                              final checked = selected.contains(t.subphaseCode);
                              return CheckboxListTile(
                                value: checked,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      selected.add(t.subphaseCode);
                                    } else {
                                      selected.remove(t.subphaseCode);
                                    }
                                  });
                                },
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                dense: true,
                                visualDensity: const VisualDensity(
                                    horizontal: -4, vertical: -4),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${t.subphaseCode}  ${t.subphaseName}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    },
  );
}

Future<List<SubphaseTemplate>> _loadSubphaseTemplates(
  SubphaseTemplateRepository repo, {
  required String ownerUid,
  String? fallbackOwnerUid,
}) async {
  final result = <SubphaseTemplate>[];
  final seenCodes = <String>{};
  final visitedOwners = <String>{};

  Future<void> appendOwner(String candidate) async {
    if (visitedOwners.contains(candidate)) return;
    visitedOwners.add(candidate);
    final templates = await repo.getAllForUser(candidate);
    for (final template in templates) {
      final code = template.subphaseCode;
      if (seenCodes.add(code)) {
        result.add(template);
      }
    }
  }

  await appendOwner(ownerUid);

  if (fallbackOwnerUid != null &&
      fallbackOwnerUid.isNotEmpty &&
      fallbackOwnerUid != ownerUid) {
    await appendOwner(fallbackOwnerUid);
  }

  await appendOwner('');

  result.sort((a, b) => a.subphaseCode.compareTo(b.subphaseCode));
  return result;
}
