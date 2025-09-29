// lib/src/pages/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'subphases_page.dart';
import 'starred_tasks_page.dart';
import 'active_tasks_page.dart';
import '../dialogs/city_inspect_links_dialog.dart';

class DashboardPage extends StatelessWidget {
  DashboardPage({super.key});

  final _user = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    final linkColor = Theme.of(context).colorScheme.onSurface;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: Icon(Icons.engineering, size: 80)),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Welcome to Sky Engineering',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Text(_user?.email ?? '(no email)')),
              const SizedBox(height: 24),
              const Center(
                child:
                Text('Use the tabs below to navigate. Projects will appear here soon.'),
              ),
              const SizedBox(height: 32),

              Text('Helpful Links', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),

              // Project Tasking (Subphases)
              _linkButton(
                context: context,
                color: linkColor,
                label: 'Project Tasking',
                onTap: () {
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => SubphasesPage()));
                },
              ),
              const SizedBox(height: 6),

              // Starred Tasks
              _linkButton(
                context: context,
                color: linkColor,
                label: 'Starred Tasks',
                onTap: () {
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => StarredTasksPage()));
                },
              ),
              const SizedBox(height: 6),

              // In Progress Tasks (Pending + In Progress)
              _linkButton(
                context: context,
                color: linkColor,
                label: 'In Progress Tasks',
                onTap: () {
                  Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => ActiveTasksPage()));
                },
              ),
              const SizedBox(height: 6),

              // Sky Engineering Website
              _linkButton(
                context: context,
                color: linkColor,
                label: 'Sky Engineering Website',
                onTap: () => _openExternal(
                  context,
                  Uri.parse('https://www.skyengineering.co'),
                ),
              ),
              const SizedBox(height: 6),

              // Sky Engineering Dropbox
              _linkButton(
                context: context,
                color: linkColor,
                label: 'Sky Engineering Dropbox',
                onTap: () => _openExternal(
                  context,
                  Uri.parse(
                    'https://www.dropbox.com/scl/fo/qb19djm48m3ko65x8ua1n/ADxAvonvBPlx5uVypAWlQ6A?rlkey=z1y61ir805qvgk3k0r9j3ky2g&st=6ub8qjcc&dl=0',
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // City Inspect Links (dialog)
              _linkButton(
                context: context,
                color: linkColor,
                label: 'City Inspect Links',
                onTap: () => showCityInspectLinksDialog(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkButton({
    required BuildContext context,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft,
      ),
      child: Text(
        label,
        style: const TextStyle(
          decoration: TextDecoration.underline,
          decorationThickness: 1.5,
        ),
      ),
    );
  }

  Future<void> _openExternal(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }
}
