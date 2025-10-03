// lib/src/dialogs/task_edit_dialog.dart
import 'package:flutter/material.dart';
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
}) async {
  final titleCtl = TextEditingController(text: task.title);
  final descCtl = TextEditingController(text: task.description ?? '');
  final assigneeCtl = TextEditingController(text: task.assigneeName ?? '');
  final codeCtl = TextEditingController(text: task.taskCode ?? '');
  DateTime? dueDate = task.dueDate;
  String taskStatus = _kTaskStatuses.contains(task.taskStatus)
      ? task.taskStatus
      : 'In Progress';
  bool isStarred = task.isStarred;

  final repo = TaskRepository();
  final formKey = GlobalKey<FormState>();

  String? validateCode(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    if (s.length != 4 || int.tryParse(s) == null) {
      return 'Enter a 4-digit code';
    }
    return null;
  }

  Future<void> pickDue() async {
    final seed = dueDate ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: seed,
      firstDate: DateTime(seed.year - 5),
      lastDate: DateTime(seed.year + 5),
    );
    if (d != null) dueDate = d;
  }

  void viewOnlySnack() {
    if (!canEdit && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('View-only: only the project owner can modify tasks.'),
        ),
      );
    }
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Task: ${task.title}'),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      appTextField('Title', titleCtl, required: true),
                      const SizedBox(height: 10),
                      appTextField('Description', descCtl),
                      const SizedBox(height: 10),
                      appTextField(
                        'Task Code (optional, 4 digits)',
                        codeCtl,
                        validator: validateCode,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: canEdit
                                  ? () async {
                                      await pickDue();
                                      setState(() {});
                                    }
                                  : viewOnlySnack,
                              child: AbsorbPointer(
                                absorbing: true,
                                child: appDateField(
                                  label: 'Due Date',
                                  value: dueDate,
                                  onPick: () async {
                                    await pickDue();
                                    setState(() {});
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: assigneeCtl,
                              decoration: const InputDecoration(
                                labelText: 'Assignee (optional)',
                                border: OutlineInputBorder(),
                              ),
                              enabled: canEdit,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: taskStatus,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        items: _kTaskStatuses
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: canEdit
                            ? (v) =>
                                  setState(() => taskStatus = v ?? taskStatus)
                            : null,
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Star this task'),
                        value: isStarred,
                        onChanged: canEdit
                            ? (v) => setState(() => isStarred = v)
                            : (v) => viewOnlySnack(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (!canEdit) {
                    viewOnlySnack();
                    return;
                  }
                  if (!(formKey.currentState?.validate() ?? false)) return;

                  final code = codeCtl.text.trim();
                  final data = {
                    'title': titleCtl.text.trim(),
                    'description': descCtl.text.trim().isEmpty
                        ? null
                        : descCtl.text.trim(),
                    'taskCode': code.isEmpty ? null : code,
                    'taskStatus': taskStatus,
                    'status': _legacyFromNew(taskStatus),
                    'dueDate': dueDate,
                    'assigneeName': assigneeCtl.text.trim().isEmpty
                        ? null
                        : assigneeCtl.text.trim(),
                    'isStarred': isStarred,
                  };

                  try {
                    await repo.update(task.id, data);
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Update failed: $e')),
                      );
                    }
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

String _legacyFromNew(String taskStatus) {
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
