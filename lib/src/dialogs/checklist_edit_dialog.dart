// lib/src/dialogs/checklist_edit_dialog.dart
import 'package:flutter/material.dart';

import '../data/models/checklist.dart';

Future<ChecklistEditResult?> showChecklistEditDialog(
  BuildContext context, {
  Checklist? initial,
}) {
  return showDialog<ChecklistEditResult?>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _ChecklistEditDialog(initial: initial);
    },
  );
}

class ChecklistEditResult {
  ChecklistEditResult({required this.title, required this.items});

  final String title;
  final List<ChecklistItem> items;
}

class _ChecklistEditDialog extends StatefulWidget {
  const _ChecklistEditDialog({this.initial});

  final Checklist? initial;

  @override
  State<_ChecklistEditDialog> createState() => _ChecklistEditDialogState();
}

class _ChecklistEditDialogState extends State<_ChecklistEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final List<_EditableChecklistItem> _items;
  String? _itemsError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initial?.title ?? '');
    final existing = widget.initial?.items ?? const <ChecklistItem>[];
    if (existing.isEmpty) {
      _items = <_EditableChecklistItem>[
        _EditableChecklistItem(ChecklistItem.create(title: '')),
      ];
    } else {
      _items = existing
          .map(_EditableChecklistItem.fromItem)
          .toList(growable: true);
    }
  }

  @override
  void dispose() {
    for (final entry in _items) {
      entry.dispose();
    }
    _titleController.dispose();
    super.dispose();
  }

  void _addItem() {
    setState(() {
      _itemsError = null;
      _items.add(_EditableChecklistItem(ChecklistItem.create(title: '')));
    });
  }

  void _removeAt(int index) {
    setState(() {
      _itemsError = null;
      if (_items.length == 1) {
        _items[index].controller.clear();
      } else {
        final removed = _items.removeAt(index);
        removed.dispose();
      }
    });
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      _itemsError = null;
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final entry = _items.removeAt(oldIndex);
      _items.insert(newIndex, entry);
    });
  }

  Future<void> _save() async {
    setState(() {
      _itemsError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final trimmedItems = <ChecklistItem>[];
    for (final entry in _items) {
      final title = entry.controller.text.trim();
      if (title.isEmpty) continue;
      trimmedItems.add(entry.item.copyWith(title: title));
    }

    if (trimmedItems.isEmpty) {
      setState(() {
        _itemsError = 'Add at least one checklist item to continue.';
      });
      return;
    }

    final title = _titleController.text.trim();
    final result = ChecklistEditResult(title: title, items: trimmedItems);
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = (media.size.height * 0.7).clamp(360.0, 640.0);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      buttonPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(widget.initial == null ? 'New Checklist' : 'Edit Checklist'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 520,
          height: maxHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Checklist title',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Enter a checklist title.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: _items.length,
                  buildDefaultDragHandles: false,
                  onReorder: _onReorder,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemBuilder: (context, index) {
                    final entry = _items[index];
                    return Card(
                      key: ValueKey('editable-item-${entry.item.id}'),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 2,
                        ),
                        visualDensity: const VisualDensity(vertical: -2),
                        minVerticalPadding: 0,
                        dense: true,
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                        title: TextFormField(
                          controller: entry.controller,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Checklist item',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 12,
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Enter text or remove this row.';
                            }
                            return null;
                          },
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove item',
                          onPressed: () => _removeAt(index),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_itemsError != null) ...[
                const SizedBox(height: 2),
                Text(
                  _itemsError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addItem,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add checklist item'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EditableChecklistItem {
  _EditableChecklistItem(this.item)
    : controller = TextEditingController(text: item.title);

  factory _EditableChecklistItem.fromItem(ChecklistItem item) {
    return _EditableChecklistItem(item);
  }

  final ChecklistItem item;
  final TextEditingController controller;

  void dispose() {
    controller.dispose();
  }
}
