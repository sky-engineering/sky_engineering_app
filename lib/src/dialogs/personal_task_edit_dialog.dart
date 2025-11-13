// lib/src/dialogs/personal_task_edit_dialog.dart
import 'package:flutter/material.dart';

class PersonalTaskEditResult {
  const PersonalTaskEditResult({
    required this.title,
    required this.isDone,
  });

  final String title;
  final bool isDone;
}

Future<PersonalTaskEditResult?> showPersonalTaskEditDialog(
  BuildContext context, {
  required String initialTitle,
  required bool initialIsDone,
}) {
  return showDialog<PersonalTaskEditResult>(
    context: context,
    builder: (context) => PersonalTaskEditDialog(
      initialTitle: initialTitle,
      initialIsDone: initialIsDone,
    ),
  );
}

class PersonalTaskEditDialog extends StatefulWidget {
  const PersonalTaskEditDialog({
    required this.initialTitle,
    required this.initialIsDone,
    super.key,
  });

  final String initialTitle;
  final bool initialIsDone;

  @override
  State<PersonalTaskEditDialog> createState() => _PersonalTaskEditDialogState();
}

class _PersonalTaskEditDialogState extends State<PersonalTaskEditDialog> {
  late TextEditingController _controller;
  late bool _isDone;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
    _isDone = widget.initialIsDone;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSave() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      PersonalTaskEditResult(
        title: trimmed,
        isDone: _isDone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Edit Task'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
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
            value: _isDone,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _isDone = value);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSave ? _handleSave : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
