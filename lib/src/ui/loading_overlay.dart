import 'package:flutter/material.dart';

/// Simple modal spinner you can show/hide during async work:
///   LoadingOverlay.show(context, message: 'Signing in...');
///   // await something...
///   LoadingOverlay.hide();
class LoadingOverlay {
  static bool _showing = false;
  static BuildContext? _dialogContext;

  static void show(BuildContext context, {String message = 'Loading...'}) {
    if (_showing) return;
    _showing = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      useRootNavigator: true,
      builder: (dialogContext) {
        _dialogContext = dialogContext;
        final theme = Theme.of(dialogContext);

        return WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(blurRadius: 10, color: Colors.black26),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      message,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      _dialogContext = null;
      _showing = false;
    });
  }

  static void hide([BuildContext? context]) {
    if (!_showing) return;

    final navigatorContext = _dialogContext ?? context;
    if (navigatorContext != null) {
      try {
        Navigator.of(navigatorContext, rootNavigator: true).pop();
      } catch (_) {
        try {
          Navigator.of(navigatorContext).maybePop();
        } catch (_) {
          // Ignore if the dialog is already gone.
        }
      }
    }

    _dialogContext = null;
    _showing = false;
  }
}
