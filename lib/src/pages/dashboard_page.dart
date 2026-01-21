// lib/src/pages/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'template_checklists_page.dart';
import 'big_picture_page.dart';
import 'proposals_page.dart';
import 'subphases_page.dart';
import 'contract_snapshot_page.dart';
import '../dialogs/city_inspect_links_dialog.dart';
import '../dialogs/other_links_dialog.dart';
import '../pages/clients_page.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_scaffold.dart';

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

    Widget buildLinkGroup(String title, List<Widget> buttons) {
      return SectionCard(
        header: SectionHeader(title: title),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _withGaps(buttons),
        ),
      );
    }

    final workflowLinks = buildLinkGroup(
      'Workspace',
      [
        linkButton('Workload', () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => BigPicturePage()));
        }),
        linkButton('Contract Snapshot', () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ContractSnapshotPage()),
          );
        }),
        linkButton('Proposals', () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => ProposalsPage()));
        }),
        linkButton('Checklists', () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TemplateChecklistsPage()),
          );
        }),
        linkButton('Clients', () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => ClientsPage()));
        }),
        linkButton('Task Structure', () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SubphasesPage()));
        }),
      ],
    );

    final resourcesLinks = buildLinkGroup(
      'Resources',
      [
        linkButton('Sky Engineering Dropbox', () {
          _launchExternal(
            context,
            'https://www.dropbox.com/scl/fo/qb19djm48m3ko65x8ua1n/ADxAvonvBPlx5uVypAWlQ6A?rlkey=e9brozwr2qpq9k1b0t256kt56&dl=0',
          );
        }),
        linkButton('City Inspect Links', () {
          showCityInspectLinksDialog(context);
        }),
        linkButton('Washington County GIS', () {
          _launchExternal(
            context,
            'https://geoprodvm.washco.utah.gov/Html5Viewer/?viewer=RecordersOffice',
          );
        }),
        linkButton('Other Links', () {
          showOtherLinksDialog(context);
        }),
      ],
    );

    return AppPageScaffold(
      scrollable: true,
      useSafeArea: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Image.asset(
              'assets/SkyEngineering-Horizontal-Light.png',
              height: 128,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(child: Text(_user?.email ?? '(no email)')),
          const SizedBox(height: AppSpacing.lg),
          workflowLinks,
          const SizedBox(height: AppSpacing.lg),
          resourcesLinks,
        ],
      ),
    );
  }

  List<Widget> _withGaps(List<Widget> children) {
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i != children.length - 1) {
        spaced.add(const SizedBox(height: AppSpacing.sm));
      }
    }
    return spaced;
  }
}
