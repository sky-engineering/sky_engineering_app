import 'package:flutter/material.dart';

/// Simple modal spinner you can show/hide during async work:
///   LoadingOverlay.show(context, message: 'Signing in...');
///   // await something...
///   LoadingOverlay.hide(context);
class LoadingOverlay {
  static bool _showing = false;

  static void show(BuildContext context, {String message = 'Loading...'}) {
    if (_showing) return;
    _showing = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
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
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void hide(BuildContext context) {
    if (!_showing) return;
    _showing = false;
    Navigator.of(context, rootNavigator: true).pop();
  }
}
