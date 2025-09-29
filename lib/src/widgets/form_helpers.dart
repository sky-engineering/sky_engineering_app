import 'package:flutter/material.dart';

String fmtDate(DateTime? d) {
  if (d == null) return '—';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Widget appTextField(
    String label,
    TextEditingController ctl, {
      bool required = false,
      String? hint,
      TextInputType? keyboardType,
      int maxLines = 1,
    }) {
  return TextFormField(
    controller: ctl,
    maxLines: maxLines,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
    validator: (v) {
      if (required && (v == null || v.trim().isEmpty)) return 'Required';
      return null;
    },
  );
}

Widget appDateField({
  required String label,
  required DateTime? value,
  required VoidCallback onPick,
}) {
  final txt = (value == null)
      ? '—'
      : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  return InkWell(
    onTap: onPick,
    child: InputDecorator(
      decoration: const InputDecoration(
        labelText: null, // label applied via InputDecorator's labelText below
        border: OutlineInputBorder(),
      ).copyWith(labelText: label),
      child: Text(txt),
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, String msg) async {
  bool ok = false;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm'),
      content: Text(msg),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            ok = true;
            Navigator.pop(context);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return ok;
}

/// Shows a brief snackbar indicating the current view is read-only.
///
/// Use this anywhere you block edits for non-owners:
/// `viewOnlySnack(context);`
void viewOnlySnack(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('View only. You don’t have permission to edit.'),
      duration: Duration(seconds: 2),
    ),
  );
}
