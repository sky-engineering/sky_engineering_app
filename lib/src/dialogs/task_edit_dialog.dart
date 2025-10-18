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
  String? selectedCode =
      (task.taskCode != null && task.taskCode!.trim().isNotEmpty)
      ? task.taskCode!.trim()
      : null;
  String taskStatus = _kTaskStatuses.contains(task.taskStatus)
      ? task.taskStatus
      : 'In Progress';
  final repo = TaskRepository();
  final formKey = GlobalKey<FormState>();
  var currentSubtasks = List<SubtaskItem>.from(task.subtasks);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> handleAddSubtask() async {
            final initialSubtasks = List<SubtaskItem>.from(currentSubtasks);
            final editable = <_EditableSubtaskEntry>[
              if (initialSubtasks.isEmpty)
                _EditableSubtaskEntry(SubtaskItem.create(title: ''))
              else
                ...initialSubtasks.map(_EditableSubtaskEntry.fromItem),
            ];

            List<Map<String, Object?>> normalizedSnapshot() {
              final result = <Map<String, Object?>>[];
              for (final entry in editable) {
                final title = entry.controller.text.trim();
                if (title.isEmpty) continue;
                result.add({
                  'id': entry.item.id,
                  'title': title,
                  'isDone': entry.item.isDone,
                });
              }
              return result;
            }

            final initialSnapshot = normalizedSnapshot();

            if (editable.isEmpty) {
              editable.add(
                _EditableSubtaskEntry(SubtaskItem.create(title: '')),
              );
            }

            final updated = await showDialog<List<SubtaskItem>>(
              context: context,
              builder: (innerContext) {
                return StatefulBuilder(
                  builder: (innerContext, innerSetState) {
                    final subtaskFormKey = GlobalKey<FormState>();

                    Future<bool> confirmDiscard() async {
                      final currentSnapshot = normalizedSnapshot();
                      final hasChanges =
                          currentSnapshot.length != initialSnapshot.length ||
                          currentSnapshot.asMap().entries.any((entry) {
                            final index = entry.key;
                            final current = entry.value;
                            if (index >= initialSnapshot.length) return true;
                            final initial = initialSnapshot[index];
                            return current['id'] != initial['id'] ||
                                current['title'] != initial['title'] ||
                                current['isDone'] != initial['isDone'];
                          });
                      if (!hasChanges) {
                        return true;
                      }
                      final discard = await confirmDialog(
                        innerContext,
                        'Discard subtask changes?',
                      );
                      return discard;
                    }

                    void removeAt(int index) {
                      innerSetState(() {
                        if (editable.length == 1) {
                          editable[index].controller.clear();
                        } else {
                          final removed = editable.removeAt(index);
                          removed.dispose();
                        }
                      });
                    }

                    void onReorder(int oldIndex, int newIndex) {
                      innerSetState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final entry = editable.removeAt(oldIndex);
                        editable.insert(newIndex, entry);
                      });
                    }

                    final listHeight = ((editable.length * 72.0).clamp(
                      180.0,
                      360.0,
                    )).toDouble();

                    return PopScope(
                      canPop: false,
                      onPopInvokedWithResult: (didPop, __) async {
                        if (didPop) return;
                        final navigator = Navigator.of(innerContext);
                        if (await confirmDiscard()) {
                          navigator.pop();
                        }
                      },
                      child: AlertDialog(
                        title: const Text('Add/Edit Subtasks'),
                        content: Form(
                          key: subtaskFormKey,
                          child: SizedBox(
                            width: 520,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: listHeight,
                                  child: ReorderableListView.builder(
                                    itemCount: editable.length,
                                    buildDefaultDragHandles: false,
                                    itemBuilder: (context, index) {
                                      final entry = editable[index];
                                      return ListTile(
                                        key: ValueKey(
                                          'editable-${entry.item.id}',
                                        ),
                                        leading: ReorderableDragStartListener(
                                          index: index,
                                          child: const Icon(Icons.drag_handle),
                                        ),
                                        title: TextFormField(
                                          controller: entry.controller,
                                          decoration: const InputDecoration(
                                            labelText: 'Subtask',
                                          ),
                                          validator: (value) {
                                            if ((value ?? '').trim().isEmpty) {
                                              return 'Enter a title or remove the row';
                                            }
                                            return null;
                                          },
                                        ),
                                        trailing: IconButton(
                                          tooltip: 'Remove',
                                          onPressed: () => removeAt(index),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      );
                                    },
                                    onReorder: onReorder,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () {
                                      innerSetState(() {
                                        editable.add(
                                          _EditableSubtaskEntry(
                                            SubtaskItem.create(title: ''),
                                          ),
                                        );
                                      });
                                    },
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add subtask'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () async {
                              final navigator = Navigator.of(innerContext);
                              if (!await confirmDiscard()) {
                                return;
                              }
                              navigator.pop();
                            },
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () {
                              final trimmed = <SubtaskItem>[];
                              for (final entry in editable) {
                                final title = entry.controller.text.trim();
                                if (title.isEmpty) continue;
                                trimmed.add(entry.item.copyWith(title: title));
                              }

                              if (trimmed.isEmpty) {
                                Navigator.of(innerContext).pop(trimmed);
                                return;
                              }

                              if (!(subtaskFormKey.currentState?.validate() ??
                                  false)) {
                                return;
                              }

                              Navigator.of(innerContext).pop(trimmed);
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );

            for (final entry in editable) {
              entry.dispose();
            }

            if (updated == null || !context.mounted) {
              return;
            }

            setState(() {
              currentSubtasks = updated;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Saved ${updated.length} subtask(s).')),
            );
          }

          return AlertDialog(
            title: Text('Task: ${task.title}'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      appTextField('Title', titleCtl, required: true),
                      const SizedBox(height: 10),
                      appTextField('Notes', notesCtl),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        // ignore: deprecated_member_use
                        value: selectedCode,
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
                                // ignore: deprecated_member_use
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
                        // ignore: deprecated_member_use
                        value: taskStatus,
                        isExpanded: true,
                        items: _kTaskStatuses
                            .map(
                              (status) => DropdownMenuItem(
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
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            actions: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (canEdit)
                    Row(
                      children: [
                        FilledButton.tonal(
                          onPressed: handleAddSubtask,
                          child: const Text('Add/Edit Subtasks'),
                        ),
                      ],
                    ),
                  if (canEdit) const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (canEdit)
                        TextButton(
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
                        ),
                      if (canEdit) const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(canEdit ? 'Cancel' : 'Close'),
                      ),
                      if (canEdit) const SizedBox(width: 8),
                      if (canEdit)
                        FilledButton(
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
                              await repo.update(task.id, {
                                'title': titleCtl.text.trim(),
                                'description': notesCtl.text.trim().isEmpty
                                    ? null
                                    : notesCtl.text.trim(),
                                'taskCode': selectedCode,
                                'taskStatus': taskStatus,
                                'subtasks': currentSubtasks,
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
                        ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
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

class _EditableSubtaskEntry {
  _EditableSubtaskEntry(this.item)
    : controller = TextEditingController(text: item.title);

  factory _EditableSubtaskEntry.fromItem(SubtaskItem item) {
    return _EditableSubtaskEntry(item);
  }

  final SubtaskItem item;
  final TextEditingController controller;

  void dispose() {
    controller.dispose();
  }
}
