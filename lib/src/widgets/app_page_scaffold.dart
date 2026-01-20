import 'package:flutter/material.dart';

import '../app/shell.dart';
import '../theme/tokens.dart';

/// Consistent wrapper for secondary pages pushed from the shell.
class AppPageScaffold extends StatelessWidget {
  const AppPageScaffold({
    super.key,
    this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.fabLocation,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.lg,
    ),
    this.useSafeArea = false,
    this.scrollable = false,
    this.maxContentWidth,
    this.bottomNavigationBar,
    this.includeShellBottomNav = false,
    this.popShellRoute = false,
    this.centerTitle = false,
    this.appBar,
  });

  final String? title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? fabLocation;
  final EdgeInsetsGeometry? padding;
  final bool useSafeArea;
  final bool scrollable;
  final double? maxContentWidth;
  final Widget? bottomNavigationBar;
  final bool includeShellBottomNav;
  final bool popShellRoute;
  final bool centerTitle;
  final PreferredSizeWidget? appBar;

  Widget _wrapWithMaxWidth(Widget child) {
    if (maxContentWidth == null) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth!),
        child: child,
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar() {
    if (appBar != null) return appBar;
    if (title == null && (actions == null || actions!.isEmpty)) {
      return null;
    }
    return AppBar(
      centerTitle: centerTitle,
      title: title != null ? Text(title!) : null,
      actions: actions,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = body;
    if (scrollable) {
      content = SingleChildScrollView(
        padding: padding,
        child: _wrapWithMaxWidth(body),
      );
    } else if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }
    content = _wrapWithMaxWidth(content);
    if (useSafeArea) {
      content = SafeArea(child: content);
    }

    final bottomNav = bottomNavigationBar ??
        (includeShellBottomNav
            ? ShellBottomNav(popCurrentRoute: popShellRoute)
            : null);

    return Scaffold(
      appBar: _buildAppBar(),
      body: content,
      bottomNavigationBar: bottomNav,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: fabLocation,
    );
  }
}

/// Standard card for grouping related controls or data.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.header,
    required this.child,
    this.footer,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.gap = AppSpacing.md,
    this.color,
    this.onTap,
  });

  final Widget? header;
  final Widget child;
  final Widget? footer;
  final EdgeInsetsGeometry padding;
  final double gap;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (header != null) header!,
      child,
      if (footer != null) footer!,
    ];

    Widget content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _withSpacing(children, gap),
      ),
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: AppRadii.md,
        child: content,
      );
    }

    return Card(
      color: color,
      child: content,
    );
  }

  List<Widget> _withSpacing(List<Widget> children, double gap) {
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i != children.length - 1) {
        spaced.add(SizedBox(height: gap));
      }
    }
    return spaced;
  }
}

/// Consistent header row for section titles + actions.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.padding = EdgeInsets.zero,
  });

  final String title;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
