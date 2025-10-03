// lib/src/pages/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'subphases_page.dart';
import 'in_progress_tasks_page.dart';
import 'starred_tasks_page.dart';
import '../dialogs/city_inspect_links_dialog.dart';
import '../integrations/dropbox/dropbox_folder_list_page.dart';
import '../pages/clients_page.dart';

class DashboardPage extends StatelessWidget {
  DashboardPage({super.key});

  final _user = FirebaseAuth.instance.currentUser;

  Future<void> _launchExternal(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

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
              Center(
                child: Image.asset(
                  'assets/SkyEngineering-Horizontal-Light.png',
                  height: 128,
                ),
              ),
              const SizedBox(height: 12),
              Center(child: Text(_user?.email ?? '(no email)')),
              const SizedBox(height: 32),

              Text(
                'Helpful Links',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),

              const SizedBox(height: 16),

              // In Progress Tasks
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => InProgressTasksPage()),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: linkColor,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                child: const Text(
                  'In Progress Tasks',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationThickness: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Starred Tasks
              TextButton(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => StarredTasksPage()));
                },
                style: TextButton.styleFrom(
                  foregroundColor: linkColor,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                child: const Text(
                  'Starred Tasks',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationThickness: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Project Tasking
              TextButton(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => SubphasesPage()));
                },
                style: TextButton.styleFrom(
                  foregroundColor: linkColor,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                child: const Text(
                  'Project Tasking',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationThickness: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Sky Engineering Website
              TextButton(
                onPressed: () {
                  _launchExternal(context, 'https://www.skyengineering.co');
                },
                style: TextButton.styleFrom(
                  foregroundColor: linkColor,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                child: const Text(
                  'Sky Engineering Website',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationThickness: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Sky Engineering Dropbox
              TextButton(
                onPressed: () {
                  _launchExternal(
                    context,
                    'https://www.dropbox.com/scl/fo/qb19djm48m3ko65x8ua1n/ADxAvonvBPlx5uVypAWlQ6A?rlkey=e9brozwr2qpq9k1b0t256kt56&dl=0',
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: linkColor,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                child: const Text(
                  'Sky Engineering Dropbox',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationThickness: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DropboxFolderListPage(
                        title: 'Proposal Dropbox Folders',
                        path: 'SKY/02 PROP',
                      ),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: linkColor,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                child: const Text(
                  'Proposal Dropbox Folders',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationThickness: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              TextButton(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => ClientsPage()));
                },
                style: TextButton.styleFrom(
                  foregroundColor: linkColor,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                child: const Text(
                  'Clients',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationThickness: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // City Inspects
              TextButton(
                onPressed: () => showCityInspectLinksDialog(context),
                style: TextButton.styleFrom(
                  foregroundColor: linkColor,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                child: const Text(
                  'City Inspects',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                    decorationThickness: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
