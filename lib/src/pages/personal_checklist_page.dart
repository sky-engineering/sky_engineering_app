// lib/src/pages/personal_checklist_page.dart
import 'package:flutter/material.dart';

import '../data/models/personal_checklist_item.dart';
import '../services/personal_checklist_service.dart';

class PersonalChecklistPage extends StatefulWidget {
  const PersonalChecklistPage({super.key});

  @override
  State<PersonalChecklistPage> createState() => _PersonalChecklistPageState();
}

class _PersonalChecklistPageState extends State<PersonalChecklistPage> {
  final PersonalChecklistService _service = PersonalChecklistService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _service.ensureLoaded().then((_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _addItem() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Checklist Item'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'What do you need to remember?',
            ),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) {
      return;
    }

    await _service.addItem(result);
  }

  Future<void> _toggleItem(PersonalChecklistItem item, bool value) async {
    await _service.setCompletion(item.id, value);
  }

  Future<void> _toggleStar(PersonalChecklistItem item) async {
    await _service.setStarred(item.id, !item.isStarred);
  }

  Future<void> _editItem(PersonalChecklistItem item) async {
    final controller = TextEditingController(text: item.title);
    var isDone = item.isDone;
    var isStarred = item.isStarred;

    final result = await showDialog<_PersonalEditResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final canSave = controller.text.trim().isNotEmpty;
            return AlertDialog(
              title: const Text('Edit Task'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Task name',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mark complete'),
                    value: isDone,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => isDone = value);
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Star task'),
                    value: isStarred,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => isStarred = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: canSave
                      ? () => Navigator.of(dialogContext).pop(
                            _PersonalEditResult(
                              title: controller.text.trim(),
                              isDone: isDone,
                              isStarred: isStarred,
                            ),
                          )
                      : null,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (result == null) return;

    await _service.updateItem(
      id: item.id,
      title: result.title,
      isDone: result.isDone,
      isStarred: result.isStarred,
    );
  }

  Future<void> _removeItem(PersonalChecklistItem item) async {
    await _service.removeItem(item.id);
  }

  Future<void> _clearCompleted() async {
    await _service.clearCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final items = _service.items;
    final hasCompleted = items.any((item) => item.isDone);

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (items.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: _EmptyState(),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemBuilder: (context, index) {
          final item = items[index];
          return Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _removeItem(item),
            background: _dismissBackground(context),
            child: _PersonalChecklistTile(
              item: item,
              onToggleComplete: (value) => _toggleItem(item, value),
              onToggleStar: () => _toggleStar(item),
              onEdit: () => _editItem(item),
            ),
          );
        },
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemCount: items.length,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Tasks'),
        actions: [
          if (!_loading && hasCompleted)
            IconButton(
              tooltip: 'Clear completed',
              onPressed: _clearCompleted,
              icon: const Icon(Icons.clear_all),
            ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add checklist item',
        onPressed: _addItem,
        child: const Icon(Icons.playlist_add),
      ),
    );
  }
}

class _PersonalChecklistTile extends StatelessWidget {
  const _PersonalChecklistTile({
    required this.item,
    required this.onToggleComplete,
    required this.onToggleStar,
    required this.onEdit,
  });

  final PersonalChecklistItem item;
  final ValueChanged<bool> onToggleComplete;
  final VoidCallback onToggleStar;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filledStar = theme.colorScheme.secondary;
    final hollowStar = theme.colorScheme.onSurfaceVariant;
    final titleStyle = theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          decoration: item.isDone ? TextDecoration.lineThrough : null,
        ) ??
        TextStyle(
          fontWeight: FontWeight.w600,
          decoration: item.isDone ? TextDecoration.lineThrough : null,
        );

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                tooltip: item.isStarred ? 'Unstar' : 'Star',
                splashRadius: 20,
                icon: Icon(
                  item.isStarred ? Icons.star : Icons.star_border,
                  color: item.isStarred ? filledStar : hollowStar,
                ),
                onPressed: onToggleStar,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  style: titleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: item.isDone ? 'Mark incomplete' : 'Mark complete',
                child: Checkbox(
                  value: item.isDone,
                  onChanged: (value) {
                    if (value == null) return;
                    onToggleComplete(value);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.fact_check_outlined, size: 48),
            SizedBox(height: 12),
            Text(
              'Nothing on your personal task list yet. Use the add button to add a personal task and tap the star to send it to Starred Tasks.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonalEditResult {
  const _PersonalEditResult({
    required this.title,
    required this.isDone,
    required this.isStarred,
  });

  final String title;
  final bool isDone;
  final bool isStarred;
}

Widget _dismissBackground(BuildContext context) {
  final color = Theme.of(context).colorScheme.errorContainer;
  final onColor = Theme.of(context).colorScheme.onErrorContainer;
  return Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    color: color,
    child: Icon(Icons.delete_outline, color: onColor),
  );
}
