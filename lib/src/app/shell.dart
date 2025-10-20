// lib/src/app/shell.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/user_service.dart';
import '../pages/dashboard_page.dart';
import '../pages/projects_page.dart';
import '../pages/profile_page.dart';
import '../pages/note_editor_page.dart';
import '../dialogs/quick_actions.dart';
import '../pages/invoices_page.dart';
import '../pages/personal_checklist_page.dart';
import '../pages/starred_tasks_page.dart';
import '../pages/task_overview_page.dart';
import '../pages/external_tasks_overview_page.dart';

const _brandYellow = Color(0xFFF1C400);

class Shell extends StatefulWidget {
  const Shell({super.key, required this.user});

  final User user;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with SingleTickerProviderStateMixin {
  final _pages = <Widget>[];

  bool _ready = false;
  int _navIndex = 0;
  int _bodyIndex = 0;
  int _previousIndex = 0;

  late final AnimationController _taskMenuController;
  late final Animation<double> _taskMenuAnimation;

  Widget _logoTitle() =>
      SizedBox(height: 32, child: Image.asset('assets/logo_white.png'));

  @override
  void initState() {
    super.initState();
    _pages.addAll([
      DashboardPage(),
      const ProfilePage(),
      const StarredTasksPage(),
      const ProjectsPage(),
      InvoicesPage(),
    ]);

    _taskMenuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _taskMenuAnimation = CurvedAnimation(
      parent: _taskMenuController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );

    _init();
  }

  @override
  void dispose() {
    _taskMenuController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    UserService.ensureUserDoc(widget.user).catchError((e) {
      debugPrint('ensureUserDoc failed: $e');
    });
    if (mounted) setState(() => _ready = true);
  }

  void _showQuickActionSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.checklist_rtl),
                title: const Text('New Task'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (!mounted) return;
                  await showQuickAddTaskDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.note_alt_outlined),
                title: const Text('New Note'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (!mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NoteEditorPage()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.request_quote_outlined),
                title: const Text('New Invoice'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  if (!mounted) return;
                  await showQuickAddInvoiceDialog(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openChecklist() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PersonalChecklistPage()));
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

    setState(() {
      _navIndex = index;
      _bodyIndex = index;
    });
  }

  void _openTaskMenu() {
    _previousIndex = _navIndex;
    setState(() {
      _navIndex = 2;
    });
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
        setState(() {
          _navIndex = 2;
          _bodyIndex = 2;
        });
        break;
      case _TaskAction.overview:
        setState(() {
          _navIndex = _previousIndex;
          _bodyIndex = _previousIndex;
        });
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => TaskOverviewPage()));
        break;
      case _TaskAction.external:
        setState(() {
          _navIndex = _previousIndex;
          _bodyIndex = _previousIndex;
        });
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ExternalTasksOverviewPage()),
        );
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

        final options = const <_TaskMenuOption>[
          _TaskMenuOption(
            action: _TaskAction.starred,
            label: 'Starred Tasks',
            icon: Icons.star,
            offset: Offset(0, -150),
          ),
          _TaskMenuOption(
            action: _TaskAction.overview,
            label: 'Tasks Overview',
            icon: Icons.dashboard_customize,
            offset: Offset(-120, -110),
          ),
          _TaskMenuOption(
            action: _TaskAction.external,
            label: 'External Tasks',
            icon: Icons.public,
            offset: Offset(120, -110),
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

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scaffold = Scaffold(
      appBar: AppBar(title: _logoTitle()),
      body: IndexedStack(index: _bodyIndex, children: _pages),
      floatingActionButton: _bodyIndex == 0
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FloatingActionButton(
                    heroTag: 'dashboard-checklist',
                    onPressed: _openChecklist,
                    tooltip: 'Personal checklist',
                    child: const Icon(Icons.fact_check),
                  ),
                  FloatingActionButton(
                    heroTag: 'dashboard-quick',
                    backgroundColor: _brandYellow,
                    foregroundColor: Colors.black,
                    onPressed: _showQuickActionSheet,
                    child: const Icon(Icons.add),
                  ),
                ],
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: _handleDestinationSelected,
        destinations: const [
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
        ],
      ),
    );

    return Stack(children: [scaffold, _buildTaskMenuOverlay(context)]);
  }
}

enum _TaskAction { starred, overview, external }

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
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );

    return Transform.translate(
      offset: effectiveOffset,
      child: Opacity(
        opacity: opacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55 * opacity),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(option.label, style: textStyle),
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
    final borderColor = isSelected
        ? Colors.transparent
        : _brandYellow.withValues(alpha: 0.5);
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
            color: isSelected
                ? shadowColor
                : shadowColor.withValues(alpha: 0.15),
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
