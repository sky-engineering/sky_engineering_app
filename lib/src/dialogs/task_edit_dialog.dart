// lib/src/dialogs/task_edit_dialog.dart
import 'package:flutter/material.dart';

import '../data/models/project.dart';
import '../data/models/task.dart';
import '../data/repositories/task_repository.dart';
import '../widgets/form_helpers.dart';

const _kTaskStatuses = <String>[
  'In Progress',
  'On Hold',
  'Pending',
  'Completed',
];

Future<void> showTaskEditDialog(
  BuildContext context,
  TaskItem task, {
  required bool canEdit,
  List<SelectedSubphase> subphases = const [],
}) async {
  final titleCtl = TextEditingController(text: task.title);
  final notesCtl = TextEditingController(text: task.description ?? '');
  var subtasksText = _formatSubtasksField(task.subtasks);
  String? selectedCode =
      (task.taskCode != null && task.taskCode!.trim().isNotEmpty)
          ? task.taskCode!.trim()
          : null;
  String taskStatus = _kTaskStatuses.contains(task.taskStatus)
      ? task.taskStatus
      : 'In Progress';
  final repo = TaskRepository();
  final formKey = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AppFormDialog(
            title: 'Task: ${task.title}',
            width: 520,
            actions: [
              AppDialogActions(
                leading: canEdit
                    ? TextButton(
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await confirmDialog(
                            context,
                            'Delete this task?',
                          );
                          if (!ok) {
                            return;
                          }
                          try {
                            await repo.delete(task.id);
                            if (navigator.mounted) {
                              navigator.pop();
                            }
                          } catch (e) {
                            if (!navigator.mounted) {
                              return;
                            }
                            if (messenger.mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Failed to delete task: $e'),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Delete'),
                      )
                    : null,
                secondary: canEdit
                    ? TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      )
                    : null,
                primary: canEdit
                    ? FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () async {
                          if (!(formKey.currentState?.validate() ?? false)) {
                            return;
                          }

                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final updatedSubtasks = canEdit
                                ? _parseSubtasksField(
                                    subtasksText,
                                    task.subtasks,
                                  )
                                : task.subtasks;
                            await repo.update(task.id, {
                              'title': titleCtl.text.trim(),
                              'description': notesCtl.text.trim().isEmpty
                                  ? null
                                  : notesCtl.text.trim(),
                              'taskCode': selectedCode,
                              'taskStatus': taskStatus,
                              'subtasks': updatedSubtasks,
                              'status': _legacyStatusFromNew(taskStatus),
                            });
                            if (navigator.mounted) {
                              navigator.pop();
                            }
                          } catch (e) {
                            if (!navigator.mounted) {
                              return;
                            }
                            if (messenger.mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Failed to save task: $e'),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Save'),
                      )
                    : TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
              ),
            ],
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  appTextField('Title', titleCtl, required: true),
                  const SizedBox(height: 10),
                  appTextField('Notes', notesCtl),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: subtasksText,
                    maxLines: 3,
                    enabled: canEdit,
                    onChanged: canEdit ? (value) => subtasksText = value : null,
                    decoration: const InputDecoration(
                      labelText: 'Subtasks (comma separated)',
                      hintText: 'Survey, permits, final walk',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedCode,
                    isExpanded: true,
                    items: () {
                      final seen = <String>{};
                      final items = <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No Task Code'),
                        ),
                      ];
                      for (final subphase in subphases) {
                        if (!seen.add(subphase.code)) continue;
                        items.add(
                          DropdownMenuItem<String?>(
                            value: subphase.code,
                            child: Text(
                              '${subphase.code}  ${subphase.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        );
                      }
                      if (selectedCode != null &&
                          !seen.contains(selectedCode!)) {
                        items.insert(
                          1,
                          DropdownMenuItem<String?>(
                            value: selectedCode,
                            child: Text(
                              '$selectedCode (inactive)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                          ),
                        );
                      }
                      return items;
                    }(),
                    onChanged: canEdit
                        ? (value) => setState(() => selectedCode = value)
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Task Code (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: taskStatus,
                    isExpanded: true,
                    items: _kTaskStatuses
                        .map(
                          (status) => DropdownMenuItem<String>(
                            value: status,
                            child: Text(status),
                          ),
                        )
                        .toList(),
                    onChanged: canEdit
                        ? (value) => setState(
                              () => taskStatus = value ?? taskStatus,
                            )
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Task Status',
                      border: OutlineInputBorder(),
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
}

String _formatSubtasksField(List<SubtaskItem> subtasks) {
  return subtasks
      .map((s) => s.title.trim())
      .where((title) => title.isNotEmpty)
      .join(', ');
}

List<SubtaskItem> _parseSubtasksField(
  String raw,
  List<SubtaskItem> existing,
) {
  final tokens = raw
      .split(RegExp(r'[\n,]'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();

  final result = <SubtaskItem>[];
  for (var i = 0; i < tokens.length; i++) {
    if (i < existing.length) {
      result.add(existing[i].copyWith(title: tokens[i]));
    } else {
      result.add(SubtaskItem.create(title: tokens[i]));
    }
  }
  return result;
}

String _legacyStatusFromNew(String taskStatus) {
  switch (taskStatus) {
    case 'In Progress':
      return 'In Progress';
    case 'On Hold':
      return 'Blocked';
    case 'Completed':
      return 'Done';
    case 'Pending':
    default:
      return 'Open';
  }
}
