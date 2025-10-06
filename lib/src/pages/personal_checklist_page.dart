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

  Future<void> _toggleItem(PersonalChecklistItem item, bool? value) async {
    await _service.setCompletion(item.id, value ?? false);
  }

  Future<void> _removeItem(PersonalChecklistItem item) async {
    await _service.removeItem(item.id);
  }

  Future<void> _clearCompleted() async {
    await _service.clearCompleted();
  }

  Future<void> _handleShowInStarred(bool value) async {
    await _service.setShowInStarred(value);
  }

  @override
  Widget build(BuildContext context) {
    final items = _service.items;
    final hasCompleted = items.any((item) => item.isDone);
    final showInStarred = _service.showInStarred;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal Checklist'),
        actions: [
          if (!_loading && hasCompleted)
            IconButton(
              tooltip: 'Clear completed',
              onPressed: _clearCompleted,
              icon: const Icon(Icons.clear_all),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Card(
                    margin: EdgeInsets.zero,
                    child: SwitchListTile.adaptive(
                      title: const Text('Show on Starred Tasks'),
                      subtitle: const Text(
                        'Mirror these personal reminders on your Starred Tasks page.',
                      ),
                      value: showInStarred,
                      onChanged: _handleShowInStarred,
                    ),
                  );
                }

                if (items.isEmpty) {
                  return const _EmptyState();
                }

                final item = items[index - 1];
                return Dismissible(
                  key: ValueKey(item.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _removeItem(item),
                  background: _dismissBackground(context),
                  child: CheckboxListTile(
                    title: Text(
                      item.title,
                      style: item.isDone
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                    subtitle: item.isDone
                        ? const Text('Completed')
                        : const Text('Pending'),
                    value: item.isDone,
                    onChanged: (value) => _toggleItem(item, value),
                  ),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemCount: 1 + (items.isEmpty ? 1 : items.length),
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add checklist item',
        onPressed: _addItem,
        child: const Icon(Icons.playlist_add),
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
            Text('Nothing on your checklist yet.'),
            SizedBox(height: 6),
            Text('Use the add button to capture a quick reminder.'),
          ],
        ),
      ),
    );
  }
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
