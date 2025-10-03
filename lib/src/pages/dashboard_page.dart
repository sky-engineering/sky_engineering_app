// lib/src/pages/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'subphases_page.dart';
import 'in_progress_tasks_page.dart';
import 'starred_tasks_page.dart';
import '../dialogs/city_inspect_links_dialog.dart';
import '../dialogs/other_links_dialog.dart';
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
    final linkStyle = TextButton.styleFrom(
      foregroundColor: linkColor,
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 0),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      alignment: Alignment.centerLeft,
    );

    Widget linkButton(String label, VoidCallback onPressed) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_right, size: 16),
        label: Text(
          label,
          style: const TextStyle(
            decoration: TextDecoration.underline,
            decorationThickness: 1.5,
          ),
        ),
        style: linkStyle,
      );
    }

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

              linkButton('Current Tasks', () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => InProgressTasksPage()),
                );
              }),
              const SizedBox(height: 16),

              linkButton('Starred Tasks', () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => StarredTasksPage()));
              }),
              const SizedBox(height: 16),

              linkButton('Proposals', () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DropboxFolderListPage(
                      title: 'Proposals',
                      path: 'SKY/02 PROP',
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),

              linkButton('Clients', () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => ClientsPage()));
              }),
              const SizedBox(height: 16),

              linkButton('Task Structure', () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => SubphasesPage()));
              }),
              const SizedBox(height: 16),

              linkButton('Dropbox', () {
                _launchExternal(
                  context,
                  'https://www.dropbox.com/scl/fo/qb19djm48m3ko65x8ua1n/ADxAvonvBPlx5uVypAWlQ6A?rlkey=e9brozwr2qpq9k1b0t256kt56&dl=0',
                );
              }),
              const SizedBox(height: 24),

              linkButton('City Inspect Links', () {
                showCityInspectLinksDialog(context);
              }),
              const SizedBox(height: 16),

              linkButton('Washington County GIS', () {
                _launchExternal(
                  context,
                  'https://geoprodvm.washco.utah.gov/Html5Viewer/?viewer=RecordersOffice',
                );
              }),
              const SizedBox(height: 16),

              linkButton('Other Links', () {
                showOtherLinksDialog(context);
              }),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
