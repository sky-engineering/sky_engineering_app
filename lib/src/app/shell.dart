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

class Shell extends StatefulWidget {
  final User user;
  const Shell({super.key, required this.user});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  bool _ready = false;
  String? _error;

  final _pages = <Widget>[];

  Widget _logoTitle() =>
      SizedBox(height: 32, child: Image.asset('assets/logo_white.png'));

  @override
  void initState() {
    super.initState();
    _pages.addAll([
      DashboardPage(),
      const ProjectsPage(),
      InvoicesPage(),
      const ProfilePage(),
    ]);
    _init();
  }

  Future<void> _init() async {
    try {
      await UserService.ensureUserDoc(widget.user);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
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

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: _logoTitle()),
        body: Center(child: Text('Error: $_error')),
      );
    }
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: _logoTitle()),
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: _index == 0
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
                    backgroundColor: const Color(0xFFF1C400),
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
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
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
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
