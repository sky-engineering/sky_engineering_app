import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

String fmtDate(DateTime? d) {
  if (d == null) return '--';
  return '--';
}

/// Shared text field with Sky spacing/validation defaults.
Widget appTextField(
  String label,
  TextEditingController ctl, {
  bool required = false,
  String? hint,
  TextInputType? keyboardType,
  int maxLines = 1,
  List<TextInputFormatter>? inputFormatters,
  int? maxLength,
  String? Function(String?)? validator,
  bool dense = false,
  EdgeInsetsGeometry? contentPadding,
}) {
  return TextFormField(
    controller: ctl,
    maxLines: maxLines,
    keyboardType: keyboardType,
    inputFormatters: inputFormatters,
    maxLength: maxLength,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: dense,
      contentPadding: contentPadding ??
          (dense
              ? const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm)
              : null),
    ),
    validator: (v) {
      if (required && (v == null || v.trim().isEmpty)) return 'Required';
      if (validator != null) return validator(v);
      return null;
    },
  );
}

Widget appDateField({
  required String label,
  required DateTime? value,
  required VoidCallback onPick,
}) {
  final txt = value == null ? '--' : '--';
  return InkWell(
    onTap: onPick,
    child: InputDecorator(
      decoration: const InputDecoration(
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

/// Consistent wrapper for form dialogs with padding + scroll.
class AppFormDialog extends StatelessWidget {
  const AppFormDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.width = 420,
    this.scrollable = true,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final double width;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final body = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );

    return AlertDialog(
      title: Text(title),
      content: scrollable ? SingleChildScrollView(child: body) : body,
      actions: actions,
    );
  }
}

class AppDialogActions extends StatelessWidget {
  const AppDialogActions(
      {super.key, required this.primary, this.secondary, this.leading});

  final Widget primary;
  final Widget? secondary;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (leading != null) leading!,
        if (secondary != null) ...[
          secondary!,
          const SizedBox(width: AppSpacing.sm),
        ],
        primary,
      ],
    );
  }
}

/// Shows a brief snackbar indicating the current view is read-only.
void viewOnlySnack(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('View only. You don\'t have permission to edit.'),
      duration: Duration(seconds: 2),
    ),
  );
}
