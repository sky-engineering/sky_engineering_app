// lib/src/app/shell.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/user_service.dart';
import '../data/models/user_profile.dart';
import '../data/repositories/user_repository.dart';
import 'user_access_scope.dart';

import '../pages/dashboard_page.dart';
import '../pages/projects_page.dart';
import '../pages/profile_page.dart';
import '../pages/note_editor_page.dart';
import '../dialogs/quick_actions.dart';
import '../pages/invoices_page.dart';
import '../pages/starred_tasks_page.dart';
import '../pages/task_overview_page.dart';
import '../pages/external_tasks_overview_page.dart';
import '../pages/personal_checklist_page.dart';

const _brandYellow = Color(0xFFF1C400);

class Shell extends StatefulWidget {
  const Shell({super.key, required this.user});

  final User user;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with TickerProviderStateMixin {
  static const int _starredTasksPageIndex = 2;
  static const int _taskOverviewPageIndex = 5;
  static const int _externalTasksPageIndex = 6;
  static const int _personalTasksPageIndex = 7;
  static const int _pageCount = 8;
  static const List<NavigationDestination> _navDestinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: 'Home',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: 'Profile',
    ),
    NavigationDestination(
      icon: _StarTabIcon(isSelected: false),
      selectedIcon: _StarTabIcon(isSelected: true),
      label: 'Tasks',
    ),
    NavigationDestination(
      icon: Icon(Icons.work_outline),
      selectedIcon: Icon(Icons.work),
      label: 'Projects',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'Invoices',
    ),
  ];

  bool _ready = false;
  int _navIndex = 0;
  int _bodyIndex = 0;
  int _previousIndex = 0;
  bool _quickMenuVisible = false;
  final _userRepo = UserRepository();

  late final AnimationController _taskMenuController;
  late final Animation<double> _taskMenuAnimation;
  late final AnimationController _quickMenuController;
  late final Animation<double> _quickMenuAnimation;

  Widget _logoTitle() =>
      SizedBox(height: 32, child: Image.asset('assets/logo_white.png'));

  @override
  void initState() {
    super.initState();

    _taskMenuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _taskMenuAnimation = CurvedAnimation(
      parent: _taskMenuController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );

    _quickMenuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _quickMenuAnimation = CurvedAnimation(
      parent: _quickMenuController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );

    _quickMenuController.addListener(() {
      if (mounted) setState(() {});
    });

    _quickMenuController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _quickMenuVisible) {
        setState(() => _quickMenuVisible = false);
      }
    });

    _init();
  }

  @override
  void dispose() {
    _taskMenuController.dispose();
    _quickMenuController.dispose();
    UserAccessController.instance.clear();
    super.dispose();
  }

  Future<void> _init() async {
    UserService.ensureUserDoc(widget.user).catchError((e) {
      debugPrint('ensureUserDoc failed: $e');
    });
    if (mounted) setState(() => _ready = true);
  }

  bool get _isQuickMenuActive =>
      _quickMenuVisible ||
      _quickMenuController.isAnimating ||
      !_quickMenuController.isDismissed;

  void _toggleQuickMenu() {
    if (_isQuickMenuActive) {
      _closeQuickMenu();
    } else {
      _openQuickMenu();
    }
  }

  void _openQuickMenu() {
    if (!_taskMenuController.isDismissed) {
      _closeTaskMenu(restoreSelection: true);
    }
    if (!_quickMenuVisible) {
      setState(() => _quickMenuVisible = true);
    }
    _quickMenuController.forward(from: 0);
  }

  void _closeQuickMenu() {
    if (_quickMenuController.isDismissed && !_quickMenuController.isAnimating) {
      if (_quickMenuVisible) {
        setState(() => _quickMenuVisible = false);
      }
      return;
    }
    _quickMenuController.reverse();
  }

  void _handleDestinationSelected(int index) {
    if (index == 2) {
      if (_taskMenuController.isDismissed) {
        _openTaskMenu();
      } else {
        _closeTaskMenu(restoreSelection: true);
      }
      return;
    }

    if (!_taskMenuController.isDismissed) {
      _closeTaskMenu();
    }
    if (_isQuickMenuActive) {
      _closeQuickMenu();
    }

    _setActivePage(index, navIndex: index);
  }

  void _openTaskMenu() {
    _previousIndex = _navIndex;
    if (_navIndex != 2) {
      setState(() {
        _navIndex = 2;
      });
    }
    if (_isQuickMenuActive) {
      _closeQuickMenu();
    }
    _taskMenuController.forward();
  }

  void _closeTaskMenu({bool restoreSelection = false}) {
    if (_taskMenuController.isDismissed) {
      return;
    }
    if (restoreSelection) {
      setState(() {
        _navIndex = _previousIndex;
      });
    }
    _taskMenuController.reverse();
  }

  Future<void> _handleTaskAction(_TaskAction action) async {
    await _taskMenuController.reverse();
    if (!mounted) return;

    switch (action) {
      case _TaskAction.starred:
        _setActivePage(_starredTasksPageIndex, navIndex: 2);
        break;
      case _TaskAction.overview:
        _setActivePage(_taskOverviewPageIndex, navIndex: 2);
        break;
      case _TaskAction.personal:
        _setActivePage(_personalTasksPageIndex, navIndex: 2);
        break;
      case _TaskAction.external:
        _setActivePage(_externalTasksPageIndex, navIndex: 2);
        break;
    }
  }

  Future<void> _handleQuickAction(_QuickAction action) async {
    await _quickMenuController.reverse();
    if (!mounted) return;

    switch (action) {
      case _QuickAction.newTask:
        await showQuickAddTaskDialog(context);
        break;
      case _QuickAction.newNote:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NoteEditorPage()));
        break;
      case _QuickAction.newInvoice:
        await showQuickAddInvoiceDialog(context);
        break;
    }
  }

  Widget _buildTaskMenuOverlay(BuildContext context) {
    return AnimatedBuilder(
      animation: _taskMenuAnimation,
      builder: (context, child) {
        final progress = _taskMenuAnimation.value;
        if (progress == 0) {
          return const SizedBox.shrink();
        }

        const options = <_TaskMenuOption>[
          _TaskMenuOption(
            action: _TaskAction.overview,
            label: 'Overview',
            icon: Icons.dashboard_customize,
            offset: Offset(-117, -68),
          ),
          _TaskMenuOption(
            action: _TaskAction.starred,
            label: 'Starred',
            icon: Icons.star,
            offset: Offset(-46, -127),
          ),
          _TaskMenuOption(
            action: _TaskAction.personal,
            label: 'Personal',
            icon: Icons.person,
            offset: Offset(46, -127),
          ),
          _TaskMenuOption(
            action: _TaskAction.external,
            label: 'External',
            icon: Icons.public,
            offset: Offset(117, -68),
          ),
        ];

        return Positioned.fill(
          child: IgnorePointer(
            ignoring: progress == 0,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                GestureDetector(
                  onTap: () => _closeTaskMenu(restoreSelection: true),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35 * progress),
                  ),
                ),
                for (final option in options)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: _TaskMenuButton(
                      option: option,
                      progress: progress,
                      onTap: () => _handleTaskAction(option.action),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickMenuOverlay(BuildContext context) {
    final showOverlay = _quickMenuVisible ||
        _quickMenuController.isAnimating ||
        !_quickMenuController.isDismissed;
    if (!showOverlay) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _quickMenuAnimation,
      builder: (context, child) {
        final progress = _quickMenuAnimation.value;

        const options = <_QuickMenuOption>[
          _QuickMenuOption(
            action: _QuickAction.newTask,
            label: 'Task',
            icon: Icons.checklist_rtl,
            angleDeg: 95,
            radius: 115,
          ),
          _QuickMenuOption(
            action: _QuickAction.newInvoice,
            label: 'Invoice',
            icon: Icons.request_quote_outlined,
            angleDeg: 55,
            radius: 115,
          ),
          _QuickMenuOption(
            action: _QuickAction.newNote,
            label: 'Note',
            icon: Icons.note_alt_outlined,
            angleDeg: 15,
            radius: 115,
          ),
        ];

        return Positioned.fill(
          child: IgnorePointer(
            ignoring: progress == 0,
            child: Stack(
              children: [
                GestureDetector(
                  onTap: _closeQuickMenu,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.28 * progress),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24, bottom: 94),
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final option in options)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: _QuickMenuButton(
                                option: option,
                                progress: progress,
                                onTap: () => _handleQuickAction(option.action),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBarTitle(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.appBarTheme.titleTextStyle ??
        theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.onPrimary,
        );
    final displayStyle = baseStyle ??
        theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.onPrimary,
        );

    String? pageTitle;
    switch (_bodyIndex) {
      case 0:
        pageTitle = 'Home';
        break;
      case 1:
        pageTitle = 'Profile';
        break;
      case 2:
        pageTitle = 'Starred Tasks';
        break;
      case 3:
        pageTitle = 'Projects';
        break;
      case 4:
        pageTitle = 'Invoices';
        break;
      case _taskOverviewPageIndex:
        pageTitle = 'Tasks Overview';
        break;
      case _externalTasksPageIndex:
        pageTitle = 'External Tasks';
        break;
      case _personalTasksPageIndex:
        pageTitle = 'Personal Tasks';
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _logoTitle(),
        if (pageTitle != null) ...[
          const Spacer(),
          Text(pageTitle, style: displayStyle),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<UserProfile?>(
      stream: _userRepo.streamByUid(widget.user.uid),
      builder: (context, snap) {
        final access = UserAccess(user: widget.user, profile: snap.data);
        UserAccessController.instance.update(access);
        return UserAccessScope(
          access: access,
          child: _buildShellContents(context),
        );
      },
    );
  }

  Widget _buildShellContents(BuildContext context) {
    final pages = List<Widget>.generate(
      _pageCount,
      (index) => _buildPageForIndex(index),
      growable: false,
    );

    final scaffold = Scaffold(
      appBar: AppBar(title: _buildAppBarTitle(context)),
      body: IndexedStack(index: _bodyIndex, children: pages),
      floatingActionButton: _bodyIndex == 0
          ? FloatingActionButton(
              heroTag: 'dashboard-quick',
              backgroundColor: _brandYellow,
              foregroundColor: Colors.black,
              onPressed: _toggleQuickMenu,
              child: const Icon(Icons.add),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: const ShellBottomNav(),
    );

    return _ShellScope(
      state: this,
      navIndex: _navIndex,
      child: Stack(
        children: [
          scaffold,
          _buildTaskMenuOverlay(context),
          _buildQuickMenuOverlay(context),
        ],
      ),
    );
  }

  int get navigationIndex => _navIndex;

  void handleDestinationSelected(int index) {
    _handleDestinationSelected(index);
  }

  void handleDestinationSelectedFromChild(
      int index, BuildContext childContext) {
    if (Navigator.of(childContext).canPop()) {
      Navigator.of(childContext).popUntil((route) => route.isFirst);
    }
    _handleDestinationSelected(index);
  }

  void _setActivePage(int bodyIndex, {int? navIndex}) {
    setState(() {
      _bodyIndex = bodyIndex;
      if (navIndex != null) {
        _navIndex = navIndex;
      }
    });
  }

  Widget _buildPageForIndex(int index) {
    final isActive = _bodyIndex == index;
    switch (index) {
      case 0:
        return DashboardPage();
      case 1:
        return const ProfilePage();
      case _starredTasksPageIndex:
        return isActive ? const StarredTasksPage() : const SizedBox.shrink();
      case 3:
        return const ProjectsPage();
      case 4:
        return InvoicesPage();
      case _taskOverviewPageIndex:
        return isActive ? TaskOverviewPage() : const SizedBox.shrink();
      case _externalTasksPageIndex:
        return isActive
            ? const ExternalTasksOverviewPage()
            : const SizedBox.shrink();
      case _personalTasksPageIndex:
        return isActive
            ? const PersonalChecklistPage()
            : const SizedBox.shrink();
      default:
        return const SizedBox.shrink();
    }
  }
}

enum _TaskAction { starred, overview, personal, external }

class _TaskMenuOption {
  const _TaskMenuOption({
    required this.action,
    required this.label,
    required this.icon,
    required this.offset,
  });

  final _TaskAction action;
  final String label;
  final IconData icon;
  final Offset offset;
}

enum _QuickAction { newTask, newNote, newInvoice }

class _QuickMenuOption {
  const _QuickMenuOption({
    required this.action,
    required this.label,
    required this.icon,
    required this.angleDeg,
    required this.radius,
  });

  final _QuickAction action;
  final String label;
  final IconData icon;
  final double angleDeg;
  final double radius;
}

class _QuickMenuButton extends StatelessWidget {
  const _QuickMenuButton({
    required this.option,
    required this.progress,
    required this.onTap,
  });

  final _QuickMenuOption option;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final angleRad = option.angleDeg * math.pi / 180;
    final dx = option.radius * math.cos(angleRad);
    final dy = option.radius * math.sin(angleRad);
    final translation = Offset(-dx * progress, -dy * progress);
    final opacity = progress.clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.labelSmall ??
        theme.textTheme.bodySmall ??
        const TextStyle(fontSize: 12);
    final textStyle = baseStyle.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return Transform.translate(
      offset: translation,
      child: Transform.scale(
        scale: 0.78 + (0.22 * progress),
        child: Opacity(
          opacity: opacity,
          child: SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  bottom: 64,
                  right: 32,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55 * opacity),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(option.label, style: textStyle),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Material(
                    color: Colors.transparent,
                    elevation: 8 * opacity,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: onTap,
                      customBorder: const CircleBorder(),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [_brandYellow, Color(0xFFFFD84D)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          option.icon,
                          color: Colors.black87,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskMenuButton extends StatelessWidget {
  const _TaskMenuButton({
    required this.option,
    required this.progress,
    required this.onTap,
  });

  final _TaskMenuOption option;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveOffset = Offset(
      option.offset.dx * progress,
      option.offset.dy * progress,
    );
    final opacity = progress.clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.labelSmall ??
        theme.textTheme.bodySmall ??
        const TextStyle(fontSize: 12);
    final textStyle = baseStyle.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return Transform.translate(
      offset: effectiveOffset,
      child: Opacity(
        opacity: opacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45 * opacity),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Text(option.label, style: textStyle),
              ),
            ),
            const SizedBox(height: 6),
            Material(
              color: Colors.transparent,
              elevation: 8 * opacity,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [_brandYellow, Color(0xFFFFD84D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(option.icon, color: Colors.black87, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarTabIcon extends StatelessWidget {
  const _StarTabIcon({required this.isSelected});

  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isSelected ? _brandYellow : Colors.white;
    final borderColor =
        isSelected ? Colors.transparent : _brandYellow.withValues(alpha: 0.5);
    final iconColor = isSelected ? Colors.black : _brandYellow;
    final shadowColor = _brandYellow.withValues(alpha: 0.35);

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor,
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color:
                isSelected ? shadowColor : shadowColor.withValues(alpha: 0.15),
            blurRadius: isSelected ? 14 : 6,
            offset: isSelected ? const Offset(0, 6) : const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        isSelected ? Icons.star : Icons.star_border,
        color: iconColor,
        size: 26,
      ),
    );
  }
}

class _ShellScope extends InheritedWidget {
  const _ShellScope({
    required this.state,
    required this.navIndex,
    required super.child,
  });

  final _ShellState state;
  final int navIndex;

  static _ShellScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_ShellScope>();
  }

  @override
  bool updateShouldNotify(covariant _ShellScope oldWidget) =>
      navIndex != oldWidget.navIndex || state != oldWidget.state;
}

class ShellBottomNav extends StatelessWidget {
  const ShellBottomNav({super.key, this.popCurrentRoute = false});

  final bool popCurrentRoute;

  @override
  Widget build(BuildContext context) {
    final scope = _ShellScope.of(context);
    if (scope == null) return const SizedBox.shrink();
    final state = scope.state;
    return NavigationBar(
      selectedIndex: scope.navIndex,
      onDestinationSelected: (index) {
        if (popCurrentRoute) {
          state.handleDestinationSelectedFromChild(index, context);
        } else {
          state.handleDestinationSelected(index);
        }
      },
      destinations: _ShellState._navDestinations,
    );
  }
}
