import 'package:flutter/material.dart';

/// Simple modal spinner you can show/hide during async work:
///   LoadingOverlay.show(context, message: 'Signing in...');
///   // await something...
///   LoadingOverlay.hide();
class LoadingOverlay {
  static bool _showing = false;
  static BuildContext? _dialogContext;
  static NavigatorState? _rootNavigator;

  static NavigatorState? _navigatorFrom(BuildContext? context) {
    if (context == null) return null;
    try {
      return Navigator.of(context, rootNavigator: true);
    } catch (_) {
      try {
        return Navigator.of(context);
      } catch (_) {
        return null;
      }
    }
  }

  static void _resetState() {
    _dialogContext = null;
    _rootNavigator = null;
    _showing = false;
  }

  static void show(BuildContext context, {String message = 'Loading...'}) {
    if (_showing) return;
    _rootNavigator = _navigatorFrom(context);
    _showing = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      useRootNavigator: true,
      builder: (dialogContext) {
        _dialogContext = dialogContext;
        final theme = Theme.of(dialogContext);

        return PopScope(
          canPop: false,
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
    ).whenComplete(_resetState);
  }

  static void hide([BuildContext? context]) {
    if (!_showing && _dialogContext == null) return;

    final navigator = _rootNavigator ??
        _navigatorFrom(context) ??
        _navigatorFrom(_dialogContext);

    if (navigator == null) {
      _resetState();
      return;
    }

    if (navigator.canPop()) {
      try {
        navigator.pop();
      } catch (_) {
        _resetState();
      }
    } else {
      _resetState();
    }
  }
}
