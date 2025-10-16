// lib/src/widgets/tasks_section.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/task.dart';
import '../data/repositories/task_repository.dart';
import 'form_helpers.dart';
import '../dialogs/task_edit_dialog.dart';

const _kTaskStatuses = <String>[
  'In Progress',
  'On Hold',
  'Pending',
  'Completed',
];

class TasksSection extends StatelessWidget {
  final String projectId;
  final bool isOwner;

  const TasksSection({
    super.key,
    required this.projectId,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context) {
    final repo = TaskRepository();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tasks', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            StreamBuilder<List<TaskItem>>(
              stream: repo.streamByProject(projectId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  );
                }
                final items = snap.data ?? const <TaskItem>[];

                // Sort: prefer explicit taskCode (numeric asc), then fallback to code in title,
                // then dueDate asc (nulls last), then title asc.
                final tasks = [...items]..sort(_taskComparator);

                if (tasks.isEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('No tasks yet'),
                      ),
                      const SizedBox(height: 8),
                      if (isOwner)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            onPressed: () =>
                                _showAddTaskDialog(context, projectId),
                            icon: const Icon(Icons.add),
                            label: const Text('New Task'),
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
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final t = tasks[i];

                        return _CompactTaskTile(
                          task: t,
                          isOwner: isOwner,
                          onToggleStar: () async {
                            if (!isOwner) {
                              _viewOnlySnack(context);
                              return;
                            }
                            try {
                              await repo.setStarred(t, !t.isStarred);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Could not update star: $e'),
                                  ),
                                );
                              }
                            }
                          },
                          onChangeStatus: (newStatus) async {
                            if (!isOwner) return _viewOnlySnack(context);
                            await repo.update(t.id, {
                              'taskStatus': newStatus,
                              // legacy mirror for any old code still reading 'status'
                              'status': _legacyFromNew(newStatus),
                            });
                          },
                          onTap: () =>
                              showTaskEditDialog(context, t, canEdit: isOwner),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    if (isOwner)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: () =>
                              _showAddTaskDialog(context, projectId),
                          icon: const Icon(Icons.add),
                          label: const Text('New Task'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static void _viewOnlySnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('View-only: only the project owner can modify tasks.'),
      ),
    );
  }

  // ---- Sorting helpers ----
  static int? _codeToInt(String? code) {
    if (code == null) return null;
    final s = code.trim();
    if (s.length != 4) return null;
    return int.tryParse(s);
  }

  static int? _extractTitleCode(String title) {
    final m = RegExp(r'^\s*(\d{4})\b').firstMatch(title);
    return (m == null) ? null : int.tryParse(m.group(1)!);
  }

  static int _taskComparator(TaskItem a, TaskItem b) {
    final ac = _codeToInt(a.taskCode) ?? _extractTitleCode(a.title);
    final bc = _codeToInt(b.taskCode) ?? _extractTitleCode(b.title);
    if (ac != null && bc != null) return ac.compareTo(bc);
    if (ac != null && bc == null) return -1;
    if (ac == null && bc != null) return 1;

    final ad = a.dueDate, bd = b.dueDate;
    if (ad != null && bd != null) {
      final cmp = ad.compareTo(bd);
      if (cmp != 0) return cmp;
    } else if (ad == null && bd != null) {
      return 1; // nulls last
    } else if (ad != null && bd == null) {
      return -1;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  // Map new -> legacy for mirror writes
  static String _legacyFromNew(String taskStatus) {
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
}

// ===== Compact tile =====
class _CompactTaskTile extends StatelessWidget {
  final TaskItem task;
  final bool isOwner;
  final VoidCallback onToggleStar;
  final ValueChanged<String> onChangeStatus;
  final VoidCallback onTap;

  const _CompactTaskTile({
    required this.task,
    required this.isOwner,
    required this.onToggleStar,
    required this.onChangeStatus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final hasDesc = (task.description ?? '').trim().isNotEmpty;

    // Visible colors for star states on dark theme
    final filledStarColor = Theme.of(
      context,
    ).colorScheme.secondary; // accent (yellow)
    final hollowStarColor = Theme.of(
      context,
    ).colorScheme.onSurfaceVariant; // subtle gray

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          // Align to top when there IS a description, else center with title line.
          crossAxisAlignment: hasDesc
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            // Star icon (hollow vs solid)
            Padding(
              padding: EdgeInsets.only(top: hasDesc ? 2 : 0),
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                iconSize: 20,
                splashRadius: 18,
                onPressed: onToggleStar,
                icon: Icon(
                  task.isStarred ? Icons.star : Icons.star_border,
                  color: task.isStarred ? filledStarColor : hollowStarColor,
                ),
                tooltip: task.isStarred ? 'Unstar' : 'Star',
              ),
            ),

            // Title + (inline status dropdown) + small description
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // First line: Title + inline status dropdown (right-aligned)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _InlineStatusDropdown(
                        value: task.taskStatus,
                        enabled: isOwner,
                        onChanged: (v) {
                          if (v == null) return;
                          onChangeStatus(v);
                        },
                      ),
                    ],
                  ),
                  // Second line (optional): tiny description
                  if (hasDesc)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        task.description!.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineStatusDropdown extends StatelessWidget {
  final String value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  const _InlineStatusDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final txtStyle = Theme.of(context).textTheme.bodySmall;

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _kTaskStatuses.contains(value) ? value : 'Pending',
        items: _kTaskStatuses
            .map(
              (s) => DropdownMenuItem(
                value: s,
                child: Text(s, style: txtStyle),
              ),
            )
            .toList(),
        onChanged: enabled ? onChanged : null,
        isDense: true,
      ),
    );
  }
}

// ------------------- Dialogs — unchanged from the last step -------------------

Future<void> _showAddTaskDialog(BuildContext context, String projectId) async {
  final titleCtl = TextEditingController();
  final descCtl = TextEditingController();
  final assigneeCtl = TextEditingController();
  final codeCtl = TextEditingController();
  DateTime? dueDate;
  String taskStatus = 'Pending';
  bool isStarred = false;

  final me = FirebaseAuth.instance.currentUser;
  final repo = TaskRepository();
  final formKey = GlobalKey<FormState>();

  if (me == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('You must be signed in.')));
    return;
  }

  String? validateTaskCode(String? value) {
    final input = (value ?? '').trim();
    if (input.isEmpty) return null; // optional
    if (input.length != 4 || int.tryParse(input) == null) {
      return 'Enter a 4-digit code';
    }
    return null;
  }

  Future<void> pickDue() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) dueDate = d;
  }

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('New Task'),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      appTextField(
                        'Title',
                        titleCtl,
                        required: true,
                        hint: 'e.g., 0201 Concept Site Plan',
                      ),
                      const SizedBox(height: 10),
                      appTextField('Description', descCtl),
                      const SizedBox(height: 10),

                      // Task Code + Status side-by-side
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: codeCtl,
                              decoration: const InputDecoration(
                                labelText: 'Task Code (optional)',
                                hintText: 'e.g., 0201',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              validator: validateTaskCode,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: taskStatus,
                              items: _kTaskStatuses
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => taskStatus = v ?? 'Pending'),
                              decoration: const InputDecoration(
                                labelText: 'Task Status',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      Row(
                        children: [
                          Expanded(
                            child: appDateField(
                              label: 'Due Date',
                              value: dueDate,
                              onPick: () async {
                                await pickDue();
                                setState(() {});
                              },
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
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Star this task'),
                        value: isStarred,
                        onChanged: (v) => setState(() => isStarred = v),
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
                  if (!(formKey.currentState?.validate() ?? false)) return;

                  final code = codeCtl.text.trim();
                  final t = TaskItem(
                    id: '_',
                    projectId: projectId,
                    ownerUid: me.uid,
                    title: titleCtl.text.trim(),
                    description: descCtl.text.trim().isEmpty
                        ? null
                        : descCtl.text.trim(),
                    taskStatus: taskStatus,
                    isStarred: isStarred,
                    taskCode: code.isEmpty ? null : code,
                    starredOrder: isStarred
                        ? DateTime.now().millisecondsSinceEpoch
                        : null,
                    dueDate: dueDate,
                    assigneeName: assigneeCtl.text.trim().isEmpty
                        ? null
                        : assigneeCtl.text.trim(),
                    createdAt: null,
                    updatedAt: null,
                  );
                  await repo.add(t);
                  // ignore: use_build_context_synchronously
                  Navigator.pop(context);
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
    },
  );
}
