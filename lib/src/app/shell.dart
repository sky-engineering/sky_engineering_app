// lib/src/app/shell.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../pages/dashboard_page.dart';
import '../pages/projects_page.dart';
import '../pages/profile_page.dart';
import '../pages/invoices_page.dart';

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
      appBar: AppBar(
        title: _logoTitle(),
        actions: [
          IconButton(
            tooltip: 'Dropbox',
            icon: const Icon(Icons.folder),
            onPressed: () => Navigator.of(context).pushNamed('/dropbox'),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
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
