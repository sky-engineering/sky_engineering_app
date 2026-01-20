import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_scaffold.dart';

class HomePage extends StatefulWidget {
  final User user;
  const HomePage({super.key, required this.user});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
    final actions = [
      IconButton(
        tooltip: 'Sign out',
        onPressed: () async {
          await FirebaseAuth.instance.signOut();
        },
        icon: const Icon(Icons.logout),
      ),
    ];

    if (_error != null) {
      return AppPageScaffold(
        title: 'Sky Engineering Home',
        actions: actions,
        useSafeArea: true,
        padding: const EdgeInsets.all(AppSpacing.md),
        body: Center(child: Text('Error: $_error')),
      );
    }
    if (!_ready) {
      return const AppPageScaffold(
        title: 'Sky Engineering Home',
        useSafeArea: true,
        padding: EdgeInsets.all(AppSpacing.md),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return AppPageScaffold(
      title: 'Sky Engineering Home',
      actions: actions,
      useSafeArea: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.engineering, size: 64),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Signed in as:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(widget.user.email ?? '(no email)'),
            const SizedBox(height: AppSpacing.lg),
            const Text('Firestore user document ensured.'),
          ],
        ),
      ),
    );
  }
}
